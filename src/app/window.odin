package app

import "core:strings"
import sdl "vendor:sdl3"
import "core:mem"

import "../playlist"

Vector2 :: distinct [2]i32
WindowId :: sdl.WindowID

WindowSize_Default :: (Vector2) { 1366, 768 }

WindowPosition_Undefined :: (Vector2) { sdl.WINDOWPOS_UNDEFINED, sdl.WINDOWPOS_UNDEFINED }
WindowPosition_Centered :: (Vector2) { sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED }

WindowSettings :: struct {
  title: cstring,
  initial_position: Vector2,
  initial_size: Vector2,
  maximized: bool,
}

Window :: struct {
  id: sdl.WindowID,
  display_id: sdl.DisplayID,
  renderer: ^sdl.Renderer,
  wnd: ^sdl.Window,
  size: Vector2,
  position: Vector2,
  handler_id: HandlerId,
  playlist: ^playlist.Playlist,
}

Window_Error :: union {
  SdlError,
  mem.Allocator_Error,
  playlist.Playlist_Error,
}

window_init :: proc(settings: WindowSettings, bus: ^EventBus, allocator := context.allocator) -> (w: ^Window, error: Window_Error) {
  flags := sdl.WINDOW_RESIZABLE

  if settings.maximized {
    flags |= sdl.WINDOW_MAXIMIZED
  }

  wnd: ^sdl.Window
  renderer: ^sdl.Renderer
  sdl.CreateWindowAndRenderer(
    settings.title,
    settings.initial_size.x,
    settings.initial_size.y,
    sdl.WINDOW_RESIZABLE,
    &wnd,
    &renderer,
  )

  if wnd == nil || renderer == nil {
    return nil, make_sdl_error(sdl.GetError())
  }

  window := new(Window, allocator)
  if window == nil {
    defer sdl.DestroyRenderer(renderer)
    defer sdl.DestroyWindow(wnd)
    return nil, mem.Allocator_Error.Out_Of_Memory
  }

  window.id = sdl.GetWindowID(wnd)
  window.display_id = sdl.GetDisplayForWindow(wnd^)
  window.wnd = wnd
  sdl.GetWindowSize(wnd, &window.size.x, &window.size.y)
  sdl.GetWindowPosition(wnd, &window.position.x, &window.position.y)

  return window, nil
}

window_destroy :: proc(window: ^Window, allocator := context.allocator) {
  window_unload_playlist(window)

  if window.renderer != nil {
    sdl.DestroyRenderer(window.renderer)
    window.renderer = nil
  }

  if window.wnd != nil {
    sdl.DestroyWindow(window.wnd)
    window.wnd = nil
  }

  free(window, allocator)
}

window_render :: proc(window: ^Window) {
  color: sdl.FColor = {.3, .4, .4, 1}
  sdl.SetRenderDrawColorFloat(window.renderer, color.r, color.g, color.b, color.a)
  sdl.RenderClear(window.renderer)
  sdl.RenderPresent(window.renderer)
}

window_unload_playlist :: proc(window: ^Window, allocator := context.allocator) {
  if window.playlist != nil {
    playlist.playlist_destroy(window.playlist, allocator)
    window.playlist = nil
  }
}

window_load_playlist :: proc(window: ^Window, path: string, allocator := context.allocator) -> playlist.Playlist_Error {
  pl := new(playlist.Playlist, allocator)

  err := playlist.playlist_open(pl, path, allocator)
  if err != nil {
    free(pl, allocator)
    return err
  }

  window_unload_playlist(window)
  window.playlist = pl
  return nil
}
