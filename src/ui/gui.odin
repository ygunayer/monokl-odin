package ui

import "vendor:sdl3"

import "../linalg"
import "../playlist"
import "../platform"

Gui :: struct {
  viewport: Viewport,
  main_image: SceneObject_Image,
  playlist: ^playlist.Playlist,
}

gui_init :: proc(gui: ^Gui, renderer: ^sdl3.Renderer, size: linalg.Vec2i, playlist: ^playlist.Playlist, theme: Theme) {
  viewport_init(&gui.viewport, renderer, size, theme)
  gui.playlist = playlist
}

gui_set_theme :: proc(gui: ^Gui, theme: Theme) {
  gui.viewport.theme = theme
}

gui_resize :: proc(gui: ^Gui, size: linalg.Vec2i) {
  gui.viewport.size = size
}

gui_update :: proc(gui: ^Gui) {

}

gui_render :: proc(gui: ^Gui) {
  viewport_render(&gui.viewport)
}

gui_destroy :: proc(gui: ^Gui) {
  viewport_destroy(&gui.viewport)
}
