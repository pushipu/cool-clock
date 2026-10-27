#!/usr/bin/env python3
"""Cross-compile x64/ARM64 hosts and package a single per-user Windows installer."""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import shutil
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = "0.9.0"


def run(*command, **kwargs):
    subprocess.run([str(part) for part in command], check=True, cwd=ROOT, **kwargs)


def quote(value):
    value = str(value)
    if "\n" in value or "\r" in value:
        raise ValueError("Newlines are not allowed in package paths")
    return value.replace("$", "$$").replace('"', '$\\"')


def pe(path, expected_machine):
    data = path.read_bytes()
    if len(data) < 256 or data[:2] != b"MZ":
        raise ValueError(f"Not a PE executable: {path}")
    offset = struct.unpack_from("<I", data, 0x3C)[0]
    if data[offset:offset + 4] != b"PE\0\0" or struct.unpack_from("<H", data, offset + 4)[0] != expected_machine:
        raise ValueError(f"Unexpected machine architecture: {path}")


def payload_macros(common, output):
    files = sorted(path for path in common.rglob("*") if path.is_file())
    if any(path.is_symlink() for path in common.rglob("*")):
        raise ValueError("Package sources must not contain symbolic links")
    directories = sorted({parent for path in files for parent in path.relative_to(common).parents if parent != pathlib.Path(".")}, key=lambda p: (len(p.parts), str(p)))
    lines = ["; Generated from explicit package files; do not edit.", "!macro InstallCommon ROOT"]
    for path in files:
        relative = path.relative_to(common)
        folder = str(relative.parent).replace("/", "\\")
        lines += [f'  SetOutPath "${{ROOT}}\\{quote(folder)}"', f'  File "{quote(path)}"', "  IfErrors stage_failed"]
    lines += ["!macroend", "", "!macro RemoveCommon ROOT", "  Push $0", "  Push $1", "  Push $2", "  StrCpy $2 0"]

    def guard(relative):
        result = ["  StrCpy $1 1"]
        for parent in [pathlib.Path("."), *reversed(relative.parents), relative]:
            suffix = "" if parent == pathlib.Path(".") else "\\" + str(parent).replace("/", "\\")
            result += [f'  System::Call \'kernel32::GetFileAttributesW(w "${{ROOT}}{quote(suffix)}") i .r0\'', "  ${If} $0 == -1", "    StrCpy $1 0", "  ${Else}", "    IntOp $0 $0 & 0x400", "    ${If} $0 != 0", "      StrCpy $1 0", "    ${EndIf}", "  ${EndIf}"]
        return result

    for path in files:
        relative = path.relative_to(common)
        target = str(relative).replace("/", "\\")
        lines += [f'  ${{If}} ${{FileExists}} "${{ROOT}}\\{quote(target)}"']
        lines += guard(relative.parent)
        lines += ["    ${If} $1 == 1", "      ClearErrors", f'      Delete "${{ROOT}}\\{quote(target)}"', "      ${If} ${Errors}", "        StrCpy $2 1", "      ${EndIf}", "    ${Else}", "      StrCpy $2 1", "    ${EndIf}", "  ${EndIf}"]
    for directory in reversed(directories):
        lines += guard(directory)
        # A non-empty directory can contain user-added files. Keep it without an error.
        lines += ["  ${If} $1 == 1", f'    RMDir "${{ROOT}}\\{quote(str(directory).replace(chr(47), chr(92)))}"', "  ${EndIf}", "  ClearErrors"]
    lines += ["  ${If} $2 == 1", "    Pop $2", "    Pop $1", "    Pop $0", "    SetErrors", "  ${Else}", "    Pop $2", "    Pop $1", "    Pop $0", "    ClearErrors", "  ${EndIf}", "!macroend", ""]
    output.write_text("\n".join(lines))


