#!/usr/bin/env python3
"""Validate update.json against module.prop for manager update discovery."""
from __future__ import annotations
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
def read_prop():
    m = {}
    for line in (ROOT / "module" / "module.prop").read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1); m[k.strip()] = v.strip()
    return m

def main() -> int:
    data = json.loads((ROOT / "update.json").read_text(encoding="utf-8"))
    prop = read_prop()
    errs = []
    for key in ("version", "versionCode", "zipUrl", "changelog"):
        if key not in data:
            errs.append(f"missing {key}")
    # update.json 是线上文件，必须始终指向「已经发布过的版本」；开发中它可以落后于
    # module.prop，等真正发布时再同步。允许 <=，禁止 >（指向不存在的资产会让用户下载 404）。
    try:
        upd_vc = int(data.get("versionCode", -1))
        prop_vc = int(prop.get("versionCode", -2))
    except (TypeError, ValueError):
        errs.append("versionCode not integer")
        upd_vc = prop_vc = -1
    if upd_vc > prop_vc:
        errs.append(f"update.json versionCode {upd_vc} is ahead of module.prop {prop_vc}（指向尚未发布的版本）")
    if data.get("version") == prop.get("version") and upd_vc != prop_vc:
        errs.append("same version but versionCode differs")
    zip_url = str(data.get("zipUrl", ""))
    if not zip_url.startswith("https://github.com/DawnyFY/lkm-susfs-manager/releases/download/v"):
        errs.append("zipUrl must be the GitHub HTTPS release URL")
    if zip_url.rsplit("/", 1)[-1] != f"susfs_allinone-{data.get('version')}.zip":
        errs.append("zipUrl filename does not match update.json version")
    if f"/download/v{data.get('version')}/" not in zip_url:
        errs.append("zipUrl tag does not match update.json version")
    if not str(data.get("changelog", "")).startswith("https://"):
        errs.append("changelog must be HTTPS")
    expected = "https://raw.githubusercontent.com/DawnyFY/lkm-susfs-manager/main/update.json"
    if prop.get("updateJson") != expected:
        errs.append("module.prop updateJson mismatch")
    if errs:
        for e in errs: print("FAIL:", e)
        return 1
    note = "" if data.get("version") == prop.get("version") else f"（module.prop 已是 {prop.get('version')}，发布时需同步）"
    print(f"OK: update.json version={data['version']} versionCode={data['versionCode']}{note}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
