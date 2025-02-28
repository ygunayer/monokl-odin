package monokl

import "core:strings"
import "core:os"
import "base:runtime"

SdlError :: struct {
  msg: string,
}

ImageLoadingError :: struct {
  path: string,
  message: string,
}

Error :: union {
  string,
  SdlError,
  ImageLoadingError,
  os.Error,
  runtime.Allocator_Error,
}

make_sdl_error :: proc(err: cstring) -> Error {
  assert(err != nil, "attempted to create an SDL error from a nil cstring")
  return SdlError { msg = string(err) }
}
