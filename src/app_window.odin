package monokl

AppWindow :: struct {
  window: WindowId,
}

AppWindow_CreateEmpty :: struct {}

AppWindowCreateArgs :: union {
  AppWindow_CreateEmpty,
}

app_window_init :: proc(app_window: ^AppWindow) -> Error {
  assert(app_window != nil)
  return nil
}

app_window_destroy :: proc(app_window: ^AppWindow) {
  if app_window == nil {
    return
  }
}
