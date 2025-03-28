package monokl

import "core:container/queue"
import "vendor:sdl3"

KeyModMask :: sdl3.Keymod { .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI }

KeyboardActionTrigger :: struct {
  key: sdl3.Keycode,
  ctrl: bool,
  shift: bool,
  alt: bool,
  meta: bool,
}

ActionTrigger :: union {
  KeyboardActionTrigger,
}

ActionMapping :: struct {
  type: ActionType,
  trigger: ActionTrigger,
}

ActionType :: enum {
  Open,
  OpenNewWindow,
  CloseWindow,
  MaximizeWindow,
  MinimizeWindow,
  Favorite,
  Unfavorite,
  ToggleOnlyFavorites,
  GoToNext,
  GoToPrevious,
  GoToFirst,
  GoToLast,
  ZoomIn,
  ZoomOut,
  ResetZoom,
  FitImageToScreen,
}

EventType :: enum {
  PlaylistLoaded,
  PlaylistUnloaded,
  PlaylistPositionChanged,
  PlaylistItemAdded,
  PlaylistItemRemoved,
  PlaylistItemChanged,

  WindowMaximized,
  WindowMinimized,
  WindowRestored,
  WindowGainedFocus,
  WindowLostFocus,
  WindowResized,
  WindowMoved,

  FileDropStarted,
  FileDropped,
  FileDropStopped,

  Action,
}

WindowEventPayload :: struct {
  window_id: WindowId,
}

FileDropEventPayload :: struct {
  window_id: WindowId,
  file: string,
}

ActionPayload :: struct {
  window_id: WindowId,
  type: ActionType,
  dropped_files: []string,
}

EventPayload :: union {
  WindowEventPayload,
  ActionPayload,
  FileDropEventPayload,
}

Event :: struct {
  type: EventType,
  payload: EventPayload,
}

EventSubscriber :: struct {
  id: SubscriberId,
  handler: rawptr,
  handle: proc(handler: rawptr, event: Event) -> bool,
  event_types: map[EventType]bool,
}

EventHandler :: struct($T: typeid) {
  handler: ^T,
  handle: proc(handler: ^T, event: Event) -> bool,
}

SubscriberId :: u32

EventBus :: struct {
  event_queue: queue.Queue(Event),
  subscribers: [dynamic]EventSubscriber,
  next_id: SubscriberId,
}

@(private="file")
_wrap_handler_window :: proc(raw_handler: rawptr, event: Event) -> bool {
  instance := cast(^EventHandler(Window))raw_handler
  return instance.handle(instance.handler, event)
}

@(private="file")
_wrap_handler_ui :: proc(raw_handler: rawptr, event: Event) -> bool {
  instance := cast(^EventHandler(Ui))raw_handler
  return instance.handle(instance.handler, event)
}

event_bus_init :: proc(bus: ^EventBus) {
  queue.init(&bus.event_queue)
  bus.subscribers = make([dynamic]EventSubscriber)
  bus.next_id = 1
}

event_bus_publish :: proc(bus: ^EventBus, event: Event) {
  queue.push_back(&bus.event_queue, event)
}

event_bus_subscribe :: proc(
  bus: ^EventBus,
  handler: ^$T,
  handle_fn: proc(h: ^T, e: Event) -> bool,
  event_types: []EventType
) -> SubscriberId {
  wrap_fn: proc(rawptr, Event) -> bool


  when T == Window {
    wrap_fn = _wrap_handler_window
  } else when T == Ui {
    wrap_fn = _wrap_handler_ui
  } else {
    #assert(false, "Unknown event handler type")
  }

  instance := new(EventHandler(T))
  instance.handler = handler
  instance.handle = handle_fn

  sub := EventSubscriber {
    id = bus.next_id,
    handler = instance,
    handle = wrap_fn,
    event_types = make(map[EventType]bool),
  }

  for type in event_types {
    sub.event_types[type] = true
  }

  bus.next_id += 1

  append(&bus.subscribers, sub)

  return sub.id
}

event_bus_unsubscribe :: proc(bus: ^EventBus, id: SubscriberId) {
  for i in 0..<len(bus.subscribers) {
    sub := bus.subscribers[i]
    if sub.id == id {
      delete(sub.event_types)
      free(sub.handler)
      ordered_remove(&bus.subscribers, i)
      return
    }
  }
}

event_bus_update :: proc(bus: ^EventBus) {
  for queue.len(bus.event_queue) > 0 {
    event := queue.pop_front(&bus.event_queue)

    for sub in bus.subscribers {
      if event.type in sub.event_types {
        if sub.handle(sub.handler, event) {
          break
        }
      }
    }
  }
}

event_bus_destroy :: proc(bus: ^EventBus) {
  queue.destroy(&bus.event_queue)

  for sub in bus.subscribers {
    delete(sub.event_types)
    free(sub.handler)
  }

  delete(bus.subscribers)
}

sdl_event_translate :: proc(event: sdl3.Event, settings: ^Settings) -> (e: Event, ok: bool) {
  #partial switch event.type {
    case .WINDOW_MAXIMIZED:
      return window_event(event.window.windowID, .WindowMaximized), true

    case .WINDOW_MINIMIZED:
      return window_event(event.window.windowID, .WindowMinimized), true

    case .WINDOW_RESTORED:
      return window_event(event.window.windowID, .WindowRestored), true

    case .WINDOW_FOCUS_LOST:
      return window_event(event.window.windowID, .WindowLostFocus), true

    case .WINDOW_FOCUS_GAINED:
      return window_event(event.window.windowID, .WindowGainedFocus), true

    case .WINDOW_RESIZED:
      return window_event(event.window.windowID, .WindowResized), true

    case .WINDOW_MOVED:
      return window_event(event.window.windowID, .WindowMoved), true

    case .DROP_BEGIN:
      return window_event(event.window.windowID, .FileDropStarted), true

    case .DROP_COMPLETE:
      return window_event(event.window.windowID, .FileDropStopped), true

    case .DROP_FILE:
      return {
        type = .FileDropped,
        payload = FileDropEventPayload {
          window_id = event.window.windowID,
          file = string(event.drop.data),
        }
      }, true

    case .KEY_DOWN: {
      action_type, ok := sdl_event_translate_action_type(event, settings)
      if ok {
        return {
          type = .Action,
          payload = ActionPayload {
            window_id = event.window.windowID,
            type = action_type
          }
        }, true
      }
    }
  }

  return {}, false,
}

sdl_event_translate_action_type :: proc(event: sdl3.Event, settings: ^Settings) -> (type: ActionType, ok: bool) {
  for &mapping in settings.input.mappings {
    #partial switch event.type {
      case .KEY_UP, .KEY_DOWN: {
        switch trigger in mapping.trigger {
          case KeyboardActionTrigger:
            if event.key.key != trigger.key {
              return {}, false
            }


            keymod := event.key.mod & KeyModMask
            ctrl := (event.key.mod & sdl3.KMOD_CTRL) != {}
            shift := (event.key.mod & sdl3.KMOD_SHIFT) != {}
            alt := (event.key.mod & sdl3.KMOD_ALT) != {}
            meta := (event.key.mod & sdl3.KMOD_GUI) != {}

            matches := trigger.ctrl == ctrl &&
              trigger.shift == shift &&
              trigger.alt == alt &&
              trigger.meta == meta

            if matches {
              return mapping.type, true
            }
        }
      }
    }
  }

  return {}, false
}

window_event :: proc(id: WindowId, type: EventType) -> Event {
  return {
    type = type,
    payload = WindowEventPayload {
      window_id = id,
    },
  }
}
