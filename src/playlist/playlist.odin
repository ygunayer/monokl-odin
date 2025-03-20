package playlist

import "core:path/filepath"
import "core:time"
import "core:os"
import "core:log"
import "core:strings"
import "core:io"
import "core:bytes"
import "core:slice"
import "base:runtime"
import "core:encoding/json"
import "../platform"
import stbi "vendor:stb/image"
import "vendor:sdl3"

ImageInfo :: struct {
  width: i32,
  height: i32,
  channels: i32,
}

PlaylistEntry :: struct {
  is_favorited: bool,
  is_hidden: bool,
  is_supported: bool,
  full_path: string,
  filename: string,
  extension: string,
  last_modified: time.Time,
}

Playlist :: struct {
  base_path: string,
  entries: [dynamic]^PlaylistEntry,
  shown_entries: []^PlaylistEntry,
  current_index: int,
  entry_count: int,
  options: PlaylistOptions,
  favorites: []string,
}

Playlist_OptionsError :: union #shared_nil {
  json.Marshal_Error,
  json.Unmarshal_Error,
}

Playlist_ImageLoadingError :: struct {
  path: string,
  message: string,
}

Playlist_Error :: union {
  Playlist_ImageLoadingError,
  Playlist_OptionsError,
  io.Error,
  os.Error,
  runtime.Allocator_Error,
}

playlist_init :: proc(playlist: ^Playlist) {
  playlist.entries = make([dynamic]^PlaylistEntry)
  playlist.shown_entries = playlist.entries[:]
}

playlist_entry_compare_names :: proc(a: ^PlaylistEntry, b: ^PlaylistEntry) -> bool {
  return a.filename < b.filename
}

playlist_entry_compare_last_modified_dates :: proc(a: ^PlaylistEntry, b: ^PlaylistEntry) -> bool {
  diff := time.diff(a.last_modified, b.last_modified)
  return diff < 0
}

playlist_try_read_entry :: proc(playlist: ^Playlist, info: os.File_Info) -> (ok: bool, error: Playlist_Error) {
  w, h, c: i32

  entry := new(PlaylistEntry)
  entry.full_path = strings.clone(info.fullpath)
  entry.filename = strings.clone(info.name)
  entry.last_modified = info.modification_time
  entry.is_favorited = false
  entry.is_supported = is_supported_file(info)
  entry.is_hidden = platform.is_file_hidden(info)

  for fav in playlist.favorites {
    if info.name == fav {
      entry.is_favorited = true
      break
    }
  }

  append(&playlist.entries, entry)

  return false, nil
}

playlist_open_path :: proc(playlist: ^Playlist, path: string) -> Playlist_Error {
  log.infof("Opening file or folder at %v", path)
  info := os.lstat(path, context.temp_allocator) or_return

  if !info.is_dir {
    parent := filepath.dir(path, context.temp_allocator)
    err := playlist_open_path(playlist, parent)
    if err != nil {
      return err
    }

    playlist_go_to_filename(playlist, info.name)
    return nil
  }

  fd := os.open(info.fullpath) or_return

  files: []os.File_Info
  files = os.read_dir(fd, 0) or_return
  defer os.file_info_slice_delete(files)

  return playlist_open_files(playlist, info.fullpath, files)
}

playlist_open_files :: proc(playlist: ^Playlist, parent_path: string, files: []os.File_Info) -> Playlist_Error {
  log.infof("Opening %d file under %s", len(files), parent_path)

  options_loaded, oerr := playlist_options_load(playlist)
  if oerr != nil {
    log.warnf("Failed to read playlist options for path %s due to %v", playlist.base_path, oerr)
  } else {
    log.debugf("Loaded playlist options for %s -- favorites: %d", playlist.base_path, len(playlist.options.favorites))
  }

  for file in files {
    if file.is_dir || file.name == ".monokl" {
      continue
    }

    e, ierr := playlist_try_read_entry(playlist, file)
    if ierr != nil {
      log.warnf("Failed to load image %v", ierr)
      continue
    }
  }

  playlist_refresh_shown_entries(playlist)

  log.infof("Loaded playlist from %s with %d entries (%d shown) %s", parent_path, len(playlist.entries), playlist.entry_count, "and options" if options_loaded else "but without options")

  return nil
}

