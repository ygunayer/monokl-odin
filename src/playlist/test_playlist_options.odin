package playlist

import "core:testing"
import "core:strings"
import "core:fmt"
import "core:bytes"

@(test)
test_playlist_options_write :: proc(t: ^testing.T) {
  opts: PlaylistOptions
  opts.skip_hidden = true
  opts.only_favorites = true
  opts.sort_order = .LastModifiedDesc
  append(&opts.favorites, "foo1.jpg")
  append(&opts.favorites, "foo2.jpg")
  defer playlist_options_destroy(&opts)

  expected := `{"skip_hidden":true,"only_favorites":true,"sort_order":"LastModifiedDesc","favorites":["foo1.jpg","foo2.jpg"]}`

  testing.expectf(t, len(opts.favorites) == 2, "Should have 2 favorites after inserting")

  sb := strings.builder_make()
  _, sberr := strings.builder_init_none(&sb)
  defer strings.builder_destroy(&sb)
  testing.expectf(t, sberr == .None, "Should create string builder without errors %v", sberr)

  w := strings.to_writer(&sb)
  werr := playlist_options_write(&opts, w)
  testing.expectf(t, werr == nil, "Should write to stream without errors %v", werr)

  actual := fmt.sbprint(&sb)

  testing.expect_value(t, strings.trim_space(actual), strings.trim_space(expected))
}

@(test)
test_playlist_options_read :: proc(t: ^testing.T) {
  expected := PlaylistOptions {
    skip_hidden = true,
    only_favorites = true,
    sort_order = .LastModifiedDesc,
    favorites = {},
  }
  append(&expected.favorites, "foo1.jpg")
  append(&expected.favorites, "foo2.jpg")
  defer playlist_options_destroy(&expected)

  actual: PlaylistOptions
  defer playlist_options_destroy(&actual)

  input := `{"skip_hidden":true,"only_favorites":true,"sort_order":"LastModifiedDesc","favorites":["foo1.jpg","foo2.jpg"]}`

  b: bytes.Buffer
  defer bytes.buffer_destroy(&b)
  bytes.buffer_init_string(&b, input)

  err := playlist_options_read(&actual, bytes.buffer_to_bytes(&b))
  testing.expectf(t, err == nil, "Should read without errors %v", err)

  testing.expect_value(t, expected.sort_order, actual.sort_order)
  testing.expect_value(t, expected.skip_hidden, actual.skip_hidden)
  testing.expect_value(t, expected.only_favorites, actual.only_favorites)
  testing.expect_value(t, len(expected.favorites), len(actual.favorites))

  for i in 0..<len(expected.favorites) {
    testing.expect_value(t, expected.favorites[i], actual.favorites[i])
  }
}

// @(test)
// test_playlist_try_read_options :: proc(t: ^testing.T) {
//   temp_dir, err := make_temp_dir()
//   defer delete(temp_dir)
//   testing.expectf(t, err == nil, "Should make a temp dir %v", err)

//   // p := new(Playlist, context.temp_allocator)
//   // testin.
//   // defer playlist_destroy(p)

//   // is_ok, err := playlist_try_read_options(p)
//   // assert(is_ok, "should read options")
// }
