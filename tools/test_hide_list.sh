#!/bin/sh
# 离线回归：/proc/susfs_hide_modules 的模块名在 names: 行里以空格分隔
# 曾经的回归：改成「整行等于模块名」比较后，kernelsu 永远被判为未隐藏
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

has() { HIDE_MODULES_NODE="$1" sh -c ". '$REPO/common.sh' >/dev/null 2>&1; hide_list_has '$2'"; echo $?; }

# 真实格式（设备上抓取）
cat > "$TMP/real" <<'EOF'
hide_modules: 3/16 name(s), /sys/module rules=2 (failed=3), /proc/modules lines removed=591, kallsyms lines removed=0
names: susfs_guard_lkm kernelsu generic_pid_guard
EOF
chk "names 行里的 kernelsu 命中" "$(has "$TMP/real" kernelsu)" "0"
chk "names 行里的 generic_pid_guard 命中" "$(has "$TMP/real" generic_pid_guard)" "0"
chk "kernelsu2 不应命中（按词匹配）" "$(has "$TMP/real" kernelsu2)" "1"
chk "不存在的名字不命中" "$(has "$TMP/real" magisk)" "1"

# 空文件 / 单行 names
printf 'names:\n' > "$TMP/empty"
chk "空 names 不命中" "$(has "$TMP/empty" kernelsu)" "1"
printf 'names: kernelsu\n' > "$TMP/one"
chk "只有一个名字时命中" "$(has "$TMP/one" kernelsu)" "0"

# 文件不存在
chk "文件不存在返回不命中" "$(has "$TMP/nonexistent" kernelsu)" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