playlist_refresh_shown_entries :: proc(playlist: ^Playlist) {
  num_entries := len(playlist.entries)
  playlist.entry_count = num_entries
  if num_entries < 1 {
    return
  }

  delete(playlist.shown_entries)

  new_entries := make_dynamic_array([dynamic]^PlaylistEntry, context.temp_allocator)
  for entry in playlist.entries {
    if playlist.options.skip_hidden && entry.is_hidden {
      continue
    }

    append(&new_entries, entry)
  }

  playlist.shown_entries = playlist.entries[:]
  switch playlist.options.sort_order {
    case .Name:
      slice.sort_by(playlist.shown_entries, playlist_entry_compare_names)
    case .NameDesc:
      slice.reverse_sort_by(playlist.shown_entries, playlist_entry_compare_names)
    case .LastModified:
      slice.sort_by(playlist.shown_entries, playlist_entry_compare_last_modified_dates)
    case .LastModifiedDesc:
      slice.reverse_sort_by(playlist.shown_entries, playlist_entry_compare_last_modified_dates)
  }

  playlist.entry_count = len(playlist.shown_entries)

  if playlist.entry_count > 0 {
    playlist_go_to_first(playlist)
  }
}

playlist_destroy :: proc(playlist: ^Playlist) {
  if playlist == nil {
    return
  }

  delete(playlist.base_path)

  for entry in playlist.entries {
    playlist_entry_destroy(entry)
    free(entry)
  }

  delete(playlist.entries)
}

playlist_get_current_entry :: proc(playlist: ^Playlist) -> ^PlaylistEntry {
  if playlist == nil {
    return nil
  }

  if playlist.current_index < 0 || playlist.current_index > len(playlist.shown_entries) {
    return nil
  }

  if playlist.entry_count < 1 {
    return nil
  }

  return playlist.shown_entries[playlist.current_index]
}

@(private)
_playlist_make_current :: proc(playlist: ^Playlist, idx: int) -> ^PlaylistEntry {
  if playlist == nil {
    return nil
  }
  playlist.current_index = idx
  return playlist.shown_entries[idx]
}

playlist_advance :: proc(playlist: ^Playlist, by: int) -> ^PlaylistEntry {
  if len(playlist.shown_entries) < 1 {
    return nil
  }

  idx := playlist.current_index + by
  if idx < 0 {
    idx = playlist.entry_count + by
  } else if idx >= playlist.entry_count {
    idx = idx % playlist.entry_count
  }

  return _playlist_make_current(playlist, idx)
}

playlist_go_to_first :: proc(playlist: ^Playlist) -> ^PlaylistEntry {
  if len(playlist.shown_entries) < 1 {
    return nil
  }
  return _playlist_make_current(playlist, 0)
}

playlist_go_to_last :: proc(playlist: ^Playlist) -> ^PlaylistEntry {
  num_entries := len(playlist.shown_entries)
  if num_entries < 1 {
    return nil
  }
  return _playlist_make_current(playlist, num_entries - 1)
}

playlist_go_to_filename :: proc(playlist: ^Playlist, filename: string) -> ^PlaylistEntry {
  num_entries := len(playlist.shown_entries)
  if num_entries < 1 {
    return nil
  }

  for i in 0..<num_entries {
    entry := playlist.shown_entries[i]
    if entry.filename == filename {
      return _playlist_make_current(playlist, i)
    }
  }

  return nil
}
playlist_entry_destroy :: proc(entry: ^PlaylistEntry) {
  if entry == nil {
    return
  }

  delete(entry.filename)
  delete(entry.extension)
  delete(entry.full_path)
}
