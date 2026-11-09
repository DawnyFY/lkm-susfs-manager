#!/bin/sh
# 发布引用一致性：防止 NOTICE/UPSTREAM/provenance 回退到旧 tag，
# 以及防止文档重新引入无效的 NeoZygisk 子目录排除建议。
set -eu
ROOT=${1:-.}
cd "$ROOT"
fail=0
chk() { if ! eval "$1"; then echo "FAIL: $2"; fail=1; else echo "PASS  $2"; fi; }

chk "grep -q 'v2.3.0-r18.9-1' NOTICE" "NOTICE LKM tag r18.9-1"
chk "! grep -q 'v2.3.0-r18.8' NOTICE" "NOTICE no r18.8"
chk "grep -q 'susfs4ksu-for-lkm' NOTICE" "NOTICE canonical repo"
chk "grep -q 'v1.5.2+_R28' NOTICE" "NOTICE AGPL tag"
chk "grep -q 'v2.3.0-r18.9-1' docs/UPSTREAM.md" "UPSTREAM LKM tag"
chk "grep -q 'v1.5.2+_R28' docs/UPSTREAM.md" "UPSTREAM AGPL tag"
chk "! grep -rq 'v1.5.2-R28' docs/UPSTREAM.md NOTICE" "no old AGPL tag"
chk "grep -q 'v2.3.0-r18.9-1' provenance.json" "provenance LKM tag"

for f in README.md docs/FAQ.md docs/VERIFICATION.md; do
    chk "! grep -q '或至少排除' \"$f\"" "$f no invalid subdir-exclusion advice"
done
chk "! grep -q 'or exclude /data/adb/neozygisk' README.en.md" "README.en no invalid subdir-exclusion advice"
exit "$fail"
