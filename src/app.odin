package monokl

import "core:os"
import "core:log"
import "core:strings"
import "vendor:sdl3"
import sdli "vendor:sdl3/image"

App :: struct {
  windows: map[sdl3.WindowID]AppWindow,
  dropped_files: map[sdl3.WindowID][dynamic]string,
  image_cache: ImageCache,
}

MOD_KEY_MASK: sdl3.Keymod = {.LSHIFT, .RSHIFT, .LALT, .RALT, .LCTRL, .RCTRL, .LGUI, .RGUI}

app: App

is_key_down :: proc(event: sdl3.Event, key: sdl3.Keycode, mods: sdl3.Keymod) -> bool {
  return event.type == .KEY_DOWN && event.key.key == key && (event.key.mod & MOD_KEY_MASK == mods)
}

app_init :: proc() -> Error {
  if !sdl3.Init({.VIDEO, .EVENTS}) {
    return sdl_last_error("Failed to initialize app")
  }

  app.windows = make(map[sdl3.WindowID]AppWindow)
  app.dropped_files = make(map[sdl3.WindowID][dynamic]string)

  image_cache_init(&app.image_cache)

  app_window_open() or_return

  return nil
}

app_destroy :: proc() {
  if app.windows != nil {
    ids := make([dynamic]sdl3.WindowID)
    defer delete(ids)
    for id, _ in app.windows {
      append(&ids, id)
    }
    for id in ids {
      app_close_window(id)
    }
    delete(app.windows)
    app.windows = nil
  }

  if app.dropped_files != nil {
    for _, files in app.dropped_files {
      for file in files {
        delete(file)
      }
      delete(files)
    }
    delete(app.dropped_files)
    app.dropped_files = nil
  }

  image_cache_destroy(&app.image_cache)

  sdl3.Quit()
}

app_run :: proc() -> Error {
  app_init() or_return
  defer app_destroy()

  event: sdl3.Event
  for len(app.windows) > 0 {
    for sdl3.PollEvent(&event) {

      #partial switch event.type {
        case .KEY_DOWN, .KEY_UP: {
          if event.key.windowID in app.windows {
            app_window_handle_event(&app.windows[event.key.windowID], event)
          }
        }

        case .MOUSE_WHEEL, .MOUSE_MOTION: {
          if event.wheel.windowID in app.windows {
            app_window_handle_event(&app.windows[event.wheel.windowID], event)
          }
        }

        case .MOUSE_BUTTON_UP, .MOUSE_BUTTON_DOWN: {
          if event.button.windowID in app.windows {
            app_window_handle_event(&app.windows[event.button.windowID], event)
          }
        }

        case .WINDOW_FIRST..=.WINDOW_LAST: {
          if event.window.windowID in app.windows {
            app_window_handle_event(&app.windows[event.window.windowID], event)
          }
        }

        case .DROP_BEGIN:
          if event.drop.windowID not_in app.dropped_files {
            app.dropped_files[event.drop.windowID] = make([dynamic]string)
          }

        case .DROP_FILE:
          if event.drop.windowID in app.dropped_files {
            filename := strings.clone_from_cstring(event.drop.data)
            append(&app.dropped_files[event.drop.windowID], filename)
          }

        case .DROP_COMPLETE: {
          if event.drop.windowID in app.dropped_files {
            files := app.dropped_files[event.drop.windowID]

            app_open_file_paths(files[:])

            for file in files {
              delete(file)
            }
            defer delete(files)
            delete_key(&app.dropped_files, event.drop.windowID)
          }
        }
      }
    }

    for _, &window in &app.windows {
      app_window_update(&window)
    }
  }

  return nil
}

app_is_supported_file :: proc(full_path: string) -> bool {
  ext := strings.to_lower(os.ext(full_path))
  defer delete(ext)
  return ext == ".jpg" || ext == ".jpeg" || ext == ".png" || ext == ".bmp"
}

app_open_file_paths :: proc(file_paths: []string) -> Error {
  folders_and_files := make(map[string]string)
  defer delete(folders_and_files)

  for full_path in file_paths {
    if os.is_file(full_path) {
      folder_path := os.dir(full_path)
      folders_and_files[folder_path] = full_path
    }

    if os.is_dir(full_path) {
      if full_path not_in folders_and_files {
        folders_and_files[full_path] = ""
      }
    }
  }

  for folder_path, focused_file in folders_and_files {
    maybe_focused_file: Maybe(string) = focused_file if focused_file != "" else nil
    target_window: ^AppWindow
    first_empty: ^AppWindow
    for _, &window in &app.windows {
      if !window.loaded {
        if first_empty == nil {
          first_empty = &window
        }
        continue
      }

      if strings.compare(window.folder_path, folder_path) == 0 {
        target_window = &window
        break
      }
    }

    if target_window == nil && first_empty != nil {
      target_window = first_empty
    }

    if target_window == nil {
      id := app_window_open(folder_path, maybe_focused_file) or_return
      target_window = &app.windows[id]
    } else {
      app_window_load_folder(target_window, folder_path, maybe_focused_file)
    }
  }

  return nil
}

app_close_window :: proc(id: sdl3.WindowID) {
  if id not_in app.windows {
    return
  }

  window := &app.windows[id]

  app_window_destroy(window)

  delete_key(&app.windows, id)
}

app_request_load_files :: proc(window_id: sdl3.WindowID, full_paths: []string) {
  image_cache_request_load(&app.image_cache, window_id, full_paths)
}

app_on_image_load_finished :: proc(result: ImageLoadResultItem) {
  wnd, ok := &app.windows[result.window_id]
  if ok {
    app_window_on_image_load_finished(wnd, result.image)
  }
}
