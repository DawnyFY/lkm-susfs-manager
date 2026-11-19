#!/usr/bin/env python3
"""Validate the packaged SUSFS 管理器 ZIP.

Usage:
    python tools/check_zip.py [path/to/module.zip]

Checks archive integrity, required files, module name/version, branch
support strings, WebUI fields, and executable modes.
"""
from __future__ import annotations

import hashlib
import re
import sys
import zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
def _version_key(p: Path):
    import re
    m = re.search(r"susfs_allinone-(\d+(?:\.\d+)*)", p.name)
    return tuple(int(x) for x in m.group(1).split(".")) if m else (0,)

def _newest_zip() -> Path:
    zips = sorted((BASE / "dist").glob("susfs_allinone-*.zip"), key=_version_key)
    return zips[-1] if zips else BASE / "dist" / "susfs_allinone.zip"

DEFAULT = _newest_zip()

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
    "webroot/assets/app.js",
    "webroot/assets/app.css",
    "config/sus_path_loop.txt",
    "pid_guard.sh",
    "pid_guard_ctl.sh",
    "config/pid_guard.conf",
    "lib/pid_guard/5.10/generic_pid_guard.ko",
    "lib/pid_guard/5.15/generic_pid_guard.ko",
    "lib/pid_guard/6.1/generic_pid_guard.ko",
    "lib/pid_guard/6.6/generic_pid_guard.ko",
    "lib/pid_guard/6.12/generic_pid_guard.ko",
    "lib/pid_guard/6.18/generic_pid_guard.ko",
}
EXEC_REQUIRED = {"load.sh", "apply.sh", "ctl.sh", "action.sh", "customize.sh", "service.sh",
                 "pid_guard.sh", "pid_guard_ctl.sh"}


def _webui_fingerprint() -> str:
    """调用统一的指纹实现（tools/webui_fingerprint.py），保证与 build_webui.sh 一致。"""
    import importlib.util
    import os

    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(here, "webui_fingerprint.py")
    if not os.path.isfile(target):
        return ""
    spec = importlib.util.spec_from_file_location("webui_fingerprint", target)
    if spec is None or spec.loader is None:
        return ""
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.fingerprint(os.path.join(os.path.dirname(here), "webui"))

def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def verify_manifest(z: zipfile.ZipFile, names: set[str]) -> None:
    """Validate .cache.files / .cache.meta against the actual archive bytes."""
    if ".cache.files" not in names or ".cache.meta" not in names:
        fail("missing .cache.files or .cache.meta")
    manifest = z.read(".cache.files")
    if not manifest.strip():
        fail("empty .cache.files")
    seen: dict[str, str] = {}
    for line in manifest.decode("utf-8", "replace").splitlines():
        if not line.strip():
            continue
        parts = line.split("  ", 1)
        if len(parts) != 2 or len(parts[0]) != 64:
            fail(f"bad manifest line: {line[:80]}")
        digest, name = parts[0].lower(), parts[1]
        if name in seen:
            fail(f"duplicate manifest entry: {name}")
        if name not in names:
            fail(f"manifest entry missing from zip: {name}")
        actual = hashlib.sha256(z.read(name)).hexdigest()
        if actual != digest:
            fail(f"manifest hash mismatch: {name}")
        seen[name] = digest
    meta_text = z.read(".cache.meta").decode("utf-8", "replace")
    meta = {}
    for line in meta_text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k.strip()] = v.strip()
    if meta.get("manifest_sha256", "").lower() != hashlib.sha256(manifest).hexdigest():
        fail(".cache.meta manifest_sha256 mismatch")
    try:
        if int(meta.get("files", "-1")) != len(seen):
            fail(".cache.meta files count mismatch")
    except ValueError:
        fail(".cache.meta files is not an integer")
    skip = {"module.prop", "customize.sh", ".cache.files", ".cache.meta"}
    extra = [
        n for n in names
        if n not in seen and n not in skip and not n.startswith(("config/", "state/"))
    ]
    if extra:
        fail(f"unmanifested zip entries: {', '.join(sorted(extra)[:5])}")
    print(f"manifest: {len(seen)} files verified")
def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    if not path.is_file():
        fail(f"missing {path}")
    # 运行期密钥/状态绝不能进入发布包
    with zipfile.ZipFile(path) as _z:
        _names = set(_z.namelist())
    if any(n.startswith("state/") or "install_key" in n for n in _names):
        fail("release zip contains state/ or install_key")

    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest().upper()
    print(f"file: {path}")
    print(f"size: {len(raw)}")
    print(f"sha256: {digest}")

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
        _src = BASE / "module" / "module.prop"
        if not _src.is_file():
            _src = BASE / "module.prop"
        _expect_v = re.search(r"^version=(.+)$", _src.read_text(encoding="utf-8"), re.M)
        _expect_c = re.search(r"^versionCode=(.+)$", _src.read_text(encoding="utf-8"), re.M)
        if _expect_v and f"version={_expect_v.group(1).strip()}" not in prop:
            fail("module.prop version mismatch vs repo module.prop")
        if _expect_c and f"versionCode={_expect_c.group(1).strip()}" not in prop:
            fail("module.prop versionCode mismatch vs repo module.prop")

        common = z.read("common.sh").decode("utf-8")
        for token in ("find_susfs_bin", "select_susfs_bin", "ksu_branch", "marker_exists"):
            if token not in common:
                fail(f"common.sh missing {token}")

        customize = z.read("customize.sh").decode("utf-8")
        for token in ("SukiSU", "ReSukiSU", "KernelSU Next"):
            if token not in customize:
                fail(f"customize.sh missing branch token {token}")

        html = z.read("webroot/index.html").decode("utf-8")
        for token in ("<title>LKM SUSFS管理器</title>", "assets/app.js", "assets/app.css"):
            if token not in html:
                fail(f"webroot/index.html missing {token}")
        # WebUI 必须相对路径加载资源：ksu:// 与 file:// 下绝对路径会 404
        if 'src="/' in html or 'href="/' in html:
            fail("webroot/index.html uses absolute asset paths")

        app = z.read("webroot/assets/app.js").decode("utf-8")
        for token in ("ctl.sh", "root_manager", "pid_guard_reload", "set_stats"):
            if token not in app:
                fail(f"webroot/assets/app.js missing {token}")
        for token in ("/data/adb/modules/susfs_allinone/ctl.sh",):
            if token not in app:
                fail(f"webroot/assets/app.js missing control path {token}")

        for name in sorted(EXEC_REQUIRED):
            mode = (z.getinfo(name).external_attr >> 16) & 0o777
            if mode != 0o755:
                fail(f"{name} mode is {oct(mode)}, expected 0o755")
        common_mode = (z.getinfo("common.sh").external_attr >> 16) & 0o777
        if common_mode != 0o644:
            fail(f"common.sh mode is {oct(common_mode)}, expected 0o644")

        # WebUI 产物必须与源码一致：改 webui/src 后忘了 rebuild，这里会拦下来
        if "webroot/.build.json" not in names:
            fail("missing webroot/.build.json (run tools/build_webui.sh)")
        import json as _json
        stamp = _json.loads(z.read("webroot/.build.json").decode("utf-8"))
        want = stamp.get("source_sha256") or ""
        proc = _webui_fingerprint()
        if not want:
            fail("webroot/.build.json missing source_sha256")
        if proc != want:
            fail("webroot is stale: source_sha256 mismatch (rerun tools/build_webui.sh)")

        verify_manifest(z, names)

    print("OK: archive, manifest, branch support, WebUI and modes validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
