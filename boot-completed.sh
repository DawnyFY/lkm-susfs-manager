#!/system/bin/sh
# 开机完成：设置 sdcard 根路径并应用 sus_path / hide_modules 等规则。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"

boot_gate_ok || exit 0

[ -f "$MODDIR/config/config.sh" ] && . "$MODDIR/config/config.sh"
[ "${auto_load:-1}" = "1" ] || exit 0

# 先执行应用；只有真正跑完（rc=0）才认为本次启动成功，清除守卫标记
AUTOLOAD=1 sh "$MODDIR/apply.sh"
rc=$?
if [ "$rc" = "0" ]; then
    clear_boot_guard
fi
exit "$rc"