package monokl

import "core:log"
import "core:os/os2"
import "core:path/filepath"
import "core:container/queue"
import "core:strings"
import "vendor:glfw"

// TODO(platform): get rid of glfw dependency

WindowId :: int

when ODIN_OS == .Darwin {
CTRL_OR_CMD :: KeyMod.Meta
} else {
CTRL_OR_CMD :: KeyMod.Ctrl
}

AppWindow :: struct {
  app: ^App,
  id: WindowId,
  wnd: PlatformWindow,
  close_requested: bool,
  event_queue: queue.Queue(Event),
  playlist: Playlist,
}

app_window_init :: proc(app_window: ^AppWindow) -> Error {
  assert(app_window != nil)
  queue.init(&app_window.event_queue)
  platform_set_window_user_ptr(app_window.wnd, rawptr(app_window))
  platform_show_window(app_window.wnd)
  return nil
}

app_window_update :: proc(app_window: ^AppWindow, delta: f64) {
  assert(app_window != nil)

  defer glfw.SwapBuffers(app_window.wnd)

  if glfw.WindowShouldClose(app_window.wnd) {
    app_window.close_requested = true
    return
  }

  glfw.MakeContextCurrent(app_window.wnd)

  // TODO(concurrency): guard this behind a mutex
  for {
    e, ok := queue.pop_back_safe(&app_window.event_queue)
    if !ok {
      break
    }
    app_window_handle_event(app_window, &e)
  }
}

app_window_handle_event :: proc(app_window: ^AppWindow, event: ^Event) {
  assert(app_window != nil)
  #partial switch e in event {
    case KeyEvent: {
      if e.action == .Press && e.key == .W && e.mods == {CTRL_OR_CMD} {
        app_window.close_requested = true
      }

      if e.action == .Press && e.key == .N && e.mods == {CTRL_OR_CMD} {
        app_create_window(app_window.app)
      }

      if e.action == .Press && e.key == .Left && e.mods == {} {
        playlist_advance(&app_window.playlist, -1)
      }

      if e.action == .Press && e.key == .Right && e.mods == {} {
        playlist_advance(&app_window.playlist, 1)
      }
    }

    case FileDropEvent: {
      if len(e.file_paths) < 1 {
        break
      }

      wnd := app_window
      should_open_new := false
      for path in e.file_paths {
        folder_path, is_dir, err := get_folder_path(path)
        if err != nil {
          log.errorf("#d - Failed to get the folder path for path %s - %v", wnd.id, path, err)
          continue
        }

        if should_open_new {
          new_wnd, err := app_create_window(app_window.app)
          if err != nil {
            log.errorf("#d - Failed to create a new window for opening path %s - %s", wnd.id, path, error_stringify(&err))
            app_window_destroy(new_wnd)
            continue
          }

          wnd = new_wnd
        }

        app_window_open_folder(wnd, folder_path)
        if !is_dir {
          playlist_go_to_file(&wnd.playlist, filepath.base(path))
        } else {
          playlist_go_to_first(&wnd.playlist)
        }
        should_open_new = true
      }
    }
  }
}

app_window_open_folder :: proc(app_window: ^AppWindow, folder_path: string) {
  assert(app_window != nil)

  err := playlist_load_folder(&app_window.playlist, folder_path)
  if err != nil {
    log.errorf("#%d - Failed to load path %s: %v", app_window.id, folder_path, error_stringify(&err))
    return
  }

  log.debugf(
    "%d - Loaded playlist with %d total entries (%d shown, %d unsupported)",
    app_window.id,
    app_window.playlist.total_count,
    len(app_window.playlist.shown_entries),
    app_window.playlist.unsupported_count,
  )
}

app_window_destroy :: proc(app_window: ^AppWindow) {
  if app_window == nil {
    return
  }

  if app_window.wnd != nil {
    glfw.DestroyWindow(app_window.wnd)
    app_window.wnd = nil
  }

  playlist_destroy(&app_window.playlist)

  queue.destroy(&app_window.event_queue)
}
