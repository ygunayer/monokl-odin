package monokl

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:container/queue"
import "vendor:glfw"

PlatformError :: struct {
  using _: BaseError,
  message: string,
  error_code: c.int,
}

PlatformWindow :: glfw.WindowHandle

PlatformTicks :: f64

glfw_get_app_window :: proc "c" (window: glfw.WindowHandle) -> ^AppWindow {
  ptr := glfw.GetWindowUserPointer(window)
  if ptr == nil {
    return nil
  }
  return cast(^AppWindow)ptr
}

glfw_handle_key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
  app_window := glfw_get_app_window(window)
  if app_window == nil {
    return
  }
  // TODO(platform): maybe move these to somewhere else?
  context = runtime.default_context()
  log.debugf("%p - Received key event: %d, %d, %d", window, key, action, mods)
  event := glfw_translate_key_event(key, scancode, action, mods)
  queue.enqueue(&app_window.event_queue, event)
}

glfw_handle_drop_callback :: proc "c" (window: glfw.WindowHandle, size: c.int, paths: [^]cstring) {
  app_window := glfw_get_app_window(window)
  if app_window == nil {
    return
  }
  // TODO(platform): maybe move these to somewhere else?
  context = runtime.default_context()
  event: FileDropEvent
  event.file_paths = make([dynamic]string, context.temp_allocator)
  for i in 0..<size {
    path := strings.clone_from_cstring(paths[i], context.temp_allocator)
    append(&event.file_paths, path)
  }
  queue.enqueue(&app_window.event_queue, event)
  log.debugf("Enqueued drop event: %v", event)
}

glfw_last_error :: proc(location := #caller_location) -> Error {
  descr, code := glfw.GetError()
  return PlatformError {
    location = location,
    message = descr,
    error_code = code,
  }
}

platform_error_stringify :: proc(err: ^PlatformError) -> string {
  return fmt.tprintf("Platform Error @ %v - %s (0x%x)", err.location, err.message, err.error_code)
}

platform_init :: proc() -> Error {
  err := glfw.Init()
  if !err {
    return glfw_last_error()
  }
  return nil
}

platform_create_window :: proc(w, h: int, title: string) -> (PlatformWindow, Error) {
  handle := glfw.CreateWindow(1366, 768, cstring("monokl"), nil, nil)
  if handle == nil {
    return nil, glfw_last_error()
  }
  glfw.SetKeyCallback(handle, glfw_handle_key_callback)
  glfw.SetDropCallback(handle, glfw_handle_drop_callback)
  return handle, nil
}

platform_request_close_window :: proc(window: PlatformWindow) {
  if window == nil {
    return
  }
  glfw.SetWindowShouldClose(window, true)
}

platform_set_window_user_ptr :: proc(window: PlatformWindow, ptr: rawptr) {
  assert(window != nil)
  glfw.SetWindowUserPointer(window, ptr)
}

platform_show_window :: proc(window: PlatformWindow) {
  assert(window != nil)
  glfw.ShowWindow(window)
}

platform_get_ticks :: proc() -> PlatformTicks {
  return glfw.GetTime()
}

platform_poll_events :: proc() {
  glfw.PollEvents()
}

platform_destroy :: proc() {
  glfw.Terminate()
}
