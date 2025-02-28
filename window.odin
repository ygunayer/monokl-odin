package monokl

import "core:strings"
import sdl "vendor:sdl3"
import "core:mem"

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
}

window_init :: proc(settings: WindowSettings, bus: ^EventBus, allocator: mem.Allocator = context.allocator) -> (^Window, Error) {
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
    return nil, "Failed to allocate memory for a new window"
  }

  window.id = sdl.GetWindowID(wnd)
  window.display_id = sdl.GetDisplayForWindow(wnd^)
  window.wnd = wnd
  sdl.GetWindowSize(wnd, &window.size.x, &window.size.y)
  sdl.GetWindowPosition(wnd, &window.position.x, &window.position.y)

  return window, nil
}

window_destroy :: proc(window: ^Window) {
  if window.renderer != nil {
    sdl.DestroyRenderer(window.renderer)
    window.renderer = nil
  }

  if window.wnd != nil {
    sdl.DestroyWindow(window.wnd)
    window.wnd = nil
  }
}

window_render :: proc(window: ^Window) {
  color: sdl.FColor = {.3, .4, .4, 1}
  sdl.SetRenderDrawColorFloat(window.renderer, color.r, color.g, color.b, color.a)
  sdl.RenderClear(window.renderer)
  sdl.RenderPresent(window.renderer)
}
