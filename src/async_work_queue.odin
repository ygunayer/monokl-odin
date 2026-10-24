package monokl

import "core:log"
import "core:sync"
import "core:time"
import "core:thread"
import "core:sync/chan"
import "core:container/queue"
import pqueue "core:container/priority_queue"

AsyncWorkQueue :: struct($C, $T, $R: typeid) {
  user_ctx: C,
  fn_handle_work: proc(user_ctx: C, item: T) -> R,
  fn_handle_result: proc(user_ctx: C, result: R),

  queue: queue.Queue(T),
  mutex: sync.Mutex,

  t_workers: [dynamic]^thread.Thread,
  worker_signal: sync.Cond,

  chan_results: chan.Chan(R),
  t_result_listener: ^thread.Thread,

  started: bool,
  stopped: bool,
}

_make_worker_proc :: proc($C, $T, $R: typeid) -> thread.Thread_Proc {
  return proc(t: ^thread.Thread) {
    q := (^AsyncWorkQueue(C, T, R))(t.data)

    for {
      sync.mutex_lock(&q.mutex)
      for queue.len(q.queue) < 1 && !q.stopped {
        sync.cond_wait(&q.worker_signal, &q.mutex)
      }

      item: T
      has_item := false
      if queue.len(q.queue) > 0 {
        item = queue.dequeue(&q.queue)
        has_item = true
      }

      sync.mutex_unlock(&q.mutex)

      if !has_item && q.stopped {
        break
      }

      if has_item {
        result := q.fn_handle_work(q.user_ctx, item)
        chan.send(q.chan_results, result)
      }
    }
  }
}

_make_result_listener_proc :: proc($C, $T, $R: typeid) -> thread.Thread_Proc {
  return proc(t: ^thread.Thread) {
    q := (^AsyncWorkQueue(C, T, R))(t.data)
    for {
      item, ok := chan.recv(q.chan_results)
      if !ok {
        break
      }
      q.fn_handle_result(q.user_ctx, item)
    }
  }
}

async_work_queue_create :: proc(
  user_ctx: $C,
  fn_handle_work: proc(user_ctx: C, item: $T) -> $R,
  fn_handle_result: proc(user_ctx: C, result: R),
  max_workers: int,
) -> (^AsyncWorkQueue(C, T, R), Error) {
  chan_results, err_chan := chan.create(chan.Chan(R), context.allocator)
  if err_chan != nil {
    return {}, common_error("Failed to create result channel")
  }

  t_workers := make([dynamic]^thread.Thread)
  for i in 0..<max_workers {
    t := thread.create(_make_worker_proc(C, T, R))
    t.init_context = context
    append(&t_workers, t)
  }

  t_result_listener := thread.create(_make_result_listener_proc(C, T, R))
  t_result_listener.init_context = context

  result := new(AsyncWorkQueue(C, T, R))
  result.user_ctx = user_ctx
  result.fn_handle_work = fn_handle_work
  result.fn_handle_result = fn_handle_result
  result.chan_results = chan_results
  result.t_workers = t_workers
  result.t_result_listener = t_result_listener

  for t in t_workers {
    t.data = rawptr(result)
  }
  t_result_listener.data = rawptr(result)

  queue.init(&result.queue)

  return result, nil
}

async_work_queue_start :: proc(queue: ^AsyncWorkQueue($C, $T, $R)) {
  assert(queue != nil)

  if queue.started {
    return
  }

  thread.start(queue.t_result_listener)
  for t in queue.t_workers {
    thread.start(t)
  }

  queue.started = true
  log.debug("Async work queue started")
}

async_work_queue_stop_and_wait :: proc(q: ^AsyncWorkQueue($C, $T, $R)) {
  assert(q != nil)

  {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)
    if q.stopped {
      return
    }
    q.stopped = true
  }

  sync.cond_broadcast(&q.worker_signal)

  chan.close(&q.chan_results)

  thread.join_multiple(..q.t_workers[:])
  thread.join(q.t_result_listener)

  log.debug("Async work queue stopped")
}

async_work_queue_destroy :: proc(q: ^AsyncWorkQueue($C, $T, $R)) {
  if q == nil {
    return
  }

  async_work_queue_stop_and_wait(q)

  if q.t_workers != nil {
    for t in q.t_workers {
      thread.destroy(t)
    }
    delete(q.t_workers)
    q.t_workers = nil
  }

  if q.t_result_listener != nil {
    thread.destroy(q.t_result_listener)
    q.t_result_listener = nil
  }

  queue.destroy(&q.queue)

  chan.destroy(&q.chan_results)
}

async_work_queue_submit :: proc(q: ^AsyncWorkQueue($C, $T, $R), work: T) {
  sync.mutex_lock(&q.mutex)
  defer sync.mutex_unlock(&q.mutex)
  queue.push_back(&q.queue, work)
  sync.cond_signal(&q.worker_signal)
}

async_work_queue_submit_all :: proc(q: ^AsyncWorkQueue($C, $T, $R), work: []T) {
  sync.mutex_lock(&q.mutex)
  defer sync.mutex_unlock(&q.mutex)
  queue.append_elems(&q.queue, ..work)
  sync.cond_broadcast(&q.worker_signal)
}
