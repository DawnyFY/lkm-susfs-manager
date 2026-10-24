#!/system/bin/sh
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
[ -f "$STATE/loading" ] && { echo "[!] 上次 LKM 加载未完成（state/loading 残留），跳过规则应用"; exit 0; }

[ -f "$CONFIG/config.sh" ] && . "$CONFIG/config.sh"
hide_sus_mnts=${hide_sus_mnts:-1}
avc_spoof=${avc_spoof:-0}
replace_rules=${replace_rules:-1}
hide_compat_matrix=${hide_compat_matrix:-0}
hide_revanced=${hide_revanced:-0}
hide_custom_rom=${hide_custom_rom:-0}
hide_ksu_loop=${hide_ksu_loop:-0}
fake_cmdline=${fake_cmdline:-0}
fake_cmdline_value=${fake_cmdline_value:-}
force_kmi=${force_kmi:-}
# 只允许 KMI 名称字符，防止路径穿越
case "$force_kmi" in *[!A-Za-z0-9._-]*) force_kmi="" ;; esac
spoof_uname=${spoof_uname:-0}
spoof_uname_release=${spoof_uname_release:-}
spoof_uname_version=${spoof_uname_version:-}

# 1. 确保 LKM
if ! lkm_present; then
    echo "[i] LKM 未加载，先加载"
    sh "$MODDIR/load.sh" manual
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
if [ -z "$VARIANT" ] && [ -x "$MODDIR/bin/ksu_susfs_good" ] && [ "$BIN" != "$MODDIR/bin/ksu_susfs_good" ]; then
    echo "[i] 当前 ksu_susfs 无法通信，切换到模块备份"
    BIN="$MODDIR/bin/ksu_susfs_good"
    VARIANT=$("$BIN" show variant 2>/dev/null)
fi
[ -n "$VARIANT" ] || { echo "[!] ksu_susfs 无法与内核通信"; set_description "❌ ksu_susfs 无法通信"; exit 1; }
VERSION=$("$BIN" show version 2>/dev/null)
FEATURES=$("$BIN" show enabled_features 2>/dev/null)
has_feature() { printf "%s\n" "$FEATURES" | grep -qx "$1"; }
REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
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
if [ "$hide_sus_mnts" = "1" ]; then
    if has_feature CONFIG_KSU_SUSFS_HIDE_SUS_MNTS; then
        "$BIN" hide_sus_mnts_for_non_su_procs 1 >/dev/null 2>&1 \
            && echo "[i] hide_sus_mnts_for_non_su_procs=1"
    else
        echo "[i] 内核未启用 HIDE_SUS_MNTS，跳过（当前 LKM 不支持）"
    fi
fi
if has_feature CONFIG_KSU_SUSFS_AVC_LOG_SPOOFING; then
    if [ "$avc_spoof" = "1" ]; then
        "$BIN" enable_avc_log_spoofing 1 >/dev/null 2>&1 \
            && echo "[i] avc_log_spoofing=1"
    else
        "$BIN" enable_avc_log_spoofing 0 >/dev/null 2>&1
    fi
else
    echo "[i] 内核未启用 AVC_LOG_SPOOFING，跳过（当前 LKM 不支持）"
fi

# 读取配置文件的第一个字段，忽略注释和空行
read_entries() {
    file=$1
    [ -f "$file" ] || return 0
    while IFS= read -r line; do
        line=$(printf '%s\n' "$line" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$line" ] || continue
        printf '%s\n' "$line" | awk '{print $1}'
    done < "$file"
}

# 清洗单行：去 \r、去注释、去首尾空白
clean_entry() {
    _v=$(printf '%s' "$1" | tr -d '\r')
    _v=${_v%%#*}
    _v=$(printf '%s' "$_v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    printf '%s' "$_v"
}

# 5. sus_path（可选：先清空普通规则，让删除立即生效）
if [ "$replace_rules" = "1" ] && [ -e /proc/susfs_path ]; then
    if echo clear > /proc/susfs_path 2>/dev/null; then
        echo "[i] 已清空旧 sus_path 规则"
    else
        echo "[!] 清空旧 sus_path 规则失败，继续追加"
    fi
fi
if [ -f "$CONFIG/sus_path.txt" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        if grep -F -q "path=$path " /proc/susfs_path 2>/dev/null; then
            echo "[=] sus_path $path (已存在)"
        elif "$BIN" add_sus_path "$path" >/dev/null 2>&1; then
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
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        "$BIN" add_sus_mount "$path" >/dev/null 2>&1 \
            && echo "[+] sus_mount $path" || echo "[=] sus_mount $path (失败)"
    done < "$CONFIG/sus_mount.txt"
fi

# 7. try_umount
if [ -f "$CONFIG/try_umount.txt" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        "$BIN" add_try_umount "$path" 1 >/dev/null 2>&1 \
            && echo "[+] try_umount $path" || echo "[=] try_umount $path (失败)"
    done < "$CONFIG/try_umount.txt"
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

# 9. WebUI 兼容标记 + 统计
touch_marker

RULES=$(grep '^path=' /proc/susfs_path 2>/dev/null | grep -v '\[ours:' | sed 's/^path=//' | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
RULES=${RULES:-0}
echo "[i] 当前用户 sus_path 唯一规则数: $RULES"
set_description "✅ 运行中 | $RULES 条规则 | $KMI | ${VERSION:-unknown}"
echo "=== apply ok ==="
exit 0
