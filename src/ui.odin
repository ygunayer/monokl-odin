package monokl

import "core:os"
import "core:fmt"
import "core:log"
import "core:path/filepath"
import "core:strings"
import "vendor:sdl3"

Vec2 :: [2]f32
Vec2i :: [2]i32

Ui :: struct {
  app: ^App,
  window: ^Window,

  playlist: ^Playlist,
  theme: Theme,

  size: Vec2i,

  image: ^Ui_Image,
  image_zoom_factor: f32,

  dropping_files: bool,
  dropped_files: [dynamic]string,
}

Ui_Image :: struct {
  visible: bool,
  size: Vec2,
  texture: ^sdl3.Texture,

  size_rect: sdl3.FRect,
  render_rect: sdl3.FRect,
}

Theme :: struct {
  background_color: sdl3.FColor,
  text_color: sdl3.FColor,
  text_background_color: sdl3.FColor,
}

Theme_Light :: Theme {
  background_color = sdl3.FColor { .76, .76, .76, 1 },
  text_color = sdl3.FColor { .34, .34, .34, 1 },
  text_background_color = sdl3.FColor { 0, 0, 0, 0 }
}

Theme_Dark :: Theme {
  background_color = sdl3.FColor { .192, .192, .192, 1 },
  text_color = sdl3.FColor { 1, 1, 1, 1 },
  text_background_color = sdl3.FColor { 0, 0, 0, 0 }
}

get_system_theme :: proc() -> Theme {
  if sdl3.GetSystemTheme() == .DARK {
    return Theme_Dark
  }

  return Theme_Light
}

ui_init :: proc(ui: ^Ui, window: ^Window) {
  ui.window = window
  ui.app = window.app
  ui.theme = settings_get_theme(window.app.settings)

  ui.image = new(Ui_Image)

  ui.playlist = new(Playlist)
  playlist_init(ui.playlist)

  event_bus_subscribe(window.app.event_bus, ui, ui_handle_event, {
    .Action,
    .WindowResized,
    .FileDropStarted,
    .FileDropStopped,
    .FileDropped,
  })

  ui_refresh_size(ui)
  ui_update_title(ui)
}

ui_refresh_size :: proc(ui: ^Ui) {
  if ui == nil || ui.window == nil || ui.window.wnd == nil {
    return
  }

  sdl3.GetWindowSizeInPixels(ui.window.wnd, &ui.size.x, &ui.size.y)
  log.debugf("New UI size: %v", ui.size)
  ui_fit_image_to_sceen(ui)
}

ui_set_theme :: proc(ui: ^Ui, theme: Theme) {
  ui.theme = theme
}

ui_unload_image :: proc(ui: ^Ui) {
  ui.image_zoom_factor = 1.0
  ui.image.size = {0, 0}
  ui.image.render_rect = {}
  ui.image.size_rect = {}
  ui.image.visible = false
  ui.image.texture = nil
}

ui_reload_image :: proc(ui: ^Ui) {
  assert(ui != nil)
  assert(ui.app != nil)
  assert(ui.window != nil)
  assert(ui.window.renderer != nil)

  ui_unload_image(ui)
  defer ui_update_title(ui)

  entry := ui.playlist.current_entry
  if entry == nil {
    return
  }

  if len(entry.full_path) < 1 {
    return
  }

  texture := texture_cache_get(ui.app.texture_cache, ui.window.renderer, entry.full_path)
  if texture == nil {
    log.warnf("Failed to load image from path %s due to %s", entry.full_path, sdl3.GetError())
    return
  }
  sdl3.GetTextureSize(texture, &ui.image.size.x, &ui.image.size.y)

  ui.image.texture = texture
  ui.image.visible = true
  ui.image.size_rect = {0, 0, ui.image.size.x, ui.image.size.y}

  ui_fit_image_to_sceen(ui)
}

