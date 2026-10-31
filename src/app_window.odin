package monokl

import "core:c"
import "core:os"
import "core:path/filepath"
import "core:log"
import "core:fmt"
import "core:math"
import "core:sync"
import "core:container/queue"
import "core:time"
import "core:slice"
import "core:strings"
import "vendor:sdl3"

AutoFitMode :: enum {
  None,
  FitWindow,
  KeepOriginalSize,
}

FileEntryState :: enum {
  Loading,
  Loaded,
  Failed,
}

FileEntry :: struct {
  full_path: string,
  filename: string, // borrowed
  texture: ^sdl3.Texture, // owned

  state: FileEntryState,

  image_size: [2]i32,

  is_favorite: bool,
  is_hidden: bool,
  t_created: time.Time,
  t_last_modified: time.Time,
  t_last_accessed: time.Time,
}

FolderSettings :: struct {
  favorites: map[string]bool,
  hidden: map[string]bool,
  only_favorites: bool,
  show_hidden: bool,
}

AppWindow :: struct {
  id: sdl3.WindowID,
  handle: ^sdl3.Window,
  renderer: ^sdl3.Renderer,

  loaded: bool,
  folder_path: string,
  folder_settings_path: string,
  folder_settings_path_tmp: string,
  folder_settings_io_mutex: sync.Mutex,
  pending_folder_settings_save: bool,

  all_files: map[string]FileEntry, // keys are borrowed
  shown_files: [dynamic]string, // contains borrowed strings
  current_index: int, // current position in `shown_files`

  pending_title_refresh: bool,

  result_mutex: sync.Mutex,
  result_queue: queue.Queue(Image),

  window_size: [2]i32,
  mouse_pos: [2]i32,
  zoom_factor: f32,
  position_offset: [2]i32,

  pending_auto_fit: bool,
  next_fit_mode: AutoFitMode,

  is_panning: bool,
  pan_start_pos: [2]i32,
  render_offset: [2]f32,

  folder_settings: FolderSettings,

  current_entry: ^FileEntry, // borrowed
}


/////////////////////////////
// Private API
/////////////////////////////
_folder_settings_read_from_file :: proc(settings: ^FolderSettings, full_path: string) -> Error {
  assert(settings != nil)

  bytes, err := os.read_entire_file(full_path, context.allocator)
  if err != nil {
    return common_error(fmt.tprintf("Failed to read folder settings from %s", full_path))
  }
  defer delete(bytes)

  ReaderState :: enum {
    ReadAny,
    ReadFavorites,
    ReadHidden,
  }
  text := string(bytes)
  state := ReaderState.ReadAny
  for line in strings.split_lines_iterator(&text) {
    trimmed_line := strings.trim_space(line)

    if trimmed_line == "" {
      continue
    }

    if strings.starts_with(line, "[only_favorites") {
      if strings.ends_with(line, "true]") {
        settings.only_favorites = true
      }
      continue
    }

    if strings.starts_with(line, "[show_hidden") {
      if strings.ends_with(line, "true]") {
        settings.show_hidden = true
      }
      continue
    }

    if line == "[favorites]" {
      state = .ReadFavorites
      continue
    }

    if line == "[hidden]" {
      state = .ReadHidden
      continue
    }

    #partial switch state {
      case .ReadFavorites: {
        // can't insert new keys into the map otherwise we corrupt memory
        if trimmed_line in settings.favorites {
          settings.favorites[trimmed_line] = true
        }
      }

      case .ReadHidden: {
        // can't insert new keys into the map otherwise we corrupt memory
        if trimmed_line in settings.hidden {
          settings.hidden[trimmed_line] = true
        }
      }
    }
  }

  log.debugf("Successfully read folder settings from %s", full_path)

  return nil
}

_folder_settings_write_to_file :: proc(settings: ^FolderSettings, full_path: string) -> Error {
  assert(settings != nil)

  {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)
  
    strings.write_string(&sb, "[favorites]\n")
    for filename, is_favorite in settings.favorites {
      if is_favorite {
        strings.write_string(&sb, filename)
        strings.write_string(&sb, "\n")
      }
    }
  
    strings.write_string(&sb, "\n")
  
    strings.write_string(&sb, "[hidden]\n")
    for filename, is_hidden in settings.hidden {
      if is_hidden {
        strings.write_string(&sb, filename)
        strings.write_string(&sb, "\n")
      }
    }

    str := strings.to_string(sb)

    err := os.write_entire_file(full_path, str[:])
    if err != nil {
      return common_error(fmt.tprintf("Failed to write settings to path %s due to %v", full_path, err))
    }
  }

  // TODO: hide the file

  return nil
}

