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

Event :: struct {
  type: EventType,
  window: WindowEventPayload,
  action: ActionPayload,
  drop: FileDropEventPayload,
}

EventHandler :: struct($T: typeid) {
  handle: proc(handler: ^T, event: Event) -> bool,
  handler: T,
}

EventSubscriber :: struct {
  handler: rawptr,
  handle: proc(handler: rawptr, event: Event) -> bool,
  event_types: map[EventType]bool,
}

SubscriberId :: u32

EventBus :: struct {
  event_queue: queue.Queue(Event),
  subscribers: map[SubscriberId]^EventSubscriber,
  next_id: SubscriberId,
}

event_bus_init :: proc(bus: ^EventBus) {
  queue.init(&bus.event_queue)
  bus.subscribers = make(map[SubscriberId]^EventSubscriber)
  bus.next_id = 1
}

event_bus_destroy :: proc(bus: ^EventBus) {
  queue.destroy(&bus.event_queue)

  for _, sub in bus.subscribers {
    delete(sub.event_types)
    free(sub)
  }
  delete(bus.subscribers)
}

event_bus_publish :: proc(bus: ^EventBus, event: Event) {
  queue.push_back(&bus.event_queue, event)
}

@private
_wrap_handler_window :: proc(handler: rawptr, event: Event) -> bool {
  casted := cast(^Window)handler
  wrapped := cast(^EventHandler(Window))handler
  return wrapped.handle(casted, event)
}

event_bus_subscribe :: proc(bus: ^EventBus, handler: ^$T/EventHandler, event_types: []EventType) -> SubscriberId {
  wrapper: proc(h: rawptr, e: Event) -> bool

  when T == EventHandler(Window) {
    wrapper = _wrap_handler_window
  } else {
    #assert(false, "Unsupported event handler type")
  }

  sub := EventSubscriber {
    handle = wrapper,
    handler = handler,
    event_types = make(map[EventTye]bool),
  }

  for type in event_types {
    sub.event_types[type] = true
  }

  sub_id := bus.next_id
  bus.next_id += 1
  bus.subscribers[sub_id] = &sub
  return sub_id
}

event_bus_unsubscribe :: proc(bus: ^EventBus, id: SubscriberId) {
  if id in bus.subscribers {
    delete_key(&bus.subscribers, id)
  }
}

event_bus_update :: proc(bus: ^EventBus) {
  for queue.len(bus.event_queue) > 0 {
    event := queue.pop_front(&bus.event_queue)

    for id, sub in bus.subscribers {
      if event.type in sub.event_types {
        if sub.handle(sub.handler, event) {
          break
        }
      }
    }
  }
}


sdl_event_translate :: proc(event: sdl3.Event, settings: ^Settings) -> (e: Event, ok: bool) {
  #partial switch event.type {
    case .WINDOW_MAXIMIZED:
      return { window = { window_id = event.window.windowID }, type = .WindowMaximized }, true

    case .WINDOW_MINIMIZED:
      return { window = { window_id = event.window.windowID }, type = .WindowMinimized }, true

    case .WINDOW_RESTORED:
      return { window = { window_id = event.window.windowID }, type = .WindowRestored }, true

    case .WINDOW_FOCUS_LOST:
      return { window = { window_id = event.window.windowID }, type = .WindowLostFocus }, true

    case .WINDOW_FOCUS_GAINED:
      return { window = { window_id = event.window.windowID }, type = .WindowGainedFocus }, true

    case .WINDOW_RESIZED:
      return { window = { window_id = event.window.windowID }, type = .WindowResized }, true

    case .WINDOW_MOVED:
      return { window = { window_id = event.window.windowID }, type = .WindowMoved }, true

    case .DROP_BEGIN:
      return { drop = { window_id = event.window.windowID }, type = .FileDropStarted }, true

    case .DROP_COMPLETE:
      return { drop = { window_id = event.window.windowID }, type = .FileDropStopped }, true

    case .DROP_FILE:
      return {
        type = .FileDropped,
        drop = {
          window_id = event.window.windowID,
          file = string(event.drop.data),
        }
      }, true

    case .KEY_DOWN: {
      action_type, ok := sdl_event_translate_action_type(event, settings)
      if ok {
        return {
          type = .Action,
          action = {
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
