package monokl

import "core:os"
import win32 "core:sys/windows"

MemoryMappedFile :: struct {
  hfile: win32.HANDLE,
  hmap: win32.HANDLE,
  data: rawptr,
  size: u32,
}

is_file_hidden :: proc(info: os.File_Info) -> bool {
  path := win32.utf8_to_wstring(info.fullpath)
  attrs := win32.GetFileAttributesW(path)
  return (attrs & win32.FILE_ATTRIBUTE_HIDDEN) == win32.FILE_ATTRIBUTE_HIDDEN
}

mmap_file :: proc(path: string) -> (file: MemoryMappedFile, err: os.Error) {
  wide_path := win32.utf8_to_wstring(path)
  defer free(wide_path)

  hfile := win32.CreateFileW(
    wide_path,
    win32.GENERIC_READ,
    win32.FILE_SHARE_READ,
    nil,
    win32.OPEN_EXISTING,
    win32.FILE_ATTRIBUTE_NORMAL,
    nil
  )

  if hfile == win32.INVALID_HANDLE_VALUE {
    return {}, os.ERROR_INVALID_HANDLE
  }

  hmap := win32.CreateFileMappingW(hfile, nil, win32.PAGE_READONLY, 0, 0, nil)
  if hmap == nil {
    win32.CloseHandle(hfile)
    return {}, os.ERROR_INVALID_HANDLE
  }

  data := win32.MapViewOfFile(hmap, win32.FILE_MAP_READ, 0, 0, 0)
  if data == nil {
    win32.CloseHandle(hfile)
    win32.CloseHandle(hmap)
    return {}, os.ERROR_INVALID_HANDLE
  }

  size_high: win32.LARGE_INTEGER
  size_low := win32.GetFileSizeEx(hfile, &size_high)

  return MemoryMappedFile {
    hfile = hfile,
    hmap = hmap,
    data = data,
    size = u32(size_low), // most likely smaller than 4gb
  }, nil
}

unmmap_file :: proc(mapped_file: ^MemoryMappedFile) {
  if mapped_file.data != nil {
    win32.UnmapViewOfFile(mapped_file.data)
    mapped_file.data = nil
  }

  if mapped_file.hmap != nil {
    win32.CloseHandle(mapped_file.hmap)
    mapped_file.hmap = nil
  }

  if mapped_file.hfile != nil {
    win32.CloseHandle(mapped_file.hfile)
    mapped_file.hfile = nil
  }

  mapped_file.size = 0
}
