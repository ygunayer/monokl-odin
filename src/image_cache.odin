package monokl

import "core:os"
import "core:mem"
import "core:log"
import "core:sync"
import "core:fmt"
import "core:strings"
import "core:thread"
import "vendor:sdl3"
import sdl3i "vendor:sdl3/image"

Image :: struct {
  full_path: string,
  surface: ^sdl3.Surface,
  loaded_successfully: bool,
}

ImageLoadRequestItem :: struct {
  window_id: sdl3.WindowID,
  full_path: string,
}

ImageLoadResultItem :: struct {
  window_id: sdl3.WindowID,
  image: Image,
}

ImageCache :: struct {
  result_mutex: sync.Mutex,
  loaded: map[string]bool,
  work_queue: ^AsyncWorkQueue(^ImageCache, ImageLoadRequestItem, ImageLoadResultItem),
}

_load_image :: proc(full_path: string) -> (^sdl3.Surface, Error) {
  data, err := os.read_entire_file(full_path, context.allocator)
  defer delete(data)
  if err != nil {
    return {}, common_error(fmt.tprintf("OS Error %v", err))
  }

  cpath := strings.clone_to_cstring(full_path)
  defer delete(cpath)

  img := sdl3i.Load(cpath)
  defer sdl3.DestroySurface(img)
  if img == nil {
    return {}, sdl_last_error("Image load failure")
  }

  new_img := sdl3.ConvertSurface(img, .RGBA32)
  if new_img == nil {
    return {}, sdl_last_error("Failed to convert image to RGBA32")
  }
  return new_img, nil
}

_fn_handle_work :: proc(ic: ^ImageCache, request: ImageLoadRequestItem) -> ImageLoadResultItem {
  surface, err := _load_image(request.full_path)
  if err != nil {
    log.errorf("Failed to load image from path %s due to %v", request.full_path, err)
    return {
      window_id = request.window_id,
      image = {
        full_path = request.full_path,
        loaded_successfully = false,
      },
    }
  }

  return {
    window_id = request.window_id,
    image = {
      full_path = request.full_path,
      surface = surface,
      loaded_successfully = true,
    }
  }
}

_fn_handle_result :: proc(ic: ^ImageCache, result: ImageLoadResultItem) {
  sync.mutex_lock(&ic.result_mutex)
  defer sync.mutex_unlock(&ic.result_mutex)

  if result.image.full_path not_in ic.loaded {
    if result.image.surface != nil {
      sdl3.DestroySurface(result.image.surface)
    }
    log.warn("Received load result for unrecognized file %s, discarding...", result.image.full_path)
    return
  }

  app_on_image_load_finished(result)
}

image_cache_init :: proc(ic: ^ImageCache, num_threads := 4, allocator := context.allocator) -> Error {
  // ic.images = make(map[string]Image)
  ic.loaded = make(map[string]bool)
  work_queue, err := async_work_queue_create(
    ic,
    _fn_handle_work,
    _fn_handle_result,
    num_threads
  )
  if err != nil {
    return err
  }

  ic.work_queue = work_queue
  async_work_queue_start(work_queue)
  return nil
}

image_cache_destroy :: proc(ic: ^ImageCache) {
  if ic == nil {
    return
  }

  if ic.work_queue != nil {
    async_work_queue_destroy(ic.work_queue)
    free(ic.work_queue)
    ic.work_queue = nil
  }

  if ic.loaded != nil {
    delete(ic.loaded)
    ic.loaded = nil
  }
}

image_cache_request_load :: proc(ic: ^ImageCache, window_id: sdl3.WindowID, full_paths: []string) {
  sync.mutex_lock(&ic.result_mutex)
  defer sync.mutex_unlock(&ic.result_mutex)

  requests := make([dynamic]ImageLoadRequestItem)
  defer delete(requests)

  for path in full_paths {
    if path in ic.loaded {
      continue
    }

    ic.loaded[path] = true

    append(&requests, ImageLoadRequestItem {
      window_id = window_id,
      full_path = path,
    })
  }

  async_work_queue_submit_all(ic.work_queue, requests[:])
}
