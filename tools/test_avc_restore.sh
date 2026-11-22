#!/bin/sh
# 回归：AVC 参数开启/还原必须尊重"原值"（audit M1）
# 旧实现关闭时硬编码写回 u:r:ksu:s0，会覆盖用户自定义的 su 域。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
S="$REPO/apply.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 结构断言：必须有原值记录与按原值还原
chk "记录原值到 state/avc_orig_ctx" "$(grep -c 'STATE/avc_orig_ctx' "$S" | awk '{print ($1>=3)?"yes":"no"}')" "yes"
chk "关闭时优先用原值" "$(grep -c '_avc_target=\$_avc_saved' "$S")" "1"
chk "还原后清理记录文件" "$(grep -c 'rm -f \"\$STATE/avc_orig_ctx\"' "$S")" "1"
chk "缺少记录时退回 u:r:ksu:s0" "$(grep -c 'AVC_REAL_CTX=\"u:r:ksu:s0\"' "$S")" "1"
chk "写入前不覆盖已保存的原值" "$(grep -c '! -s \"\$STATE/avc_orig_ctx\"' "$S")" "1"

# 反证：不允许出现"关闭时直接用硬编码常量还原"的老写法
chk "无硬编码还原直写" "$(grep -c 'printf .%s\\\\n. \"\$AVC_REAL_CTX\" > \"\$AVC_PARAM\"' "$S" || true)" "0"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
