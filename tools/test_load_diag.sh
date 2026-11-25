#!/bin/sh
# 回归：加载失败时的共存诊断（errno 解释 / 其它 .ko 模块 / 并发 insmod / 内核日志）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MODS="$TMP/modules"
mkdir -p "$MODS/other_lkm/system/lib/modules" "$MODS/disabled_mod/lib" "$MODS/noko" "$MODS/susfs_allinone/lib"
: > "$MODS/other_lkm/system/lib/modules/foo.ko"
: > "$MODS/other_lkm/system/lib/modules/bar.ko"
: > "$MODS/disabled_mod/lib/baz.ko"
: > "$MODS/susfs_allinone/lib/self.ko"
printf 'id=disabled_mod\n' > "$MODS/disabled_mod/module.prop"
: > "$MODS/disabled_mod/disable"

KLOG="$TMP/kmsg.txt"
cat > "$KLOG" <<'EOF'
[  120.5] susfs_guard_lkm: no symbol version for module_layout
[  120.5] susfs_guard_lkm: disagrees about version of symbol module_layout
[  120.6] module verification failed: signature and/or required key missing
EOF

PMOD="$TMP/proc_modules"
printf 'susfs_guard_lkm 123456 1 - Live 0x0\nkernelsu 4096 0 - Live 0x0\n' > "$PMOD"

fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
has() { printf '%s' "$2" | grep -q -- "$3" && echo yes || echo no; }

out=$(MODDIR="$TMP" LD_MODULES_DIR="$MODS" LD_KLOG_SRC="$KLOG" LD_PROC_MODULES="$PMOD" \
      sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; diag_load_failure 22' 2>&1)

chk "解释了 errno 22" "$(has x "$out" "EINVAL")" "yes"
chk "列出 /proc/modules 已有模块" "$(has x "$out" "susfs_guard_lkm(used=1)")" "yes"
chk "列出其它 .ko 模块" "$(has x "$out" "other_lkm")" "yes"
chk "跳过已停用模块" "$(has x "$out" "disabled_mod")" "no"
chk "不含自身" "$(has x "$out" "susfs_allinone :")" "no"
chk "命中内核日志关键行" "$(has x "$out" "disagrees about version")" "yes"
chk "给出签名/版本说明" "$(has x "$out" "符号版本对不上")" "yes"
chk "给出收集建议" "$(has x "$out" "ctl.sh kmiinfo")" "yes"

# errno 17 时应指出「同名模块已加载」
out17=$(MODDIR="$TMP" LD_MODULES_DIR="$MODS" LD_KLOG_SRC="$KLOG" LD_PROC_MODULES="$PMOD" \
        sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; diag_load_failure 17' 2>&1)
chk "errno 17 指向 EEXIST" "$(has x "$out17" "EEXIST")" "yes"
chk "errno 17 提示已被加载" "$(has x "$out17" "已经把同名模块加载了")" "yes"

# 无其它模块时不应误报
EMPTY="$TMP/empty"
mkdir -p "$EMPTY"
out0=$(MODDIR="$TMP" LD_MODULES_DIR="$EMPTY" LD_KLOG_SRC=/dev/null LD_PROC_MODULES=/dev/null \
       sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; diag_load_failure 14' 2>&1)
chk "无其它模块时不误报冲突" "$(has x "$out0" "同时装了")" "no"
chk "仍解释 EFAULT" "$(has x "$out0" "EFAULT")" "yes"

# /sys/module 优先：/proc/modules 被隐藏时仍能发现冲突
SYSMOD="$TMP/sysmod"
mkdir -p "$SYSMOD/susfs_guard_lkm" "$SYSMOD/generic_pid_guard" "$SYSMOD/not_related"
outsys=$(MODDIR="$TMP" LD_MODULES_DIR="$MODS" LD_KLOG_SRC=/dev/null LD_PROC_MODULES=/dev/null          LD_SYS_MODULE_DIR="$SYSMOD"          sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; diag_load_failure 17' 2>&1)
chk "sys/module 优先发现已有模块" "$(has x "$outsys" "susfs_guard_lkm")" "yes"
chk "sys/module 过滤无关模块" "$(has x "$outsys" "not_related")" "no"
chk "说明 /proc/modules 可能被隐藏" "$(has x "$outsys" "可能被隐藏")" "yes"

# errno 61：应指向签名并给出实测检查（可注入 config.gz 文本）
CONF="$TMP/config.txt"
printf 'CONFIG_MODULES=y
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_FORCE=y
' > "$CONF"
out61=$(MODDIR="$TMP" LD_MODULES_DIR="$EMPTY" LD_KLOG_SRC=/dev/null LD_PROC_MODULES=/dev/null         LD_SYS_MODULE_DIR="$EMPTY"         sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; _dl_gz=/dev/null; errno_meaning 61' 2>&1)
chk "errno 61 指向签名" "$(has x "$out61" "SIG_FORCE")" "yes"
chk "errno 61 提到验签失败" "$(has x "$out61" "验签")" "yes"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
