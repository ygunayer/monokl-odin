package monokl

import "core:fmt"
import sdl "vendor:sdl3"
import "core:c"
import "core:log"
import "core:os"

main :: proc() {
  logger := log.create_console_logger()
  context.logger = logger

  init_success := sdl.Init(sdl.INIT_VIDEO)
  assert(init_success, string(sdl.GetError()))
  defer sdl.Quit()

  bus := event_bus_init()
  defer event_bus_destroy(&bus)

  playlist, perr := playlist_open("/home/ygunayer/Pictures/Screenshots")
  if perr != nil {
    log.errorf("Failed to open playlist: %v", perr)
    os.exit(1)
  }

  window_settings := WindowSettings {
    initial_position = WindowPosition_Centered,
    initial_size = WindowSize_Default,
    maximized = false,
    title = cstring("monokl"),
  }

  first_window, err := window_init(window_settings, &bus)
  if err != nil {
    panic(fmt.tprintf("Failed to create initial window due to: %v", err))
  }

  defer window_destroy(first_window)

  windows: [dynamic]^Window;
  append(&windows, first_window)

  sdl_event: sdl.Event
  for {
    if len(windows) < 1 {
      return
    }

    has_event := sdl.PollEvent(&sdl_event)
    if has_event {
      event, ok := event_bus_translate(&sdl_event).?
      if !ok {
        continue
      }

      event_bus_publish(&bus, event)

      switch e in event {
        case WindowEvent:
          if e.type == .CloseRequested {
            for w, i in windows {
              if w.id == e.event.window_id {
                window_destroy(w)
                unordered_remove(&windows, i)
                break
              }
            }
          }
      }
    }

    for w in windows {
      window_render(w)
    }
  }
}
