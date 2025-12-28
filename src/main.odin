package monokl

import "core:fmt"
import "core:log"
import "core:os"
import "core:mem"

run :: proc() -> Error {
  platform_init() or_return
  defer platform_destroy()

  app: App
  defer app_destroy(&app)
  app_init(&app) or_return
  return app_run(&app)
}

main :: proc() {
  exit_code := 0
  defer os.exit(exit_code)

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
    log.debugf("Tracking allocator cleared")
  }

  defer mem.tracking_allocator_destroy(&ta)
  defer clear_ta(&ta)

  err := run()
  if err != nil {
    log.fatalf("%s", error_stringify(&err))
    exit_code = 1
  }
}