_app_window_reload_folder_settings :: proc(window: ^AppWindow) {
  assert(window != nil)
  if window.folder_settings_path == "" {
    return
  }
  sync.mutex_lock(&window.folder_settings_io_mutex)
  defer sync.mutex_unlock(&window.folder_settings_io_mutex)
  err := _folder_settings_read_from_file(&window.folder_settings, window.folder_settings_path)
  if err != nil {
    log.warnf("Failed to reload folder settings due to %v", err)
  } else {
    log.warnf("Successfully loaded folder settings")
  }
}

_app_window_save_folder_settings :: proc(window: ^AppWindow) {
  assert(window != nil)
  sync.mutex_lock(&window.folder_settings_io_mutex)
  defer sync.mutex_unlock(&window.folder_settings_io_mutex)
  window.pending_folder_settings_save = false
  if window.folder_settings_path_tmp == "" || window.folder_settings_path == "" {
    return
  }
  err1 := _folder_settings_write_to_file(&window.folder_settings, window.folder_settings_path_tmp)
  if err1 != nil {
    log.warnf("Failed to save settings due to %v", err1)
    return
  }

  err2 := os.rename(window.folder_settings_path_tmp, window.folder_settings_path)
  if err2 != nil {
    log.warnf("Failed to rename folder settings file: %v", err2)
  } else {
    log.warnf("Successfully saved folder settings")
  }
}

_app_window_handle_one_result :: proc(window: ^AppWindow) -> bool {
  assert(window != nil)

  item: Image

  {
    sync.lock(&window.result_mutex)
    defer sync.unlock(&window.result_mutex)

    if queue.len(window.result_queue) < 1 {
      return false
    }

    item = queue.pop_front(&window.result_queue)
    window.pending_title_refresh = true
  }

  entry, ok := &window.all_files[item.full_path]
  if !ok {
    log.warnf("Received image result for unrecognized path %s", item.full_path)
    return false
  }

  if !item.loaded_successfully || item.surface == nil {
    entry.state = .Failed
    return false
  }

  texture := sdl3.CreateTextureFromSurface(window.renderer, item.surface)
  if texture == nil {
    log.warnf("Failed to convert image to texture: %v", sdl_last_error("Reason"))
    entry.state = .Failed
  } else {
    entry.state = .Loaded
    entry.texture = texture
    entry.image_size.x = item.surface.w
    entry.image_size.y = item.surface.h

    sdl3.DestroySurface(item.surface)
  }

  return true
}

_app_window_refresh_shown_files :: proc(window: ^AppWindow) {
  clear(&window.shown_files)

  for _, entry in window.all_files {
    if window.folder_settings.only_favorites && !entry.is_favorite {
      continue
    }

    if !window.folder_settings.show_hidden && entry.is_hidden {
      continue
    }

    append(&window.shown_files, entry.full_path)
  }

  // TODO: sort by other methods
  slice.sort_by_cmp(window.shown_files[:], proc(a, b: string) -> slice.Ordering {
    c := strings.compare(a, b)
    if c == 0 do return .Equal
    if c < 0 do return .Less
    return .Greater
  })

  desired_idx := 0
  if window.current_entry != nil {
    found_idx, found := slice.linear_search(window.shown_files[:], window.current_entry.full_path)
    if found {
      desired_idx = found_idx
    }
  }

  app_window_go_to_index(window, clamp(desired_idx, 0, len(window.shown_files)))
}

