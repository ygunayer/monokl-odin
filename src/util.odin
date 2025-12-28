package monokl

import "core:strings"
import "core:os/os2"
import "core:path/filepath"

get_folder_path :: proc(path: string, allocator := context.temp_allocator) -> (string, bool, os2.Error) {
  abs_path, err := os2.get_absolute_path(path, allocator)
  if err != nil {
    return "", false, err
  }

  if os2.is_directory(abs_path) {
    return abs_path, true, nil
  }

  if os2.is_file(abs_path) {
    return filepath.dir(abs_path, allocator), false, nil
  }

  return "", false, nil
}

is_supported_filename :: proc(filename: string) -> bool {
  ext := filepath.ext(filename)
  lower_ext := strings.to_lower(ext)
  defer delete(lower_ext)
  return (
    strings.compare(lower_ext, ".jpg") == 0 ||
    strings.compare(lower_ext, ".jpeg") == 0 ||
    strings.compare(lower_ext, ".bmp") == 0 ||
    strings.compare(lower_ext, ".png") == 0 ||
    strings.compare(lower_ext, ".psd") == 0 ||
    strings.compare(lower_ext, ".tga") == 0 ||
    strings.compare(lower_ext, ".gif") == 0
  )
}

get_file_extension :: proc(filename: string) -> string {
  return filepath.ext(filename)
}
