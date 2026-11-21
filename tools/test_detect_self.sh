#!/bin/sh
# 离线回归：module/detect_self.sh 存在、语法正确、关键输出项齐全
# 这个脚本是给用户直接跑的诊断工具，语法坏了就等于没有。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
S="$REPO/detect_self.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "脚本存在" "$([ -f "$S" ] && echo yes || echo no)" "yes"
chk "可执行位/可被 sh 读取" "$([ -r "$S" ] && echo yes || echo no)" "yes"

if sh -n "$S" 2>/dev/null; then r=ok; else r=bad; fi
chk "sh 语法正确" "$r" "ok"

# 关键输出项（用户按这些键对账，缺了就没法用）
for k in "模块版本" "LKM 已加载" "proc/modules" "kallsyms" "spoof_uname" "sus_path 规则数" "归属与建议"; do
    n=$(grep -c "$k" "$S")
    chk "输出含「$k」" "$([ "$n" -ge 1 ] && echo yes || echo no)" "yes"
done

# 必须明确标注「不属本模块」的坑，避免误导用户
chk "标注 kallsyms 不属本模块" "$(grep -c "属内核/root 管理器侧" "$S")" "1"
chk "标注 netlink 属 ROM" "$(grep -c "ROM 的 SELinux 策略" "$S")" "1"

# 只读：不允许出现写操作
chk "不含重定向写入配置" "$(grep -cE '>>?[[:space:]]*"?\\$(CONF|CFG)' "$S" || true)" "0"
chk "不含 sed -i" "$(grep -c "sed -i" "$S" || true)" "0"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
