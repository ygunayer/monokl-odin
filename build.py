#!/usr/bin/env python3

import os
import sys
import shutil
import argparse
import platform
import subprocess
import urllib.request
from typing import List, Tuple, NoReturn, Optional, Dict
from pathlib import Path

PROJECT_NAME = "monokl"

SYSTEM = platform.system()
IS_WINDOWS = SYSTEM == "Windows"
IS_MACOS = SYSTEM == "Darwin"
IS_LINUX = SYSTEM == "Linux"

BINARY_EXTENSION = ".exe" if IS_WINDOWS else ""

ASSETS_ROOT = Path("assets")
BUILD_ASSETS_ROOT = ASSETS_ROOT / "build"

BIN_ROOT = Path("bin")
DEBUG_OUT_ROOT = BIN_ROOT / "debug"
RELEASE_OUT_ROOT = BIN_ROOT / "release"
BUNDLE_OUT_ROOT = BIN_ROOT / "bundle"

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

def get_current_platform() -> str:
    match platform.system():
        case "Windows":
            return "windows"
        case "Linux":
            return "linux"
        case "Darwin":
            return "macos"
        case name:
            raise ValueError(f"Unknown platform {name}")

def get_current_arch() -> str:
    match platform.machine():
        case "i386":
            return "i386"
        case "AMD64":
            return "amd64"
        case "ARM64":
            return "arm64"
        case name:
            raise ValueError(f"Unknown CPU architecture {name}")


ODIN_EXE_PATH = shutil.which("odin") or ""
if not ODIN_EXE_PATH:
    die("Odin compiler binary not found in PATH")



class AppBuilder:
    def __init__(self, app_name: str):
        self.app_name = app_name

    def platform_name(self) -> str:
        raise NotImplemented

    def supported_archs(self) -> List[str]:
        raise NotImplemented

    def get_additional_compile_args(self, arch: str, is_release: bool = False, is_bundle: bool = False) -> List[str]:
        raise NotImplemented

    def get_bundle_artifact_paths(self, src_exe_path: Path, bundle_out_root: Path) -> Dict[Path, Path]:
        raise NotImplemented

    def get_exe_extension(self) -> str:
        return ""

    def get_bundle_output_path(self, arch: str) -> Path:
        return BUNDLE_OUT_ROOT / f"{self.platform_name()}-{arch}"

    def get_compiled_exe_path(self, arch: str, is_release: bool):
        parent = RELEASE_OUT_ROOT if is_release else DEBUG_OUT_ROOT
        return parent / f"{self.app_name}{self.get_exe_extension()}"

    def compile(self, arch: str, is_release: bool = False, is_bundle: bool = False, clean: bool = False) -> Path:
        out_exe_path = self.get_compiled_exe_path(arch, is_release)
        if clean and out_exe_path.parent.exists():
            shutil.rmtree(out_exe_path.parent)
        out_exe_path.parent.mkdir(parents=True, exist_ok=True)
        odin_args = [
            "build",
            "src/",
            f"-out:{out_exe_path}",
            f"-target:{self.platform_name()}_{arch}"
        ] + (
            ["-o:speed", "-no-bounds-check"] if is_release else ["-o:none", "-debug"]
        ) + self.get_additional_compile_args(arch, is_release, is_bundle)
        shexec(ODIN_EXE_PATH, odin_args)
        if not out_exe_path.exists():
            die("Compilation failed")
        print(f"Successfully compiled {self.app_name} to path {out_exe_path}")
        return out_exe_path

    def recreate_bundle_output_path(self, arch: str) -> Path:
        output_path = self.get_bundle_output_path(arch)
        if output_path.exists():
            shutil.rmtree(output_path)
        output_path.mkdir(parents=True, exist_ok=True)
        return output_path

    def bundle(self, arch: str) -> Path:
        archs = self.supported_archs()
        if arch not in archs:
            raise ValueError(f"Unsupported arch {arch} for platform {self.platform_name()} - possible values are: {archs}")
        bundle_out_path = self.recreate_bundle_output_path(arch)
        out_exe_path = self.compile(arch, is_release=True, is_bundle=True, clean=True)
        artifacts = self.get_bundle_artifact_paths(out_exe_path, bundle_out_path)
        for src in artifacts.keys():
            dst = artifacts[src]
            shutil.copy(src, dst)
            print(f"Successfully copied build artifact {src} to {dst}")
        print(f"Successfully bundled {self.app_name} into path {bundle_out_path}")
        return bundle_out_path

    def bundle_all(self) -> List[Path]:
        return [self.bundle(arch) for arch in self.supported_archs()]


