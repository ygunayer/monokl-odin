package app

import sdl "vendor:sdl3"

ActionType :: enum {
  OpenNewWindow,
  CloseWindow,
  MaximizeWindow,
  MinimizeWindow,
  Open,
  ToggleFavorite,
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

Action :: struct {
  type: ActionType,
}

KeyboardActionTrigger :: struct {
  key_code: sdl.Keycode,
  flags: Maybe(sdl.Keymod),
}

ActionTrigger :: union {
  KeyboardActionTrigger,
}

ActionMapping :: struct {
  type: ActionType,
  trigger: ActionTrigger,
}

action_mapping_matches_event :: proc(mapping: ^ActionMapping, event: ^sdl.Event) -> bool {
  assert(mapping != nil, "nil mapping instance passed to function")
  assert(event != nil, "nil event instance passed to function")

  switch trigger in mapping.trigger {
    case KeyboardActionTrigger:
      if event.type != sdl.EventType.KEY_DOWN && event.type != sdl.EventType.KEY_UP {
        return false
      }

      key_event := cast(^sdl.KeyboardEvent)event
      if key_event.key != trigger.key_code {
        return false
      }

      if trigger.flags != nil {
        flags := trigger.flags.?
        return key_event.mod & flags == flags
      }

      return true
  }

  return false
}
