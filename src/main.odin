package monokl

import "core:fmt"
import sdl "vendor:sdl3"
import "core:c"
import "core:log"
import "core:os"
import "core:mem"
import "core:time"

import "app"

main :: proc() {
  logger := log.create_console_logger()
  context.logger = logger

  ta: mem.Tracking_Allocator
  mem.tracking_allocator_init(&ta, context.allocator)
  context.allocator = mem.tracking_allocator(&ta)

  clear_ta :: proc(a: ^mem.Tracking_Allocator) -> bool {
    num_leaked, total_size: int
    for _, value in a.allocation_map {
      num_leaked += 1
      total_size += value.size
      log.errorf("Leaked %v bytes at %v", value.size, value.location)
      leaked := true
    }
    if num_leaked > 0 {
      log.errorf("Found %v memory leaks for a total of %v bytes", num_leaked, total_size)
    }
    mem.tracking_allocator_clear(a)
    return num_leaked > 0
  }

  init_success := sdl.Init(sdl.INIT_VIDEO)
  assert(init_success, string(sdl.GetError()))

  bus := app.event_bus_init()
  defer app.event_bus_destroy(&bus)

  window_settings := app.WindowSettings {
    initial_position = app.WindowPosition_Centered,
    initial_size = app.WindowSize_Default,
    maximized = false,
    title = cstring("monokl"),
  }

  first_window, err := app.window_init(window_settings, &bus)
  if err != nil {
    panic(fmt.tprintf("Failed to create initial window due to: %v", err))
  }

  windows: [dynamic]^app.Window
  append(&windows, first_window)

  perr := app.window_load_playlist(first_window, "C:\\Users\\Selgesel\\Downloads\\sticky\\named\\mikey-madison")
  if perr != nil {
    log.warnf("Failed to load playlist for initial window due to %v", perr)
  }

  sdl_event: sdl.Event

  initial_time := time.tick_now()
  last_rendered := time.tick_now()

  target_fps := 20.0
  max_frame_delay := 1000.0 / target_fps
  fmt.printfln("FRAME DELAY: %.2f", max_frame_delay)

  for {
    if len(windows) < 1 {
      break
    }

    has_event := sdl.PollEvent(&sdl_event)
    if has_event {
      event, ok := app.event_bus_translate(&sdl_event).?
      if !ok {
        continue
      }

      app.event_bus_publish(&bus, event)

      switch e in event {
        case app.WindowEvent:
          if e.type == .CloseRequested {
            for w, i in windows {
              if w.id == e.event.window_id {
                app.window_destroy(w)
                unordered_remove(&windows, i)
                break
              }
            }
          }
      }
    }

    elapsed := time.duration_milliseconds(time.tick_since(last_rendered))

    if elapsed >= max_frame_delay {
      last_rendered = time.tick_now()
      fmt.printfln("Rendered after delay: %.4f", elapsed)

      for w in windows {
        app.window_render(w)
      }
    }


    if len(ta.bad_free_array) > 0 {
      for v in ta.bad_free_array {
        log.errorf("Bad free at %v", v.location)
      }
    }

    free_all(context.temp_allocator)
  }
  free_all(context.temp_allocator)

  delete(windows)

  clear_ta(&ta)
  mem.tracking_allocator_destroy(&ta)

  sdl.Quit()
}
