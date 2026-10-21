#!/system/bin/sh
# 开机完成：设置 sdcard 根路径并应用 sus_path / hide_modules 等规则。
MODDIR=/data/adb/modules/susfs_allinone

[ -f "$MODDIR/disable" ] && exit 0
[ -f "$MODDIR/remove" ] && exit 0
[ -f "$MODDIR/disable_autoload" ] && exit 0
[ "$(getprop persist.sys.safemode)" = "1" ] && exit 0
[ "$(getprop ro.sys.safemode)" = "1" ] && exit 0

[ -f "$MODDIR/config/config.sh" ] && . "$MODDIR/config/config.sh"
[ "${auto_load:-1}" = "1" ] || exit 0

exec /system/bin/sh "$MODDIR/apply.sh"
