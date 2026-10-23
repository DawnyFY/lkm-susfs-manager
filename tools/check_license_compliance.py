#!/usr/bin/env python3
"""License-compliance gate for a built module zip.

usage: python check_license_compliance.py [dist/susfs_allinone-*.zip ...]
Exit 0 = all checks pass; 1 = gaps found (each printed as GAP:).
"""
from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest().upper()


def check(path: Path) -> list[str]:
    gaps: list[str] = []
    z = zipfile.ZipFile(path)
    names = set(z.namelist())

    def need(cond: bool, msg: str) -> None:
        if not cond:
            gaps.append(msg)

    need("LICENSE" in names, "缺少 LICENSE（GPL-2.0 全文）")
    lic = z.read("LICENSE").decode("utf-8", "replace") if "LICENSE" in names else ""
    need("GNU GENERAL PUBLIC LICENSE" in lic and "Version 2" in lic, "LICENSE 不是 GPLv2 全文")
    need("LICENSE-AGPL-3.0" in names, "缺少 AGPL-3.0 全文（bundled ksu_susfs 为 sidex15/ksu_module_susfs, AGPL-3.0）")
    need("NOTICE" in names or "THIRD_PARTY.md" in names, "缺少 NOTICE/THIRD_PARTY 第三方声明")

    raw = z.read("provenance.json").decode("utf-8") if "provenance.json" in names else ""
    need(bool(raw), "缺少 provenance.json")
    need("license" in raw.lower(), "provenance.json 未标注许可证")
    prov = json.loads(raw) if raw else {}

    ksu = z.read("bin/ksu_susfs_good") if "bin/ksu_susfs_good" in names else b""
    if ksu:
        need(sha(ksu) in raw.upper(), "provenance.json 未包含 bin/ksu_susfs_good 的哈希/来源（AGPL 组件）")

    for name, digest in prov.get("assets_sha256", {}).items():
        matches = [n for n in names if n == name or n.endswith("/" + name)]
        need(bool(matches), f"provenance 列出的 {name} 不在包内")
        for n in matches:
            need(sha(z.read(n)) == digest.upper(), f"{n} 与 provenance 哈希不一致")

    prop = z.read("module.prop").decode("utf-8", "replace") if "module.prop" in names else ""
    need("inforcqb" in prop, "module.prop 未署名 LKM 作者 inforcqb")
    need("sidex15" in prop or "simonpunk" in prop, "module.prop 未署名 ksu_susfs 作者 sidex15 & simonpunk (AGPL-3.0)")
    return gaps


def main() -> int:
    paths = [Path(a) for a in sys.argv[1:]] or [Path("dist/susfs_allinone-1.1.7.zip")]
    rc = 0
    for path in paths:
        if not path.is_file():
            print(f"{path}: MISSING")
            rc = 1
            continue
        gaps = check(path)
        print(f"zip: {path}")
        if gaps:
            rc = 1
            print(f"RESULT: {len(gaps)} GAP(S)")
            for g in gaps:
                print(" GAP:", g)
        else:
            print("RESULT: OK")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
