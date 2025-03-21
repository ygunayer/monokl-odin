package monokl

import "core:os"
import "vendor:sdl3"

ThemeSetting_System :: struct {}
ThemeSetting_Dark :: struct {}
ThemeSetting_Light :: struct {}

ThemeSettingType :: enum {
  System,
  Dark,
  Light,
  Custom,
}

ThemeSettings :: struct {
  type: ThemeSettingType,
  custom: Theme,
}

InputSettings :: struct {
  mappings: []ActionMapping,
}

Settings :: struct {
  theme: ThemeSettings,
  input: InputSettings,
}

settings_get_default :: proc() -> Settings {
  settings := Settings {}

  // Theme settings
  settings.theme.type = .System

  // Input settings
  mappings := make([dynamic]ActionMapping)
  defer delete(mappings)

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

  settings.input.mappings = mappings[:]

  return settings
}

settings_load :: proc() -> (result: Settings, err: Settings_Error) {
  return settings_get_default(), nil
}

settings_get_theme :: proc(settings: ^Settings) -> Theme {
  switch settings.theme.type {
    case .System:
      return get_system_theme()

    case .Dark:
      return Theme_Dark

    case .Light:
      return Theme_Light

    case .Custom:
      return settings.theme.custom
  }

  return Theme_Light
}
