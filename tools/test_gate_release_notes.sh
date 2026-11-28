#!/bin/sh
# 门禁自检：check_release_notes（尺寸/哈希/manifest/文件数）+ check_no_crlf（.symbols）
# 用一棵最小合成树，不依赖仓库真实产物
set -u
ROOT="$1"
[ -f "$ROOT/module/module.prop" ] || ROOT="$(dirname "$ROOT")"
export PATH="/usr/bin:/bin:/c/Python314:$PATH"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "CI 里有该门禁" "$(grep -c check_release_notes "$ROOT/.github/workflows/build.yml")" "1"

T=$(mktemp -d)
# Windows 上的 python 不认 /tmp/... 这类 MSYS 路径，统一换成盘符形式
TW=$(cygpath -m "$T" 2>/dev/null || printf "%s" "$T")
mkdir -p "$T/module" "$T/docs" "$T/dist" "$T/module/lib/symbols"
printf "version=9.9.9\nversionCode=99\n" > "$T/module/module.prop"
printf "hello\n" > "$T/a.txt"
cp -a "$ROOT/tools/check_release_notes.py" "$ROOT/tools/check_no_crlf.py" "$T/"
python - "$TW" <<'EOP'
import hashlib, sys, zipfile, pathlib
t = pathlib.Path(sys.argv[1])
z = t / "dist/susfs_allinone-9.9.9.zip"
with zipfile.ZipFile(z, "w") as f:
    f.writestr("module.prop", "version=9.9.9\n")
    f.writestr(".cache.files", "")
data = z.read_bytes()
size = len(data)
sha = hashlib.sha256(data).hexdigest()
names = [n for n in zipfile.ZipFile(z).namelist() if not n.startswith(".cache") and not n.endswith("/")]
lines = []
with zipfile.ZipFile(z) as zf:
    for n in sorted(names):
        if n in {"module.prop", "customize.sh"}:
            continue
        lines.append(hashlib.sha256(zf.read(n)).hexdigest() + "  " + n)
man = hashlib.sha256(("\n".join(lines) + "\n").encode()).hexdigest()
files = len(names)
txt = "产物 {:,} B / `{}` / manifest `{}…`（{} 文件）\n".format(size, sha, man, files)
(t / "docs/RELEASE_NOTES_999.md").write_text(txt, encoding="utf-8")
(t / "good.txt").write_text(txt, encoding="utf-8")
EOP

run() { python "$TW/check_release_notes.py" "$TW" >/dev/null 2>&1; echo $?; }
chk "基准通过" "$(run)" "0"

for m in size sha manifest files wipe; do
    cp "$T/good.txt" "$T/docs/RELEASE_NOTES_999.md"
    python - "$TW" "$m" <<'EOP'
import re, sys, pathlib
t, mode = pathlib.Path(sys.argv[1]), sys.argv[2]
p = t / "docs/RELEASE_NOTES_999.md"
s = p.read_text(encoding="utf-8")
if mode == "size":
    s = re.sub(r"([\d,]+) B", "9,999,999 B", s, count=1)
elif mode == "sha":
    s = re.sub(r"`([0-9a-f]{16,64})`", "`" + "0" * 64 + "`", s, count=1)
elif mode == "manifest":
    s = re.sub(r"manifest `([0-9a-f]{8})", lambda m: "manifest `deadbeef", s, count=1)
elif mode == "files":
    s = re.sub(r"（(\d+) 文件）", "（999 文件）", s, count=1)
elif mode == "wipe":
    s = "# 空文档"
p.write_text(s, encoding="utf-8")
EOP
    chk "篡改 $m 被抓" "$(run)" "1"
done

printf "abc\r\n" > "$T/module/lib/symbols/android15-6.6.symbols"
chk "带 CR 的 .symbols 被 CRLF 门禁抓" "$(python "$TW/check_no_crlf.py" "$TW" 2>&1 | grep -c CR)" "1"
printf "abc\n" > "$T/module/lib/symbols/android15-6.6.symbols"
chk "LF 的 .symbols 放行" "$?" "0"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"