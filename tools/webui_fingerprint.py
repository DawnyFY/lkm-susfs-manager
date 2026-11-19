#!/usr/bin/env python3
"""WebUI 源码指纹：build_webui.sh 与 check_zip.py 共用同一个实现，避免两套算法漂移。

指纹 = sha256( 每行 "<文件sha256>  <相对路径>\\n" )，按路径排序，
覆盖 webui/src 全树与构建配置。
"""

from __future__ import annotations

import hashlib
import os
import sys

FINGERPRINT_TARGETS = ("src", "index.html", "package.json", "vite.config.ts", "tsconfig.json")


def fingerprint(ui_dir: str) -> str:
    if not os.path.isdir(ui_dir):
        return ""
    files: list[str] = []
    for name in FINGERPRINT_TARGETS:
        full = os.path.join(ui_dir, name)
        if os.path.isfile(full):
            files.append(full)
        elif os.path.isdir(full):
            for root, _dirs, names in os.walk(full):
                for f in names:
                    files.append(os.path.join(root, f))
    files.sort()
    outer = hashlib.sha256()
    for path in files:
        rel = os.path.relpath(path, ui_dir).replace(os.sep, "/")
        with open(path, "rb") as fh:
            inner = hashlib.sha256(fh.read()).hexdigest()
        outer.update((inner + "  " + rel + "\n").encode("utf-8"))
    return outer.hexdigest()


def main(argv: list[str]) -> int:
    ui = argv[1] if len(argv) > 1 else os.path.join("webui")
    value = fingerprint(ui)
    if not value:
        print("webui directory not found: " + ui, file=sys.stderr)
        return 1
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
