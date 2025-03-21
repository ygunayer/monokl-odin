package monokl

import "vendor:sdl3"

Ui :: struct {
  window: ^Window,
  viewport: Viewport,
  playlist: ^Playlist,
  main_image: SceneObject_Image,
}

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

ui_init :: proc(ui: ^Ui, renderer: ^sdl3.Renderer, size: Vec2i, playlist: ^Playlist, theme: Theme) {
  viewport_init(&ui.viewport, renderer, size, theme)
  ui.playlist = playlist

}

ui_set_theme :: proc(ui: ^Ui, theme: Theme) {
  ui.viewport.theme = theme
}

ui_resize :: proc(ui: ^Ui, size: Vec2i) {
  ui.viewport.size = size
}

ui_handle_event :: proc(event: Event) {

}

ui_render :: proc(ui: ^Ui) {
  viewport_render(&ui.viewport)
}

ui_destroy :: proc(ui: ^Ui) {
  viewport_destroy(&ui.viewport)
}
