package monokl

import "core:mem"
import "core:log"
import "core:time"
import "core:os"
import "vendor:sdl3"

Application :: struct {
  windows: map[WindowId]^Window,
  settings: Settings,
  window_stack: Stack,
  event_bus: EventBus,
}

application_init :: proc(app: ^Application) -> Application_Error {
  settings, settings_err := settings_load()
  if settings_err != nil {
    log.errorf("Error loading application settings: %v", settings_err)
  }

  app.settings = settings
  app.windows = make(map[WindowId]^Window)
  event_bus_init(&app.event_bus)

  init_success := sdl3.Init(sdl3.INIT_VIDEO)
  if !init_success {
    return Application_InitError { message = string(sdl3.GetError()) }
  }

  window, err := application_create_window(app)
  if err != nil {
    return err
  }

  if len(os.args) > 1 {
    window_load_playlist(window, os.args[1:])
  }

  return nil
}

 application_create_window :: proc(app: ^Application) -> (w: ^Window, err: Window_Error) {
  window, e := window_init_after(app, application_get_last_focused_window(app))
  if e != nil {
    return nil, e
  }

  app.windows[window.id] = window
  log.debugf("Window %d created on display %d", window.id, window.display_id)
  return window, e
}

application_get_last_focused_window :: proc(app: ^Application) -> ^Window {
  id, found := stack_peek(&app.window_stack)

  if !found {
    return nil
  }

  if !(id in app.windows) {
    return nil
  }

  return app.windows[id]
}

application_close_window :: proc(app: ^Application, window_id: WindowId) {
  if !(window_id in app.windows) {
    return
  }

  stack_delete(&app.window_stack, window_id)

  window := app.windows[window_id]
  window_destroy(window)
  delete_key(&app.windows, window_id)

  log.debugf("Window %d closed", window_id)
}

application_handle_event :: proc(app: ^Application, event: sdl3.Event) {
  if event.type == .WINDOW_CLOSE_REQUESTED {
    application_close_window(app, event.window.windowID)
  }

  if event.type == .SYSTEM_THEME_CHANGED {
    if app.settings.theme.type == .System {
      theme := get_system_theme()
      for _, &w in app.windows {
        ui_set_theme(&w.ui, theme)
      }
    }
  }

  translated_event, is_translated := sdl_event_translate(event, &app.settings)
  if !is_translated {
    return
  }

  // TODO
}

application_run_main_loop :: proc(app: ^Application) {
  last_rendered := time.tick_now()
  max_frame_delay := 1000.0 / 60.0

  sdl_event: sdl3.Event
  for {
    if len(app.windows) < 1 {
      break
    }

    has_event := sdl3.PollEvent(&sdl_event)
    if has_event {
      application_handle_event(app, sdl_event)
    }

    elapsed := time.duration_milliseconds(time.tick_since(last_rendered))

    if elapsed >= max_frame_delay {
      last_rendered = time.tick_now()

      for _, w in app.windows {
        window_render(w)
      }
    }

    free_all(context.temp_allocator)
  }

  free_all(context.temp_allocator)
}

application_destroy :: proc(app: ^Application) {
  if app == nil {
    return
  }

  event_bus_destroy(&app.event_bus)

  for _, wnd in app.windows {
    window_destroy(wnd)
  }

  delete(app.windows)

  free(app)
}
