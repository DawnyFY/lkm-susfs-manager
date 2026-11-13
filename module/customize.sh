#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 安装脚本：KernelSU 系列（官方版 / SukiSU / ReSukiSU / KernelSU Next）、Magisk、APatch。
# 开机阶段：KernelSU 系列与 APatch 都有 boot-completed，Magisk 只有 service（late_start）。
# 注意：APatch 会把 MAGISK_VER_CODE 设成 27000，所以必须先认 APatch，否则会被误标成 Magisk。
IS_APATCH=0
if [ "$APATCH" = true ] || [ "$KERNELPATCH" = true ] || [ -n "$APATCH_VER" ] || [ -x /data/adb/ap/bin/apd ] || [ -x /data/adb/apd ]; then
    IS_APATCH=1
fi

if [ "$IS_APATCH" = "1" ] || [ "$KSU" = true ] || [ -n "$KSU_VER" ] || [ -n "$KSU_KERNEL_VER_CODE" ] || [ -d /data/adb/ksu ] \
    || [ -n "$MAGISK_VER_CODE" ] || [ -n "$MAGISK_VER" ] || [ -d /data/adb/magisk ]; then
    :
else
    abort "- 需要 KernelSU / SukiSU / ReSukiSU / KernelSU Next / Magisk / APatch 管理器"
fi
[ "$ARCH" = arm64 ] || abort "- 仅支持 arm64"

# 内核预检（只提示不阻断）：LKM 路线需要 CONFIG_MODULES/KALLSYMS；
# 内核直接编入 SUSFS 时不需要这些，模块只负责管理规则。
_cfg=""
if command -v zcat >/dev/null 2>&1 && [ -r /proc/config.gz ]; then
    _cfg=$(zcat /proc/config.gz 2>/dev/null)
fi
if [ -z "$_cfg" ] && [ -r /proc/config.gz ]; then
    for _bz in /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox /data/adb/magisk/busybox; do
        if [ -x "$_bz" ]; then
            _cfg=$("$_bz" zcat /proc/config.gz 2>/dev/null)
            [ -n "$_cfg" ] && break
        fi
    done
fi
if [ -n "$_cfg" ]; then
    case "$_cfg" in
        *CONFIG_MODULES=y*) : ;;
        *) ui_print "- 注意：内核未开 CONFIG_MODULES，无法加载 SUSFS LKM；若内核已内置 SUSFS，本模块只管理规则" ;;
    esac
    case "$_cfg" in
        *CONFIG_MODULE_SIG_FORCE=y*) ui_print "- 注意：内核强制模块签名，自编译的 SUSFS LKM 可能被拒绝加载" ;;
    esac
    case "$_cfg" in
        *CONFIG_KALLSYMS=y*) : ;;
        *) ui_print "- 注意：内核缺少 CONFIG_KALLSYMS，SUSFS LKM 大概率加载失败" ;;
    esac
    case "$_cfg" in
        *CONFIG_KPROBES=y*) : ;;
        *) ui_print "- 注意：内核缺少 CONFIG_KPROBES，SUSFS LKM 的符号解析与隐藏能力会受限" ;;
    esac
fi

if [ "$IS_APATCH" = "1" ]; then
    ui_print "- 管理器: APatch ${APATCH_VER:-unknown}"
    ui_print "- APatch 未实机验证：本模块需要加载 SUSFS LKM，内核拒绝时会写进 load.log 并改写模块描述"
elif [ "$KSU" = true ] || [ -n "$KSU_VER" ] || [ -n "$KSU_KERNEL_VER_CODE" ]; then
    ui_print "- 管理器: ${KSU_VER:-KernelSU}"
elif [ -n "$MAGISK_VER" ]; then
    ui_print "- 管理器: Magisk $MAGISK_VER"
fi

