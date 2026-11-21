#!/bin/sh
# 离线回归：tools/avc_spoof.sh（给 1.2.9 用户的 AVC 伪装开关）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
S="$ROOT/tools/avc_spoof.sh"
[ -f "$S" ] || S="$(dirname "$REPO")/tools/avc_spoof.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "脚本存在" "$([ -f "$S" ] && echo yes || echo no)" "yes"
if sh -n "$S" 2>/dev/null; then r=ok; else r=bad; fi
chk "sh 语法正确" "$r" "ok"

# 五个子命令都得有
# case 标签形如 "    status)" 或 "    on|enable|1)"
for c in on off status install-boot remove-boot; do
    if grep -qE "^    ($c\||$c\))" "$S"; then n=1; else n=0; fi
    chk "支持子命令 $c" "$n" "1"
done

# 关键路径：写入与还原都必须是内核参数，且还原值正确
chk "使用 avc_su_ctx 参数" "$([ "$(grep -c 'parameters/avc_su_ctx' "$S")" -ge 1 ] && echo yes || echo no)" "yes"
chk "还原值为 u:r:ksu:s0" "$(grep -c 'REAL_CTX="u:r:ksu:s0"' "$S")" "1"
chk "伪装值为 priv_app" "$(grep -c 'SPOOF_CTX="u:r:priv_app:s0:c512,c768"' "$S")" "1"

# 必须拒绝非 root
chk "检查 root" "$(grep -c 'id -u' "$S")" "1"

# 不许改模块目录里的文件（避免触发模块完整性校验）
chk "不写模块 config" "$(grep -cE '(>|>>)[[:space:]]*"?\\$MOD/(config|module.prop)' "$S" || true)" "0"
chk "不使用 sed -i" "$(grep -c 'sed -i' "$S" || true)" "0"

# 不在模块包内分发
chk "不在模块包内" "$([ -f "$ROOT/module/avc_spoof.sh" ] && echo in-module || echo standalone)" "standalone"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
