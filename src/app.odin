package monokl

import "core:os"
import "core:log"
import "core:strings"
import "vendor:sdl3"
import sdli "vendor:sdl3/image"

App :: struct {
  windows: map[sdl3.WindowID]Window,
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

  app.windows = make(map[sdl3.WindowID]Window)
  app.dropped_files = make(map[sdl3.WindowID][dynamic]string)

  image_cache_init(&app.image_cache)

  app_open_window() or_return

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
        case .WINDOW_CLOSE_REQUESTED:
          app_close_window(event.window.windowID)

        case .KEY_DOWN: {
          if !event.key.repeat && is_key_down(event, sdl3.K_N, {.LCTRL}) {
            app_open_window();
          }
          if !event.key.repeat && is_key_down(event, sdl3.K_W, {.LCTRL}) {
            app_close_window(event.window.windowID);
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

    for _, window in &app.windows {
      sdl3.SetRenderDrawColor(window.rnd, 38, 38, 38, 255)
      sdl3.RenderClear(window.rnd)

      sdl3.RenderPresent(window.rnd)
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
    target_window: ^Window
    first_empty: ^Window
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
      id := app_open_window(folder_path) or_return
      target_window = &app.windows[id]
    } else {
      window_load_folder(target_window, folder_path)
    }

    if focused_file != "" {
      window_go_to_file(target_window, focused_file)
    }
  }

  return nil
}

app_open_window :: proc {
  app_open_window_empty,
  app_open_window_at_folder,
}

app_open_window_empty :: proc() -> (sdl3.WindowID, Error) {
  wnd: ^sdl3.Window
  rnd: ^sdl3.Renderer

  if !sdl3.CreateWindowAndRenderer("monokl", 1920, 1080, {.RESIZABLE}, &wnd, &rnd) {
    return 0, sdl_last_error("Failed to create window")
  }

  sdl3.SetWindowPosition(wnd, sdl3.WINDOWPOS_CENTERED, sdl3.WINDOWPOS_CENTERED)
  sdl3.ShowWindow(wnd)

  id := sdl3.GetWindowID(wnd)

  app.windows[id] = Window {
    id = id,
    rnd = rnd,
    wnd = wnd,
  }

  return id, nil
}

app_open_window_at_folder :: proc(folder_path: string) -> (sdl3.WindowID, Error) {
  id, err := app_open_window_empty()
  if err != nil {
    return 0, err
  }
  window := &app.windows[id]
  window_load_folder(window, folder_path)
  return id, nil
}

app_close_window :: proc(id: sdl3.WindowID) {
  if id not_in app.windows {
    return
  }

  window := &app.windows[id]

  window_unload_folder(window)

  sdl3.DestroyWindow(window.wnd)
  sdl3.DestroyRenderer(window.rnd)

  delete_key(&app.windows, id)
}
