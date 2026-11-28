#!/bin/sh
# 1.3.2 一次性迁移：老配置 avc_spoof=1 → 0，只做一次；用户手动再开不覆盖
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
export REPO
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

T=$(mktemp -d)
mkdir -p "$T/config" "$T/state"
printf "avc_spoof=1\nhide_gapps=1\n" > "$T/config/config.ini"
printf 'set -u\n. "$REPO/common.sh" >/dev/null 2>&1\nmigrate_avc_spoof_132\n' > "$T/run.sh"

# 1) 首次：1 → 0，且有提示，哨兵落盘
out=$(MODDIR="$T" sh "$T/run.sh" 2>&1)
chk "首次迁移 1→0" "$(grep '^avc_spoof=' "$T/config/config.ini")" "avc_spoof=0"
chk "其他键不受影响" "$(grep -c '^hide_gapps=1$' "$T/config/config.ini")" "1"
chk "输出提示" "$(printf "%s" "$out" | grep -c "升级兼容")" "1"
chk "哨兵已写" "$([ -f "$T/state/migrated_avc_132" ] && echo yes || echo no)" "yes"

# 2) 用户手动改回 1：第二次调用必须不再动
printf "avc_spoof=1\nhide_gapps=1\n" > "$T/config/config.ini"
out2=$(MODDIR="$T" sh "$T/run.sh" 2>&1)
chk "二次调用不改用户选择" "$(grep '^avc_spoof=' "$T/config/config.ini")" "avc_spoof=1"
chk "二次调用无提示" "$(printf "%s" "$out2" | grep -c "升级兼容")" "0"

# 3) 已经是 0 的配置：无提示、哨兵照样写
rm -f "$T/state/migrated_avc_132"
printf "avc_spoof=0\n" > "$T/config/config.ini"
out3=$(MODDIR="$T" sh "$T/run.sh" 2>&1)
chk "已是 0 不变" "$(grep '^avc_spoof=' "$T/config/config.ini")" "avc_spoof=0"
chk "已是 0 无提示" "$(printf "%s" "$out3" | grep -c "升级兼容")" "0"
chk "哨兵仍写" "$([ -f "$T/state/migrated_avc_132" ] && echo yes || echo no)" "yes"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"