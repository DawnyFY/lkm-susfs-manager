#!/bin/sh
# 回归：符号预检 / KMI 建议 / doctor / watchdog 配置项
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
C="$REPO/common.sh"; A="$REPO/apply.sh"; L="$REPO/load.sh"; T="$REPO/ctl.sh"; S="$REPO/service.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "有符号预检函数" "$(grep -c '^lkm_symbols_check()' "$C")" "1"
chk "预检在 insmod 之前" "$(grep -n 'lkm_symbols_check' "$L" | head -1 | cut -d: -f1 | awk '{print ($1 < 300) ? "yes" : "no"}')" "yes"
chk "符号清单存在" "$(ls "$REPO"/lib/symbols/*.symbols 2>/dev/null | wc -l)" "8"
chk "有 suggest_kmi" "$(grep -c '^suggest_kmi()' "$C")" "1"
chk "有相邻 KMI 提示" "$(grep -c '^adjacent_kmi_hint()' "$C")" "1"
chk "errno 14/22 用相邻提示" "$(grep -c 'adjacent_kmi_hint "$KMI"' "$C")" "1"
chk "ctl 有 doctor" "$(grep -c '^    doctor)' "$T")" "1"
chk "ctl 有 suggest_kmi" "$(grep -c '^    suggest_kmi)' "$T")" "1"
chk "service 有看护" "$(grep -c 'conf_get watchdog_minutes' "$S")" "1"
chk "默认配置有看护项" "$(grep -c '^watchdog_minutes=0' "$REPO/config/config.ini.default")" "1"
chk "节点后端 loop 退化" "$(grep -c '节点后端无 loop 接口' "$A")" "1"

# 行为：suggest_kmi 对几种内核串给出合理结论
WD=$(mktemp -d); mkdir -p "$WD/lib" "$WD/state" "$WD/config"
for k in android13-5.15 android14-6.1 android15-6.6; do : > "$WD/lib/susfs_guard_lkm-$k.ko"; done
out=$(MODDIR="$WD" sh -c '. "'"$C"'" >/dev/null 2>&1; suggest_kmi 5.15.194-android13-8-gabc' 2>/dev/null | tail -1)
chk "5.15 + android13 → android13-5.15" "$out" "android13-5.15"
out2=$(MODDIR="$WD" sh -c '. "'"$C"'" >/dev/null 2>&1; suggest_kmi 6.1.118-android14-11-o-g64180a' 2>/dev/null | tail -1)
chk "6.1 + android14 → android14-6.1" "$out2" "android14-6.1"
out3=$(MODDIR="$WD" sh -c '. "'"$C"'" >/dev/null 2>&1; suggest_kmi 4.19.157' 2>/dev/null | tail -1)
chk "无同版本 → 空" "$out3" ""
rm -rf "$WD"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"