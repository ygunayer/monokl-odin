package app

import "vendor:sdl3"
import "core:log"

KeyModMask :: sdl3.Keymod { .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI }

ActionType :: enum {
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

get_default_action_mappings :: proc(allocator := context.allocator) -> [dynamic]ActionMapping {
  mappings := make([dynamic]ActionMapping, allocator)

  when ODIN_OS == .Darwin {
    append(&mappings, ActionMapping{ type = .OpenNewWindow, trigger = KeyboardActionTrigger { key = sdl3.K_N, meta = true } })
    append(&mappings, ActionMapping{ type = .CloseWindow, trigger = KeyboardActionTrigger { key = sdl3.K_W, meta = true } })
  } else {
    append(&mappings, ActionMapping{ type = .OpenNewWindow, trigger = KeyboardActionTrigger { key = sdl3.K_N, ctrl = true } })
    append(&mappings, ActionMapping{ type = .CloseWindow, trigger = KeyboardActionTrigger { key = sdl3.K_W, ctrl = true } })
  }

  append(&mappings, ActionMapping{ type = .GoToNext, trigger = KeyboardActionTrigger { key = sdl3.K_RIGHT } })
  append(&mappings, ActionMapping{ type = .GoToPrevious, trigger = KeyboardActionTrigger { key = sdl3.K_LEFT } })
  append(&mappings, ActionMapping{ type = .GoToFirst, trigger = KeyboardActionTrigger { key = sdl3.K_HOME } })
  append(&mappings, ActionMapping{ type = .GoToLast, trigger = KeyboardActionTrigger { key = sdl3.K_END } })
  append(&mappings, ActionMapping{ type = .ResetZoom, trigger = KeyboardActionTrigger { key = sdl3.K_KP_0 } })
  append(&mappings, ActionMapping{ type = .ZoomIn, trigger = KeyboardActionTrigger { key = sdl3.K_KP_PLUS } })
  append(&mappings, ActionMapping{ type = .ZoomOut, trigger = KeyboardActionTrigger { key = sdl3.K_KP_MINUS } })
  append(&mappings, ActionMapping{ type = .Favorite, trigger = KeyboardActionTrigger { key = sdl3.K_F } })
  append(&mappings, ActionMapping{ type = .Unfavorite, trigger = KeyboardActionTrigger { key = sdl3.K_F, alt = true } })
  append(&mappings, ActionMapping{ type = .ToggleOnlyFavorites, trigger = KeyboardActionTrigger { key = sdl3.K_F, shift = true } })

  return mappings
}
