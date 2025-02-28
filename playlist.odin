package monokl

import "core:path/filepath"
import "core:time"
import "core:os"
import "core:log"
import "core:strings"
import stbi "vendor:stb/image"

PlaylistSortOrder :: enum {
  None,
  Name,
  NameDesc,
  LastModified,
  LastModifiedDesc,
}

ImageInfo :: struct {
  width: i32,
  height: i32,
  channels: i32,
}

PlaylistOptions :: struct {
  sort_order: PlaylistSortOrder,
  skip_hidden: bool,
  only_favorites: bool,
}

PlaylistEntry :: struct {
  is_favorited: bool,
  is_hidden: bool,
  last_modified: time.Time,
  image_info: ImageInfo,
  filename: string,
}

Playlist :: struct {
  base_path: string,
  entries: [dynamic]PlaylistEntry,
  shown_entries: []^PlaylistEntry,
  current_index: u32,
  options: PlaylistOptions,
}

playlist_try_read_options :: proc (playlist: ^Playlist) -> (ok: bool, error: Error) {
  options_file_path := filepath.join({playlist.base_path, ".monokl"}, context.temp_allocator)
  fd, err := os.open(options_file_path)

  if err == os.ENOENT {
    return false, nil
  }

  bytes, is_ok := os.read_entire_file_from_handle(fd, context.temp_allocator)
  return is_ok, nil
}

playlist_try_read_entry :: proc (playlist: ^Playlist, info: os.File_Info, allocator := context.allocator) -> (ok: bool, error: Error) {
  w, h, c: i32

  cpath := strings.clone_to_cstring(info.fullpath, context.temp_allocator)

  is_image := stbi.info(cpath, &w, &h, &c)
  if is_image != 0 {
    clean_path := filepath.clean(info.fullpath) or_return
    return false, ImageLoadingError { path = clean_path, message = string(stbi.failure_reason()) }
  }

  entry := PlaylistEntry {
    filename = strings.clone(info.name, allocator),
    last_modified = info.modification_time,
    is_favorited = false, // TODO
    is_hidden = false, // TODO
  }

  append(&playlist.entries, entry)

  return false, nil
}

playlist_open :: proc(base_path: string, allocator := context.allocator) -> (playlist: Playlist, error: Error) {
  info := os.lstat(base_path, allocator) or_return
  defer os.file_info_delete(info)

  if !info.is_dir {
    parent_path := filepath.dir(base_path, allocator)
    return playlist_open(parent_path)
  }

  fd := os.open(info.fullpath) or_return

  files: []os.File_Info
  files = os.read_dir(fd, 0, allocator) or_return
  defer os.file_info_slice_delete(files, allocator)

  pl := Playlist {
    base_path = strings.clone(info.fullpath, allocator),
    current_index = 0,
    entries = {},
    shown_entries = {},
    options = PlaylistOptions {
      only_favorites = false,
      skip_hidden = true,
      sort_order = .LastModified,
    },
  }

  options_loaded, oerr := playlist_try_read_options(&pl)
  if oerr != nil {
    log.warn("Failed to read playlist options for path %s due to %v", pl.base_path, oerr)
  }

  for file in files {
    if file.name == ".monokl" {
      continue
    }

    if !file.is_dir {
      playlist_try_read_entry(&pl, file) or_continue
    }
  }

  log.infof("Loaded playlist from %s with %d entries %s", info.fullpath, len(pl.entries), "and options" if options_loaded else "but without options")

  return pl, nil
}
