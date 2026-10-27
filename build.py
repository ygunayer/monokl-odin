#!/usr/bin/env python3

import os
import sys
import shutil
import argparse
import platform
import subprocess
import urllib.request
from typing import List, Tuple, NoReturn, Optional

PROJECT_NAME = "monokl"

SYSTEM = platform.system()
IS_WINDOWS = SYSTEM == "Windows"
IS_MACOS = SYSTEM == "Darwin"
IS_LINUX = SYSTEM == "Linux"

BINARY_EXTENSION = ".exe" if IS_WINDOWS else ""

def die(*args) -> NoReturn:
    for a in args:
        print(a, file=sys.stderr)
    sys.exit(1)

def shexec(cmd: str, flags: List[str] = []):
    full_cmd = [cmd] + flags
    result = subprocess.run(full_cmd, stdout=subprocess.PIPE)
    if result.returncode != 0:
        output = result.stdout.decode('utf-8')
        cmdline = " ".join(full_cmd)
        die(
            f"Failed to run command \"{cmdline}\" (exit code: {result.returncode})",
            output,
        )


ODIN_EXE_PATH = shutil.which("odin") or ""
if not ODIN_EXE_PATH:
    die("Odin compiler binary not found in PATH")


RELEASE_ROOT = os.path.join("build", "release")

def recreate_release_path(target: str, arch: str) -> str:
    target_dir = os.path.join(RELEASE_ROOT, f"{PROJECT_NAME}-{target}-{arch}")
    if os.path.exists(target_dir):
        shutil.rmtree(target_dir)
    os.makedirs(target_dir)
    return target_dir

def release_windows(arch: str) -> str:
    rc_path = shutil.which("rc.exe")
    if not rc_path:
        die("rc.exe not found in PATH. You might want to run this command from a Visual Studio command prompt")

    # prepare
    clean()
    os.makedirs("bin")
    copy_assets()

    shexec("rc.exe", ["/fo", "bin\\resources.res", "assets\\build\\resources.rc"])
    shexec("cvtres.exe", ["/MACHINE:" + ("X64" if arch == "amd64" else "X86"), "bin\\resources.res"])

    # compile
    exe_name = f"{PROJECT_NAME}.exe"
    odin_args = [
        "build",
        "src/",
        "-subsystem:windows",
        f"-target:windows_{arch}",
        f"-out=bin\\{PROJECT_NAME}.exe",
        "-o:speed",
        "-extra-linker-flags:bin\\resources.obj"
    ]
    shexec(ODIN_EXE_PATH, odin_args)

    # copy build artifacts to release folder
    target_dir = recreate_release_path("windows", arch)
    # shutil.copytree(
    #     os.path.join("bin", "assets"),
    #     os.path.join(target_dir, "assets")
    # )
    for name in ["SDL3.dll", "SDL3_image.dll"]:
        if not os.path.exists(os.path.join(target_dir, name)):
            shutil.copy(os.path.join("lib", name), target_dir)
    shutil.copy(
        os.path.join("bin", exe_name),
        os.path.join(target_dir, exe_name)
    )

    return target_dir

def release_linux(arch: str):
    # prepare
    clean()
    os.makedirs("bin")
    copy_assets()

    # compile
    odin_args = [
        "build",
        "src/",
        f"-target:linux_{arch}",
        f"-out=bin/{PROJECT_NAME}",
        "-o:speed",
    ]
    shexec(ODIN_EXE_PATH, odin_args)

    # copy build artifacts to release folder
    target_dir = recreate_release_path("linux", arch)
    shutil.copytree(
        os.path.join("bin", "assets"),
        os.path.join(target_dir, "assets")
    )
    shutil.copy(
        os.path.join("bin", PROJECT_NAME),
        os.path.join(target_dir, PROJECT_NAME)
    )
    return target_dir

def release_macos(arch: str):
    # prepare
    clean()
    os.makedirs("bin")
    copy_assets()

    # compile
    odin_args = [
        "build",
        "src/",
        f"-target:darwin_{arch}",
        f"-out=bin/{PROJECT_NAME}",
        "-o:speed",
        "-define:MACOS_BUNDLE=true",
    ]
    shexec(ODIN_EXE_PATH, odin_args)

    # copy build artifacts to release folder
    target_dir = recreate_release_path("darwin", arch)

    curr_target_path = os.path.join(target_dir, PROJECT_NAME + ".app")
    contents_dir = os.path.join(curr_target_path, "Contents")
    bin_dir = os.path.join(contents_dir, "MacOS")
    res_dir = os.path.join(contents_dir, "Resources")
    os.makedirs(bin_dir)
    os.makedirs(res_dir)

    shutil.copy(
        os.path.join("assets", "build", "Info.plist"),
        os.path.join(contents_dir, "Info.plist")
    )
    shutil.copy(
        os.path.join("bin", PROJECT_NAME),
        os.path.join(bin_dir, PROJECT_NAME)
    )
    shutil.copy(
        os.path.join("assets", "build", "Icon.icns"),
        os.path.join(res_dir, "Icon.icns")
    )
    # shutil.copytree(
    #     os.path.join("bin", "assets"),
    #     os.path.join(res_dir, "assets"),
    # )

    return target_dir

