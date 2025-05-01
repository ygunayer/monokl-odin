package monokl

import "core:os"
import "core:log"
import "core:thread"
import "core:mem"
import "core:strings"
import "core:sync"
import "vendor:sdl3"
import sdl3i "vendor:sdl3/image"

TextureCache_LoaderTaskData :: struct {
  cache: ^TextureCache,
  renderer: ^sdl3.Renderer,
  path: string,
}

TextureCache_Entry :: struct {
  texture: ^sdl3.Texture,
  refcount: int,
}

TextureCache :: struct {
  entries: map[string]TextureCache_Entry,
  pending_tasks: [dynamic]^TextureCache_LoaderTaskData,
  thread_pool: ^thread.Pool,
  mutex_allocator: mem.Mutex_Allocator,
  allocator: mem.Allocator,
  size: u32,
  capacity: u32,
  mutex: ^sync.RW_Mutex,
}

texture_cache_init :: proc(cache: ^TextureCache, capacity: u32, max_threads: u32) {
  assert(cache != nil)

  mem.mutex_allocator_init(&cache.mutex_allocator, context.allocator)
  cache.allocator = mem.mutex_allocator(&cache.mutex_allocator)

  cache.thread_pool = new(thread.Pool)
  cache.entries = make(map[string]TextureCache_Entry)
  cache.mutex = new(sync.RW_Mutex)
  cache.pending_tasks = make([dynamic]^TextureCache_LoaderTaskData)
  cache.size = 0
  cache.capacity = capacity

  thread.pool_init(cache.thread_pool, cache.allocator, int(max_threads))

  log.debugf("Initialized texture cache with a capacity of %d bytes", capacity)
}

texture_cache_destroy :: proc(cache: ^TextureCache) {
  if cache == nil {
    return
  }

  if cache.mutex != nil {
    mut := cache.mutex
    if sync.rw_mutex_guard(mut) {
      cache.mutex = nil
      free(mut)
    }
  }

  if cache.entries != nil {
    for _, &entry in cache.entries {
      if entry.texture != nil {
        sdl3.DestroyTexture(entry.texture)
        entry.texture = nil
      }
    }
    delete(cache.entries)
    cache.entries = nil
  }

  if cache.thread_pool != nil {
    thread.pool_destroy(cache.thread_pool)
    free(cache.thread_pool)
    cache.thread_pool = nil
  }

  if cache.pending_tasks != nil {
    for task_data in cache.pending_tasks {
      free(task_data)
    }
    delete(cache.pending_tasks)
    cache.pending_tasks = nil
  }
}

texture_cache_load_all :: proc(cache: ^TextureCache, renderer: ^sdl3.Renderer, file_paths: []string) {
  // TODO: not yet implemented
  return
  // assert(cache != nil)
  // assert(renderer != nil)

  // if !thread.pool_is_empty(cache.thread_pool) {
  //   thread.pool_finish(cache.thread_pool)
  // }

  // clear(&cache.pending_tasks)

  // if len(file_paths) < 1 {
  //   return
  // }

  // tex := texture_cache_get(cache, renderer, file_paths[0])
  // if tex != nil {
  //   texture_cache_add_entry(cache, file_paths[0], tex)
  // }

  // for path in file_paths[1:] {
  //   task_data := new(TextureCache_LoaderTaskData)
  //   task_data.cache = cache
  //   task_data.path = path
  //   task_data.renderer = renderer
  //   append(&cache.pending_tasks, task_data)
  //   thread.pool_add_task(cache.thread_pool, cache.allocator, texture_cache_load_task, task_data)
  // }

  // thread.pool_start(cache.thread_pool)
}

texture_cache_add_entry :: proc(cache: ^TextureCache, path: string, texture: ^sdl3.Texture) {
  assert(cache != nil)
  assert(texture != nil)

  if sync.rw_mutex_guard(cache.mutex) {
    if path in cache.entries {
      entry := &cache.entries[path]
      entry.refcount += 1
      log.debugf("Texture for path %s now has % refs", path, entry.refcount)
      return
    }

    cache.entries[path] = { texture = texture, refcount = 1 }
    log.debugf("Texture for path %s loaded into cache", path)
  }
}

texture_cache_load_task :: proc(task: thread.Task) {
  data := cast(^TextureCache_LoaderTaskData)task.data
  assert(data != nil)
  assert(data.cache != nil)
  assert(data.renderer != nil)

  // mapfile, err := mmap_file(data.path)
  // if err != nil {
  //   log.errorf("Failed to map file %s to memory due to %v", data.path, err)
  //   return
  // }

  // log.infof("File mapped to memory %s", data.path)

  cpath := strings.clone_to_cstring(data.path)
  defer delete(cpath)
  texture := sdl3i.LoadTexture(data.renderer, cpath)
  if texture == nil {
    log.warnf("Failed to load texture from path %s", data.path)
    return
  }

  texture_cache_add_entry(data.cache, data.path, texture)
}

texture_cache_get :: proc(cache: ^TextureCache, renderer: ^sdl3.Renderer, path: string) -> ^sdl3.Texture {
  assert(cache != nil)
  assert(renderer != nil)

  if sync.rw_mutex_guard(cache.mutex) {
    if path in cache.entries {
      return cache.entries[path].texture
    }
  }

  // log.warnf("Path %s was not in cache, loading directly for immediate display", path)

  cpath := strings.clone_to_cstring(path)
  defer delete(cpath)
  return sdl3i.LoadTexture(renderer, cpath)
}
