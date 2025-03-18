package playlist

import "core:os"
import "core:log"
import "core:strings"
import "core:path/filepath"
import "vendor:sdl3"
import stbi "vendor:stb/image"

SUPPORTED_EXTENSIONS :: [?]string{
  ".jpg",
  ".jpeg",
  ".png",
  ".bmp",
  ".gif",
}

Media :: struct {
  size: [2]i32,
  channels: i32,
  frame_rate: f32,
  frames: [dynamic]^sdl3.Surface,
}

Media_LoadingError :: struct {
  reason: string,
}

Media_SdlError :: struct {
  reason: string,
}

Media_Error :: union {
  Media_SdlError,
  Media_LoadingError,
}

is_supported_file :: proc(info: os.File_Info) -> bool {
  ext := filepath.ext(info.fullpath)

  for sext in SUPPORTED_EXTENSIONS {
    if ext == sext {
      return true
    }
  }

  return false
}

media_load :: proc(media: ^Media, path: string) -> Media_Error {
  cpath := strings.unsafe_string_to_cstring(path)

  data := stbi.load(cpath, &media.size.x, &media.size.y, &media.channels, 0)
  if data == nil {
    return Media_LoadingError { reason = string(stbi.failure_reason()) }
  }
  defer stbi.image_free(data)

  log.debugf("Loaded image with size=%v, channels=%v, num_frames=%v", media.size, media.channels, 1)

  sdl3.getpixelformat

  surf := sdl3.CreateSurfaceFrom(media.size.x, media.size.y, sdl3.PixelFormat.RGB24, data, media.size.x * media.channels)
  if surf == nil {
    return Media_SdlError { reason = string(sdl3.GetError()) }
  }

  append(&media.frames, surf)

  return nil
}

media_unload :: proc(media: ^Media) {
  if media == nil {
    return
  }

  for surf in media.frames {
    sdl3.DestroySurface(surf)
  }

  clear(&media.frames)
}
