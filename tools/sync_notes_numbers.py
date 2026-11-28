#!/usr/bin/env python3
"""把发布说明里的产物三元组同步成 dist 里 zip 的实测值（供发布前跑一次）。"""
import hashlib, io, re, sys, zipfile, pathlib

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
ver = re.search(r"^version=(\S+)", (root / "module/module.prop").read_text(encoding="utf-8"), re.M).group(1)
zips = sorted((root / "dist").glob(f"susfs_allinone-{ver}*.zip"))
if not zips:
    print(f"没有 {ver} 的产物")
    raise SystemExit(1)
z = zips[0]
data = z.read_bytes()
size = len(data)
sha = hashlib.sha256(data).hexdigest()
names = [n for n in zipfile.ZipFile(z).namelist() if not n.startswith(".cache") and not n.endswith("/")]
man_file = root / "tools/release_manifest.sha256"
man = man_file.read_text(encoding="utf-8").strip()[:8] if man_file.exists() else ""
repl = "产物 {:,} B / `{}` / manifest `{}…`（{} 文件）".format(size, sha, man, len(names))

docs = list((root / "docs").glob(f"RELEASE_NOTES_{ver.replace(chr(46), chr(0))}*.md")) if False else list((root / "docs").glob("RELEASE_NOTES_%s*.md" % ver.replace(".", "")))
changed = 0
for p in docs:
    s = p.read_text(encoding="utf-8")
    new = re.sub(r"产物 [0-9,]+ B[^\n]*?（\d+ 文件）", repl, s)
    if new != s:
        # 必须显式 LF：Windows 上 write_text 会写成 CRLF，直接被 check_no_crlf 抓
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
        changed += 1
print(repl)
print(f"更新 {changed} 个文件")