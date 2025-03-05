package playlist

import "core:os"
import "core:io"
import "core:encoding/json"
import "core:path/filepath"

when ODIN_OS == .Windows {
  ERR_FILE_NOT_FOUND := os.ERROR_NOT_FOUND
} else {
  ERR_FILE_NOT_FOUND := os.ENOENT
}

PlaylistSortOrder :: enum {
  None,
  Name,
  NameDesc,
  LastModified,
  LastModifiedDesc,
}

PlaylistOptions :: struct {
  skip_hidden: bool,
  skip_excluded: bool,
  only_favorites: bool,
  sort_order: Maybe(PlaylistSortOrder),
  favorites: [dynamic]string,
}

PlaylistOptions_Error :: union #shared_nil {
  json.Marshal_Error,
  json.Unmarshal_Error,
}

playlist_options_read :: proc(opts: ^PlaylistOptions, input: []byte, loc := #caller_location) -> PlaylistOptions_Error {
  return json.unmarshal(input, opts, allocator = context.temp_allocator)
}

playlist_options_write :: proc(opts: ^PlaylistOptions, w: io.Writer) -> PlaylistOptions_Error {
  json_opts := json.Marshal_Options {
    indentation = 2,
    pretty = false,
    spaces = 0,
    use_spaces = true,
    use_enum_names = true,
  }
  return json.marshal_to_writer(w, opts^, &json_opts)
}

playlist_options_destroy :: proc(opts: ^PlaylistOptions) {
  if opts == nil {
    return
  }

  delete(opts.favorites)
}

playlist_options_load :: proc (playlist: ^Playlist) -> (ok: bool, error: PlaylistOptions_Error) {
  options_file_path := filepath.join({playlist.base_path, ".monokl"}, context.temp_allocator)
  fd, err := os.open(options_file_path)

  if err == ERR_FILE_NOT_FOUND {
    return false, nil
  } 

  bytes, is_ok := os.read_entire_file_from_handle(fd, context.temp_allocator)

  if is_ok {
    playlist_options_read(&playlist.options, bytes) or_return
  }

  return is_ok, nil
}
