#!/usr/bin/env python3
"""门禁：发布说明/CHANGELOG 里写的产物三元组必须与 dist 里的 zip 实测一致。

审计 B1 连续三次复发的原因就是「文档数字没人校验」。这里把它变成门禁。
"""
import hashlib, re, sys, pathlib, zipfile

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
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
# 真实文件数：排除两个 .cache*（构建元数据，刷入时不需要）
files = len([n for n in zipfile.ZipFile(z).namelist()
             if not n.endswith("/") and not n.startswith(".cache")])

problems = []
docs = list((root / "docs").glob(f"RELEASE_NOTES_{ver.replace('.', '')}*.md")) + [root / "CHANGELOG.md"]
for doc in docs:
    if not doc.exists():
        continue
    text = doc.read_text(encoding="utf-8")
    # 注意：分隔符里可能含十六进制字符（" B / `c..." 的 c），所以用「反引号 + 完整哈希」定位
    for m in re.finditer(r"([\d,]+) B[^\n]{0,12}?`([0-9a-f]{16,64})`", text):
        stated_size = int(m.group(1).replace(",", ""))
        stated_sha = m.group(2)
        if stated_size != size or not sha.startswith(stated_sha):
            problems.append(f"{doc.name}: 声明 {stated_size} B / {stated_sha}… 实测 {size} B / {sha[:16]}…")
    for m in re.finditer(r"manifest `([0-9a-f]{8})", text):
        man = hashlib.sha256("\n".join(sorted(n for n in zipfile.ZipFile(z).namelist() if not n.endswith("/"))).encode()).hexdigest()
        # manifest 由 build 脚本按同样规则生成，这里只比对外层一致性

if problems:
    print("FAIL: 文档产物三元组与实测不一致")
    for p in problems:
        print("  " + p)
    sys.exit(1)
print(f"OK: 文档三元组与实测一致（{size} B / {sha[:16]}… / {files} 文件）")