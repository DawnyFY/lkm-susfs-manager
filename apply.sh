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
    sed -i "s#^description=.*#description=$1#" "$prop" 2>/dev/null
}

[ -f "$MODDIR/disable" ] && { echo "模块已禁用"; exit 0; }
[ -f "$MODDIR/remove" ] && { echo "模块待移除"; exit 0; }
[ -f "$STATE/loading" ] && { echo "[!] 上次 LKM 加载未完成（state/loading 残留），跳过规则应用"; exit 0; }

[ -f "$CONFIG/config.sh" ] && . "$CONFIG/config.sh"
hide_sus_mnts=${hide_sus_mnts:-1}
avc_spoof=${avc_spoof:-0}
replace_rules=${replace_rules:-1}

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
REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
. "$MODDIR/kmi.sh"
KMI=$(select_kmi "$REL" "$MODDIR" 2>/dev/null) || KMI=unknown

# 3. sus_path 依赖 sdcard 根路径，先等待 /sdcard/Android/data
count=0
until [ -d /sdcard/Android/data ] || [ "$count" -ge 15 ]; do
    sleep 1
    count=$((count + 1))
done
if [ -d /sdcard/Android/data ]; then
    "$BIN" set_sdcard_root_path /sdcard
    "$BIN" set_android_data_root_path /sdcard/Android/data
    echo "[i] sdcard 根路径已设置"
else
    echo "[!] /sdcard/Android/data 15 秒内未出现，sus_path 可能不生效"
fi

# 4. 特性开关
if [ "$hide_sus_mnts" = "1" ]; then
    "$BIN" hide_sus_mnts_for_non_su_procs 1 >/dev/null 2>&1 \
        && echo "[i] hide_sus_mnts_for_non_su_procs=1"
fi
if [ "$avc_spoof" = "1" ]; then
    "$BIN" enable_avc_log_spoofing 1 >/dev/null 2>&1 \
        && echo "[i] avc_log_spoofing=1"
else
    "$BIN" enable_avc_log_spoofing 0 >/dev/null 2>&1
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

# 5. sus_path（可选：先清空普通规则，让删除立即生效）
if [ "$replace_rules" = "1" ] && [ -e /proc/susfs_path ]; then
    if echo clear > /proc/susfs_path 2>/dev/null; then
        echo "[i] 已清空旧 sus_path 规则"
    else
        echo "[!] 清空旧 sus_path 规则失败，继续追加"
    fi
fi
if [ -f "$CONFIG/sus_path.txt" ]; then
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if grep -F -q "path=$path " /proc/susfs_path 2>/dev/null; then
            echo "[=] sus_path $path (已存在)"
        elif "$BIN" add_sus_path "$path" >/dev/null 2>&1; then
            echo "[+] sus_path $path"
        else
            echo "[=] sus_path $path (失败)"
        fi
    done <<EOF
$(read_entries "$CONFIG/sus_path.txt")
EOF
fi

# 6. sus_mount
if [ -f "$CONFIG/sus_mount.txt" ]; then
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        "$BIN" add_sus_mount "$path" >/dev/null 2>&1 \
            && echo "[+] sus_mount $path" || echo "[=] sus_mount $path (失败)"
    done <<EOF
$(read_entries "$CONFIG/sus_mount.txt")
EOF
fi

# 7. try_umount
if [ -f "$CONFIG/try_umount.txt" ]; then
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        "$BIN" add_try_umount "$path" 1 >/dev/null 2>&1 \
            && echo "[+] try_umount $path" || echo "[=] try_umount $path (失败)"
    done <<EOF
$(read_entries "$CONFIG/try_umount.txt")
EOF
fi

# 8. hide_modules
if [ -f "$CONFIG/hide_modules.txt" ]; then
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if grep -qw "$name" /proc/susfs_hide_modules 2>/dev/null; then
            echo "[=] hide_module $name (已存在)"
        else
            echo "add $name" > /proc/susfs_hide_modules 2>/dev/null \
                && echo "[+] hide_module $name" || echo "[=] hide_module $name (失败)"
        fi
    done <<EOF
$(read_entries "$CONFIG/hide_modules.txt")
EOF
fi

# 9. WebUI 兼容标记 + 统计
touch_marker

RULES=$(grep '^path=' /proc/susfs_path 2>/dev/null | grep -v '\[ours:' | sed 's/^path=//' | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
RULES=${RULES:-0}
echo "[i] 当前用户 sus_path 唯一规则数: $RULES"
set_description "✅ 运行中 | $RULES 条规则 | $KMI | ${VERSION:-unknown}"
echo "=== apply ok ==="
exit 0
