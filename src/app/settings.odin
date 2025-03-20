package app

import "core:os"
import "vendor:sdl3"

import "../ui"

ThemeSetting_System :: struct {}
ThemeSetting_Dark :: struct {}
ThemeSetting_Light :: struct {}

ThemeSetting_BuiltIn :: enum {
  System,
  Dark,
  Light,
}

ThemeSetting_Custom :: struct {
  theme: ui.Theme,
}

ThemeSetting :: union {
  ThemeSetting_BuiltIn,
  ThemeSetting_Custom,
}

AppSettings :: struct {
  theme: ThemeSetting,
}

AppSettings_Error :: union {
  os.Error,
}

app_settings_load :: proc(settings: ^AppSettings) -> AppSettings_Error {
  settings.theme = ThemeSetting_BuiltIn.System
  return nil
  // TODO
}

theme_setting_to_ui_theme :: proc(theme_setting: ^ThemeSetting) -> ui.Theme {
  switch s in theme_setting {
    case ThemeSetting_BuiltIn: {
      switch s {
        case .Dark:
          return ui.Theme_Dark

        case .Light:
          return ui.Theme_Light

        case .System:
          return ui.get_system_theme()
      }
    }

    case ThemeSetting_Custom:
      return s.theme
  }

  return ui.Theme_Light
}
