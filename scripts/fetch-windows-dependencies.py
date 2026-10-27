#!/usr/bin/env python3
"""Fetch pinned Windows build tools into build/windows-tools, without global installs."""
import hashlib
import json
import pathlib
import platform
import shutil
import tarfile
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT / "build/windows-tools"


def fetch(url, path, expected, headers=None):
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        temporary = path.with_suffix(path.suffix + ".download")
        try:
            request = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(request, timeout=90) as source, temporary.open("wb") as target:
                shutil.copyfileobj(source, target)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
                raise ValueError(f"SHA-256 mismatch: {path.name}; dependency versions must be updated explicitly")
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    return path


def host_key():
    machine = platform.machine().lower()
    architecture = {"amd64": "x64", "x86_64": "x64", "aarch64": "arm64"}.get(machine, machine)
    return f"{platform.system()}-{architecture}"


def extract(archive, destination):
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as package:
            for member in package.infolist():
                path = pathlib.PurePosixPath(member.filename)
                if path.is_absolute() or ".." in path.parts or "\\" in member.filename or ":" in member.filename:
                    raise ValueError("Unsafe build dependency archive path")
            package.extractall(destination)
    else:
        with tarfile.open(archive) as package:
            package.extractall(destination, filter="data")


def main():
    manifest = json.loads((ROOT / "windows/dependencies.json").read_text())
    host = manifest["hosts"].get(host_key())
    if not host:
        raise SystemExit(f"Unsupported build host: {host_key()}; see windows/README.md for manual build inputs.")
    TOOLS.mkdir(parents=True, exist_ok=True)
    for name in (host["toolchain"], host["nsis"], "webview2", "webview2_bootstrapper"):
        item = manifest[name]
        headers = {}
        if name == "nsis_macos_arm64":
            with urllib.request.urlopen("https://ghcr.io/token?service=ghcr.io&scope=repository:homebrew/core/makensis:pull", timeout=30) as response:
                headers["Authorization"] = "Bearer " + json.load(response)["token"]
        archive = fetch(item["url"], TOOLS / item["filename"], item["sha256"], headers)
        if "directory" in item and not (TOOLS / item["directory"]).exists():
            extract(archive, TOOLS / item["directory"] if name == "webview2" else TOOLS)
        print(f"Verified {name} ({item.get('version', 'pinned bootstrapper')})")


if __name__ == "__main__":
    main()
