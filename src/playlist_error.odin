package monokl

import "core:os/os2"
import "core:fmt"

PlaylistErrorReason_LoadFolderFailed :: struct {
  error: os2.Error,
}

PlaylistErrorReason :: union {
  PlaylistErrorReason_LoadFolderFailed,
}

PlaylistError :: struct {
  using _: BaseError,
  reason: PlaylistErrorReason,
}

playlist_error_with_reason :: proc(reason: PlaylistErrorReason, location := #caller_location) -> Error {
  return PlaylistError {
    location = location,
    reason = reason,
  }
}

playlist_error_load_folder_failed :: proc(error: os2.Error, location := #caller_location) -> Error {
  return playlist_error_with_reason(
    PlaylistErrorReason_LoadFolderFailed {
      error = error,
    },
    location
  )
}

playlist_error_stringify :: proc(error: ^PlaylistError) -> string {
  switch reason in error.reason {
    case PlaylistErrorReason_LoadFolderFailed: {
      return fmt.tprintf("Playlist Error @ %v - Failed to load folder due to %v", error.location, reason.error)
    }
  }

  return fmt.tprintf("Playlist Error @ %v - Unexpected error", error.location)
}
