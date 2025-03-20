package ui

import "vendor:sdl3"

Theme :: struct {
  background_color: sdl3.FColor,
  text_color: sdl3.FColor,
  text_background_color: sdl3.FColor,
}

Theme_Light :: Theme {
  background_color = sdl3.FColor { .76, .76, .76, 1 },
  text_color = sdl3.FColor { .34, .34, .34, 1 },
  text_background_color = sdl3.FColor { 0, 0, 0, 0 }
}

Theme_Dark :: Theme {
  background_color = sdl3.FColor { .192, .192, .192, 1 },
  text_color = sdl3.FColor { 1, 1, 1, 1 },
  text_background_color = sdl3.FColor { 0, 0, 0, 0 }
}


get_system_theme :: proc() -> Theme {
  if sdl3.GetSystemTheme() == .DARK {
    return Theme_Dark
  }

  return Theme_Light
}