_sort_file_paths_by_proximity :: proc(file_paths: ^[dynamic]string, target: string) {
  count := len(file_paths)
  if count <= 1 {
    return
  }

  start_idx, found := slice.linear_search(file_paths[:], target)
  if !found {
    return
  }

  idx_order := make([]int, count)
  defer delete(idx_order)

  visited := make([]bool, count)
  defer delete(visited)

  order_count := 0

  push_idx :: proc(idx_order: []int, visited: []bool, count: ^int, idx: int) {
    cnt := len(visited)
    wrapped_idx := ((idx % cnt) + cnt) % cnt
    if !visited[wrapped_idx] {
      visited[wrapped_idx] = true
      idx_order[count^] = wrapped_idx
      count^ += 1
    }
  }

  push_idx(idx_order, visited, &order_count, start_idx)
  push_idx(idx_order, visited, &order_count, start_idx + 1)
  push_idx(idx_order, visited, &order_count, start_idx - 1)
  push_idx(idx_order, visited, &order_count, count - 1)
  push_idx(idx_order, visited, &order_count, 0)

  offset := 2
  for order_count < count {
    push_idx(idx_order, visited, &order_count, start_idx + offset)
    if order_count < count {
      push_idx(idx_order, visited, &order_count, start_idx - offset)
    }
    offset += 1
  }

  // use a temp buffer to sort the original array
  permuted := make([]bool, count)
  defer delete(permuted)
  for i in 0..<count {
    if permuted[i] {
      continue
    }

    current := i
    temp := file_paths[i]
    for {
      src := idx_order[current]

      if src == i {
        file_paths[current] = temp
        permuted[current] = true
        break
      }

      file_paths[current] = file_paths[src]
      permuted[current] = true
      current = src
    }
  }
}


/////////////////////////////
// Public API
/////////////////////////////
app_window_open :: proc {
  app_window_open_empty,
  app_window_open_at_folder,
}

app_window_open_empty :: proc() -> (sdl3.WindowID, Error) {
  handle: ^sdl3.Window
  renderer: ^sdl3.Renderer

  if !sdl3.CreateWindowAndRenderer("monokl", 1920, 1080, {.RESIZABLE}, &handle, &renderer) {
    return 0, sdl_last_error("Failed to create window")
  }

  sdl3.SetWindowPosition(handle, sdl3.WINDOWPOS_CENTERED, sdl3.WINDOWPOS_CENTERED)
  sdl3.ShowWindow(handle)

  id := sdl3.GetWindowID(handle)

  app.windows[id] = AppWindow {
    id = id,
    renderer = renderer,
    handle = handle,
    all_files = make(map[string]FileEntry),
    shown_files = make([dynamic]string),
    window_size = {1920, 1080},
    zoom_factor = 1.0,
  }

  window := &app.windows[id]
  queue.init(&window.result_queue)

  icon_surface := app_get_window_icon()
  if icon_surface != nil {
    if !sdl3.SetWindowIcon(handle, icon_surface) {
      return 0, sdl_last_error("Failed to set window icon")
    }
  }

  return id, nil
}

app_window_open_at_folder :: proc(folder_path: string, focused_file: Maybe(string) = nil) -> (sdl3.WindowID, Error) {
  id, err := app_window_open_empty()
  if err != nil {
    return 0, err
  }
  window := &app.windows[id]
  app_window_load_folder(window, folder_path, focused_file)
  return id, nil
}

