package monokl

import "core:sys/windows"
import "core:strings"
import "core:log"

WNDCLASS_NAME :: "monoklWndClass"

Platform :: struct {
  inited: bool,
  next_window_id: WindowId,
  hinstance: windows.HINSTANCE,
  windows: map[windows.HWND]WindowId,
}

platform: Platform

windows_handle_message :: proc "std" (hwnd: windows.HWND, msg: windows.UINT, wparam: windows.WPARAM, lparam: windows.LPARAM) -> int {
  return windows.DefWindowProcW(hwnd, msg, wparam, lparam)
}

platform_init :: proc() -> Error {
  assert(!platform.inited)

  hinstance := windows.GetModuleHandleW(nil)
  if hinstance == nil {
    return windows_last_error()
  }

  wndclass := windows.WNDCLASSEXW {
    cbSize = size_of(windows.WNDCLASSEXW),
    lpfnWndProc = windows_handle_message,
  }
  register_class_result := windows.RegisterClassExW(&wndclass)
  if !windows.SUCCEEDED(register_class_result) {
    return windows_last_error()
  }

  platform.next_window_id = 1
  platform.windows = make(map[windows.HWND]WindowId)
  platform.inited = true

  return nil
}

platform_create_window :: proc(w, h: i32, title: string) -> (WindowId, Error) {
  assert(platform.inited)
  hwnd := windows.CreateWindowExW(
    0,
    windows.L(WNDCLASS_NAME),
    windows.utf8_to_wstring(title),
    windows.WS_OVERLAPPEDWINDOW,
    windows.CW_USEDEFAULT, windows.CW_USEDEFAULT,
    w, h,
    nil,
    nil,
    platform.hinstance,
    nil,
  )
  if hwnd == nil {
    return 0, windows_last_error()
  }
  windows.ShowWindow(hwnd, windows.SW_SHOW)
  window_id := platform.next_window_id
  platform.windows[hwnd] = window_id
  platform.next_window_id += 1
  log.debugf("Window created hwnd=%p, window_id=%d\n", hwnd, window_id)
  return window_id, nil
}

platform_close_window :: proc(window_id: WindowId) -> bool {
  for hwnd in platform.windows {
    if platform.windows[hwnd] == window_id {
      windows.DestroyWindow(hwnd)
      delete_key(&platform.windows, hwnd)
      log.debugf("Window closed hwnd=%p, window_id=%d\n", hwnd, window_id)
      return true
    }
  }
  return false
}

platform_dispatch_events :: proc() {
  @(static) msg: windows.MSG
  for windows.PeekMessageW(&msg, nil, 0, 0, windows.PM_REMOVE) {
    windows.TranslateMessage(&msg)
    windows.DispatchMessageW(&msg)
  }
}

platform_destroy :: proc() {
  if platform.windows != nil {
    for w in platform.windows {
      if w != nil {
        windows.DestroyWindow(w)
      }
    }
    delete(platform.windows)
    platform.windows = nil
  }

  platform.next_window_id = 0
  platform.hinstance = nil
  platform.inited = false
}
