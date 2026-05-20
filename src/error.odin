package monokl

import "base:runtime"
import "core:fmt"
import "core:strings"
import "vendor:sdl3"

BaseError :: struct {
  location: runtime.Source_Code_Location,
}

CommonError :: struct {
  using _: BaseError,
  message: string,
}

Error :: union {
  CommonError,
}

common_error :: proc(message: string, location := #caller_location) -> CommonError {
  return CommonError { message = message, location = location }
}

sdl_last_error :: proc(message: string, location := #caller_location) -> Error {
  sdl_err := sdl3.GetError()
  return CommonError { message = fmt.tprintf("%v - %v", message, sdl_err), location = location }
}

error_string :: #force_inline proc(error: Error) -> string {
  switch &err in error {
    case CommonError:
      return fmt.aprintf("Error @ %v - %s", err.location, err.message)
  }

  return "Unknown reason"
}
