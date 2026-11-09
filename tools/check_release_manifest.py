#!/usr/bin/env python3
"""Assert the built zip's manifest hash matches the checked-in release gate.

The zip bytes differ across platforms (ZIP create_system), but
.cache.meta:manifest_sha256 is content-derived and must be stable.
"""
from __future__ import annotations
import re, sys, zipfile
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent


def _ver(p: Path):
    m = re.search(r"susfs_allinone-(\d+(?:\.\d+)*)", p.name)
    return tuple(int(x) for x in m.group(1).split(".")) if m else (0,)


def main() -> int:
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    else:
        zips = sorted((BASE / "dist").glob("susfs_allinone-*.zip"), key=_ver)
        if not zips:
            print("FAIL: no zip under dist/")
            return 1
        path = zips[-1]
    gate = BASE / "tools" / "release_manifest.sha256"
    expected = gate.read_text(encoding="utf-8").split()[0].lower() if gate.is_file() else ""
    if not expected:
        print(f"FAIL: missing/empty {gate}")
        return 1
    with zipfile.ZipFile(path) as z:
        try:
            meta = z.read(".cache.meta").decode("utf-8", "replace")
        except KeyError:
            print("FAIL: .cache.meta missing")
            return 1
    actual = ""
    for line in meta.splitlines():
        if line.startswith("manifest_sha256="):
            actual = line.split("=", 1)[1].strip().lower()
            break
    print(f"zip: {path}")
    print(f"manifest_sha256={actual}")
    print(f"expected={expected}")
    if actual != expected:
        print("FAIL: manifest hash drift")
        return 1
    print("OK: release manifest matches gate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
