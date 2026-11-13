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
    if data.get("version") != prop.get("version"):
        errs.append(f"version mismatch: update.json={data.get('version')} module.prop={prop.get('version')}")
    try:
        if int(data.get("versionCode", -1)) != int(prop.get("versionCode", -2)):
            errs.append("versionCode mismatch")
    except (TypeError, ValueError):
        errs.append("versionCode not integer")
    zip_url = str(data.get("zipUrl", ""))
    if not zip_url.startswith("https://github.com/DawnyFY/lkm-susfs-manager/releases/download/v"):
        errs.append("zipUrl must be the GitHub HTTPS release URL")
    if zip_url.rsplit("/", 1)[-1] != f"susfs_allinone-{prop.get('version')}.zip":
        errs.append("zipUrl filename does not match version")
    if not str(data.get("changelog", "")).startswith("https://"):
        errs.append("changelog must be HTTPS")
    expected = "https://raw.githubusercontent.com/DawnyFY/lkm-susfs-manager/main/update.json"
    if prop.get("updateJson") != expected:
        errs.append("module.prop updateJson mismatch")
    if errs:
        for e in errs: print("FAIL:", e)
        return 1
    print(f"OK: update.json version={data['version']} versionCode={data['versionCode']}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
