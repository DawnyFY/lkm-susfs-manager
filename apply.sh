#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 应用 SUSFS 规则：确保 LKM 已加载，设置 sdcard 根路径，再写 sus_path / hide_modules 等。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"
LOG=$MODDIR/apply.log
mkdir -p "$STATE" 2>/dev/null

# 日志过大时只保留最近 500 行
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null)" -gt 262144 ]; then
    tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi
exec >>"$LOG" 2>&1
echo ""
echo "=== apply $(date '+%F %T') ==="
echo "[i] root: $(root_family)"

set_description() {
    prop="$MODDIR/module.prop"
    [ -f "$prop" ] || return 0
    _tmp="$prop.tmp"
    # 用 awk 写入，避免描述里的 # & 等字符破坏 sed 表达式
    awk -v d="$1" '
        /^description=/ { print "description=" d; next }
        { print }
    ' "$prop" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$prop" 2>/dev/null
}

[ -f "$MODDIR/disable" ] && { echo "模块已禁用"; exit 0; }
[ -f "$MODDIR/remove" ] && { echo "模块待移除"; exit 0; }
if [ -f "$STATE/loading" ]; then
    # 残留超过 10 分钟视为上次异常退出，自动清理后继续，避免永久跳过
    if file_older_than "$STATE/loading" 600; then
        rm -f "$STATE/loading"
        echo "[!] 清理过期的 state/loading 残留（>10 分钟）"
    else
        echo "[!] 上次 LKM 加载未完成（state/loading 残留），跳过规则应用"
        exit 0
    fi
fi

# 互斥：开机脚本与 WebUI 可能同时触发 apply，重复执行会让 our_paths 清单错乱
if ! lock_acquire "$STATE/apply.lock" 900; then
    echo "[!] 另一个 apply 正在运行，跳过本次"
    exit 0
fi
trap 'lock_release "$STATE/apply.lock"' EXIT

restore_config_if_missing
ensure_skip_hide_file
cfg_ensure
cfg_load
# 配置不能改变这些路径：否则可借 MODDIR/STATE 加载任意脚本或写入任意位置
MODDIR=/data/adb/modules/susfs_allinone
CONFIG=$MODDIR/config
STATE=$MODDIR/state
hide_sus_mnts=${hide_sus_mnts:-1}
avc_spoof=${avc_spoof:-0}
replace_rules=${replace_rules:-0}
hide_compat_matrix=${hide_compat_matrix:-0}
hide_revanced=${hide_revanced:-0}
hide_custom_rom=${hide_custom_rom:-0}
hide_ksu_loop=${hide_ksu_loop:-0}
fake_cmdline=${fake_cmdline:-0}
fake_cmdline_value=${fake_cmdline_value:-}
force_kmi=${force_kmi:-}
hide_gapps=${hide_gapps:-0}
hide_dex2oat=${hide_dex2oat:-0}
hide_scene=${hide_scene:-0}
auto_try_umount=${auto_try_umount:-0}
skip_detection_paths=${skip_detection_paths:-1}
skip_legit_mounts=${skip_legit_mounts:-1}
hide_vendor_sepolicy=${hide_vendor_sepolicy:-0}
vold_isolation=${vold_isolation:-0}
# 只允许 KMI 名称字符，防止路径穿越
case "$force_kmi" in *[!A-Za-z0-9._-]*) force_kmi="" ;; esac
spoof_uname=${spoof_uname:-0}
spoof_uname_release=${spoof_uname_release:-}
spoof_uname_version=${spoof_uname_version:-}


# 早期版本曾在 /data/local/tmp 建探测目录；这里只提示，不删除模块目录以外的路径
for _j in /data/local/tmp/.susfs_probe_dir /data/local/tmp/.susfs_cap_probe /data/local/tmp/.diag_probe; do
    [ -e "$_j" ] && echo "[i] 发现旧版遗留目录，可手动删除：$_j"
done

