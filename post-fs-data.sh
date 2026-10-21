#!/system/bin/sh
# 开机早期：只负责加载 LKM，规则留到 boot-completed 再应用。
MODDIR=/data/adb/modules/susfs_allinone

[ -f "$MODDIR/disable" ] && exit 0
[ -f "$MODDIR/remove" ] && exit 0
[ -f "$MODDIR/disable_autoload" ] && exit 0
[ "$(getprop persist.sys.safemode)" = "1" ] && exit 0
[ "$(getprop ro.sys.safemode)" = "1" ] && exit 0

[ -f "$MODDIR/config/config.sh" ] && . "$MODDIR/config/config.sh"
[ "${auto_load:-1}" = "1" ] || exit 0

if command -v timeout >/dev/null 2>&1; then
    timeout 20 /system/bin/sh "$MODDIR/load.sh"
else
    /system/bin/sh "$MODDIR/load.sh"
fi
