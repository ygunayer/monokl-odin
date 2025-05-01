package monokl

import "core:log"

CAPACITY :: 64

Stack :: struct {
  items: [CAPACITY]WindowId,
  size: u32,
}

stack_find_index :: proc(stack: ^Stack, id: WindowId) -> (idx: u32, found: bool) {
  for i in 0..<stack.size {
    if stack.items[i] == id {
      return idx, true
    }
  }
  return 0, false
}

stack_is_full :: proc(stack: ^Stack) -> bool {
  return stack.size == CAPACITY
}

stack_is_empty :: proc(stack: ^Stack) -> bool {
  return stack.size == 0
}

stack_peek :: proc(stack: ^Stack) -> (id: WindowId, found: bool) {
  if stack.size == 0 {
    return 0, false
  }

  return stack.items[0], true
}

stack_push :: proc(stack: ^Stack, id: WindowId) {
  idx, found := stack_find_index(stack, id)

  if !found {
    if stack_is_full(stack) {
      for i in 1..<stack.size {
        stack.items[i] = stack.items[i - 1]
      }
    } else if stack_is_empty(stack) {
      stack.size += 1
    } else {
      for i in 0..<stack.size {
        stack.items[i + 1] = stack.items[i]
      }
      stack.size += 1
    }
  } else {
    for i in 1..=idx {
      stack.items[i] = stack.items[i - 1]
    }

    stack.size += 1
  }

  stack.items[0] = id
}

stack_delete :: proc(stack: ^Stack, id: WindowId) -> bool {
  idx, found := stack_find_index(stack, id)
  if !found {
    return false
  }

  for i in idx..<(stack.size-1) {
    stack.items[i] = stack.items[i + 1]
  }

  stack.items[stack.size - 1] = 0
  stack.size -= 1
  return true
}
