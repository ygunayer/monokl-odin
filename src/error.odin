package monokl

import "core:fmt"
import "core:c"
import "vendor:glfw"
import "base:runtime"

BaseError :: struct {
  location: runtime.Source_Code_Location,
}

CommonError :: struct {
  using _: BaseError,
  message: string,
}

Error :: union {
  CommonError,
  PlatformError,
  PlaylistError,
}

error_stringify :: proc(error: ^Error) -> string {
  switch &err in error {
    case CommonError:
      return fmt.tprintf("Error @ %v - %s", err.location, err.message)

    case PlatformError:
      return platform_error_stringify(&err)

    case PlaylistError:
      return playlist_error_stringify(&err)
  }

  return "Unknown error"
}