# 1. 确保 LKM
if ! lkm_present; then
    if [ "$AUTOLOAD" = "1" ]; then
        # 上次自动加载后没能完成启动（marker 还在），本次暂停
        if autoload_paused || [ -f "$(boot_guard_path)" ]; then
            pause_autoload
            echo "[!] 上次加载后未能完成启动，本次暂停自动加载"
            echo "[i] 请先确认 KMI 选对：WebUI 配置页的「强制指定 KMI」，或执行 ctl.sh kmiinfo 查看"
            echo "[i] 确认后点「加载并应用」（手动路径不受暂停限制），或执行 ctl.sh resume_autoload"
            set_description "⚠️ 自动加载已暂停（上次启动未完成），请检查 KMI 后手动加载"
            exit 1
        fi
    fi
    echo "[i] LKM 未加载，先加载"
    if [ "$AUTOLOAD" = "1" ]; then
        # 自动路径：先落守卫标记，加载后若没能完成启动，下次会自动暂停
        mark_boot_guard "$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
        sh "$MODDIR/load.sh" auto
    else
        sh "$MODDIR/load.sh" manual
    fi
    rc=$?
    if [ "$rc" != "0" ]; then
        echo "[!] 加载失败，无法应用规则"
        set_description "❌ LKM 加载失败，请查看日志"
        exit 1
    fi
fi

# 2. 选择可用的 ksu_susfs：优先当前管理器/分支自带，失败回退模块备份
BIN=$(select_susfs_bin) || { echo "[!] 缺少 ksu_susfs"; set_description "❌ ksu_susfs 缺失"; exit 1; }
echo "[i] ksu_susfs: $BIN"
VARIANT=$("$BIN" show variant 2>/dev/null)
if [ -z "$VARIANT" ] && ! susfs_bin_runnable "$BIN"; then
    echo "[!] 当前 ksu_susfs 无法执行（可能是架构不符或文件损坏）: $BIN"
    echo "[i] 建议重装管理器，或让模块改用内置备份（apply 会自动回退）"
fi
if [ -z "$VARIANT" ] && [ -x "$MODDIR/bin/ksu_susfs_good" ] && [ "$BIN" != "$MODDIR/bin/ksu_susfs_good" ]; then
    echo "[i] 当前 ksu_susfs 无法通信，切换到模块备份"
    BIN="$MODDIR/bin/ksu_susfs_good"
    VARIANT=$("$BIN" show variant 2>/dev/null)
fi
[ -n "$VARIANT" ] || { echo "[!] ksu_susfs 无法与内核通信"; set_description "❌ ksu_susfs 无法通信"; exit 1; }
VERSION=$("$BIN" show version 2>/dev/null)
FEATURES=$("$BIN" show enabled_features 2>/dev/null)
has_feature() { printf "%s\n" "$FEATURES" | grep -qx "$1"; }
# 用真实内核选 KMI：osrelease 可能被本模块的 uname 伪装改写
REL=$(real_kernel_release 2>/dev/null)
[ -n "$REL" ] || REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
. "$MODDIR/kmi.sh"
KMI=$(select_kmi "$REL" "$MODDIR" 2>/dev/null)
[ -n "$force_kmi" ] && [ -s "$MODDIR/lib/susfs_guard_lkm-$force_kmi.ko" ] && KMI="$force_kmi"
KMI=${KMI:-unknown}

# 3. sus_path 依赖 sdcard 根路径，先等待 /sdcard/Android/data
count=0
until [ -d /sdcard/Android/data ] || [ "$count" -ge 15 ]; do
    sleep 1
    count=$((count + 1))
done
if [ -d /sdcard/Android/data ]; then
    # 部分内核不支持这两个命令（需要 susfs v1.5.8+），按返回码如实记录
    _sd_out=$("$BIN" set_sdcard_root_path /sdcard 2>&1); _sd_rc=$?
    _ad_out=$("$BIN" set_android_data_root_path /sdcard/Android/data 2>&1); _ad_rc=$?
    if [ "$_sd_rc" = "0" ] && [ "$_ad_rc" = "0" ]; then
        echo "[i] sdcard 根路径已设置"
    else
        echo "[i] 内核不支持 sdcard 根路径设置（需 susfs v1.5.8+），跳过"
    fi
else
    echo "[!] /sdcard/Android/data 15 秒内未出现，sus_path 可能不生效"
fi

