package monokl

import "core:os"
import "core:log"
import "core:path/filepath"
import "vendor:sdl3"

Ui :: struct {
  window: ^Window,

  viewport: Viewport,
  playlist: Playlist,
  main_image: SceneObject_Image,

  dropping_files: bool,
  dropped_files: [dynamic]string,
}

Theme :: struct {
  background_color: sdl3.FColor,
  text_color: sdl3.FColor,
  text_background_color: sdl3.FColor,
}

Theme_Light :: Theme {
  background_color = sdl3.FColor { .76, .76, .76, 1 },
  text_color = sdl3.FColor { .34, .34, .34, 1 },
  text_background_color = sdl3.FColor { 0, 0, 0, 0 }
}

Theme_Dark :: Theme {
  background_color = sdl3.FColor { .192, .192, .192, 1 },
  text_color = sdl3.FColor { 1, 1, 1, 1 },
  text_background_color = sdl3.FColor { 0, 0, 0, 0 }
}

get_system_theme :: proc() -> Theme {
  if sdl3.GetSystemTheme() == .DARK {
    return Theme_Dark
  }

  return Theme_Light
}

ui_init :: proc(ui: ^Ui, window: ^Window) {
  ui.window = window
  viewport_init(&ui.viewport, window.renderer, window.size, settings_get_theme(&window.app.settings))
  playlist_init(&ui.playlist)

  event_bus_subscribe(&window.app.event_bus, ui, ui_handle_event, { .WindowResized })
}

ui_set_theme :: proc(ui: ^Ui, theme: Theme) {
  ui.viewport.theme = theme
}

ui_reload_image :: proc(ui: ^Ui) {
  
}

ui_handle_event :: proc(ui: ^Ui, event: Event) -> bool {
  #partial switch event.type {
    case .WindowResized: {
      sdl3.GetWindowSizeInPixels(ui.window.wnd, &ui.viewport.size.x, &ui.viewport.size.y)
      log.debugf("Viewport resized: %v", ui.viewport.size)
    }
  }

  return true
}

ui_render :: proc(ui: ^Ui) {
  viewport_render(&ui.viewport)
}

ui_unload_playlist :: proc(ui: ^Ui) {
  playlist_destroy(&ui.playlist)
  ui.playlist = {}
}

ui_load_playlist :: proc(ui: ^Ui, paths: []string) -> Playlist_Error {
  ui_unload_playlist(ui)

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
      ui.playlist = pl
      is_first = false
      continue
    }

    new_window, window_err := app_create_window(ui.window.app)
    if window_err != nil {
      log.warnf("Failed to create a new window to open playlist %s due to %v", parent, window_err)
    } else {
      new_window.ui.playlist = pl
    }
  }

  return nil
}


ui_destroy :: proc(ui: ^Ui) {
  if ui == nil {
    return
  }

  playlist_destroy(&ui.playlist)

  viewport_destroy(&ui.viewport)
}