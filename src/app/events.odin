package app

import sdl "vendor:sdl3"

WindowEventType :: enum {
  Maximized,
  Minimized,
  Restored,
  GainedFocus,
  LostFocus,
  Resized,
  Moved,
}

WindowEvent :: struct {
  window_id: WindowId,
  type: WindowEventType,
}

ActionEvent :: struct {
  window_id: WindowId,
  action: Action,
}

Event :: union {
  ActionEvent,
  WindowEvent,
}

event_translate :: proc(event: sdl.Event, mappings: []ActionMapping) -> Maybe(Event) {
  #partial switch event.type {
    case .WINDOW_MAXIMIZED:
      return (WindowEvent) {
        type = .Maximized,
        window_id = event.window.windowID,
      }

    case .WINDOW_MINIMIZED:
      return (WindowEvent) {
        type = .Minimized,
        window_id = event.window.windowID,
      }

    case .WINDOW_RESTORED:
      return (WindowEvent) {
        type = .Restored,
        window_id = event.window.windowID,
      }

    case .WINDOW_FOCUS_LOST:
      return (WindowEvent) {
        type = .LostFocus,
        window_id = event.window.windowID,
      }

    case .WINDOW_FOCUS_GAINED:
      return (WindowEvent) {
        type = .GainedFocus,
        window_id = event.window.windowID,
      }

    case .WINDOW_RESIZED:
      return (WindowEvent) {
        type = .Resized,
        window_id = event.window.windowID,
      }

    case .WINDOW_MOVED:
      return (WindowEvent) {
        type = .Moved,
        window_id = event.window.windowID,
      }

    case .KEY_DOWN: {
      for mapping in mappings {
        if action_mapping_matches_event(mapping, event) {
          return (ActionEvent) {
            action = Action {
              type = mapping.type,
            },
            window_id = event.window.windowID,
          }
        }
      }
    }
  }
  return nil
}
