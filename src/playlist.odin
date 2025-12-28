package monokl

import "core:log"
import "core:time"
import "core:slice"
import "core:strings"
import "core:os/os2"
import stbi "vendor:stb/image"

PlaylistSortOrder :: enum {
  NameAsc,
  NameDesc,
  LastModifiedAsc,
  LastModifiedDesc,
}

Playlist :: struct {
  root_path: string,

  entries: map[string]PlaylistEntry,
  total_count: int,
  unsupported_count: int,

  current_entry: ^PlaylistEntry,
  current_index: int,
  shown_entries: []^PlaylistEntry,
}

PlaylistEntry :: struct {
  full_path: string,
  parent_path: string,
  filename: string,
  extension: string,
  last_modified: time.Time,
  supported: bool,
}

playlist_entry_compare_by_name_asc :: proc(a, b: ^PlaylistEntry) -> slice.Ordering {
  diff := strings.compare(a.filename, b.filename)
  return .Equal if diff == 0 else (.Greater if diff > 0 else .Less)
}

playlist_entry_compare_by_name_desc :: proc(a, b: ^PlaylistEntry) -> slice.Ordering {
  return -playlist_entry_compare_by_name_asc(a, b)
}

playlist_entry_compare_by_last_modified_asc :: proc(a, b: ^PlaylistEntry) -> slice.Ordering {
  diff := time.diff(a.last_modified, b.last_modified)
  return .Equal if diff == 0 else (.Greater if diff > 0 else .Less)
}

playlist_entry_compare_by_last_modified_desc :: proc(a, b: ^PlaylistEntry) -> slice.Ordering {
  return -playlist_entry_compare_by_last_modified_asc(a, b)
}

playlist_load_folder :: proc(playlist: ^Playlist, folder_path: string) -> Error {
  assert(playlist != nil)

  file_infos, err := os2.read_all_directory_by_path(folder_path, context.temp_allocator)
  if err != nil {
    return playlist_error_load_folder_failed(err)
  }

  playlist_unload(playlist)

  playlist.entries = make(map[string]PlaylistEntry)

  for file in file_infos {
    filename := strings.clone(file.name)
    full_path := strings.clone(file.fullpath)
    extension := get_file_extension(filename)
    supported := is_supported_filename(filename)

    playlist.entries[filename] = PlaylistEntry {
      full_path = full_path,
      parent_path = folder_path,
      filename = filename,
      extension = extension,
      supported = supported,
    }

    playlist.total_count += 1

    if !supported {
      playlist.unsupported_count += 1
    }
  }

  playlist_set_sort_order(playlist, .NameAsc)

  return nil
}

playlist_set_sort_order :: proc(playlist: ^Playlist, order: PlaylistSortOrder) {
  assert(playlist != nil)

  entries := make([dynamic]^PlaylistEntry, context.temp_allocator)

  for _, &entry in playlist.entries {
    append(&entries, &entry)
  }

  playlist.shown_entries = entries[:]

  cmp: proc(a, b: ^PlaylistEntry) -> slice.Ordering

  switch order {
    case .NameAsc:
      cmp = playlist_entry_compare_by_name_asc

    case .NameDesc:
      cmp = playlist_entry_compare_by_name_desc

    case .LastModifiedAsc:
      cmp = playlist_entry_compare_by_last_modified_asc

    case .LastModifiedDesc:
      cmp = playlist_entry_compare_by_last_modified_desc
  }

  slice.sort_by_cmp(playlist.shown_entries, cmp)

  log.debugf("Sorted playlist entries under %s:", playlist.root_path)
  for e in playlist.shown_entries {
    log.debugf("  %s %s", "+" if e.supported else "-", e.filename)
  }
}

playlist_unload :: proc(playlist: ^Playlist) {
  if playlist == nil {
    return
  }

  playlist.shown_entries = {}

  if playlist.entries != nil {
    for _, &entry in playlist.entries {
      playlist_entry_destroy(&entry)
    }
    delete(playlist.entries)
  }

  playlist.total_count = 0
  playlist.unsupported_count = 0
}

playlist_destroy :: proc(playlist: ^Playlist) {
  if playlist == nil {
    return
  }

  playlist_unload(playlist)
}

playlist_go_to_first :: proc(playlist: ^Playlist) {
  assert(playlist != nil)
  playlist_go_to_index(playlist, 0)
}

playlist_go_to_last :: proc(playlist: ^Playlist) {
  assert(playlist != nil)
  playlist_go_to_index(playlist, len(playlist.shown_entries) - 1)
}

playlist_advance :: proc(playlist: ^Playlist, by: int) {
  assert(playlist != nil)
  num_shown := len(playlist.shown_entries)
  if num_shown < 1 {
    playlist.current_entry = nil
    playlist.current_index = -1
    return
  }
  new_idx := playlist.current_index + by
  if new_idx < 0 {
    new_idx = len(playlist.shown_entries) - 1
  } else if new_idx >= num_shown {
    new_idx = 0
  }
  playlist_go_to_index(playlist, new_idx)
}

playlist_go_to_index :: proc(playlist: ^Playlist, index: int) {
  assert(playlist != nil)
  num_shown := len(playlist.shown_entries)
  if num_shown < 1 || index < 0 || index >= num_shown {
    playlist.current_entry = nil
    playlist.current_index = -1
    return
  }
  playlist.current_entry = playlist.shown_entries[index]
  playlist.current_index = index
  log.debugf("Playlist now at file #%d - %s", playlist.current_index, playlist.current_entry.filename)
}

playlist_go_to_file :: proc(playlist: ^Playlist, filename: string) {
  assert(playlist != nil)
  if !(filename in playlist.entries) {
    return
  }
  playlist.current_entry = &playlist.entries[filename]
  playlist.current_index = -1
  for i in 0..<len(playlist.shown_entries) {
    if playlist.shown_entries[i] == playlist.current_entry {
      playlist.current_index = i
      break
    }
  }
  log.debugf("Playlist now at file #%d - %s", playlist.current_index, playlist.current_entry.filename)
}

playlist_entry_destroy :: proc(entry: ^PlaylistEntry) {
  if entry == nil {
    return
  }

  delete(entry.filename)
  delete(entry.full_path)
}
