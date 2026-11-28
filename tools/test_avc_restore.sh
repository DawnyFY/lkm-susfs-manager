#!/bin/sh
# 1.3.2 契约：apply 不再写 LKM 参数（1.3.0 的通道已移除），但必须能还原老版本残留的伪装值
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
S="$REPO/apply.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "有残留还原函数" "$(grep -c '^restore_avc_param_leftover()' "$S")" "1"
chk "还原函数被调用" "$(grep -c '^restore_avc_param_leftover$' "$S")" "1"
chk "只在当前是伪装值时才还原" "$(grep -c '\[ "\$_rp_cur" = "\$AVC_SPOOF_CTX" \] || return 0' "$S")" "1"
chk "优先用记录的原值" "$(grep -c '_rp_t=\$AVC_REAL_CTX' "$S")" "1"
chk "还原后清记录" "$(grep -c 'rm -f "\$STATE/avc_orig_ctx"' "$S" | awk '{print ($1>=2)?"yes":"no"}')" "yes"

# 反证：不允许再往参数里写伪装值（1.3.0 的老行为）
chk "不再写入伪装值" "$(grep -c 'printf .%s\\n. "\$AVC_SPOOF_CTX" > "\$AVC_PARAM"' "$S" || true)" "0"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
