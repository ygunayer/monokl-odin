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
import stbi "vendor:stb/image"

SUPPORTED_EXTENSIONS :: [?]string{
  ".jpg",
  ".jpeg",
  ".png",
  ".bmp",
  ".gif",
}

ImageInfo :: struct {
  width: i32,
  height: i32,
  channels: i32,
}

PlaylistEntry :: struct {
  is_favorited: bool,
  is_hidden: bool,
  is_excluded: bool,
  last_modified: time.Time,
  image_info: ImageInfo,
  filename: string,
}

Playlist :: struct {
  base_path: string,
  entries: [dynamic]^PlaylistEntry,
  shown_entries: []^PlaylistEntry,
  current_index: int,
  entry_count: int,
  options: PlaylistOptions,
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

playlist_entry_compare_names :: proc(a: ^PlaylistEntry, b: ^PlaylistEntry) -> bool {
  return a.filename < b.filename
}

playlist_entry_compare_last_modified_dates :: proc(a: ^PlaylistEntry, b: ^PlaylistEntry) -> bool {
  diff := time.diff(a.last_modified, b.last_modified)
  return diff < 0
}

playlist_try_read_entry :: proc (playlist: ^Playlist, info: os.File_Info) -> (ok: bool, error: Playlist_Error) {
  w, h, c: i32

  cpath := strings.clone_to_cstring(info.fullpath, context.temp_allocator)

  is_image := stbi.info(cpath, &w, &h, &c)
  if is_image == 0 {
    clean_path := filepath.clean(info.fullpath) or_return
    defer delete(clean_path)
    return false, Playlist_ImageLoadingError { path = clean_path, message = string(stbi.failure_reason()) }
  }

  is_hidden := false

  when ODIN_OS == .Windows {

  } else {
    is_hidden = info.name[0] == '.'
  }

  entry := new(PlaylistEntry)
  entry.filename = strings.clone(info.name)
  entry.last_modified = info.modification_time
  entry.is_favorited = false // TODO
  entry.is_hidden = false // TODO

  append(&playlist.entries, entry)

  return false, nil
}

playlist_open :: proc(playlist: ^Playlist, base_path: string) -> Playlist_Error {
  log.infof("Opening file at %v", base_path)
  info := os.lstat(base_path) or_return
  defer os.file_info_delete(info)

  playlist.base_path = strings.clone(base_path)

  if !info.is_dir {
    parent_path := filepath.dir(base_path)
    defer delete(parent_path)

    err := playlist_open(playlist, parent_path)
    if err != nil {
      return err
    }

    for i in 0..<playlist.entry_count {
      entry := playlist.shown_entries[i]
      if entry != nil && strings.compare(entry.filename, info.name) == 0 {
        playlist.current_index = i
        break
      }
    }

    return nil
  }

  fd := os.open(info.fullpath) or_return

  files: []os.File_Info
  files = os.read_dir(fd, 0) or_return
  defer os.file_info_slice_delete(files)

  options_loaded, oerr := playlist_options_load(playlist)
  if oerr != nil {
    log.warnf("Failed to read playlist options for path %s due to %v", playlist.base_path, oerr)
  } else {
    log.debugf("Loaded playlist options for %s -- favorites: %d", playlist.base_path, len(playlist.options.favorites))
  }

  for file in files {
    if file.is_dir {
      continue
    }

    ext := strings.to_lower(filepath.ext(file.fullpath), context.temp_allocator)
    is_supported := false
    for sext in SUPPORTED_EXTENSIONS {
      if ext == sext {
        is_supported = true
        break
      }
    }

    if !is_supported {
      continue
    }

    _, ierr := playlist_try_read_entry(playlist, file)
    if ierr != nil {
      log.warnf("Failed to load image %v", ierr)
      continue
    }
  }

  playlist_refresh_shown_entries(playlist)

  log.infof("Loaded playlist from %s with %d entries (%d shown) %s", info.fullpath, len(playlist.entries), playlist.entry_count, "and options" if options_loaded else "but without options")

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
    if playlist.options.skip_excluded && entry.is_excluded {
      continue
    }

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
}

playlist_destroy :: proc(playlist: ^Playlist) {
  if playlist == nil {
    return
  }

  delete(playlist.base_path)

  for entry in playlist.entries {
    delete(entry.filename)
    free(entry)
  }

  delete(playlist.entries)
  free(playlist)
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

playlist_advance :: proc(playlist: ^Playlist, by: int) -> ^PlaylistEntry {
  playlist.current_index += by
  if playlist.current_index < 0 {
    playlist.current_index = playlist.entry_count + by
  } else if playlist.current_index > playlist.entry_count {
    playlist.current_index = playlist.current_index % playlist.entry_count
  }
  return playlist.shown_entries[playlist.current_index]
}
