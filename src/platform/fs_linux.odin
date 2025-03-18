package platform

import "core:os"

is_file_hidden :: proc(info: os.File_Info) -> bool {
  return len(info.name) > 0 && info.name[0] == '.'
}
