package app

import "vendor:sdl3"

get_action_mappings :: proc(allocator := context.allocator) -> [dynamic]ActionMapping {
  mappings := make([dynamic]ActionMapping, allocator)

  append(&mappings, ActionMapping{ type = .OpenNewWindow, trigger = KeyboardActionTrigger { key = sdl3.K_N, ctrl = true } })
  append(&mappings, ActionMapping{ type = .CloseWindow, trigger = KeyboardActionTrigger { key = sdl3.K_W, ctrl = true } })
  append(&mappings, ActionMapping{ type = .ResetZoom, trigger = KeyboardActionTrigger { key = sdl3.K_N, ctrl = true, shift = true } })

  return mappings
}