class WindowsAppBuilder(AppBuilder):
    def platform_name(self) -> str:
        return "windows"

    def supported_archs(self) -> List[str]:
        return ["i386", "amd64", "arm64"]

    def get_additional_compile_args(self, arch: str, is_release: bool = False, is_bundle: bool = False) -> List[str]:
        rc_resource_path = BUILD_ASSETS_ROOT / "resources.rc"
        return ["-subsystem:windows", f"-resource:{rc_resource_path}"]

    def get_bundle_artifact_paths(self, src_exe_path: Path, bundle_out_root: Path) -> Dict[Path, Path]:
        return {
            src_exe_path: bundle_out_root / src_exe_path.name,
            src_exe_path.parent / "SDL3.dll": bundle_out_root / "SDL3.dll",
            src_exe_path.parent / "SDL3_image.dll": bundle_out_root / "SDL3_image.dll",
        }

    def get_exe_extension(self) -> str:
        return ".exe"

    def compile(self, arch: str, is_release: bool = False, is_bundle: bool = False, clean: bool = False) -> Path:
        result = super().compile(arch, is_release, is_bundle, clean)
        shutil.copy(Path("lib") / "SDL3.dll", result.parent / "SDL3.dll")
        shutil.copy(Path("lib") / "SDL3_image.dll", result.parent / "SDL3_image.dll")
        return result

class LinuxAppBuilder(AppBuilder):
    def platform_name(self) -> str:
        return "linux"

    def supported_archs(self) -> List[str]:
        return ["amd64"]

    def get_additional_compile_args(self, arch: str, is_release: bool = False, is_bundle: bool = False) -> List[str]:
        return []

    def get_bundle_artifact_paths(self, src_exe_path: Path, bundle_out_root: Path) -> Dict[Path, Path]:
        return {
            src_exe_path: bundle_out_root / src_exe_path.name,
        }

class MacosAppBuilder(AppBuilder):
    def platform_name(self) -> str:
        return "darwin"

    def supported_archs(self) -> List[str]:
        return ["amd64"]

    def get_additional_compile_args(self, arch: str, is_release: bool = False, is_bundle: bool = False) -> List[str]:
        return []

    def get_bundle_output_path(self, arch: str) -> Path:
        parent = BUNDLE_OUT_ROOT / f"{self.platform_name()}-{arch}"
        app_package_name = self.app_name[0].upper() + self.app_name[1:]
        return parent / f"{app_package_name}.app"

    def get_bundle_artifact_paths(self, src_exe_path: Path, bundle_out_root: Path) -> Dict[Path, Path]:
        contents_dir = bundle_out_root / "Contents"
        bin_dir = bundle_out_root / "MacOS"
        res_dir = bundle_out_root / "Resources"
        contents_dir.mkdir(exist_ok=True)
        res_dir.mkdir(exist_ok=True)
        res_dir.mkdir(exist_ok=True)
        return {
            src_exe_path: bin_dir / self.app_name,
            BUILD_ASSETS_ROOT / "Info.plist": contents_dir / "Info.plist",
            BUILD_ASSETS_ROOT / "Icon.icns": res_dir / "Icon.icns",
        }


BUILDERS = {
    "windows": WindowsAppBuilder(PROJECT_NAME),
    "linux": LinuxAppBuilder(PROJECT_NAME),
    "macos": MacosAppBuilder(PROJECT_NAME),
}


def get_builder(target_platform: Optional[str] = None) -> AppBuilder:
    platform = target_platform or get_current_platform()
    if platform not in BUILDERS:
        raise ValueError(f"Unsupported platform {platform}")
    return BUILDERS[platform]


##################################
# Commands
##################################
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
    compile_parser.add_argument("-t", "--target", help="The target platform to compile against. One of: windows, linux, macos")
    compile_parser.add_argument("-a", "--arch", help="The target architecture to compile against. One of: amd64, arm64")

    run_parser = subparsers.add_parser("run", help="Compiles the executable in debug mode and runs it")
    run_parser.add_argument("-e", "--release", action="store_true", help="Compiles the executable in release mode (default: false)")
    run_parser.add_argument("-w", "--watch", action="store_true", help="Enables watch mode, recompiling every time files are changed")
    run_parser.add_argument("-c", "--clean", action="store_true", help="Forces a cleanup before sync")
    run_parser.add_argument("-t", "--target", help="The target platform to compile against. One of: windows, linux, macos")
    run_parser.add_argument("-a", "--arch", help="The target architecture to compile against. One of: amd64, arm64")

    bundle_parser = subparsers.add_parser("bundle", help="Bundles the app for the target platform")
    bundle_parser.add_argument("-t", "--target", help="The target platform to compile against. One of: windows, linux, macos")
    bundle_parser.add_argument("-a", "--arch", help="The target architecture to compile against. One of: amd64, arm64")

    args = parser.parse_args()

    builder = get_builder(args.target)
    target_arch = args.arch or get_current_arch()

    try:
        match args.command:
            case "compile":
                builder.compile(arch=target_arch, is_release=args.release, clean=args.clean)

            case "run":
                output_path = builder.compile(arch=target_arch, is_release=args.release, clean=args.clean)
                # TODO: watch for changes if enabled
                shexec(str(output_path))

            case "bundle":
                builder.bundle(target_arch)
    except Exception as e:
        die(str(e))


if __name__ == "__main__":
    main()
# 
