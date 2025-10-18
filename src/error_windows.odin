package monokl

import "core:fmt"
import win32 "core:sys/windows"

windows_error :: proc(hresult: win32.HRESULT) -> Error {
  // TODO
  return nil
}

windows_last_error :: proc(location := #caller_location) -> Error {
  err_code := win32.GetLastError()
  buf := new(win32.wstring)
  defer free(buf)

  buf_size := win32.FormatMessageW(
    win32.FORMAT_MESSAGE_FROM_SYSTEM | win32.FORMAT_MESSAGE_ALLOCATE_BUFFER,
    nil,
    err_code,
    0,
    win32.LPWSTR(buf),
    0,
    nil
  )

  if buf_size == 0 {
    fmt_err_code := win32.GetLastError()
    err_msg := fmt.tprintf("Win32 call failed with error code %d, which we failed to translate with error code %d", err_code, fmt_err_code)
    return Win32Error { message = err_msg, error_code = err_code, location = location }
  }

  message, string_err := win32.wstring_to_utf8(buf^, int(buf_size))
  assert(string_err == nil)
  return Win32Error { message = message, error_code = err_code, location = location }
}