# 4. 特性开关
# 部分 LKM 不在 enabled_features 里上报这两项，但 /proc 节点与超调用是存在的，
# 所以判定用「特性位 or /proc 节点」，避免默认开启的项被静默跳过。
# 部分 LKM 不在 enabled_features 里上报这两项，但 /proc 节点与超调用可用；
# 判定用「特性位 or /proc 节点」，失败则本次开机内标记不可用，避免每轮刷同一错误。
if [ "$hide_sus_mnts" = "1" ]; then
    if has_feature CONFIG_KSU_SUSFS_HIDE_SUS_MNTS || [ -e /proc/susfs_hide_mounts ]; then
        if [ -f "$STATE/hide_sus_unsupported" ]; then
            echo "[i] hide_sus_mnts 已标记不可用，跳过（重新加载 LKM 后会自动重试）"
        elif "$BIN" hide_sus_mnts_for_non_su_procs 1 >/dev/null 2>&1; then
            echo "[i] hide_sus_mnts_for_non_su_procs=1"
        else
            echo "[!] hide_sus_mnts 设置失败，本次开机内不再重试"
            : > "$STATE/hide_sus_unsupported" 2>/dev/null
        fi
    else
        echo "[i] 内核未提供 hide_sus_mnts 接口（无特性位、无 /proc/susfs_hide_mounts），跳过"
    fi
fi
if has_feature CONFIG_KSU_SUSFS_AVC_LOG_SPOOFING || [ -e /proc/susfs_avc_spoof ]; then
    if [ -f "$STATE/avc_unsupported" ]; then
        echo "[i] avc_log_spoofing 已标记不可用，跳过（重新加载 LKM 后会自动重试）"
    elif [ "$avc_spoof" = "1" ]; then
        if "$BIN" enable_avc_log_spoofing 1 >/dev/null 2>&1; then
            echo "[i] avc_log_spoofing=1"
        else
            echo "[!] avc_log_spoofing 设置失败，本次开机内不再重试"
            : > "$STATE/avc_unsupported" 2>/dev/null
        fi
    else
        "$BIN" enable_avc_log_spoofing 0 >/dev/null 2>&1
    fi
else
    echo "[i] 内核未提供 avc_log_spoofing 接口（无特性位、无 /proc/susfs_avc_spoof），跳过"
fi

# 读取配置文件的第一个字段，忽略注释和空行
# 清洗单行：去 \r、去注释、去首尾空白
clean_entry() {
    _v=$(printf '%s' "$1" | tr -d '\r')
    _v=${_v%%#*}
    _v=$(printf '%s' "$_v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    printf '%s' "$_v"
}

# 5. sus_path
# replace_rules=1：只移除本模块上次写入的规则（不影响其他隐藏模块）
# replace_rules=2：整表清空（显式高危，会连同其他模块的规则一起清掉）
case "$replace_rules" in
    1)
        if [ -s "$(our_paths_file)" ]; then
            clear_own_paths
        else
            clear_migrated_paths "$CONFIG/sus_path.txt"
        fi
        ;;
    2) clear_all_paths && echo "[!] 已清空全部 sus_path 规则（replace_rules=2）" ;;
