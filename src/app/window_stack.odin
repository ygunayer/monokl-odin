package app

import "core:log"

CAPACITY :: 64

WindowIdStack :: struct {
  items: []WindowId,
  size: u32,
  next_idx: u32,
}

window_id_stack_destroy :: proc(stack: ^WindowIdStack) {
  if stack == nil {
    return
  }

  free(&stack.items)
}

window_id_stack_find_index :: proc(stack: ^WindowIdStack, id: WindowId) -> (idx: int, ok: bool) {
  for item, idx in stack.items {
    if item == id {
      return idx, true
    }
  }
  return -1, false
}

window_id_stack_is_empty :: proc(stack: ^WindowIdStack) -> bool {
  return stack.size == 0
}

window_id_stack_is_full :: proc(stack: ^WindowIdStack) -> bool {
  return stack.size == CAPACITY
}

window_id_stack_push :: proc(stack: ^WindowIdStack, id: WindowId) {
  prev_idx, found := window_id_stack_find_index(stack, id)

  if !found {
    if window_id_stack_is_full(stack) {
      for i := 0; i < int(stack.size) - 2; i += 1 {
        stack.items[i] = stack.items[i + 1]
      }

      stack_items
    }
  }

  if found {
    for i := prev_idx; i > 0; i -= 1 {
      stack.items[i] = stack.items[i - 1]
    }
    stack.items[0] = id
  } else {
    if window_id_stack_is_full(stack) {
      for i := CAPACITY - 1; i > 0; i -= 1 {
        stack.items[i] = stack.items[i - 1]
      }
      stack.items[0] = id
    } else {
      for i := stack.size; i > 0; i -= 1 {
        stack.items[i] = stack.items[i - 1]
      }
      stack.items[0] = id
      stack.size += 1
    }
  }

  log.debugf("Stack: %v", stack)
}

window_id_stack_peek :: proc(stack: ^WindowIdStack) -> (id: WindowId, ok: bool) {
  if window_id_stack_is_empty(stack) {
    return 0, false
  }

  return stack.items[0], true
}

window_id_stack_delete :: proc(stack: ^WindowIdStack, id: WindowId) {
  prev_idx, found := window_id_stack_find_index(stack, id)
  if !found {
    return
  }

  for i := prev_idx; i < int(stack.size) - 1; i += 1 {
    stack.items[i] = stack.items[i + 1]
  }
  stack.size -= 1
  log.debugf("Stack: %v", stack)
}