# 升级时保留用户配置与规则清单：安装包里的 config 只是默认值，不能覆盖已改过的配置
INSTALLED=/data/adb/modules/susfs_allinone
COPIED_CONFIG=0
if [ -d "$INSTALLED/config" ]; then
    for _f in config.ini sus_path.txt sus_path_loop.txt sus_mount.txt try_umount.txt hide_modules.txt skip_hide.txt sus_map.txt allow_lkm_on_kernelpatch; do
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
    # 保留归属清单：丢了会让 replace_rules=1 退化为"按配置清理"
    mkdir -p "$MODPATH/state" 2>/dev/null
    if [ -s "$INSTALLED/state/install_key" ]; then
        cp -f "$INSTALLED/state/install_key" "$MODPATH/state/install_key" 2>/dev/null && chmod 600 "$MODPATH/state/install_key" 2>/dev/null && ui_print "- 保留安装密钥"
    fi
    for _sf in our_paths.txt hide_mounts_added.txt sus_map_added.txt; do
        if [ -f "$INSTALLED/state/$_sf" ]; then
            cp -f "$INSTALLED/state/$_sf" "$MODPATH/state/$_sf" 2>/dev/null \
                && ui_print "- 保留规则清单: state/$_sf"
        fi
    done
elif [ -f /data/adb/susfs4ksu/sus_path.txt ]; then
    # 首次安装：继承旧 susfs4ksu 的规则文件
    for _f in sus_path sus_mount try_umount; do
        if [ -f "/data/adb/susfs4ksu/$_f.txt" ]; then
            cp -f "/data/adb/susfs4ksu/$_f.txt" "$MODPATH/config/$_f.txt" && COPIED_CONFIG=1
        fi
    done
    [ -s "$MODPATH/config/hide_modules.txt" ] || echo "kernelsu" > "$MODPATH/config/hide_modules.txt"
fi

# 安装时签发一次设备密钥；升级优先复用旧的，避免服务端标识变化。
# 只用于匿名标识/后续签名请求，不打印明文，文件权限 600；熵源失败必须中止安装。
mkdir -p "$MODPATH/state" 2>/dev/null
chmod 700 "$MODPATH/state" 2>/dev/null
if [ ! -s "$MODPATH/state/install_key" ]; then
    _ik=""
    _ik_rnd="${INSTALL_KEY_RANDOM:-/dev/urandom}"
    if [ -r "$_ik_rnd" ]; then
        _ik=$(dd if="$_ik_rnd" bs=32 count=1 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
        [ "${#_ik}" -eq 64 ] || _ik=$(od -An -N32 -tx1 "$_ik_rnd" 2>/dev/null | tr -d ' \n')
    fi
    case "$_ik" in *[!0-9a-fA-F]*|'') _ik="" ;; esac
    case "$_ik" in *[!0]*) ;; *) _ik="" ;; esac
    if [ "${#_ik}" -ne 64 ]; then
        abort "- 安装密钥熵源失败，拒绝使用固定/空 key"
    fi
    ( umask 077; printf '%s\n' "$_ik" > "$MODPATH/state/install_key" ) 2>/dev/null || abort "- 写入安装密钥失败"
    ui_print "- 已签发安装密钥"
fi
chmod 600 "$MODPATH/state/install_key" 2>/dev/null

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
chmod 700 "$MODPATH/state" 2>/dev/null
chmod 600 "$MODPATH/state/install_key" 2>/dev/null
set_perm "$MODPATH/bin/susfs_insmod" 0 0 0755
set_perm "$MODPATH/bin/ksu_susfs_good" 0 0 0755
for script in action.sh load.sh apply.sh ctl.sh post-fs-data.sh boot-completed.sh service.sh; do
    set_perm "$MODPATH/$script" 0 0 0755
done
touch "$MODPATH/skip_mount"

if [ "$KMI" = "unknown" ]; then
    ui_print "- 内核未匹配：本次未安装 LKM，重启后在 WebUI 指定 KMI 再加载"
else
    ui_print "- 已为 $KMI 安装 SUSFS LKM"
fi
if [ -e /proc/susfs_path ] || [ -e /proc/susfs_hide_mounts ]; then
    ui_print "- 检测到内核已提供 SUSFS 接口（/proc/susfs_*）：将只管理规则，不依赖外挂 LKM"
fi
ui_print "- 自带 WebUI：状态 / 配置 / 日志"
ui_print "- 重启后自动加载；也可在模块 Action 中手动加载"
if [ "$COPIED_CONFIG" = "1" ]; then
    ui_print "- 已保留现有规则配置"
else
    ui_print "- 首次安装；可在 WebUI 中导入旧 susfs4ksu 配置"
fi