package app

import "vendor:sdl3"

WindowEventType :: enum {
  Maximized,
  Minimized,
  Restored,
  GainedFocus,
  LostFocus,
  Resized,
  Moved,
}

DropEventType :: enum {
  Begin,
  DropFile,
  End,
}

WindowEvent :: struct {
  window_id: WindowId,
  type: WindowEventType,
}

ActionEvent :: struct {
  window_id: WindowId,
  action: Action,
}

DropEvent :: struct {
  window_id: WindowId,
  type: DropEventType,
  file: string,
}

Event :: union {
  ActionEvent,
  WindowEvent,
  DropEvent,
}

event_translate :: proc(event: sdl3.Event, mappings: []ActionMapping) -> Maybe(Event) {
  #partial switch event.type {
    case .WINDOW_MAXIMIZED:
      return WindowEvent {
        window_id = event.window.windowID,
        type = .Maximized,
      }

    case .WINDOW_MINIMIZED:
      return WindowEvent {
        window_id = event.window.windowID,
        type = .Minimized,
      }

    case .WINDOW_RESTORED:
      return WindowEvent {
        window_id = event.window.windowID,
        type = .Restored,
      }

    case .WINDOW_FOCUS_LOST:
      return WindowEvent {
        window_id = event.window.windowID,
        type = .LostFocus,
      }

    case .WINDOW_FOCUS_GAINED:
      return WindowEvent {
        window_id = event.window.windowID,
        type = .GainedFocus,
      }

    case .WINDOW_RESIZED:
      return WindowEvent {
        window_id = event.window.windowID,
        type = .Resized,
      }

    case .WINDOW_MOVED:
      return WindowEvent {
        window_id = event.window.windowID,
        type = .Moved,
      }

    case .DROP_BEGIN:
      return DropEvent {
        window_id = event.drop.windowID,
        type = .Begin,
      }

    case .DROP_COMPLETE:
      return DropEvent {
        window_id = event.drop.windowID,
        type = .End,
      }

    case .DROP_FILE:
      return DropEvent {
        window_id = event.drop.windowID,
        type = .DropFile,
        file = string(event.drop.data),
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
