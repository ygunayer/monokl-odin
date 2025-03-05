package monokl

import "core:strings"
import "core:os"
import "base:runtime"
import "core:io"
import "core:encoding/json"

import "playlist"
import "app"

Error :: union {
  string,
  app.SdlError,
  playlist.Playlist_Error,
}
