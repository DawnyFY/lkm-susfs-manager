#!/bin/sh
# 离线回归：tools/collect_info.sh（给用户的独立采集脚本）
# 它不是模块的一部分，但要保证：语法正确、段落齐全、只读。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
S="$(dirname "$REPO")/tools/collect_info.sh"
[ -f "$S" ] || S="$ROOT/tools/collect_info.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "脚本存在" "$([ -f "$S" ] && echo yes || echo no)" "yes"
if sh -n "$S" 2>/dev/null; then r=ok; else r=bad; fi
chk "sh 语法正确" "$r" "ok"

for k in "设备与系统" "内核" "Root 方案" "模块状态" "配置摘要" "日志尾部" "崩溃证据"; do
    n=$(grep -c "$k" "$S")
    chk "含段落「$k」" "$([ "$n" -ge 1 ] && echo yes || echo no)" "yes"
done

# 只读：不许改系统或模块文件
chk "不含 sed -i" "$(grep -c "sed -i" "$S" || true)" "0"
chk "不含 rm -rf" "$(grep -c "rm -rf" "$S" || true)" "0"

# 隐私：install_id 必须被排除
chk "排除 install_id" "$(grep -c "install_id=" "$S")" "1"

# 必须随包外分发（不在 module 目录里）
chk "不在模块包内" "$([ -f "$ROOT/module/collect_info.sh" ] && echo in-module || echo standalone)" "standalone"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