app_window_load_folder :: proc(window: ^AppWindow, full_path: string, focused_file: Maybe(string) = nil) -> Error {
  assert(window != nil)

  if window.loaded && strings.compare(window.folder_path, full_path) == 0 {
    return nil
  }

  if !os.is_directory(full_path) {
    return common_error(fmt.tprintf("The specified path is not a folder: %s", full_path))
  }

  file_infos, err := os.read_all_directory_by_path(full_path, context.temp_allocator)
  if err != nil {
    return common_error(fmt.tprintf("Failed to iterate through files in directory %s with reason %v", full_path, err))
  }

  clear(&window.folder_settings.favorites)
  clear(&window.folder_settings.hidden)

  window.loaded = true
  window.folder_path = strings.clone(full_path)
  window.folder_settings_path = filepath.join({full_path, ".monokl"}) or_return
  window.folder_settings_path_tmp = filepath.join({full_path, ".monokl.tmp"}) or_return

  saw_settings_file := false

  next_idx := 0
  for file_info in file_infos {
    if file_info.name == ".monokl" {
      saw_settings_file = true
      continue
    }

    if !app_is_supported_file(file_info.fullpath) {
      continue
    }

    full_file_path := strings.clone(file_info.fullpath)
    filename := os.base(full_file_path)

    next_idx += 1

    window.all_files[full_file_path] = FileEntry {
      full_path = full_file_path,
      filename = filename,
      t_created = file_info.creation_time,
      t_last_accessed = file_info.access_time,
      t_last_modified = file_info.modification_time,
      texture = nil,
      is_favorite = false, // TODO
      state = .Loading,
    }

    window.folder_settings.favorites[filename] = false
    window.folder_settings.hidden[filename] = false
  }

  if saw_settings_file {
    _app_window_reload_folder_settings(window)

    for _, &entry in window.all_files {
      is_favorite, fav_ok := window.folder_settings.favorites[entry.filename]
      is_hidden, hidden_ok := window.folder_settings.hidden[entry.filename]

      if is_favorite && fav_ok {
        entry.is_favorite = true
      }

      if is_hidden && hidden_ok {
        entry.is_hidden = true
      }
    }
  }

  _app_window_refresh_shown_files(window)

  if len(window.shown_files) > 0 {
    focused_file_path, has_desired := focused_file.(string)

    load_order := make([dynamic]string)
    defer delete(load_order)
    for str in window.shown_files {
      append(&load_order, str)
    }

    desired_file := focused_file_path if has_desired else window.shown_files[0]
    _sort_file_paths_by_proximity(&load_order, desired_file)
    app_request_load_files(window.id, load_order[:])

    current_index, ok := slice.linear_search(window.shown_files[:], desired_file)
    if !ok {
      current_index = 0
    }

    app_window_go_to_index(window, current_index)
  }

  log.debugf("Window %d opened folder %s with %d files (%d shown)", window.id, full_path, len(window.all_files), len(window.shown_files))
  app_window_refresh_title(window)

  sdl3.RaiseWindow(window.handle)

  return nil
}

app_window_unload_folder :: proc(window: ^AppWindow) -> Error {
  assert(window != nil)
  if !window.loaded {
    return nil
  }

  _app_window_save_folder_settings(window)

  settings := &window.folder_settings
  delete(settings.favorites)
  delete(settings.hidden)

  delete(window.folder_path)
  delete(window.shown_files)
  delete(window.folder_settings_path)
  delete(window.folder_settings_path_tmp)

  window.folder_path = ""
  window.folder_settings_path = ""
  window.folder_settings_path_tmp = ""

  if window.all_files != nil {
    for key, entry in window.all_files {
      delete(entry.full_path)
    }
    delete(window.all_files)
    window.all_files = nil
  }

  return nil
}

app_window_destroy :: proc(window: ^AppWindow) {
  if window == nil {
    return
  }

  app_window_unload_folder(window)

  queue.destroy(&window.result_queue)

  if window.renderer != nil {
    sdl3.DestroyRenderer(window.renderer)
    window.renderer = nil
  }

  if window.handle != nil {
    sdl3.DestroyWindow(window.handle)
  }
}

app_window_toggle_favorite :: proc(window: ^AppWindow) {
  assert(window != nil)
  if window.current_entry != nil {
    window.current_entry.is_favorite = !window.current_entry.is_favorite
    window.folder_settings.favorites[window.current_entry.filename] = window.current_entry.is_favorite
    app_window_refresh_title(window)
    _app_window_save_folder_settings(window)
  }
}

app_window_go_to_index :: proc(window: ^AppWindow, index: int) {
  if index >= 0 && index < len(window.shown_files) {
    window.current_index = index
    window.current_entry = &window.all_files[window.shown_files[index]]
    app_window_reset_view(window, .FitWindow)
    app_window_refresh_title(window)
  }
}

app_window_go_to_file :: proc(window: ^AppWindow, full_path: string) {
  log.debugf("Window navigating to image %s", full_path)
  for i in 0..<len(window.shown_files) {
    if window.shown_files[i] == full_path {
      app_window_go_to_index(window, i)
      return
    }
  }
}

app_window_advance :: proc(window: ^AppWindow, by: int) {
  num_entries := len(window.shown_files)
  if num_entries == 0 {
    return
  }
  new_idx := window.current_index + by
  for new_idx < 0 {
    new_idx += num_entries
  }
  new_idx = new_idx % num_entries
  app_window_go_to_index(window, new_idx)
}

app_window_on_image_load_finished :: proc(window: ^AppWindow, image: Image) {
  sync.mutex_lock(&window.result_mutex)
  defer sync.mutex_unlock(&window.result_mutex)
  queue.push_back(&window.result_queue, image)
}

