package monokl

import "core:strings"
import "vendor:sdl3"
import "core:mem"
import "core:log"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:math"

Vector2i :: [2]i32
WindowId :: sdl3.WindowID
DisplayId :: sdl3.DisplayID

WindowSize_Default :: (Vector2i) { 1366, 768 }

WindowPosition_Undefined :: (Vector2i) { sdl3.WINDOWPOS_UNDEFINED, sdl3.WINDOWPOS_UNDEFINED }
WindowPosition_Centered :: (Vector2i) { sdl3.WINDOWPOS_CENTERED, sdl3.WINDOWPOS_CENTERED }

WindowOptions :: struct {
  initial_position: Vector2i,
  initial_size: Vector2i,
  maximized: bool,
}

Window :: struct {
  app: ^App,
  id: sdl3.WindowID,
  display_id: sdl3.DisplayID,
  renderer: ^sdl3.Renderer,
  wnd: ^sdl3.Window,
  size: Vector2i,
  position: Vector2i,
  maximized: bool,
  has_focus: bool,
  ui: ^Ui,
  event_sub_id: SubscriberId,
}

window_init_from_scratch :: proc(app: ^App) -> (w: ^Window, error: Window_Error) {
  options := WindowOptions {
    initial_position = WindowPosition_Centered,
    initial_size = WindowSize_Default,
    maximized = false,
  }
  return window_init_with_settings(app, options)
}

window_init_after :: proc(app: ^App, previous: ^Window) -> (w: ^Window, error: Window_Error) {
  if previous == nil || previous.wnd == nil {
    return window_init_from_scratch(app)
  }

  options := WindowOptions {
    initial_position = WindowPosition_Centered,
    initial_size = WindowSize_Default,
    maximized = false,
  }

  display_mode := sdl3.GetCurrentDisplayMode(previous.display_id)

  bl, bt, br, bb: i32
  sdl3.GetWindowBordersSize(previous.wnd, &bt, &bl, &bb, &br)

  log.debugf("Display Mode: %p > %v", display_mode, display_mode)
  effective_width := display_mode.w - bl - br
  effective_height := display_mode.h - bt - bb

  x := previous.position.x
  y := previous.position.y

  x += 30 if bl < 30 else bl
  y += 30 if bt < 30 else bt

  if ((x + options.initial_size.x) >= effective_width) || ((y + options.initial_size.y) >= effective_height) {
    x = bl
    y = bt
  }

  options.initial_position = Vector2i { x, y }

  return window_init_with_settings(app, options)
}

window_init_with_settings :: proc(app: ^App, options: WindowOptions) -> (w: ^Window, error: Window_Error) {
  flags := sdl3.WINDOW_RESIZABLE

  if options.maximized {
    flags |= sdl3.WINDOW_MAXIMIZED
  }

  wnd: ^sdl3.Window
  renderer: ^sdl3.Renderer
  sdl3.CreateWindowAndRenderer(
    cstring("monokl"),
    options.initial_size.x,
    options.initial_size.y,
    sdl3.WINDOW_RESIZABLE,
    &wnd,
    &renderer,
  )

  if wnd == nil || renderer == nil {
    return nil, make_sdl_error(sdl3.GetError())
  }

  window := new(Window)
  if window == nil {
    defer sdl3.DestroyRenderer(renderer)
    defer sdl3.DestroyWindow(wnd)
    return nil, mem.Allocator_Error.Out_Of_Memory
  }

  window.app = app
  window.id = sdl3.GetWindowID(wnd)
  window.display_id = sdl3.GetDisplayForWindow(wnd)
  window.wnd = wnd
  window.renderer = renderer
  sdl3.SetWindowPosition(wnd, options.initial_position.x, options.initial_position.y)


  sdl3.GetWindowSize(wnd, &window.size.x, &window.size.y)
  sdl3.GetWindowPosition(wnd, &window.position.x, &window.position.y)

  event_bus_subscribe(app.event_bus, window, window_handle_event, {
    .WindowResized,
  })

  window.ui = new(Ui)
  ui_init(window.ui, window)

  return window, nil
}

window_init :: proc {
  window_init_from_scratch,
  window_init_after,
  window_init_with_settings,
}

window_set_title :: proc(window: ^Window, title: string) {
  if window == nil {
    return
  }
  title_string := strings.clone_to_cstring(title)
  defer delete(title_string)
  sdl3.SetWindowTitle(window.wnd, title_string)
}

window_render :: proc(window: ^Window) {
  ui_render(window.ui)
}

window_handle_event :: proc(window: ^Window, event: Event) -> bool {
  #partial switch event.type {
    case .WindowResized:
      sdl3.GetWindowSize(window.wnd, &window.size.x, &window.size.y)

    case .WindowMoved: {
      sdl3.GetWindowPosition(window.wnd, &window.position.x, &window.position.y)

      display_id := sdl3.GetDisplayForWindow(window.wnd)
      if display_id == 0 {
        log.warnf("Failed to get display ID for window %d", window.id)
      } else {
        window.display_id = display_id
      }
    }

    case .WindowMaximized:
      window.maximized = true

    case .WindowRestored, .WindowMinimized:
      window.maximized = false

    case .WindowGainedFocus:
      window.has_focus = true

    case .WindowLostFocus:
      window.has_focus = false

  }

  return true
}

window_destroy :: proc(window: ^Window) {
  event_bus_unsubscribe(window.app.event_bus, window.event_sub_id)

  if window.renderer != nil {
    sdl3.DestroyRenderer(window.renderer)
    window.renderer = nil
  }

  if window.wnd != nil {
    sdl3.DestroyWindow(window.wnd)
    window.wnd = nil
  }

  if window.ui != nil {
    ui_destroy(window.ui)
    free(window.ui)
    window.ui = nil
  }
}
