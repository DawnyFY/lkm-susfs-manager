#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Magisk 兼容入口：Magisk 没有 boot-completed.sh，规则在这一步应用。
# KernelSU 系走 boot-completed.sh，这里直接跳过避免重复执行。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"

boot_gate_ok || exit 0
_cf_gate || { echo "=== service: 文件被修改，跳过应用 ===" >> "$MODDIR/apply.log" 2>/dev/null; exit 0; }

# KernelSU / APatch 有 boot-completed.sh，由它负责应用；这里只补 Magisk
case "$(root_family)" in
    KernelSU|APatch) exit 0 ;;
esac

cfg_ensure
cfg_load
MODDIR=/data/adb/modules/susfs_allinone
CONFIG=$MODDIR/config
STATE=$MODDIR/state
[ "${auto_load:-1}" = "1" ] || exit 0

AUTOLOAD=1 sh "$MODDIR/apply.sh"