app_window_refresh_title :: proc(window: ^AppWindow) {
  window.pending_title_refresh = false
  if !window.loaded {
    sdl3.SetWindowTitle(window.handle, "monokl")
    return
  }

  entry := window.current_entry
  num_files := len(window.shown_files)
  if num_files < 1 || entry == nil {
    sdl3.SetWindowTitle(window.handle, fmt.ctprintf("monokl - %s - No images", window.folder_path))
    return
  }

  state_text: cstring
  switch entry.state {
    case .Loading:
      state_text = "Loading... - "

    case .Failed:
      state_text = "Failed to load - "

    case .Loaded:
      state_text = ""
  }

  flags_text: cstring = ""
  if entry.is_favorite {
    flags_text = "♥ "
  }

  sdl3.SetWindowTitle(
    window.handle,
    fmt.ctprintf(
      "monokl - %s - %d/%d - %s%s%s [%d%%]",
      window.folder_path,
      window.current_index + 1,
      num_files,
      state_text,
      flags_text,
      entry.filename,
      i32(window.zoom_factor * 100.0),
    )
  )
}

app_window_handle_event :: proc(window: ^AppWindow, event: sdl3.Event) {
  #partial switch event.type {
    case .WINDOW_CLOSE_REQUESTED: {
      app_close_window(window.id)
    }

    case .WINDOW_RESIZED: {
      w, h: c.int
      dscale: f32
      if sdl3.GetWindowSize(window.handle, &w, &h) {
        dscale = math.sqrt(f32(w * h) / f32(window.window_size.x * window.window_size.y))
        window.window_size = {w, h}
        if dscale != 0 {
          window.zoom_factor *= dscale
        }
      }
      window.pending_auto_fit = true
    }

    case .KEY_DOWN: {
      if !event.key.repeat && is_key_down(event, sdl3.K_N, {.LCTRL}) {
        app_window_open()
      }

      if !event.key.repeat && is_key_down(event, sdl3.K_W, {.LCTRL}) {
        app_close_window(event.key.windowID)
      }

      if is_key_down(event, sdl3.K_LEFT, {}) {
        app_window_advance(window, -1)
      }

      if is_key_down(event, sdl3.K_RIGHT, {}) {
        app_window_advance(window, 1)
      }

      if is_key_down(event, sdl3.K_F, {.LSHIFT}) {
        app_window_toggle_only_favorites(window)
      }

      if is_key_down(event, sdl3.K_F, {}) {
        app_window_toggle_favorite(window)
      }

      if is_key_down(event, sdl3.K_C, {}) {
        window.is_panning = false
        window.position_offset = {0,0}
      }

      if !event.key.repeat && is_key_down(event, sdl3.K_HOME, {}) {
        app_window_go_to_index(window, 0)
      }

      if !event.key.repeat && is_key_down(event, sdl3.K_END, {}) {
        app_window_go_to_index(window, len(window.shown_files) - 1)
      }

      if !event.key.repeat && is_key_down(event, sdl3.K_KP_0, {}) {
        app_window_reset_view(window, .FitWindow)
      }

      if !event.key.repeat && is_key_down(event, sdl3.K_KP_1, {}) {
        app_window_reset_view(window, .KeepOriginalSize)
      }
    }

    case .MOUSE_MOTION: {
      window.mouse_pos = {i32(event.motion.x), i32(event.motion.y)}
    }

    case .MOUSE_WHEEL: {
      if window.current_entry != nil {
        dzoom: f32 = 0
        factor: f32 = 1.0

        mod_state := sdl3.GetModState()
        if .LCTRL in mod_state {
          factor = .1
        }

        if event.wheel.integer_y > 0 {
          dzoom = 0.1
        } else if event.wheel.integer_y < 0 {
          dzoom = -.1
        }

        window.zoom_factor = clamp(window.zoom_factor + dzoom * factor, 0.1, 10.0)
        window.next_fit_mode = .None
        window.pending_title_refresh = true
      }
    }

    case .MOUSE_BUTTON_DOWN: {
      if event.button.button == sdl3.BUTTON_LEFT && !window.is_panning && window.current_entry != nil {
        window.is_panning = true
        window.pan_start_pos = {i32(event.button.x), i32(event.button.y)}
        window.mouse_pos = window.pan_start_pos
      }
    }

    case .MOUSE_BUTTON_UP: {
      if event.button.button == sdl3.BUTTON_LEFT && window.is_panning {
        window.is_panning = false
        window.position_offset += window.mouse_pos - window.pan_start_pos
      }

      if event.button.button == sdl3.BUTTON_X2 && !window.is_panning {
        app_window_advance(window, 1)
      }

      if event.button.button == sdl3.BUTTON_X1 && !window.is_panning {
        app_window_advance(window, -1)
      }
    }
  }
}

