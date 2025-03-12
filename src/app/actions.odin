package app

import "vendor:sdl3"
import "core:log"

KeyModMask :: sdl3.Keymod { .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI }

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

action_mapping_matches_event :: proc(mapping: ActionMapping, event: sdl3.Event) -> bool {
  #partial switch event.type {
    case .KEY_UP, .KEY_DOWN: {
      switch trigger in mapping.trigger {
        case KeyboardActionTrigger:
          if event.key.key != trigger.key {
            return false
          }


          keymod := event.key.mod & KeyModMask
          ctrl := (event.key.mod & sdl3.KMOD_CTRL) != {}
          shift := (event.key.mod & sdl3.KMOD_SHIFT) != {}
          alt := (event.key.mod & sdl3.KMOD_ALT) != {}
          meta := (event.key.mod & sdl3.KMOD_GUI) != {}
          return trigger.ctrl == ctrl &&
            trigger.shift == shift &&
            trigger.alt == alt &&
            trigger.meta == meta
      }
    }
  }

  return false
}
