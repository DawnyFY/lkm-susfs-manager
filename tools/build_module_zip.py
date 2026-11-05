#!/usr/bin/env python3
"""Build the SUSFS 管理器 module ZIP from ./module.

Usage:
    python tools/build_module_zip.py

The output is dist/susfs_allinone-<version>.zip. The script assigns
executable modes to shell entrypoints and the bundled binaries, matching
the original packaging, and normalizes stray CR bytes in text payloads
(a CR in a #!/bin/sh script makes MODDIR end with CR and breaks every
"$MODDIR/..." lookup on device).
"""
from __future__ import annotations

import hashlib
import os
import re
import sys
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
# Support both layouts:
#   handoff:  <base>/module/module.prop
#   git repo: <base>/module.prop
SRC = BASE / "module"
if not (SRC / "module.prop").is_file() and (BASE / "module.prop").is_file():
    SRC = BASE
DIST = BASE / "dist"

EXEC_NAMES = {
    "action.sh",
    "load.sh",
    "apply.sh",
    "ctl.sh",
    "post-fs-data.sh",
    "boot-completed.sh",
    "customize.sh",
    "bin/susfs_insmod",
    "bin/ksu_susfs_good",
}
TEXT_SUFFIXES = (".sh", ".prop", ".json", ".txt", ".md", ".js", ".css", ".html")
MANIFEST_NAME = ".cache.files"
BUILD_INFO_NAME = ".cache.meta"
MANIFEST_SKIP_PREFIXES = ("config/", "state/")
MANIFEST_SKIP_FILES = {"module.prop", ".cache.files", ".cache.meta", "customize.sh"}
SKIP_DIRS = {
    "state", "__pycache__", ".git", ".github",
    "tools", "docs", "dist", "conversation", "device_snapshot",
    "preview", "research", "legacy", "handoff", "github",
}
SKIP_FILES = {
    "README.md", "START_HERE.md", "RELEASE_NOTES.md", ".gitignore",
    "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md", "CODE_OF_CONDUCT.md",
    "ISSUE_TEMPLATE", "PULL_REQUEST_TEMPLATE.md",
}


def module_version() -> str:
    prop = SRC / "module.prop"
    text = prop.read_text(encoding="utf-8")
    match = re.search(r"^version=(.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else "unknown"


def collect_files():
    """收集要打包的文件（rel -> bytes），跳过开发文件。"""
    items = {}
    for root, dirs, files in os.walk(SRC):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in sorted(files):
            full = Path(root) / name
            rel = full.relative_to(SRC).as_posix()
            if rel in SKIP_FILES or rel.endswith((".log", ".tmp")):
                continue
            if rel.startswith("RELEASE_NOTES") or rel.startswith("CHANGELOG"):
                continue
            data = full.read_bytes()
            if rel.endswith(TEXT_SUFFIXES) and b"\r" in data:
                print(f"WARN: CR bytes in {rel}; normalizing to LF", file=sys.stderr)
                data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            items[rel] = data
    return items


def main() -> int:
    if not (SRC / "module.prop").is_file():
        print(f"missing module source: {SRC}", file=sys.stderr)
        return 1
    DIST.mkdir(parents=True, exist_ok=True)
    out = DIST / f"susfs_allinone-{module_version()}.zip"

    items = collect_files()


    manifest_lines = []
    for rel in sorted(items):
        if rel in MANIFEST_SKIP_FILES or rel.startswith(MANIFEST_SKIP_PREFIXES):
            continue
        manifest_lines.append(f"{hashlib.sha256(items[rel]).hexdigest()}  {rel}")
    manifest = ("\n".join(manifest_lines) + "\n").encode("utf-8")
    manifest_hash = hashlib.sha256(manifest).hexdigest()
    items[MANIFEST_NAME] = manifest
    items[BUILD_INFO_NAME] = (
        f"version={module_version()}\n"
        f"manifest_sha256={manifest_hash}\n"
        f"files={len(manifest_lines)}\n"
    ).encode("utf-8")

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in sorted(items):
            # Fixed timestamps keep the ZIP byte-reproducible across machines.
            info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = ((0o755 if rel in EXEC_NAMES else 0o644) & 0xFFFF) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, items[rel])

    zip_hash = hashlib.sha256(out.read_bytes()).hexdigest()
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    print(f"sha256: {zip_hash}")
    print(f"manifest: {len(manifest_lines)} files, sha256={manifest_hash}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())