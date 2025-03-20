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

ImageFrame :: struct {
  rawbytes: rawptr,
  surface: ^sdl3.Surface,
}

Media :: struct {
  size: [2]i32,
  channels: i32,
  frame_rate: f32,
  frames: [dynamic]ImageFrame,
}

Media_LoadingError :: struct {
  reason: string,
}

Media_UnsupportedTypeError :: struct {
  bits: i32,
  channels: i32,
}

Media_SdlError :: struct {
  reason: string,
}

Media_Error :: union {
  os.Error,
  Media_SdlError,
  Media_LoadingError,
  Media_UnsupportedTypeError,
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
  data, err := os.read_entire_file_from_filename_or_err(path)
  if err != nil {
    return err
  }
  defer delete(data)

  raw_bytes := raw_data(data)
  bytelen :=  i32(len(data))

  image_data: rawptr

  is_16bit := bool(stbi.is_16_bit_from_memory(raw_bytes, bytelen))

  bpp: i32
  pf: sdl3.PixelFormat

  if is_16bit {
    image_data = stbi.load_16_from_memory(
      raw_bytes,
      bytelen,
      &media.size.x,
      &media.size.y,
      &media.channels,
      0
    )

    if image_data == nil {
      return Media_LoadingError { reason = string(stbi.failure_reason()) }
    }

    bpp = media.channels * 16
    switch media.channels {
      case 4:
        pf = .RGBA64

      case 3:
        pf = .RGB48

      case:
        stbi.image_free(image_data)
        return Media_UnsupportedTypeError { bits = 16, channels = media.channels }
    }

    log.debugf("Loaded 16-bit image %s -- width=%d, height=%d, channels=%d", path, media.size.x, media.size.y, media.channels)
  } else {
    image_data = stbi.load_from_memory(
      raw_bytes,
      bytelen,
      &media.size.x,
      &media.size.y,
      &media.channels,
      0
    )

    if image_data == nil {
      return Media_LoadingError { reason = string(stbi.failure_reason()) }
    }

    bpp = media.channels * 8
    switch media.channels {
      case 4:
        pf = .RGBA32

      case 3:
        pf = .RGB24

      case 1:
        pf = .INDEX8

      case:
        stbi.image_free(image_data)
        return Media_UnsupportedTypeError { bits = 8, channels = media.channels }
    }

    log.debugf("Loaded 8-bit image %s -- width=%d, height=%d, channels=%d", path, media.size.x, media.size.y, media.channels)
  }

  surf := sdl3.CreateSurfaceFrom(media.size.x, media.size.y, pf, image_data, media.size.x * media.channels)
  if surf == nil {
    return Media_SdlError { reason = string(sdl3.GetError()) }
  }

  media.frames = make([dynamic]ImageFrame)

  append(&media.frames, ImageFrame {
    rawbytes = image_data,
    surface = surf,
  })

  return nil
}

media_destroy :: proc(media: ^Media) {
  if media == nil {
    return
  }

  for &frame in media.frames {
    if frame.surface != nil {
      sdl3.DestroySurface(frame.surface)
      frame.surface = nil
    }

    if frame.rawbytes != nil {
      stbi.image_free(frame.rawbytes)
      frame.rawbytes = nil
    }
  }

  delete(media.frames)
}
