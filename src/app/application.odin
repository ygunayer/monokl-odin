package app

import "core:mem"
import "core:log"
import "core:time"
import "vendor:sdl3"

Application :: struct {
  windows: map[WindowId]^Window,
  action_mappings: []ActionMapping,
  window_focus_stack: WindowIdStack,
}

Application_InitError :: struct {
  message: string,
}

Application_Error :: union {
  Window_Error,
  Application_InitError,
}

application_init :: proc(app: ^Application) -> Application_Error {
  app.windows = make(map[WindowId]^Window)

  action_mappings := get_action_mappings()
  app.action_mappings = action_mappings[:]

  init_success := sdl3.Init(sdl3.INIT_VIDEO)
  if !init_success {
    return Application_InitError { message = string(sdl3.GetError()) }
  }

  application_create_window(app)

  return nil
}

application_create_window :: proc(app: ^Application) -> (w: ^Window, err: Window_Error) {
  window, e := window_init_after(application_get_last_focused_window(app))
  if e != nil {
    return nil, e
  }

  app.windows[window.id] = window
  log.debugf("Window %d created on display %d", window.id, window.display_id)
  return window, e
}

application_get_last_focused_window :: proc(app: ^Application) -> ^Window {
  id, ok := window_id_stack_peek(&app.window_focus_stack)

  if !ok {
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

  window_id_stack_delete(&app.window_focus_stack, window_id)

  window := app.windows[window_id]
  window_destroy(window)
  delete_key(&app.windows, window_id)

  log.debugf("Window %d closed", window_id)
}

application_handle_event :: proc(app: ^Application, event: sdl3.Event) {
  if event.type == .WINDOW_CLOSE_REQUESTED {
    application_close_window(app, event.window.windowID)
  }

  translated_event, is_translated := event_translate(event, app.action_mappings).?
  if is_translated {
    #partial switch e in translated_event {
      case WindowEvent: {
        if e.window_id in app.windows {
          window := app.windows[e.window_id]
          window_handle_event(window, e)

          if e.type == .GainedFocus {
            window_id_stack_push(&app.window_focus_stack, window.id)
          }
        }
      }

      case ActionEvent: {
        if e.action.type == .CloseWindow {
          application_close_window(app, e.window_id)
        }

        if e.action.type == .OpenNewWindow {
          application_create_window(app)
        }
      }
    }
  }
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

  window_id_stack_destroy(&app.window_focus_stack)

  for _, wnd in app.windows {
    window_destroy(wnd)
  }

  delete(app.windows)

  delete(app.action_mappings)

  free(app)
}
