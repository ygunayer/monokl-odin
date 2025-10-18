package monokl

import "core:fmt"
import "base:runtime"

BaseError :: struct {
  location: runtime.Source_Code_Location,
}

CommonError :: struct {
  using _: BaseError,
  message: string,
}

Win32Error :: struct {
  using _: BaseError,
  message: string,
  error_code: u32,
}

Error :: union {
  CommonError,
  Win32Error,
}

error_stringify :: proc(error: ^Error) -> string {
  switch err in error {
    case CommonError:
      return fmt.tprintf("Error @ %v - %s", err.location, err.message)

    case Win32Error:
      return fmt.tprintf("Win32 Error @ %v - %s (0x%x)", err.location, err.message, err.error_code)
  }

  return "Unknown error"
}
