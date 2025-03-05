package app

SdlError :: struct {
  msg: string,
}

make_sdl_error :: proc(err: cstring) -> SdlError {
  assert(err != nil, "attempted to create an SDL error from a nil cstring")
  return SdlError { msg = string(err) }
}
