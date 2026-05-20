package monokl

import "core:log"
import "core:strings"
import "vendor:sdl3"

Platform :: struct {
  windows: map[sdl3.WindowID]Window,
  dropped_files: map[sdl3.WindowID][dynamic]string,
}

platform: Platform

platform_run :: proc() -> Error {
  platform_init() or_return
  defer platform_destroy()

  event: sdl3.Event
  for len(platform.windows) > 0 {
    for sdl3.PollEvent(&event) {

      #partial switch event.type {
        case .WINDOW_CLOSE_REQUESTED:
          platform_close_window(event.window.windowID)

        case .DROP_BEGIN:
          if event.drop.windowID not_in platform.dropped_files {
            platform.dropped_files[event.drop.windowID] = make([dynamic]string)
          }

        case .DROP_FILE:
          if event.drop.windowID in platform.dropped_files {
            filename := strings.clone_from_cstring(event.drop.data)
            append(&platform.dropped_files[event.drop.windowID], filename)
          }

        case .DROP_COMPLETE: {
          if event.drop.windowID in platform.dropped_files {
            files := platform.dropped_files[event.drop.windowID]

            for file in files {
              delete(file)
            }

            delete(files)
            delete_key(&platform.dropped_files, event.drop.windowID)

            if event.drop.windowID in platform.windows {
              window := &platform.windows[event.drop.windowID]
              window_load_files(window, files[:])
            }
          }
        }
      }
    }

    for _, window in &platform.windows {
      sdl3.SetRenderDrawColor(window.rnd, 38, 38, 38, 255)
      sdl3.RenderClear(window.rnd)

      sdl3.RenderPresent(window.rnd)
    }
  }

  return nil
}

platform_init :: proc() -> Error {
  if !sdl3.Init({.VIDEO, .EVENTS}) {
    return sdl_last_error("Failed to initialize platform")
  }

  platform.windows = make(map[sdl3.WindowID]Window)
  platform.dropped_files = make(map[sdl3.WindowID][dynamic]string)

  platform_open_window() or_return

  return nil
}

platform_destroy :: proc() {
  if platform.windows != nil {
    ids := make([dynamic]sdl3.WindowID)
    defer delete(ids)
    for id, _ in platform.windows {
      append(&ids, id)
    }
    for id in ids {
      platform_close_window(id)
    }
    delete(platform.windows)
    platform.windows = nil
  }

  if platform.dropped_files != nil {
    for _, files in platform.dropped_files {
      for file in files {
        delete(file)
      }
      delete(files)
    }
    delete(platform.dropped_files)
    platform.dropped_files = nil
  }

  sdl3.Quit()
}

platform_open_window :: proc {
  platform_open_window_empty,
  platform_open_window_at_folder,
}

platform_open_window_empty :: proc() -> (sdl3.WindowID, Error) {
  wnd: ^sdl3.Window
  rnd: ^sdl3.Renderer

  if !sdl3.CreateWindowAndRenderer("monokl", 1366, 768, {.RESIZABLE}, &wnd, &rnd) {
    return 0, sdl_last_error("Failed to create window")
  }

  sdl3.SetWindowPosition(wnd, sdl3.WINDOWPOS_CENTERED, sdl3.WINDOWPOS_CENTERED)
  sdl3.ShowWindow(wnd)

  id := sdl3.GetWindowID(wnd)

  platform.windows[id] = Window {
    id = id,
    rnd = rnd,
    wnd = wnd,
  }

  return id, nil
}

platform_open_window_at_folder :: proc(folder_path: string) -> (sdl3.WindowID, Error) {
  id, err := platform_open_window_empty()
  if err != nil {
    return 0, err
  }
  window := &platform.windows[id]
  window_load_folder(window, folder_path)
  return id, nil
}

platform_close_window :: proc(id: sdl3.WindowID) {
  if id not_in platform.windows {
    return
  }

  window := &platform.windows[id]

  window_unload_folder(window)

  sdl3.DestroyWindow(window.wnd)
  sdl3.DestroyRenderer(window.rnd)

  delete_key(&platform.windows, id)
}
