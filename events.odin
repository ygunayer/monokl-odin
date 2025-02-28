package monokl

import sdl "vendor:sdl3"

BaseEvent :: struct {
  window_id: WindowId,
}

WindowEventType :: enum {
  Created,
  GainedFocus,
  LostFocus,
  Resized,
  CloseRequested,
  Maximized,
  Minimized,
  Restored,
}

WindowEvent :: struct {
  using event: BaseEvent,
  type: WindowEventType,
}

ActionEvent :: struct {
  using event: BaseEvent,
  action: Action,
}

Event :: union {
  WindowEvent,
}

EventHandler :: ^proc(event: Event)
HandlerId :: distinct u32

EventBus :: struct {
  next_id: HandlerId,
  handlers: map[HandlerId]EventHandler,
}

event_bus_init :: proc() -> EventBus {
  bus: EventBus
  bus.next_id = 1
  bus.handlers = make(map[HandlerId]EventHandler)
  return bus
}

event_bus_subscribe :: proc(bus: ^EventBus, handler: EventHandler) -> HandlerId {
  assert(bus != nil, "nil bus instance passed to function")
  assert(handler != nil, "nil handler instance passed to function")
  id := bus.next_id
  bus.handlers[id] = handler
  bus.next_id += 1
  return id
}

event_bus_unsubscribe :: proc(bus: ^EventBus, id: HandlerId) {
  assert(bus != nil, "nil bus instance passed to function")
  if id in bus.handlers {
    delete_key(&bus.handlers, id)
  }
}

event_bus_publish :: proc(bus: ^EventBus, event: Event) {
  invalid_ids: [dynamic]HandlerId
  for id, handler in bus.handlers {
    if handler != nil {
      handler^(event)
    } else {
      append(&invalid_ids, id)
    }
  }
  if len(invalid_ids) > 0 {
    for id in invalid_ids {
      delete_key(&bus.handlers, id)
    }
  }
}

event_bus_destroy :: proc(bus: ^EventBus) {
  if bus == nil {
    return
  }

  delete(bus.handlers)
  bus.handlers = nil
  bus.next_id = 0
}

event_bus_translate :: proc(event: ^sdl.Event) -> Maybe(Event) {
  #partial switch event.type {
    case .WINDOW_MAXIMIZED:
      return (WindowEvent) {
        type = .Maximized,
        window_id = event.window.windowID,
      }

    case .WINDOW_CLOSE_REQUESTED:
      return (WindowEvent) {
        type = .CloseRequested,
        window_id = event.window.windowID,
      }
  }
  return nil
}
