package monokl

import "core:os"
import "core:path/filepath"
import "core:log"
import "core:fmt"
import "core:strings"
import "vendor:sdl3"

FileEntry :: struct {
  full_path: string,

  // don't delete
  filename: string,
}

Window :: struct {
  id: sdl3.WindowID,
  wnd: ^sdl3.Window,
  rnd: ^sdl3.Renderer,

  loaded: bool,
  folder_path: string,
  files: map[string]FileEntry,
}

// window_load_files :: proc(window: ^Window, files: []string) -> Error {
//   assert(window != nil)

//   folder_names := make(map[string]string)
//   defer delete(folder_names)

//   for file in files {
//     if os.is_dir(file) && file not_in folder_names {
//       folder_names[file] = file
//     }

//     if os.is_file(file) {
//       folder := filepath.dir(file)
//       if folder not_in folder_names {
//         folder_names[folder] = file
//       }
//     }
//   }

//   if len(folder_names) == 1 {
//     for folder, _ in folder_names {
//       window_unload_folder(window) or_return
//       return window_load_folder(window, folder)
//     }
//   }

//   for folder, _ in folder_names {
//     window_load_folder(window, folder) or_return
//   }

//   return nil
// }

window_load_folder :: proc(window: ^Window, full_path: string) -> Error {
  assert(window != nil)

  if window.loaded && strings.compare(window.folder_path, full_path) == 0 {
    return nil
  }

  if !os.is_directory(full_path) {
    return common_error(fmt.tprintf("The specified path is not a folder: %s", full_path))
  }

  file_infos, err := os.read_all_directory_by_path(full_path, context.temp_allocator)
  if err != nil {
    return common_error(fmt.tprintf("Failed to iterate through files in directory %s with reason %v", full_path, err))
  }

  window.loaded = true
  window.folder_path = strings.clone(full_path)
  window.files = make(map[string]FileEntry)
  sdl3.SetWindowTitle(window.wnd, fmt.ctprintf("monokl - %s", full_path))

  for file_info in file_infos {
    if !app_is_supported_file(file_info.fullpath) {
      continue
    }

    full_file_path := strings.clone(file_info.fullpath)
    filename := os.base(full_file_path)
    window.files[filename] = {
      filename = filename,
      full_path = full_file_path,
    }
  }

  log.debugf("Window %d opened %d files from folder %s", window.id, len(window.files), full_path)

  return nil
}

window_unload_folder :: proc(window: ^Window) -> Error {
  assert(window != nil)
  if !window.loaded {
    return nil
  }

  delete(window.folder_path)

  if window.files != nil {
    for _, file in window.files {
      delete(file.full_path)
    }
    delete(window.files)
    window.files = nil
  }

  return nil
}

window_go_to_file :: proc(window: ^Window, full_path: string) {

}
