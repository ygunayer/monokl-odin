package ui

import "core:log"
import "vendor:sdl3"

import "../playlist"
import "../linalg"

Viewport :: struct {
  size: linalg.Vec2i,
  zoom_factor: f32,
  objects: [dynamic]SceneObject,
  renderer: ^sdl3.Renderer,
  media: [dynamic]^playlist.Media,
  theme: Theme,
}

Camera :: struct {
  transform: linalg.Transform2,
}

SceneObject_Base :: struct {
  visible: bool,
  size: [2]f32,
  transform: linalg.Transform2,
}

SceneObject_Image :: struct {
  using _: SceneObject_Base,
  texture: ^sdl3.Texture,
}

SceneObject_Text :: struct {
  using _: SceneObject_Base,
  text: string,
  theme_override: Maybe(Theme),
}

SceneObject :: union {
  SceneObject_Text,
  SceneObject_Image,
}

viewport_init :: proc(viewport: ^Viewport, renderer: ^sdl3.Renderer, size: linalg.Vec2i, theme: Theme) {
  if viewport == nil {
    return
  }

  viewport.objects = make([dynamic]SceneObject)
  viewport.media = make([dynamic]^playlist.Media)
  viewport.renderer = renderer
  viewport.size = size
  viewport.zoom_factor = 1
  viewport.theme = theme
}

viewport_render :: proc(viewport: ^Viewport) {
  sdl3.SetRenderDrawColorFloat(
    viewport.renderer,
    viewport.theme.background_color.r,
    viewport.theme.background_color.g,
    viewport.theme.background_color.b,
    viewport.theme.background_color.a
  )

  sdl3.RenderClear(viewport.renderer)

  for obj in viewport.objects {
    #partial switch &o in obj {
      case SceneObject_Image: {
        sdl3.RenderTexture(viewport.renderer, o.texture, nil, nil)
      }
    }
  }

  sdl3.RenderPresent(viewport.renderer)
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

  if viewport.media != nil {
    for media in viewport.media {
      playlist.media_destroy(media)
      free(media)
    }

    delete(viewport.media)
    viewport.media = nil
  }

  if viewport.objects != nil {
    viewport_clear(viewport)
    delete(viewport.objects)
    viewport.objects = nil
  }
}
