package monokl

import "core:os"
import "core:path/filepath"
import "core:log"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:strings"
import "vendor:sdl3"

FileEntry :: struct {
  full_path: string,
  filename: string, // borrowed
  texture: ^sdl3.Texture, // owned
  image: ^Image, // borrowed

  state: ImageLoadState,

  is_favorite: bool,
  t_created: time.Time,
  t_last_modified: time.Time,
  t_last_accessed: time.Time,
}

AppWindow :: struct {
  id: sdl3.WindowID,
  handle: ^sdl3.Window,
  renderer: ^sdl3.Renderer,

  loaded: bool,
  folder_path: string,
  all_files: [dynamic]FileEntry,
  shown_files: [dynamic]int, // sorted & filtered indexes to `all_files`
  current_pos: int, // current position in `shown_files`

  current_entry: ^FileEntry, // borrowed
}

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
    all_files = make([dynamic]FileEntry),
    shown_files = make([dynamic]int),
  }

  return id, nil
}

app_window_open_at_folder :: proc(folder_path: string) -> (sdl3.WindowID, Error) {
  id, err := app_window_open_empty()
  if err != nil {
    return 0, err
  }
  window := &app.windows[id]
  app_window_load_folder(window, folder_path)
  return id, nil
}

app_window_load_folder :: proc(window: ^AppWindow, full_path: string) -> Error {
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

  window.loaded = true
  window.folder_path = strings.clone(full_path)
  sdl3.SetWindowTitle(window.handle, fmt.ctprintf("monokl - %s", full_path))

  next_idx := 0
  files_to_load := make([dynamic]string)
  for file_info in file_infos {
    if !app_is_supported_file(file_info.fullpath) {
      continue
    }

    full_file_path := strings.clone(file_info.fullpath)
    filename := os.base(full_file_path)

    append(&files_to_load, full_file_path)
    append(&window.shown_files, next_idx)

    next_idx += 1

    append(&window.all_files, FileEntry {
      full_path = full_file_path,
      filename = filename,
      t_created = file_info.creation_time,
      t_last_accessed = file_info.access_time,
      t_last_modified = file_info.modification_time,
      texture = nil,
      is_favorite = false, // TODO
    })
  }

  if len(files_to_load) > 0 {
    app_request_load_files(files_to_load[:])
  }

  log.debugf("Window %d opened folder %s with %d files (%d shown)", window.id, full_path, len(window.all_files), len(window.shown_files))

  return nil
}

app_window_unload_folder :: proc(window: ^AppWindow) -> Error {
  assert(window != nil)
  if !window.loaded {
    return nil
  }

  delete(window.folder_path)
  delete(window.shown_files)

  if window.all_files != nil {
    for entry in window.all_files {
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

  if window.renderer != nil {
    sdl3.DestroyRenderer(window.renderer)
    window.renderer = nil
  }

  if window.handle != nil {
    sdl3.DestroyWindow(window.handle)
  }
}

app_window_go_to_file :: proc(window: ^AppWindow, full_path: string) {
  log.debugf("Window navigating to image %s", full_path)
  for idx in window.shown_files {
    entry := &window.all_files[idx]
    if entry.full_path == full_path {
      window.current_pos = idx
      window.current_entry = entry
      return
    }
  }
}

app_window_advance :: proc(window: ^AppWindow, by: int) {
  num_entries := len(window.shown_files)
  if num_entries == 0 {
    return
  }
  new_idx := window.current_pos + by
  for new_idx < 0 {
    new_idx += num_entries
  }
  new_idx = new_idx % num_entries
  window.current_pos = new_idx
  window.current_entry = &window.all_files[window.shown_files[new_idx]]
}

_app_window_file_entry_update :: proc(window: ^AppWindow, entry: ^FileEntry) {
  if entry == nil {
    return
  }

  if entry.image == nil {
    image, ok := app_get_image_entry(entry.full_path)
    if ok {
      entry.image = image
    }
  }

  if entry.image == nil || entry.image.surface == nil {
    entry.state = .Loading
    return
  }

  if entry.state == .Failed || entry.state == .Loaded {
    return
  }

  texture := sdl3.CreateTextureFromSurface(window.renderer, entry.image.surface)
  if texture == nil {
    log.warnf("Failed to convert image to texture: %v", sdl_last_error("Reason"))
    entry.state = .Failed
    return
  }

  entry.texture = texture
  entry.state = .Loaded
  log.debugf("Successfully created texture for file %s", entry.full_path)
}

app_window_handle_event :: proc(window: ^AppWindow, event: sdl3.Event) {
  #partial switch event.type {
    case .KEY_DOWN: {
      if is_key_down(event, sdl3.K_LEFT, {}) {
        app_window_advance(window, -1)
      }

      if is_key_down(event, sdl3.K_RIGHT, {}) {
        app_window_advance(window, 1)
      }
    }
  }
}

app_window_update :: proc(window: ^AppWindow) {
  entry: ^FileEntry = window.current_entry
  _app_window_file_entry_update(window, entry)

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
          sdl3.RenderTexture(window.renderer, entry.texture, nil, nil)
        }
      }
    }
  } else {
    sdl3.SetRenderDrawColor(window.renderer, 255, 255, 255, 255)
    sdl3.RenderDebugText(window.renderer, 200, 200, "Not loaded")
  }

  sdl3.RenderPresent(window.renderer)
}
