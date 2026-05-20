package monokl

import "core:os"
import "core:path/filepath"
import "core:log"
import "core:fmt"
import "core:strings"
import "vendor:sdl3"

FileEntry :: struct {
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

window_load_files :: proc(window: ^Window, files: []string) -> Error {
  assert(window != nil)

  folder_names := make(map[string]string)
  defer delete(folder_names)

  for file in files {
    if os.is_dir(file) && file not_in folder_names {
      folder_names[file] = file
    }

    if os.is_file(file) {
      folder := filepath.dir(file, context.temp_allocator)
      if folder not_in folder_names {
        folder_names[folder] = file
      }
    }
  }

  if len(folder_names) == 1 {
    for folder, _ in folder_names {
      window_unload_folder(window) or_return
      return window_load_folder(window, folder)
    }
  }

  for folder, _ in folder_names {
    window_load_folder(window, folder) or_return
  }

  return nil
}

window_load_folder :: proc(window: ^Window, path: string) -> Error {
  assert(window != nil)

  if window.loaded {
    if strings.compare(window.folder_path, path) == 0 {
      return nil
    }
    platform_open_window(path) or_return
    return nil
  }

  is_path_a_file := os.is_file(path)
  folder_path := filepath.dir(path) if is_path_a_file else strings.clone(path)

  window.loaded = true
  window.folder_path = folder_path
  window.files = make(map[string]FileEntry)
  sdl3.SetWindowTitle(window.wnd, fmt.ctprintf("monokl - %s", path))


  return nil
}

window_unload_folder :: proc(window: ^Window) -> Error {
  assert(window != nil)
  if !window.loaded {
    return nil
  }

  delete(window.folder_path)

  if window.files != nil {
    for file in window.files {

    }
    delete(window.files)
    window.files = nil
  }

  return nil
}
