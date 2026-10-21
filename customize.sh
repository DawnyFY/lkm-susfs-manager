#!/system/bin/sh
# KernelSU 系列安装脚本（官方版 / SukiSU / ReSukiSU / KernelSU Next）
if [ "$KSU" = true ] || [ -n "$KSU_VER" ] || [ -n "$KSU_KERNEL_VER_CODE" ] || [ -d /data/adb/ksu ]; then
    :
else
    abort "- 需要 KernelSU / SukiSU / ReSukiSU / KernelSU Next 管理器"
fi
[ "$ARCH" = arm64 ] || abort "- 仅支持 arm64"

if [ -n "$KSU_VER" ]; then
    ui_print "- 管理器: $KSU_VER"
fi

REL=$(cat /proc/sys/kernel/osrelease) || abort "- 无法读取内核版本"
. "$MODPATH/kmi.sh"
KMI=$(select_kmi "$REL" "$MODPATH") || abort "- 没有匹配当前内核的 LKM: $REL"
[ -s "$MODPATH/lib/susfs_guard_lkm-$KMI.ko" ] || abort "- 缺少 $KMI 的 LKM 文件"

# 升级时保留本模块已有配置；首次安装时继承旧 susfs4ksu 配置
INSTALLED=/data/adb/modules/susfs_allinone
COPIED_CONFIG=0
if [ -f "$INSTALLED/config/sus_path.txt" ]; then
    for f in config.sh sus_path.txt sus_mount.txt try_umount.txt hide_modules.txt; do
        if [ -f "$INSTALLED/config/$f" ]; then
            cp -f "$INSTALLED/config/$f" "$MODPATH/config/$f"
            COPIED_CONFIG=1
        fi
    done
elif [ -f /data/adb/susfs4ksu/sus_path.txt ]; then
    for f in sus_path sus_mount try_umount; do
        if [ -f "/data/adb/susfs4ksu/$f.txt" ]; then
            cp -f "/data/adb/susfs4ksu/$f.txt" "$MODPATH/config/$f.txt"
            COPIED_CONFIG=1
        fi
    done
    echo "kernelsu" > "$MODPATH/config/hide_modules.txt"
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/bin/susfs_insmod" 0 0 0755
set_perm "$MODPATH/bin/ksu_susfs_good" 0 0 0755
for script in action.sh load.sh apply.sh ctl.sh post-fs-data.sh boot-completed.sh; do
    set_perm "$MODPATH/$script" 0 0 0755
done
touch "$MODPATH/skip_mount"

ui_print "- 已为 $KMI 安装 SUSFS LKM"
ui_print "- 自带 WebUI：状态 / 配置 / 日志"
ui_print "- 重启后自动加载；也可在模块 Action 中手动加载"
if [ "$COPIED_CONFIG" = "1" ]; then
    ui_print "- 已保留现有规则配置"
else
    ui_print "- 首次安装；可在 WebUI 中导入旧 susfs4ksu 配置"
fi