def main():
    dependencies = json.loads((ROOT / "windows/dependencies.json").read_text())
    machine = platform.machine().lower()
    architecture = {"amd64": "x64", "x86_64": "x64", "aarch64": "arm64"}.get(machine, machine)
    host = dependencies["hosts"].get(f"{platform.system()}-{architecture}", {})
    tools = ROOT / "build/windows-tools"
    toolchain = dependencies.get(host.get("toolchain"), {})
    nsis = dependencies.get(host.get("nsis"), {})
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", type=pathlib.Path, default=tools / toolchain["directory"] if toolchain else None)
    parser.add_argument("--sdk", type=pathlib.Path, default=tools / dependencies["webview2"]["directory"])
    parser.add_argument("--nsis", type=pathlib.Path, default=tools / nsis["directory"] / nsis["executable"] if nsis else None)
    args = parser.parse_args()
    if args.toolchain is None or args.nsis is None:
        parser.error("Unsupported build host; provide --toolchain and --nsis explicitly")
    args.toolchain, args.sdk, args.nsis = (path.resolve() for path in (args.toolchain, args.sdk, args.nsis))
    output = ROOT / "build/windows"
    common = output / "common"
    output.mkdir(parents=True, exist_ok=True)
    if common.exists():
        shutil.rmtree(common)
    web = common / "web"
    shutil.copytree(ROOT / "windows/web", web, dirs_exist_ok=True)
    for name in ("clock-model.js", "clock-glyphs.js"):
        shutil.copy2(ROOT / name, web / name)
    for name in ("cloud-swift.mp4", "cloud-cirrus.mp4", "rectangle-tracks.json", "audio/clock-minute.wav"):
        target = web / "assets" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "assets" / name, target)
    licenses = common / "licenses"
    licenses.mkdir(parents=True, exist_ok=True)
    for source, name in ((ROOT / "LICENSE", "LICENSE.txt"), (ROOT / "assets/CREDITS.md", "CloudCredits.md"), (args.sdk / "LICENSE.txt", "WebView2-LICENSE.txt"), (args.sdk / "NOTICE.txt", "WebView2-NOTICE.txt")):
        shutil.copy2(source, licenses / name)
    shutil.copy2(ROOT / "assets/ClockIcon.ico", output / "ClockIcon.ico")
    bootstrapper = ROOT / "build/windows-tools/MicrosoftEdgeWebview2Setup.exe"
    if hashlib.sha256(bootstrapper.read_bytes()).hexdigest() != dependencies["webview2_bootstrapper"]["sha256"]:
        raise ValueError("Microsoft bootstrapper checksum mismatch")
    shutil.copy2(bootstrapper, output / bootstrapper.name)
    resource = output / "ClockSaver.rc"
    resource.write_text(f'''#include <windows.h>
1 ICON "{(ROOT / 'assets/ClockIcon.ico').as_posix()}"
1 VERSIONINFO
 FILEVERSION 0,9,0,0
 PRODUCTVERSION 0,9,0,0
 FILEOS VOS_NT_WINDOWS32
 FILETYPE VFT_APP
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904B0"
  BEGIN
   VALUE "FileDescription", "Cool Clock Screen Saver (Windows preview)\\0"
   VALUE "FileVersion", "{VERSION}\\0"
   VALUE "ProductName", "Cool Clock\\0"
   VALUE "ProductVersion", "{VERSION}\\0"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x0409, 1200
 END
END
STRINGTABLE
BEGIN
 1 "Cool Clock"
END
''')
    suffix = ".exe" if os.name == "nt" else ""
    for architecture, target, machine in (("x64", "x86_64", 0x8664), ("arm64", "aarch64", 0xAA64)):
        directory = output / architecture
        directory.mkdir(exist_ok=True)
        compiler = args.toolchain / "bin" / (target + "-w64-mingw32-clang++" + suffix)
        windres = args.toolchain / "bin" / (target + "-w64-mingw32-windres" + suffix)
        obj = directory / "ClockSaver.res.o"
        run(windres, "-i", resource, "-o", obj)
        run(compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-static", "-municode", "-mwindows", "-isystem", args.sdk / "build/native/include", ROOT / "windows/ClockSaver.cpp", obj, "-o", directory / "Cool Clock.scr", "-lole32", "-luser32", "-lgdi32", "-ladvapi32", "-lshell32", "-luuid", "-lwtsapi32")
        shutil.copy2(args.sdk / f"runtimes/win-{architecture}/native/WebView2Loader.dll", directory / "WebView2Loader.dll")
        pe(directory / "Cool Clock.scr", machine)
        pe(directory / "WebView2Loader.dll", machine)
    payload_macros(common, output / "payload-files.nsh")
    destination = ROOT / "dist" / f"Cool-Clock-{VERSION}-Windows-Setup.exe"
    destination.parent.mkdir(exist_ok=True)
    environment = dict(os.environ)
    nsis_root = args.nsis.parent if (args.nsis.parent / "Stubs").is_dir() else args.nsis.parent.parent / "share/nsis"
    environment["NSISDIR"] = str(nsis_root)
    run(args.nsis, "-V3", "-NOCD", f"-DPAYLOAD_DIR={output}", f"-DOUTPUT_FILE={destination}", f"-DVERSION={VERSION}", ROOT / "windows/Installer.nsi", env=environment)
    pe(destination, 0x14C)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    (destination.parent / "Windows-SHA256SUMS").write_text(f"{digest}  {destination.name}\n")
    print(f"Built {destination} ({destination.stat().st_size} bytes)\nSHA256 {digest}")


if __name__ == "__main__":
    main()
