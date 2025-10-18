package monokl

import "core:log"

App :: struct {
  windows: map[WindowId]AppWindow,
}

app_init :: proc(app: ^App) -> Error {
  assert(app != nil)
  app.windows = make(map[WindowId]AppWindow)
  return nil
}

app_run :: proc(app: ^App) -> Error {
  assert(app != nil)

  app_create_window(app, AppWindow_CreateEmpty{}) or_return

  // for len(app.windows) > 0 {
  //   platform_dispatch_events()
  // }

  return nil
}

app_create_window :: proc(app: ^App, create_args: AppWindowCreateArgs) -> Error {
  assert(app != nil)

  window_id, err := platform_create_window(1366, 768, "monokl")
  if err != nil {
    return err
  }

  app.windows[window_id] = AppWindow {
    window = window_id,
  }
  // TODO poppulate form args

  err = app_window_init(&app.windows[window_id])
  if err != nil {
    platform_close_window(window_id)
    return err
  }

  log.debugf("App window created window_id=%d", window_id)

  return nil
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
