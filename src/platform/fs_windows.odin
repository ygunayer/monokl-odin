package platform

import "core:os"
import "core:sys/windows"

is_file_hidden :: proc(info: os.File_Info) -> bool {
  path := windows.utf8_to_wstring(info.fullpath, context.temp_allocator)
  defer free(path, context.temp_allocator)

  attrs := windows.GetFileAttributesW(path)
  return (attrs & windows.FILE_ATTRIBUTE_HIDDEN) == windows.FILE_ATTRIBUTE_HIDDEN
}
