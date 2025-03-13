package app

import "core:strings"
import "vendor:sdl3"
import "core:mem"
import "core:log"
import "core:fmt"

import "../playlist"

Vector2 :: distinct [2]i32
WindowId :: sdl3.WindowID
DisplayId :: sdl3.DisplayID

WindowSize_Default :: (Vector2) { 1366, 768 }

WindowPosition_Undefined :: (Vector2) { sdl3.WINDOWPOS_UNDEFINED, sdl3.WINDOWPOS_UNDEFINED }
WindowPosition_Centered :: (Vector2) { sdl3.WINDOWPOS_CENTERED, sdl3.WINDOWPOS_CENTERED }

Color_Background := sdl3.FColor { .192, .192, .192, 1.0 }

WindowOptions :: struct {
  initial_position: Vector2,
  initial_size: Vector2,
  maximized: bool,
}

Window :: struct {
  id: sdl3.WindowID,
  display_id: sdl3.DisplayID,
  renderer: ^sdl3.Renderer,
  wnd: ^sdl3.Window,
  size: Vector2,
  position: Vector2,
  maximized: bool,
  has_focus: bool,
  playlist: ^playlist.Playlist,
  dropping_files: bool,
  dropped_files: [dynamic]string,
}

Window_Error :: union {
  SdlError,
  mem.Allocator_Error,
  playlist.Playlist_Error,
}

window_init_from_scratch :: proc() -> (w: ^Window, error: Window_Error) {
  options := WindowOptions {
    initial_position = WindowPosition_Centered,
    initial_size = WindowSize_Default,
    maximized = false,
  }
  return window_init_with_settings(options)
}

window_init_after :: proc(previous: ^Window) -> (w: ^Window, error: Window_Error) {
  if previous == nil || previous.wnd == nil {
    return window_init_from_scratch()
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

  options.initial_position = Vector2 { x, y }

  return window_init_with_settings(options)
}

window_init_with_settings :: proc(options: WindowOptions) -> (w: ^Window, error: Window_Error) {
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

  window.id = sdl3.GetWindowID(wnd)
  window.display_id = sdl3.GetDisplayForWindow(wnd)
  window.wnd = wnd
  window.renderer = renderer
  sdl3.SetWindowPosition(wnd, options.initial_position.x, options.initial_position.y)

  window.playlist = new(playlist.Playlist)
  playlist.playlist_init(window.playlist)

  sdl3.GetWindowSize(wnd, &window.size.x, &window.size.y)
  sdl3.GetWindowPosition(wnd, &window.position.x, &window.position.y)

  return window, nil
}

window_init :: proc {
  window_init_from_scratch,
  window_init_after,
  window_init_with_settings,
}

window_destroy :: proc(window: ^Window) {
  window_unload_playlist(window)

  delete(window.dropped_files)

  if window.renderer != nil {
    sdl3.DestroyRenderer(window.renderer)
    window.renderer = nil
  }

  if window.wnd != nil {
    sdl3.DestroyWindow(window.wnd)
    window.wnd = nil
  }

  free(window)
}

window_update_title :: proc(window: ^Window) {
  if window == nil {
    return
  }

  if window.playlist == nil {
    sdl3.SetWindowTitle(window.wnd, "monokl")
    return
  }

  item := playlist.playlist_get_current_entry(window.playlist)
  if item == nil {
    sdl3.SetWindowTitle(window.wnd, "monokl - No images")
    return
  }

  title_string := strings.clone_to_cstring(fmt.tprintf(
    "monokl - %s%d/%d - %s",
    "♥" if item.is_favorited else "",
    window.playlist.current_index + 1,
    window.playlist.entry_count,
    item.filename,
  ), allocator = context.temp_allocator)

  sdl3.SetWindowTitle(window.wnd, title_string)
}

window_render :: proc(window: ^Window) {
  window_update_title(window)

  sdl3.SetRenderDrawColorFloat(window.renderer, Color_Background.r, Color_Background.g, Color_Background.b, Color_Background.a)
  sdl3.RenderClear(window.renderer)
  sdl3.RenderPresent(window.renderer)
}

window_unload_playlist :: proc(window: ^Window) {
  if window.playlist != nil {
    playlist.playlist_destroy(window.playlist)
    window.playlist = nil
  }
}

window_load_playlist :: proc(window: ^Window, path: string) -> playlist.Playlist_Error {
  window_unload_playlist(window)

  pl := new(playlist.Playlist)

  err := playlist.playlist_open(pl, path)
  if err != nil {
    free(pl)
    return err
  }

  window_unload_playlist(window)
  window.playlist = pl
  return nil
}

 window_handle_event :: proc(window: ^Window, event: Event) {
  switch e in event {
    case WindowEvent: {
      if e.window_id != window.id {
        return
      }

      switch e.type {
        case .Maximized:
          window.maximized = true;

        case .Minimized, .Restored:
          window.maximized = false;

        case .GainedFocus:
          window.has_focus = true;

        case .LostFocus:
          window.has_focus = false;

        case .Resized:
          sdl3.GetWindowSize(window.wnd, &window.size.x, &window.size.y)

        case .Moved: {
          sdl3.GetWindowPosition(window.wnd, &window.position.x, &window.position.y)
          display_id := sdl3.GetDisplayForWindow(window.wnd)
          if display_id == 0 {
            log.warnf("Failed to get display ID for window %d due to %s", window.id, sdl3.GetError())
          } else {
            window.display_id = display_id
          }
        }
      }

      // log.debugf(
      //   "Window %d handled window event. New state: has_focus=%v, maximized=%v, size=%v, position:%v, display_id:%v",
      //   window.id,
      //   window.has_focus,
      //   window.maximized,
      //   window.size,
      //   window.position,
      //   window.display_id,
      // )
    }

    case ActionEvent: {
      if e.window_id != window.id {
        return
      }

      #partial switch e.action.type {
        case .GoToNext:
          playlist.playlist_advance(window.playlist, 1)

        case .GoToPrevious:
          playlist.playlist_advance(window.playlist, -1)

        case .GoToFirst:
          playlist.playlist_go_to_first(window.playlist)

        case .GoToLast:
          playlist.playlist_go_to_last(window.playlist)
      }
    }

    case DropEvent: {
      switch e.type {
        case .Begin: {
          window.dropping_files = true
          clear(&window.dropped_files)
        }

        case .DropFile: {
          if window.dropping_files {
            append(&window.dropped_files, e.file)
          }
        }

        case .End: {
          if window.dropping_files {
            window.dropping_files = false
            if len(window.dropped_files) > 0 {
              window_load_playlist(window, window.dropped_files[0])
            }
            clear(&window.dropped_files)
          }
        }

      }
    }
  }

}
