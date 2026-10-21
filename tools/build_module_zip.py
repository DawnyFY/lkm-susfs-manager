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
SKIP_DIRS = {
    "state", "__pycache__", ".git", ".github",
    "tools", "docs", "dist", "conversation", "device_snapshot",
    "preview", "research", "legacy", "handoff", "github",
}
SKIP_FILES = {"README.md", "START_HERE.md", "RELEASE_NOTES.md", ".gitignore", "CHANGELOG.md"}


def module_version() -> str:
    prop = SRC / "module.prop"
    text = prop.read_text(encoding="utf-8")
    match = re.search(r"^version=(.+)$", text, re.MULTILINE)
    return match.group(1).strip() if match else "unknown"


def main() -> int:
    if not (SRC / "module.prop").is_file():
        print(f"missing module source: {SRC}", file=sys.stderr)
        return 1
    DIST.mkdir(parents=True, exist_ok=True)
    out = DIST / f"susfs_allinone-{module_version()}.zip"

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(SRC):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in sorted(files):
                full = Path(root) / name
                rel = full.relative_to(SRC).as_posix()
                if rel in SKIP_FILES or rel.endswith((".log", ".tmp")):
                    continue
                # Fixed timestamps keep the ZIP byte-reproducible across machines.
                info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
                info.external_attr = ((0o755 if rel in EXEC_NAMES else 0o644) & 0xFFFF) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                data = full.read_bytes()
                if rel.endswith(TEXT_SUFFIXES):
                    if b"\r" in data:
                        print(f"WARN: CR bytes in {rel}; normalizing to LF", file=sys.stderr)
                        data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
                z.writestr(info, data)

    print(f"wrote {out} ({out.stat().st_size} bytes)")
    with zipfile.ZipFile(out) as z:
        for info in z.infolist():
            mode = (info.external_attr >> 16) & 0o777
            print(f"{info.filename:42s} {info.file_size:9d} mode={mode:o}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
