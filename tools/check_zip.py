#!/usr/bin/env python3
"""Validate the packaged SUSFS 管理器 ZIP.

Usage:
    python tools/check_zip.py [path/to/module.zip]

Checks archive integrity, required files, module name/version, branch
support strings, WebUI fields, and executable modes.
"""
from __future__ import annotations

import hashlib
import sys
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
DEFAULT = BASE / "dist" / "susfs_allinone-1.1.7.zip"
EXPECTED_SHA256 = "03379F24D150FCA0B7D2436E15A99EE359D626E670E5D20F87AB7F54D9B79B35"

REQUIRED = {
    "module.prop",
    "common.sh",
    "load.sh",
    "apply.sh",
    "ctl.sh",
    "action.sh",
    "customize.sh",
    "post-fs-data.sh",
    "boot-completed.sh",
    "webroot/index.html",
    "webroot/app.js",
    "webroot/style.css",
}
EXEC_REQUIRED = {"load.sh", "apply.sh", "ctl.sh", "action.sh", "customize.sh"}


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    if not path.is_file():
        fail(f"missing {path}")

    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest().upper()
    print(f"file: {path}")
    print(f"size: {len(raw)}")
    print(f"sha256: {digest}")
    if path == DEFAULT and digest != EXPECTED_SHA256:
        print(f"WARN: expected handoff SHA256 is {EXPECTED_SHA256}")

    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad is not None:
            fail(f"corrupt entry: {bad}")
        names = set(z.namelist())
        missing = sorted(REQUIRED - names)
        if missing:
            fail(f"missing entries: {', '.join(missing)}")

        prop = z.read("module.prop").decode("utf-8")
        if "name=LKM SUSFS管理器" not in prop:
            fail("module.prop name is not LKM SUSFS管理器")
        if "version=1.1.7" not in prop or "versionCode=9" not in prop:
            fail("module.prop version is not 1.1.7 / 9")

        common = z.read("common.sh").decode("utf-8")
        for token in ("find_susfs_bin", "select_susfs_bin", "ksu_branch", "marker_exists"):
            if token not in common:
                fail(f"common.sh missing {token}")

        customize = z.read("customize.sh").decode("utf-8")
        for token in ("SukiSU", "ReSukiSU", "KernelSU Next"):
            if token not in customize:
                fail(f"customize.sh missing branch token {token}")

        html = z.read("webroot/index.html").decode("utf-8")
        for token in ("<title>LKM SUSFS管理器</title>", "rootManager", "binPath", "footerVersion"):
            if token not in html:
                fail(f"webroot/index.html missing {token}")

        app = z.read("webroot/app.js").decode("utf-8")
        for token in ("root_manager", "ksu_bin_path", "footerVersion"):
            if token not in app:
                fail(f"webroot/app.js missing {token}")

        for name in sorted(EXEC_REQUIRED):
            mode = (z.getinfo(name).external_attr >> 16) & 0o777
            if mode != 0o755:
                fail(f"{name} mode is {oct(mode)}, expected 0o755")
        common_mode = (z.getinfo("common.sh").external_attr >> 16) & 0o777
        if common_mode != 0o644:
            fail(f"common.sh mode is {oct(common_mode)}, expected 0o644")

    print("OK: archive, manifest, branch support, WebUI and modes validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
