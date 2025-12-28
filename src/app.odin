package monokl

import "core:c"
import "core:log"
import "core:mem"
import "core:strings"
import "core:container/queue"
import "base:runtime"

App :: struct {
  windows: map[WindowId]AppWindow,
  next_id: int,
  base_ticks: f64,
  temp_allocator: ^mem.Tracking_Allocator,
}

app_init :: proc(app: ^App) -> Error {
  assert(app != nil)
  app.windows = make(map[WindowId]AppWindow)
  app.next_id = 1
  return nil
}

app_run :: proc(app: ^App) -> Error {
  assert(app != nil)

  app_create_window(app) or_return

  app.base_ticks = platform_get_ticks()

  windows_to_close := make([dynamic]WindowId)
  defer delete(windows_to_close)

  for {
    defer platform_poll_events()
    defer free_all(context.temp_allocator)

    num_windows := len(app.windows)
    last_tick := platform_get_ticks()

    for id in app.windows {
      app_window := &app.windows[id]
      delta := platform_get_ticks() - last_tick
      app_window_update(app_window, delta)
      if app_window.close_requested {
        append(&windows_to_close, id)
      }
    }

    if len(windows_to_close) > 0 {
      for id in windows_to_close {
        app_window := &app.windows[id]
        app_window_destroy(app_window)
        delete_key(&app.windows, id)
      }

      clear(&windows_to_close)
    }

    if num_windows < 1 {
      break
    }
  }

  return nil
}

app_create_window :: proc(app: ^App) -> (^AppWindow, Error) {
  assert(app != nil)

  window, err := platform_create_window(1366, 768, "monokl")
  if err != nil {
    return nil, err
  }

  id := app.next_id
  app.next_id += 1 // TODO(concurrency): maybe make this use a mutex

  app.windows[id] = AppWindow {
    app = app,
    id = id,
    wnd = window,
  }

  err = app_window_init(&app.windows[id])
  if err != nil {
    app_window_destroy(&app.windows[id])
    delete_key(&app.windows, id)
    return nil, err
  }

  log.debugf("App window created #%d", id)
  return &app.windows[id], nil
}

app_destroy :: proc(app: ^App) {
  if app == nil {
    return
  }

  if app.windows != nil {
    for window in app.windows {
      app_window_destroy(&app.windows[window])
    }
    delete(app.windows)
    app.windows = nil
  }
}