esac
if [ -f "$CONFIG/sus_path.txt" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        case "$path" in
            /*) ;;
            *) echo "[!] 忽略非绝对路径: $path"; continue ;;
        esac
        # 检测类应用自身的数据目录默认不隐藏（隐藏它们会让检测工具判定异常）
        if [ "${skip_detection_paths:-1}" = "1" ] && is_detection_app_path "$path"; then
            echo "[i] 跳过检测类应用数据目录: $path"
            continue
        fi
        if grep -F -q "path=$path " /proc/susfs_path 2>/dev/null; then
            echo "[=] sus_path $path (已存在)"
        elif "$BIN" add_sus_path "$path" >/dev/null 2>&1; then
            record_our_path "$path"
            echo "[+] sus_path $path"
        else
            echo "[=] sus_path $path (失败)"
        fi
    done < "$CONFIG/sus_path.txt"
fi

# 5b. 扩展隐藏开关（只隐藏实际存在的路径，默认全关）
add_sus_path_safe() {
    _p=$1
    [ -n "$_p" ] || return 0
    if grep -F -q "path=$_p " /proc/susfs_path 2>/dev/null; then
        echo "[=] sus_path $_p (已存在)"
    elif "$BIN" add_sus_path "$_p" >/dev/null 2>&1; then
        record_our_path "$_p"
        echo "[+] sus_path $_p"
    else
        echo "[=] sus_path $_p (失败)"
    fi
}

if [ "$hide_compat_matrix" = "1" ]; then
    _n=0
    for _p in /system/etc/compat_matrix* /system_ext/etc/compat_matrix* /product/etc/compat_matrix* /vendor/etc/compat_matrix*; do
        [ -e "$_p" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_p"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现 compat_matrix，跳过"
fi

if [ "$hide_revanced" = "1" ]; then
    _n=0
    for _d in /data/adb/modules/*revanced* /data/adb/modules/*youtube* /data/adb/modules/*microg* /data/adb/ksu/modules/*revanced* /data/adb/ksu/modules/*youtube*; do
        [ -d "$_d" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_d"
        [ -d "$_d/system" ] && add_sus_path_safe "$_d/system"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现 revanced / youtube / microg 模块，跳过"
fi

if [ "$hide_custom_rom" = "1" ]; then
    _n=0
    for _p in /system/addon.d /system/etc/lineage /product/etc/lineage /system/etc/evolution /product/etc/evolution /system/etc/pixel /system/etc/derpfest /product/etc/derpfest; do
        [ -e "$_p" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_p"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现自定义 ROM 痕迹，跳过（官方系统属正常）"
fi

if [ "$hide_ksu_loop" = "1" ]; then
    _loops=$(grep -E "^/dev/block/loop[0-9]+ /data/adb" /proc/mounts 2>/dev/null | cut -d" " -f2 | sort -u)
    if [ -z "$_loops" ]; then
        echo "[i] 未发现 /data/adb 下的 loop 挂载，跳过 KSU LOOP 隐藏"
    else
        while IFS= read -r _m; do
            [ -n "$_m" ] || continue
            add_sus_path_safe "$_m"
        done <<EOFL
$_loops
EOFL
    fi
fi

if [ "$fake_cmdline" = "1" ] && [ -n "$fake_cmdline_value" ]; then
    if has_feature CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG; then
        _cf="$STATE/fake_cmdline.txt"
        mkdir -p "$STATE" 2>/dev/null
        printf "%s\n" "$fake_cmdline_value" > "$_cf"
        if "$BIN" set_cmdline_or_bootconfig "$_cf" >/dev/null 2>&1; then
            echo "[i] cmdline 伪装已生效: $fake_cmdline_value"
        else
            echo "[!] cmdline 伪装设置失败（内核已启用该特性，请查内核日志）"
        fi
    else
        echo "[i] 内核未启用 SPOOF_CMDLINE_OR_BOOTCONFIG，跳过 cmdline 伪装"
    fi
fi

# 6. sus_mount
if [ -f "$CONFIG/sus_mount.txt" ]; then
    _sm_ok=0; _sm_bad=0
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        case "$path" in
            /*) ;;
            *) echo "[!] 忽略非绝对路径: $path"; continue ;;
        esac
        sus_mount_add_once "$path"
        case $? in
            0) _sm_ok=$((_sm_ok + 1)); echo "[+] sus_mount $path" ;;
            2) echo "[=] sus_mount $path (本次开机已添加，跳过)" ;;
            *) _sm_bad=$((_sm_bad + 1)); echo "[=] sus_mount $path (失败)" ;;
        esac
    done < "$CONFIG/sus_mount.txt"
    if [ "$_sm_ok" = "0" ] && [ "$_sm_bad" -gt 0 ]; then
        echo "[!] add_sus_mount 实测不可用，标记为不支持"
        caps_downgrade sus_mount
    fi
fi

# 7. try_umount
if [ -f "$CONFIG/try_umount.txt" ]; then
    if ! cap_ok try_umount; then
        echo "[i] 本内核未实现 try_umount 命令，跳过"
    else
    _tu_ok=0; _tu_bad=0
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        case "$path" in
            /*) ;;
            *) echo "[!] 忽略非绝对路径: $path"; continue ;;
        esac
        try_umount_add_once "$path"
        case $? in
            0) _tu_ok=$((_tu_ok + 1)); echo "[+] try_umount $path" ;;
            2) echo "[=] try_umount $path (本次开机已添加，跳过)" ;;
            *) _tu_bad=$((_tu_bad + 1)); echo "[=] try_umount $path (失败)" ;;
        esac
        done < "$CONFIG/try_umount.txt"
        if [ "$_tu_ok" = "0" ] && [ "$_tu_bad" -gt 0 ]; then
            echo "[!] add_try_umount 实测不可用，标记为不支持"
            caps_downgrade try_umount
        fi
    fi
fi

# 8. hide_modules（统一走 common.sh 的助手）
apply_hide_modules

# 8b. 伪装 uname（只影响用户态看到的内核版本）
# 伪装前先记下真实内核，出问题时可用 ctl.sh restore_uname 还原
save_real_uname
if has_feature CONFIG_KSU_SUSFS_SPOOF_UNAME; then
    if [ "$spoof_uname" = "1" ]; then
        _r=${spoof_uname_release:-default}
        _v=${spoof_uname_version:-default}
        if "$BIN" set_uname "$_r" "$_v" >/dev/null 2>&1; then
            echo "[i] uname 伪装已生效: $_r / $_v"
        else
            echo "[!] uname 伪装设置失败"
        fi
    else
        if "$BIN" set_uname default default >/dev/null 2>&1; then
            echo "[i] uname 伪装已还原"
            save_real_uname force
        fi
    fi
else
    echo "[i] 内核未启用 SPOOF_UNAME，跳过"
fi

# 5c. 仅解锁 BL 可用的隐藏项（临时 root 下早期阶段已过，做了也无效）
if [ "$hide_vendor_sepolicy" = "1" ] || [ "$vold_isolation" = "1" ]; then
    if [ "$(cfg_force_bl)" = "1" ] && [ "$(bootloader_state)" != "unlocked" ]; then
        echo "[!] 已手动确认 BL 已解锁（配置覆盖），实际属性: $(bootloader_state)"
    fi
    if bl_unlocked; then
        if [ "$hide_vendor_sepolicy" = "1" ]; then
            _n=0
            for _p in /vendor/etc/selinux/vendor_sepolicy.cil /vendor/etc/selinux/plat_sepolicy.cil /vendor/etc/selinux/precompiled_sepolicy /system/etc/selinux/plat_sepolicy.cil; do
                [ -e "$_p" ] || continue
                _n=$((_n + 1))
                add_sus_path_safe "$_p"
            done
            [ "$_n" = "0" ] && echo "[i] 未发现 sepolicy 文件，跳过"
        fi
        if [ "$vold_isolation" = "1" ]; then
            _n=0
            for _p in /sdcard/Android/data /sdcard/Android/obb /data/media/0/Android/data /data/media/0/Android/obb; do
                [ -e "$_p" ] || continue
                _n=$((_n + 1))
                add_sus_path_safe "$_p"
            done
            [ "$_n" = "0" ] && echo "[i] 未发现 Android/data 目录，跳过"
        fi
    else
        echo "[i] 未解锁 BL（BL=$(bootloader_state)）：sepolicy / VOLD 隔离在临时 root 下无效，跳过"
    fi
fi

# 5d. GAPPS / DEX2OAT 隐藏
if [ "$hide_gapps" = "1" ]; then
    _n=0
    for _p in /system/app/GmsCore /system/priv-app/GmsCore /product/app/GmsCore               /product/priv-app/GmsCore /system/app/GoogleServicesFramework               /system/priv-app/GoogleServicesFramework /system/app/Phonesky               /product/app/Phonesky /system/app/Vending /product/app/Vending; do
        [ -e "$_p" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_p"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现 GAPPS 路径，跳过（国行系统属正常）"
fi

if [ "$hide_dex2oat" = "1" ]; then
    if ! cap_ok sus_mount; then
        echo "[i] 本内核未实现挂载命令（add_sus_mount 不可用），跳过 DEX2OAT 隐藏"
    else
    _n=0; _ok=0; _bad=0
    for _m in $(grep -E " (/(system|apex|product)/[^ ]*/oat|/data/dalvik-cache)" /proc/mounts 2>/dev/null | cut -d" " -f2 | sort -u); do
        [ -d "$_m" ] || continue
        _n=$((_n + 1))
        sus_mount_add_once "$_m"
        case $? in
            0) _ok=$((_ok + 1)); echo "[+] sus_mount $_m (dex2oat)" ;;
            2) echo "[=] sus_mount $_m (本次开机已添加，跳过)" ;;
            *) _bad=$((_bad + 1)); echo "[=] sus_mount $_m (失败)" ;;
        esac
    done
        [ "$_n" = "0" ] && echo "[i] 未发现 dex2oat 挂载，跳过"
        # 全部失败说明命令实际不可用（特性位谎报），降级后不再尝试
        if [ "$_ok" = "0" ] && [ "$_bad" -gt 0 ]; then
            echo "[!] add_sus_mount 实测不可用，标记为不支持"
            caps_downgrade sus_mount
        fi
    fi
