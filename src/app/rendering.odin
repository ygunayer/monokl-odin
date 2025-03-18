package app

import "core:log"
import "vendor:sdl3"
import "../playlist"

Theme_Dark_BgColor := sdl3.FColor { .192, .192, .192, 1.0 }

Viewport :: struct {
  camera_position: Vector2,
  size: Vector2,
  zoom_factor: f32,
  objects: [dynamic]SceneObject,
  background_color: sdl3.FColor,
  renderer: ^sdl3.Renderer
}

SceneObject_Image :: struct {
  visible: bool,
  position: Vector2,
  size: Vector2,
  texture: ^sdl3.Texture,
}

SceneObject_Video :: struct {
  visible: bool,
  position: Vector2,
  size: Vector2,
  current_frame: i32,
  num_frames: i32,
  frame_rate: f32,
  textures: [dynamic]^sdl3.Texture,
}

SceneObject_Text :: struct {
  visible: bool,
  position: Vector2,
  text_color: sdl3.Color,
  background_color: sdl3.Color,
  text: string,
}

SceneObject :: union {
  SceneObject_Text,
  SceneObject_Image,
  SceneObject_Video,
}

viewport_init :: proc(viewport: ^Viewport, renderer: ^sdl3.Renderer, size: Vector2) {
  if viewport == nil {
    return
  }

  viewport.objects = make([dynamic]SceneObject)
  viewport.renderer = renderer
  viewport.background_color = Theme_Dark_BgColor
  viewport.size = size
}

viewport_resize :: proc(viewport: ^Viewport, size: Vector2) {
  viewport.size = size
}

viewport_render :: proc(viewport: ^Viewport) {
  sdl3.SetRenderDrawColorFloat(viewport.renderer, viewport.background_color.r, viewport.background_color.g, viewport.background_color.b, viewport.background_color.a)
  sdl3.RenderClear(viewport.renderer)

  for obj in viewport.objects {
    #partial switch &o in obj {
      case SceneObject_Image: {
        rect := sdl3.FRect{ x = 20, y = 30, w = 300, h = 500 }
        sdl3.RenderTexture(viewport.renderer, o.texture, nil, &rect)
      }
    }
  }

  sdl3.RenderPresent(viewport.renderer)
}

viewport_add_media :: proc(viewport: ^Viewport, media: ^playlist.Media) {
  if media == nil {
    return
  }

  textures := make([dynamic]^sdl3.Texture)
  for surf in media.frames {
    texture := sdl3.CreateTextureFromSurface(viewport.renderer, surf)
    if texture == nil {
      delete(textures)
      log.warnf("Failed to creeate SDL texture when adding media to the viewport: %v", sdl3.GetError())
      return
    }
    append(&textures, texture)
  }

  num_frames := len(textures)
  if num_frames == 1 {
    obj: SceneObject_Image
    obj.visible = true
    obj.size = media.size
    obj.texture = textures[0]
    append(&viewport.objects, obj)
    delete(textures)
  }
}

viewport_clear :: proc(viewport: ^Viewport) {
  if viewport.objects == nil {
    return
  }

  for obj in viewport.objects {
    #partial switch &o in obj {
      case SceneObject_Image: {
        if o.texture != nil {
          sdl3.DestroyTexture(o.texture)
          o.texture = nil
        }
      }

      case SceneObject_Text: {
        delete(o.text)
      }
    }
  }

  clear(&viewport.objects)
}

viewport_destroy :: proc(viewport: ^Viewport) {
  if viewport == nil {
    return
  }

  if viewport.objects != nil {
    viewport_clear(viewport)
    delete(viewport.objects)
  }
}
