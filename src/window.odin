package monokl

import "core:strings"
import "vendor:sdl3"
import "core:mem"
import "core:log"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:math"

Vector2i :: [2]i32
WindowId :: sdl3.WindowID
DisplayId :: sdl3.DisplayID

WindowSize_Default :: (Vector2i) { 1366, 768 }

WindowPosition_Undefined :: (Vector2i) { sdl3.WINDOWPOS_UNDEFINED, sdl3.WINDOWPOS_UNDEFINED }
WindowPosition_Centered :: (Vector2i) { sdl3.WINDOWPOS_CENTERED, sdl3.WINDOWPOS_CENTERED }

WindowOptions :: struct {
  initial_position: Vector2i,
  initial_size: Vector2i,
  maximized: bool,
}

Window :: struct {
  app: ^Application,
  id: sdl3.WindowID,
  display_id: sdl3.DisplayID,
  renderer: ^sdl3.Renderer,
  wnd: ^sdl3.Window,
  size: Vector2i,
  position: Vector2i,
  maximized: bool,
  has_focus: bool,
  playlist: Playlist,
  dropping_files: bool,
  dropped_files: [dynamic]string,
  ui: Ui,
  event_bus: ^EventBus,
  event_sub_id: SubscriberId,
}

window_init_from_scratch :: proc(app: ^Application) -> (w: ^Window, error: Window_Error) {
  options := WindowOptions {
    initial_position = WindowPosition_Centered,
    initial_size = WindowSize_Default,
    maximized = false,
  }
  return window_init_with_settings(app, options)
}

window_init_after :: proc(app: ^Application, previous: ^Window) -> (w: ^Window, error: Window_Error) {
  if previous == nil || previous.wnd == nil {
    return window_init_from_scratch(app)
  }

  options := WindowOptions {
    initial_position = WindowPosition_Centered,
    initial_size = WindowSize_Default,
    maximized = false,
  }

  display_mode := sdl3.GetCurrentDisplayMode(previous.display_id)

  bl, bt, br, bb: i32
  sdl3.GetWindowBordersSize(previous.wnd, &bt, &bl, &bb, &br)

  log.debugf("Display Mode: %p > %v", display_mode, display_mode)
  effective_width := display_mode.w - bl - br
  effective_height := display_mode.h - bt - bb

  x := previous.position.x
  y := previous.position.y

  x += 30 if bl < 30 else bl
  y += 30 if bt < 30 else bt

  if ((x + options.initial_size.x) >= effective_width) || ((y + options.initial_size.y) >= effective_height) {
    x = bl
    y = bt
  }

  options.initial_position = Vector2i { x, y }

  return window_init_with_settings(app, options)
}

window_init_with_settings :: proc(app: ^Application, options: WindowOptions) -> (w: ^Window, error: Window_Error) {
  flags := sdl3.WINDOW_RESIZABLE

  if options.maximized {
    flags |= sdl3.WINDOW_MAXIMIZED
  }

  wnd: ^sdl3.Window
  renderer: ^sdl3.Renderer
  sdl3.CreateWindowAndRenderer(
    cstring("monokl"),
    options.initial_size.x,
    options.initial_size.y,
    sdl3.WINDOW_RESIZABLE,
    &wnd,
    &renderer,
  )

  if wnd == nil || renderer == nil {
    return nil, make_sdl_error(sdl3.GetError())
  }

  window := new(Window)
  if window == nil {
    defer sdl3.DestroyRenderer(renderer)
    defer sdl3.DestroyWindow(wnd)
    return nil, mem.Allocator_Error.Out_Of_Memory
  }

  window.app = app
  window.id = sdl3.GetWindowID(wnd)
  window.display_id = sdl3.GetDisplayForWindow(wnd)
  window.wnd = wnd
  window.renderer = renderer
  sdl3.SetWindowPosition(wnd, options.initial_position.x, options.initial_position.y)

  sdl3.GetWindowSize(wnd, &window.size.x, &window.size.y)
  sdl3.GetWindowPosition(wnd, &window.position.x, &window.position.y)

  window.playlist = {}
  playlist_init(&window.playlist)

  theme := settings_get_theme(&app.settings)
  ui_init(&window.ui, renderer, window.size, &window.playlist, theme)

  return window, nil
}

window_init :: proc {
  window_init_from_scratch,
  window_init_after,
  window_init_with_settings,
}

window_destroy :: proc(window: ^Window) {
  window_unload_playlist(window)

  delete(window.dropped_files)

  ui_destroy(&window.ui)

  event_bus_unsubscribe(window.event_bus, window.event_sub_id)

  if window.renderer != nil {
    sdl3.DestroyRenderer(window.renderer)
    window.renderer = nil
  }

  if window.wnd != nil {
    sdl3.DestroyWindow(window.wnd)
    window.wnd = nil
  }

  free(window)
}

window_update_title :: proc(window: ^Window) {
  if window == nil {
    return
  }

  item := playlist_get_current_entry(&window.playlist)
  if item == nil {
    sdl3.SetWindowTitle(window.wnd, "monokl - No images")
    return
  }

  title_string := strings.clone_to_cstring(fmt.tprintf(
    "monokl - %s%d/%d - %s",
    "♥" if item.is_favorited else "",
    window.playlist.current_index + 1,
    window.playlist.entry_count,
    item.filename,
  ), allocator = context.temp_allocator)

  sdl3.SetWindowTitle(window.wnd, title_string)
}

window_render :: proc(window: ^Window) {
  window_update_title(window)
  ui_render(&window.ui)
}

window_unload_playlist :: proc(window: ^Window) {
  playlist_destroy(&window.playlist)
  window.playlist = {}
}

window_load_playlist :: proc(window: ^Window, paths: []string) -> Playlist_Error {
  window_unload_playlist(window)

  folders := make(map[string][dynamic]os.File_Info, context.temp_allocator)

  for path in paths {
    if os.is_dir(path) {
      map_insert(&folders, path, make([dynamic]os.File_Info, context.temp_allocator))
    } else {
      parent_path := filepath.dir(path, context.temp_allocator)

      info, err := os.lstat(path, context.temp_allocator)
      if err != nil {
        log.warnf("Failed to read file information for %s", path)
        continue
      }

      if !(parent_path in folders) {
        map_insert(&folders, parent_path, make([dynamic]os.File_Info, context.temp_allocator))
      }

      append(&folders[parent_path], info)
    }
  }

  log.debugf("Opening folders %v", folders)

  if len(paths) < 1 {
    return nil
  }

  is_first := true
  for parent in folders {
    children := folders[parent]

    pl: Playlist = {}
    err: Playlist_Error

    switch len(children) {
      case 0:
        err = playlist_open_path(&pl, parent)

      case 1: {
        err = playlist_open_path(&pl, parent)
        if err != nil {
          playlist_go_to_filename(&pl, children[0].name)
        }
      }

      case:
        err = playlist_open_files(&pl, parent, children[:])
    }

    if err != nil {
      log.warnf("Failed to open playlist at %s due to %v", parent, err)
      continue
    }

    if is_first {
      window.playlist = pl
      is_first = false
      continue
    }

    new_window, window_err := application_create_window(window.app)
    if window_err != nil {
      log.warnf("Failed to create a new window to open playlist %s due to %v", parent, window_err)
    } else {
      new_window.playlist = pl
    }
  }

  return nil
}
