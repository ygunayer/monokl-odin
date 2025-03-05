package util

import "core:os"
import "core:crypto"
import "core:encoding/uuid"
import "core:path/filepath"

import monokl ".."

make_temp_dir :: proc() -> (path: string, error: monokl.Error) {
  base_temp_dir := os.get_env("TEMP")
  defer delete(base_temp_dir)

  temp_dir_name: string
  defer delete(temp_dir_name)
  {
    context.random_generator = crypto.random_generator()
    rand_uuid := uuid.generate_v4()
    temp_dir_name = uuid.to_string_allocated(rand_uuid)
  }

  dir_path := filepath.join({base_temp_dir, temp_dir_name})
  os.make_directory(dir_path) or_return
  return dir_path, nil
}

delete_dir :: proc(path: string) -> monokl.Error {
  return os.remove_directory(path)
}