ui_fit_image_to_sceen :: proc(ui: ^Ui) {
  assert(ui != nil)
  if ui.image == nil || ui.image.texture == nil {
    return
  }

  image_aspect := ui.image.size.x / ui.image.size.y
  window_aspect := f32(ui.window.size.x) / f32(ui.window.size.y)

  if image_aspect > window_aspect {
    ui.image_zoom_factor = f32(ui.window.size.x) / ui.image.size.x
  } else {
    ui.image_zoom_factor = f32(ui.window.size.y) / ui.image.size.y
  }

  ui_recalculate_image_render_rect(ui)
}

ui_change_zoom :: proc(ui: ^Ui, by: f32) {
  assert(ui != nil)
  ui.image_zoom_factor += by
  ui_recalculate_image_render_rect(ui)
}

ui_resize_image_to_original :: proc(ui: ^Ui) {
  assert(ui != nil)
  ui.image_zoom_factor = 1.0
  ui_recalculate_image_render_rect(ui)
}

ui_recalculate_image_render_rect :: proc(ui: ^Ui) {
  assert(ui != nil)
  if ui.image == nil || ui.image.texture == nil {
    return
  }

  ui.image.render_rect.w = ui.image.size.x * ui.image_zoom_factor
  ui.image.render_rect.h = ui.image.size.y * ui.image_zoom_factor

  ui.image.render_rect.x = (f32(ui.window.size.x) - ui.image.render_rect.w) / 2
  ui.image.render_rect.y = (f32(ui.window.size.y) - ui.image.render_rect.h) / 2
}

ui_update_title :: proc(ui: ^Ui) {
  if ui == nil {
    return
  }

  entry := ui.playlist.current_entry
  if entry == nil {
    return
  }

  new_title := fmt.tprintf(
    "monokl - %s%d/%d - %s",
    "♥" if entry.is_favorited else "",
    ui.playlist.current_index + 1,
    ui.playlist.entry_count,
    entry.filename,
  )

  window_set_title(ui.window, new_title)
}

ui_handle_event :: proc(ui: ^Ui, event: Event) -> bool {
  #partial switch event.type {
    case .WindowResized:
      ui_refresh_size(ui)

    case .Action: {
      payload, ok := event.payload.(ActionPayload)
      if ok {
        #partial switch payload.type {
          case .GoToFirst: {
            playlist_go_to_first(ui.playlist)
            ui_reload_image(ui)
          }

          case .GoToPrevious: {
            playlist_advance(ui.playlist, -1)
            ui_reload_image(ui)
          }

          case .GoToNext: {
            playlist_advance(ui.playlist, 1)
            ui_reload_image(ui)
          }

          case .GoToLast: {
            playlist_go_to_last(ui.playlist)
            ui_reload_image(ui)
          }

          case .ToggleOnlyFavorites: {
            playlist_toggle_only_favorites(ui.playlist)
            ui_reload_image(ui)
          }

          case .ResetZoom:
            ui_resize_image_to_original(ui)

          case .FitImageToScreen:
            ui_fit_image_to_sceen(ui)

          case .ZoomIn:
            ui_change_zoom(ui, .1)

          case .ZoomOut:
            ui_change_zoom(ui, -.1)
        }
      }
    }

    case .FileDropStarted: {
      if !ui.dropping_files {
        ui.dropping_files = true
        log.debugf("Drop start")
      }
    }

    case .FileDropStopped: {
      log.debugf("Drop end %v", ui.dropped_files)
      if ui.dropping_files && len(ui.dropped_files) > 0 {
        ui_load_playlist(ui, ui.dropped_files[:])
      }
      defer clear(&ui.dropped_files)
      ui.dropping_files = false

      ui_reload_image(ui)
    }

    case .FileDropped: {
      if ui.dropping_files {
        payload, ok := event.payload.(FileDropEventPayload)
        if ok {
          append(&ui.dropped_files, payload.file)
        }
      }
    }
  }

  return true
}

