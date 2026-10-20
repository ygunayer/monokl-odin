package monokl

import "core:sync/chan"
import "vendor:sdl3"

ImageCacheEntryLoadState :: enum {
  NotLoaded,
  Loading,
  Failed,
  Loaded,
}


ImageLoadResult_Success :: struct {

}

ImageWorkerState :: struct {
  chan_work: chan.Chan(string, .Recv),
  // chan_result: chan.Chan(([]byte, Error), .Send)
}

ImageCacheEntry :: struct {
  full_path: string,
  texture: ^sdl3.Texture,
  state: ImageCacheEntryLoadState,
  load_error: Error,
}

ImageCache :: struct {
  images: map[string]ImageCacheEntry,
  chan_work: chan.Chan(string),
  chan_results: chan.Chan()
}

image_cache_init :: proc(ic: ^ImageCache) {
  ic.images = make(map[string]ImageCacheEntry)
}

image_cache_destroy :: proc(ic: ^ImageCache) {
  if ic == nil {
    return
  }

  if ic.images != nil {
    for _, entry in ic.images {
      delete(entry.full_path)
      if entry.texture != nil {
        sdl3.DestroyTexture(entry.texture)
      }
    }
    delete(ic.images)
    ic.images = nil
  }
}

image_cache_request_load :: proc(ic: ^ImageCache, full_paths: []string) {

}