RELEASE_TARGETS = {
    "windows": {
        "handler": release_windows,
        "archs": ["amd64"],
    },
    "linux": {
        "handler": release_linux,
        "archs": ["amd64"],
    },
    "macos": {
        "handler": release_macos,
        "archs": ["amd64", "arm64"],
    },
}

##################################
# Commands
##################################
def clean():
    if os.path.exists("bin"):
        shutil.rmtree("bin")
        return True
    return False

def compile(is_release: bool, should_clean: bool, target: Optional[str] = None) -> str:
    if ODIN_EXE_PATH is None:
        raise ValueError("Odin compiler binary not found in PATH")

    if should_clean:
        clean()

    if not os.path.exists("bin"):
        os.makedirs("bin")

    copy_libs()
    copy_assets()

    extension = BINARY_EXTENSION
    if target and target.startswith("js_"):
        extension = ""

    output_path = os.path.join("bin", f"{PROJECT_NAME}{extension}")
    flags = ["build", "src/", f"-out={output_path}"]
    if is_release:
        flags = flags + ["-o:speed", "-no-bounds-check"]
        if IS_WINDOWS and (not target or target.startswith("win")):
            flags.append("-subsystem:windows")
        if target:
            flags.append(f"-target:{target}")
    else:
        flags = flags + ["-o:none", "-debug"]#, "-sanitize:address"]

    shexec("odin", flags)
    print(f"Successfully compiled the executable in", "release" if is_release else "debug", "mode")
    return output_path

def release(target: Optional[str] = None, arch: Optional[str] = "all"):
    if target == "all":
        for t in RELEASE_TARGETS:
            release(t)
        return

    if not target:
        if IS_WINDOWS: target = "windows"
        elif IS_LINUX: target = "linux"
        elif IS_MACOS: target = "macos"
        if target:
            print(f"Auto-detected release target {target}")

    if not target:
        die("No target specified")

    if target not in RELEASE_TARGETS:
        die(f"Invalid target {target}")

    release_target = RELEASE_TARGETS[target]

    target_archs = release_target["archs"]
    if arch != "all":
        if arch not in target_archs:
            die(f"Invalid architecture {arch} for target {target} - must be one of {target_archs}")
        target_archs = [arch]
    for arch in target_archs:
        print(f"Building release for target {target}-{arch}")
        target_dir = release_target["handler"](arch)
        print(f"Successfully built target {target}-{arch} at path {target_dir}")

def run(output_path: str):
    os.system(output_path)

def copy_assets():
    # Comment out to copy assets to your bin path
    pass

def copy_libs():
    if IS_WINDOWS:
        for name in ["SDL3.dll", "SDL3_image.dll"]:
            if not os.path.exists(os.path.join("bin", name)):
                shutil.copy(os.path.join("lib", name), "bin")


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
    compile_parser.add_argument("-t", "--target", help="The target platform to compile against")

    run_parser = subparsers.add_parser("run", help="Compiles and then runs the executable")
    run_parser.add_argument("-e", "--release", action="store_true", help="Compiles the executable in release mode (default: false)")
    run_parser.add_argument("-w", "--watch", action="store_true", help="Enables watch mode, recompiling every time files are changed")
    run_parser.add_argument("-c", "--clean", action="store_true", help="Forces a cleanup before sync")

    release_parser = subparsers.add_parser("release", help="Bundles the game for the target platform")
    release_parser.add_argument("-t", "--target", help="The target platform to compile against. One of: windows, linux, macos")
    release_parser.add_argument("-a", "--arch", help="The target architecture to compile against. One of: all, amd64, arm64")

    args = parser.parse_args()

    if args.command == "compile":
        compile(args.release, args.clean, target=args.target)
    elif args.command == "run":
        output_path = compile(args.release, args.clean)
        run(output_path)
    elif args.command == "release":
        release(args.target, args.arch)

if __name__ == "__main__":
    main()
# 
