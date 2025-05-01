package monokl

import "core:os"
import "vendor:sdl3"

ThemeSetting_System :: struct {}
ThemeSetting_Dark :: struct {}
ThemeSetting_Light :: struct {}

Keybinds :: #type map[sdl3.Keycode][dynamic]Keybind

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
  keybinds: Keybinds,
}

SystemSettings :: struct {
  max_texture_cache_memory: u32,
  max_texture_load_threads: u32,
}

Settings :: struct {
  theme: ThemeSettings,
  input: InputSettings,
  system: SystemSettings,
}

settings_load_defaults :: proc(settings: ^Settings) {
  if settings == nil {
    return
  }

  // Theme settings
  settings.theme.type = .System

  // Input settings
  keybinds := make(Keybinds)

  when ODIN_OS == .Darwin {
    keybind_add(&keybinds, { action = .OpenNewWindow,  key = sdl3.K_N, meta = true })
    keybind_add(&keybinds, { action = .CloseWindow,  key = sdl3.K_W, meta = true })
  } else {
    keybind_add(&keybinds, { action = .OpenNewWindow,  key = sdl3.K_N, ctrl = true })
    keybind_add(&keybinds, { action = .CloseWindow,  key = sdl3.K_W, ctrl = true })
  }

  keybind_add(&keybinds, { action = .GoToNext,  key = sdl3.K_RIGHT })
  keybind_add(&keybinds, { action = .GoToPrevious,  key = sdl3.K_LEFT })
  keybind_add(&keybinds, { action = .GoToFirst,  key = sdl3.K_HOME })
  keybind_add(&keybinds, { action = .GoToLast,  key = sdl3.K_END })
  keybind_add(&keybinds, { action = .ResetZoom,  key = sdl3.K_KP_0 })
  keybind_add(&keybinds, { action = .FitImageToScreen,  key = sdl3.K_KP_1 })
  keybind_add(&keybinds, { action = .ZoomIn,  key = sdl3.K_KP_PLUS })
  keybind_add(&keybinds, { action = .ZoomOut,  key = sdl3.K_KP_MINUS })
  keybind_add(&keybinds, { action = .Favorite,  key = sdl3.K_F })
  keybind_add(&keybinds, { action = .Unfavorite,  key = sdl3.K_F, alt = true })
  keybind_add(&keybinds, { action = .ToggleOnlyFavorites,  key = sdl3.K_F, shift = true })

  settings.input.keybinds = keybinds

  // default: 512MB
  settings.system.max_texture_cache_memory = 512 * 1024 * 1024

  settings.system.max_texture_load_threads = u32(os.processor_core_count() - 1)
}

keybind_add :: proc(keybinds: ^Keybinds, mapping: Keybind) {
  if !(mapping.key in keybinds) {
    keybinds[mapping.key] = make([dynamic]Keybind)
  }

  append(&keybinds[mapping.key], mapping)
}

settings_load :: proc(settings: ^Settings) -> Settings_Error {
  settings_load_defaults(settings)
  return nil
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

settings_destroy :: proc(settings: ^Settings) {
  if settings == nil {
    return
  }

  if settings.input.keybinds != nil {
    for k, &v in settings.input.keybinds {
      delete(v)
      delete_key(&settings.input.keybinds, k)
    }
    delete(settings.input.keybinds)
    settings.input.keybinds = nil
  }
}
