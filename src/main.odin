package monokl

import "core:os"
import "core:fmt"
import "core:log"
import "core:mem"

when ODIN_DEBUG {
  ENABLE_DEBUG :: true
} else {
  ENABLE_DEBUG :: false
}

main :: proc() {
  console_logger := log.create_console_logger()
  defer log.destroy_console_logger(console_logger)
  context.logger = console_logger

  exit_code := 0
  defer os.exit(exit_code)

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

  err := app_run()
  if err != nil {
    log.fatalf("%s", error_string(err))
    exit_code = 1
  }
}
