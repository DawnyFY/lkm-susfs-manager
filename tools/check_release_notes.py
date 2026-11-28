#!/usr/bin/env python3
"""门禁：发布说明/CHANGELOG 里写的产物三元组必须与 dist 里的 zip 实测一致。

审计 B1 连续三次复发的原因就是「文档数字没人校验」。这里把它变成门禁：
尺寸、sha256、manifest、文件数四个值全部校验，缺一处就不算通过。
"""
import hashlib, re, sys, pathlib, zipfile

args = [a for a in sys.argv[1:] if not a.startswith("--")]
format_only = "--format-only" in sys.argv
root = pathlib.Path(args[0] if args else ".")
prop = (root / "module/module.prop").read_text(encoding="utf-8")
ver = re.search(r"^version=(\S+)", prop, re.M).group(1)

zips = sorted((root / "dist").glob(f"susfs_allinone-{ver}*.zip"))
if not zips:
    print(f"SKIP: dist 里没有 {ver} 的产物")
    sys.exit(0)
z = zips[0]
data = z.read_bytes()
size = len(data)
sha = hashlib.sha256(data).hexdigest()
names = [n for n in zipfile.ZipFile(z).namelist() if not n.endswith("/") and not n.startswith(".cache")]
files = len(names)

# manifest：与 build_module_zip.py 完全同规则（跳过 config/、state/ 与指定文件，末尾带换行）
SKIP_FILES = {"module.prop", ".cache.files", ".cache.meta", "customize.sh"}
SKIP_PREFIXES = ("config/", "state/")
zf = zipfile.ZipFile(z)
lines = []
for n in sorted(names):
    if n in SKIP_FILES or n.startswith(SKIP_PREFIXES):
        continue
    lines.append(hashlib.sha256(zf.read(n)).hexdigest() + "  " + n)
manifest = hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()

problems = []
docs = list((root / "docs").glob(f"RELEASE_NOTES_{ver.replace('.', '')}*.md")) + [root / "CHANGELOG.md"]
checked = 0
for doc in docs:
    if not doc.exists():
        continue
    text = doc.read_text(encoding="utf-8")
    # 只认「产物」行：尺寸 + 反引号哈希 + manifest + 文件数，四者都要在
    for m in re.finditer(r"([\d,]+) B[^\n]{0,12}?`([0-9a-f]{16,64})`[^\n]{0,40}?manifest `([0-9a-f]{8})[^`]*`[^\n]{0,8}?（(\d+) 文件）", text):
        checked += 1
        stated_size = int(m.group(1).replace(",", ""))
        if format_only:
            continue
        if stated_size != size:
            problems.append(f"{doc.name}: 尺寸 {stated_size} != 实测 {size}")
        if not sha.startswith(m.group(2)):
            problems.append(f"{doc.name}: sha256 {m.group(2)[:16]}… != 实测 {sha[:16]}…")
        if not manifest.startswith(m.group(3)):
            problems.append(f"{doc.name}: manifest {m.group(3)}… != 实测 {manifest[:8]}…")
        if int(m.group(4)) != files:
            problems.append(f"{doc.name}: 文件数 {m.group(4)} != 实测 {files}")

if checked == 0:
    print("FAIL: 没在文档里找到完整的产物三元组（尺寸/哈希/manifest/文件数）")
    sys.exit(1)
if problems:
    print("FAIL: 文档产物三元组与实测不一致")
    for p in problems:
        print("  " + p)
    sys.exit(1)
if format_only:
    print(f"OK(格式): {checked} 处三元组完整；字节比对跳过（CI 构建与发布构建不保证同字节）")
else:
    print(f"OK: {checked} 处三元组与实测一致（{size} B / {sha[:16]}… / manifest {manifest[:8]}… / {files} 文件）")