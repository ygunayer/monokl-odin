#!/usr/bin/env python3

import os
import sys
import shutil
import argparse
import platform
import subprocess
from typing import List, Tuple, NoReturn

PROJECT_NAME = "monokl"

SYSTEM = platform.system()
IS_WINDOWS = SYSTEM == "Windows"
IS_OSX = SYSTEM == "Darwin"
IS_LINUX = SYSTEM == "Linux"

BINARY_EXTENSION = ".exe" if IS_WINDOWS else ""

ODIN_EXE_PATH = shutil.which("odin")

def die(*args) -> NoReturn:
    for a in args:
        print(a, file=sys.stderr)
    sys.exit(1)

def shexec(cmd: str, flags: List[str] = []) -> Tuple[int, str]:
    full_cmd = [cmd] + flags
    result = subprocess.run(full_cmd, stdout=subprocess.PIPE)
    if result.returncode != 0:
        output = result.stdout.decode('utf-8')
        cmdline = " ".join(full_cmd)
        die(
            f"Failed to run command \"{cmdline}\" (exit code: {result.returncode})",
            output,
        )

def clean():
    if os.path.exists("bin"):
        shutil.rmtree("bin")
        return True
    return False

def compile(is_release: bool, should_clean: bool):
    if ODIN_EXE_PATH is None:
        raise ValueError("Odin compiler binary not found in PATH")

    if should_clean:
        clean()

    if not os.path.exists("bin"):
        os.makedirs("bin")

    # TODO: static link libs if release
    copy_libs()

    # TODO: package assets if release
    copy_assets()

    flags = ["build", "src/", f"-out=bin/{PROJECT_NAME}" + BINARY_EXTENSION]
    if is_release:
        flags = flags + ["-o:speed", "-no-bounds-check"]
        if IS_WINDOWS:
            flags.append("-subsystem:windows")
    else:
        flags = flags + ["-o:none", "-debug"]

    shexec("odin", flags)
    print(f"Successfully compiled the executable in", "release" if is_release else "debug", "mode")

def run():
    bin_path = os.path.join("bin", f"{PROJECT_NAME}" + BINARY_EXTENSION)
    if not os.path.exists(bin_path):
        die(f"No binary exists at path {bin_path}")
    os.system(bin_path)

def copy_libs():
    odin_root = os.path.dirname(ODIN_EXE_PATH)
    files_to_copy = [
        os.path.join(odin_root, "vendor", "sdl3", "SDL3.dll"),
        os.path.join(odin_root, "vendor", "sdl3", "SDL3.lib"),
        os.path.join(odin_root, "vendor", "sdl3", "image", "SDL3_image.dll"),
        os.path.join(odin_root, "vendor", "sdl3", "image", "SDL3_image.lib"),
    ]

    for file in files_to_copy:
        filename = os.path.basename(file)
        shutil.copyfile(file, f"./bin/{filename}")

    print("Libraries copied to binary directory")

def copy_assets():
    # Comment out to copy assets to your bin path
    # shutil.copytree("./assets", "./bin/assets", dirs_exist_ok=True)
    # print("Copied assets to binary directory")
    pass

def main():
    """Set up the argument parser with the specified commands and flags."""

    parser = argparse.ArgumentParser(
        description="Build script for managing compilation and execution.",
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to execute")
    subparsers.required = True  

    compile_parser = subparsers.add_parser("compile", help="Compiles the executable")
    compile_parser.add_argument("-e", "--release", action="store_true", help="Compiles the executable in release mode (default: false)")
    compile_parser.add_argument("-w", "--watch", action="store_true", help="Enables watch mode, recompiling every time files are changed")
    compile_parser.add_argument("-c", "--clean", action="store_true", help="Forces a cleanup before sync")

    run_parser = subparsers.add_parser("run", help="Compiles and then runs the executable")
    run_parser.add_argument("-e", "--release", action="store_true", help="Compiles the executable in release mode (default: false)")
    run_parser.add_argument("-w", "--watch", action="store_true", help="Enables watch mode, recompiling every time files are changed")
    run_parser.add_argument("-c", "--clean", action="store_true", help="Forces a cleanup before sync")

    debug_parser = subparsers.add_parser("debug", help="Compiles the executable in debug mode and starts a debug process")

    clean_parser = subparsers.add_parser("clean", help="Cleans the previous build artifacts")

    sync_deps_parser = subparsers.add_parser("sync-deps", help="Synchronizes the dependencies")
    sync_deps_parser.add_argument("-c", "--clean", action="store_true", help="Forces a cleanup before sync")

    args = parser.parse_args()

    if args.command == "compile":
        compile(args.release, args.clean)
    elif args.command == "run":
        compile(args.release, args.clean)
        run()
    elif args.command == "debug":
        print("Compiling in debug mode and starting debug process")
    elif args.command == "sync-deps":
        if args.clean:
            print("Performing clean sync of dependencies")
        else:
            print("Syncing dependencies")

if __name__ == "__main__":
    main()