app_window_update :: proc(window: ^AppWindow, dt: f32) {
  // drain the result queue up to 4 items per frame
  {
    for i in 0..<4 {
      if !_app_window_handle_one_result(window) {
        break
      }
    }
  }

  if window.is_panning {
    target_offset: [2]f32 = {
      f32(window.position_offset.x + window.mouse_pos.x - window.pan_start_pos.x),
      f32(window.position_offset.y + window.mouse_pos.y - window.pan_start_pos.y),
    }
    window.render_offset = math.lerp(window.render_offset, target_offset, dt * 50)
  } else {
    window.render_offset = {
      f32(window.position_offset.x),
      f32(window.position_offset.y),
    }
  }

  if window.pending_folder_settings_save {
    _app_window_save_folder_settings(window)
  }

  if window.is_panning {
    sdl3.SetRenderDrawColor(window.renderer, 255, 255, 88, 255)
    sdl3.RenderPoint(window.renderer, f32(window.pan_start_pos.x), f32(window.pan_start_pos.y))
    sdl3.RenderDebugText(window.renderer, 20, 20, "ASDASDASD")
  }

  entry: ^FileEntry = window.current_entry

  if window.pending_auto_fit && entry != nil && entry.state == .Loaded {
    window.zoom_factor = 1.0

    if window.next_fit_mode == .FitWindow {
      aspect_img := f32(entry.image_size.x) / f32(entry.image_size.y)
      aspect_wnd := f32(window.window_size.x) / f32(window.window_size.y)

      if aspect_img > aspect_wnd {
        window.zoom_factor = f32(window.window_size.x) / f32(entry.image_size.x)
      } else {
        window.zoom_factor = f32(window.window_size.y) / f32(entry.image_size.y)
      }
    }

    window.pending_auto_fit = false
    window.pending_title_refresh = true
  }

  if window.pending_title_refresh {
    app_window_refresh_title(window)
  }

  // _app_window_file_entry_update(window, entry)

  sdl3.SetRenderDrawColor(window.renderer, 38, 38, 38, 255)
  sdl3.RenderClear(window.renderer)

  if entry != nil {
    #partial switch entry.state {
      case .Loading: {
        sdl3.SetRenderDrawColor(window.renderer, 255, 255, 255, 255)
        sdl3.RenderDebugText(window.renderer, 200, 200, "Loading...")
      }

      case .Failed: {
        sdl3.SetRenderDrawColor(window.renderer, 255, 255, 255, 255)
        sdl3.RenderDebugText(window.renderer, 100, 100, "Failed to load file")
      }

      case .Loaded: {
        if entry != nil && entry.texture != nil {
          render_size: [2]f32 = {
            f32(entry.image_size.x) * window.zoom_factor,
            f32(entry.image_size.y) * window.zoom_factor,
          }

          render_rect := sdl3.FRect {
            x = (f32(window.window_size.x) - render_size.x) * .5 + window.render_offset.x,
            y = (f32(window.window_size.y) - render_size.y) * .5 + window.render_offset.y,
            w = render_size.x,
            h = render_size.y,
          }
          sdl3.RenderTexture(window.renderer, entry.texture, nil, &render_rect)
        }
      }
    }
  } else {
    sdl3.SetRenderDrawColor(window.renderer, 255, 255, 255, 255)
    sdl3.RenderDebugText(window.renderer, 200, 200, "Not loaded")
  }

  sdl3.RenderPresent(window.renderer)
}

app_window_reset_view :: proc(window: ^AppWindow, fit_mode: AutoFitMode) {
  window.zoom_factor = 1.0
  window.is_panning = false
  window.position_offset = {0, 0}
  window.pending_auto_fit = true
  window.next_fit_mode = fit_mode
}

app_window_toggle_only_favorites :: proc(window: ^AppWindow) {
  assert(window != nil)
  window.folder_settings.only_favorites = !window.folder_settings.only_favorites
  _app_window_refresh_shown_files(window)
  window.pending_folder_settings_save = true
}