fi

# 5e. Scene 痕迹（/dev 下随机命名的目录，内含 scene_mode_category）
if [ "$hide_scene" = "1" ]; then
    # Scene 的目录名每次开机都变，创建时机也可能晚于本脚本，所以分几轮扫描
    _tries=0
    _n=0
    while [ "$_tries" -lt 3 ]; do
        for _f in /dev/*/scene_mode_category; do
            [ -e "$_f" ] || continue
            _d=${_f%/scene_mode_category}
            _n=$((_n + 1))
            add_sus_path_safe "$_d"
            add_sus_path_safe "$_f"
        done
        [ "$_n" -gt 0 ] && break
        _tries=$((_tries + 1))
        [ "$_tries" -lt 3 ] && sleep 5
    done
    if [ "$_n" = "0" ]; then
        echo "[i] 未发现 scene 痕迹，跳过（可稍后在 WebUI 点「重扫 Scene」）"
    fi
fi


# 5f. 自动 try_umount：识别 KernelSU 模块挂载（overlay 源为 KSU，或 bind 自 /data/adb）
# 开启后始终过滤真实分区（erofs/ext4/f2fs/squashfs/vfat 且根为 /），避免误卸系统分区；
# 登记结果写入 state/try_umount_auto.txt，便于排查与回滚。
if [ "$auto_try_umount" = "1" ]; then
    if ! cap_ok try_umount; then
        echo "[i] 本内核未实现 try_umount 命令，跳过自动 try_umount"
    else
        [ "$skip_legit_mounts" = "0" ] && echo "[i] 已强制过滤真实分区（该保护不可关闭）"
        _n=0; _ok=0; _bad=0
        _list="$STATE/try_umount_auto.txt"
        : > "$_list" 2>/dev/null
        while read -r _id _parent _dev _root _mp _rest; do
            [ -n "$_mp" ] || continue
            _fs=$(printf '%s' "$_rest" | awk '{for(i=1;i<=NF;i++) if($i=="-"){print $(i+1); exit}}')
            _src=$(printf '%s' "$_rest" | awk '{for(i=1;i<=NF;i++) if($i=="-"){print $(i+2); exit}}')
            _hit=0
            case "$_src" in KSU|shared) _hit=1 ;; esac
            case "$_root" in *"/adb/"*) _hit=1 ;; esac
            case "$_mp" in /data/adb|/data/adb/*) _hit=1 ;; esac
            [ "$_hit" = "1" ] || continue
            # 真实分区一律跳过（不可通过配置关闭）
            is_legit_partition_mount "$_fs" "$_root" && continue
            [ -e "$_mp" ] || continue
            _n=$((_n + 1))
            try_umount_add_once "$_mp"
            _tu_rc=$?
            if [ "$_tu_rc" = "2" ]; then
                echo "[=] try_umount $_mp (本次开机已添加，跳过)"
            elif [ "$_tu_rc" = "0" ]; then
                _ok=$((_ok + 1))
                printf '%s\n' "$_mp" >> "$_list" 2>/dev/null
                echo "[+] try_umount $_mp (auto)"
            else
                _bad=$((_bad + 1))
                echo "[=] try_umount $_mp (auto, 失败)"
            fi
        done < /proc/1/mountinfo
        # 全部失败说明命令实际不可用，标记为不支持，避免下次重复刷失败日志
        if [ "${_ok:-0}" -eq 0 ] && [ "${_bad:-0}" -gt 0 ]; then
            echo "[!] try_umount 实际不可用（全部失败），标记为不支持"
            caps_downgrade try_umount
        fi
        [ "$_n" = "0" ] && echo "[i] 未发现模块挂载，跳过自动 try_umount"
    fi
fi

backup_config

# 9. WebUI 兼容标记 + 统计
touch_marker

RULES=$(grep '^path=' /proc/susfs_path 2>/dev/null | grep -v '\[ours:' | sed 's/^path=//' | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
RULES=${RULES:-0}
echo "[i] 当前用户 sus_path 唯一规则数: $RULES"
set_description "✅ 运行中 | $RULES 条规则 | $KMI | ${VERSION:-unknown}"
echo "=== apply ok ==="
exit 0