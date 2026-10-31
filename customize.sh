#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
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

# 升级时保留用户配置与规则清单：安装包里的 config 只是默认值，不能覆盖已改过的配置
INSTALLED=/data/adb/modules/susfs_allinone
COPIED_CONFIG=0
if [ -d "$INSTALLED/config" ]; then
    for _f in config.ini sus_path.txt sus_mount.txt try_umount.txt hide_modules.txt skip_hide.txt; do
        if [ -f "$INSTALLED/config/$_f" ]; then
            cp -f "$INSTALLED/config/$_f" "$MODPATH/config/$_f" 2>/dev/null && COPIED_CONFIG=1 && ui_print "- 保留配置: $_f"
        fi
    done
    # 旧版只有 config.sh：安装时先迁移到 config.ini（只提取 KEY=VALUE，绝不 source）
    if [ ! -f "$INSTALLED/config/config.ini" ] && [ -f "$INSTALLED/config/config.sh" ]; then
        _dst="$MODPATH/config/config.ini"
        _tmp="$MODPATH/config/config.ini.migrate"
        _dropped=0
        : > "$_tmp" 2>/dev/null
        while IFS= read -r _line || [ -n "$_line" ]; do
            case "$_line" in
                ""|"#"*) printf '%s\n' "$_line" >> "$_tmp" ;;
                [A-Za-z_]*=*) printf '%s\n' "$_line" >> "$_tmp" ;;
                *) _dropped=$((_dropped + 1)) ;;
            esac
        done < "$INSTALLED/config/config.sh"
        if [ -s "$_tmp" ]; then
            mv -f "$_tmp" "$_dst"
            cp -f "$INSTALLED/config/config.sh" "$MODPATH/config/config.sh.bak" 2>/dev/null
            COPIED_CONFIG=1
            ui_print "- 已迁移旧配置 config.sh -> config.ini"
            [ "$_dropped" -gt 0 ] && ui_print "- 迁移时丢弃 $_dropped 行非 KEY=VALUE 内容"
        else
            rm -f "$_tmp"
        fi
    fi
    # 保留 sus_path 归属清单：丢了会让 replace_rules=1 退化为"按配置清理"
    if [ -f "$INSTALLED/state/our_paths.txt" ]; then
        mkdir -p "$MODPATH/state" 2>/dev/null
        cp -f "$INSTALLED/state/our_paths.txt" "$MODPATH/state/our_paths.txt" 2>/dev/null \
            && ui_print "- 保留规则清单: state/our_paths.txt"
    fi
elif [ -f /data/adb/susfs4ksu/sus_path.txt ]; then
    # 首次安装：继承旧 susfs4ksu 的规则文件
    for _f in sus_path sus_mount try_umount; do
        if [ -f "/data/adb/susfs4ksu/$_f.txt" ]; then
            cp -f "/data/adb/susfs4ksu/$_f.txt" "$MODPATH/config/$_f.txt" && COPIED_CONFIG=1
        fi
    done
    [ -s "$MODPATH/config/hide_modules.txt" ] || echo "kernelsu" > "$MODPATH/config/hide_modules.txt"
fi

# 用真实内核选 KMI（/proc/version 通常不受 uname 伪装影响）
REL=$(awk 'NR==1 { if ($3 ~ /^[0-9]+\.[0-9]+/ && $3 ~ /android[0-9]/) print $3 }' /proc/version 2>/dev/null)
[ -n "$REL" ] || REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
[ -n "$REL" ] || abort "- 无法读取内核版本"
. "$MODPATH/kmi.sh"
KMI=$(select_kmi "$REL" "$MODPATH" 2>/dev/null) || KMI=""
if [ -z "$KMI" ]; then
    GUESS=$(guess_kmis "$REL" "$MODPATH" | tr '\n' ' ')
    PACKED=$(list_kmis "$MODPATH" | tr '\n' ' ')
    ui_print "- 未匹配内核: $REL"
    ui_print "- 已打包: $PACKED"
    ui_print "- 版本号疑似: $GUESS"
    ui_print "- 照常安装，之后在 WebUI 指定 KMI"
    # 刷写日志页会自动关闭，把结果落盘供稍后查看
    {
        echo "# 安装时内核匹配记录（刷写日志关掉后仍可查看）"
        echo "osrelease=$REL"
        echo "matched="
        echo "guessed=$GUESS"
        echo "packaged=$PACKED"
        echo "saved_at=$(date '+%F %T' 2>/dev/null)"
    } > "$MODPATH/install_kmi.txt" 2>/dev/null
# 同时写进模块描述，管理器卡片上直接可见
    awk -v d="⚠️ 未匹配内核 | $REL | 疑似: $GUESS" '
        /^description=/ { print "description=" d; next }
        { print }
    ' "$MODPATH/module.prop" > "$MODPATH/module.prop.tmp" 2>/dev/null
    mv -f "$MODPATH/module.prop.tmp" "$MODPATH/module.prop" 2>/dev/null
    ui_print "- 已写入 install_kmi.txt，稍后可在 WebUI 或 kmiinfo 查看"
fi
[ -n "$KMI" ] || KMI=unmatched
if [ "$KMI" != "unmatched" ]; then
    [ -s "$MODPATH/lib/susfs_guard_lkm-$KMI.ko" ] || abort "- 缺少 $KMI 的 LKM 文件"
    ui_print "- 内核 $REL -> $KMI"
else
    KMI=unknown
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