package monokl

import "core:strings"
import "core:os"
import "base:runtime"
import "core:io"
import "core:encoding/json"
import "core:mem"

Application_InitError :: struct {
  message: string,
}

Application_Error :: union {
  Window_Error,
  Application_InitError,
}

Media_LoadingError :: struct {
  reason: string,
}

Media_UnsupportedTypeError :: struct {
  bits: i32,
  channels: i32,
}

Media_SdlError :: struct {
  reason: string,
}

Media_Error :: union {
  os.Error,
  Media_SdlError,
  Media_LoadingError,
  Media_UnsupportedTypeError,
}

Playlist_OptionsError :: union #shared_nil {
  json.Marshal_Error,
  json.Unmarshal_Error,
}

Playlist_ImageLoadingError :: struct {
  path: string,
  message: string,
}

PlaylistOptions_Error :: union #shared_nil {
  json.Marshal_Error,
  json.Unmarshal_Error,
}

Playlist_Error :: union {
  Playlist_ImageLoadingError,
  Playlist_OptionsError,
  io.Error,
  os.Error,
  runtime.Allocator_Error,
}

Settings_Error :: union {
  os.Error,
}

SdlError :: struct {
  msg: string,
}

make_sdl_error :: proc(err: cstring) -> SdlError {
  assert(err != nil, "attempted to create an SDL error from a nil cstring")
  return SdlError { msg = string(err) }
}


Window_Error :: union {
  SdlError,
  mem.Allocator_Error,
  Playlist_Error,
}

Error :: union {
  string,
  SdlError,
  Playlist_Error,
}