ui_render :: proc(ui: ^Ui) {
  sdl3.SetRenderDrawColorFloat(
    ui.window.renderer,
    ui.theme.background_color.r,
    ui.theme.background_color.g,
    ui.theme.background_color.b,
    ui.theme.background_color.a
  )

  sdl3.RenderClear(ui.window.renderer)

  if ui.image.visible && ui.image.texture != nil {
    sdl3.RenderTexture(ui.window.renderer, ui.image.texture, nil, &ui.image.render_rect)
  }

  sdl3.RenderPresent(ui.window.renderer)
}

ui_unload_playlist :: proc(ui: ^Ui) {
  if ui.playlist != nil {
    playlist_destroy(ui.playlist)
    free(ui.playlist)
    ui.playlist = nil
  }
}

ui_load_playlist :: proc(ui: ^Ui, paths: []string) -> Playlist_Error {
  ui_unload_playlist(ui)

  folders := make(map[string][dynamic]os.File_Info, context.temp_allocator)

  for path in paths {
    if os.is_dir(path) {
      map_insert(&folders, path, make([dynamic]os.File_Info, context.temp_allocator))
    } else {
      parent_path := filepath.dir(path, context.temp_allocator)

      info, err := os.lstat(path, context.temp_allocator)
      if err != nil {
        log.warnf("Failed to read file information for %s", path)
        continue
      }

      if !(parent_path in folders) {
        map_insert(&folders, parent_path, make([dynamic]os.File_Info, context.temp_allocator))
      }

      append(&folders[parent_path], info)
    }
  }

  log.debugf("Opening folders %v", folders)

  if len(paths) < 1 {
    return nil
  }

  is_first := true
  for parent in folders {
    children := folders[parent]

    pl := new(Playlist)
    playlist_init(pl)
    err: Playlist_Error

    initial_entry: ^PlaylistEntry

    switch len(children) {
      case 0:
        err = playlist_open_path(pl, parent)

      case 1: {
        err = playlist_open_path(pl, parent)
        if err == nil {
          initial_entry = playlist_go_to_filename(pl, children[0].name)
        }
      }

      case:
        err = playlist_open_files(pl, parent, children[:])
    }

    if err != nil {
      log.warnf("Failed to open playlist at %s due to %v", parent, err)
      free(pl)
      continue
    }

    if is_first {
      ui.playlist = pl
      is_first = false
      ui_preload_images(ui)
      continue
    }

    new_window, window_err := app_create_window(ui.window.app)
    if window_err != nil {
      log.warnf("Failed to create a new window to open playlist %s due to %v", parent, window_err)
      free(pl)
    } else {
      new_window.ui.playlist = pl
      ui_preload_images(new_window.ui)
    }
  }

  return nil
}

ui_preload_images :: proc(ui: ^Ui) {
  assert(ui != nil)
  assert(ui.playlist != nil)
  assert(ui.playlist.entries != nil)

  if ui.playlist.entry_count < 1 {
    return
  }

  ordered_paths := make([dynamic]string, context.temp_allocator)
  offset := ui.playlist.current_index - 1
  if offset < 0 {
    offset = 0
  }

  for i in 0..<ui.playlist.entry_count {
    idx := (i + offset) % ui.playlist.entry_count
    entry := ui.playlist.shown_entries[idx]
    append(&ordered_paths, entry.full_path)
  }

  texture_cache_load_all(ui.app.texture_cache, ui.window.renderer, ordered_paths[:])
}

ui_destroy :: proc(ui: ^Ui) {
  if ui == nil {
    return
  }

  if ui.image != nil {
    if ui.image.texture != nil {
      sdl3.DestroyTexture(ui.image.texture)
      ui.image.texture = nil
    }

    free(ui.image)
    ui.image = nil
  }


  if ui.dropped_files != nil {
    for f in ui.dropped_files {
      delete(f)
    }
    delete(ui.dropped_files)
    ui.dropped_files = nil
  }

  if ui.playlist != nil {
    playlist_destroy(ui.playlist)
    free(ui.playlist)
    ui.playlist = nil
  }
}
