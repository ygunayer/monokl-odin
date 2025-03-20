package monokl

import "core:fmt"
import sdl "vendor:sdl3"
import "core:c"
import "core:log"
import "core:os"
import "core:mem"
import "core:time"

import "app"

mainCRTStartup :: proc() {
  logger := log.create_console_logger()
  context.logger = logger

  ta: mem.Tracking_Allocator
  mem.tracking_allocator_init(&ta, context.allocator)
  context.allocator = mem.tracking_allocator(&ta)

  clear_ta :: proc(ta: ^mem.Tracking_Allocator) {
    num_leaked, total_size: int
    for _, value in ta.allocation_map {
      num_leaked += 1
      total_size += value.size
      log.errorf("Leaked %v bytes at %v", value.size, value.location)
      leaked := true
    }

    if num_leaked > 0 {
      log.errorf("Found %v memory leaks for a total of %v bytes", num_leaked, total_size)
    }

    if len(ta.bad_free_array) > 0 {
      for v in ta.bad_free_array {
        log.errorf("Bad free at %v", v.location)
      }
    }

    mem.tracking_allocator_clear(ta)
  }

  application := new(app.Application)
  err := app.application_init(application)

  if err != nil {
    log.fatalf("Failed to initialize application: %v", err)
    sdl.Quit()
    os.exit(-1)
  }

  app.application_run_main_loop(application)

  app.application_destroy(application)

  clear_ta(&ta)
  mem.tracking_allocator_destroy(&ta)
}

main :: proc() {
  mainCRTStartup()
}
