#!/system/bin/sh
# 只负责按当前内核匹配并加载 SUSFS LKM，不应用规则。
# 兼容 KernelSU 官方版及 SukiSU / ReSukiSU / KernelSU Next 等分支。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"
STATE=$MODDIR/state
LOG=$MODDIR/load.log
mkdir -p "$STATE" 2>/dev/null

# 日志追加写（保留冷启动历史），超过 64KB 时只留最近 200 行
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null)" -gt 65536 ]; then
    tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi
exec >>"$LOG" 2>&1
echo "=== SUSFS 管理器 load $(date '+%F %T') ==="
echo "[i] root: $(root_family)"

set_description() {
    prop="$MODDIR/module.prop"
    [ -f "$prop" ] || return 0
    sed -i "s#^description=.*#description=$1#" "$prop" 2>/dev/null
}

note_fail() {
    n=$(cat "$STATE/fail_count" 2>/dev/null)
    n=${n:-0}
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    n=$((n + 1))
    echo "$n" > "$STATE/fail_count"
}

fail() {
    echo "[!] $1"
    set_description "❌ $1"
    note_fail
    exit 1
}

[ -f "$MODDIR/disable" ] && { echo "模块已禁用"; exit 0; }
[ -f "$MODDIR/remove" ] && { echo "模块待移除"; exit 0; }
if [ -f "$MODDIR/disable_autoload" ] && [ "$1" != "manual" ]; then
    echo "自动加载已关闭"
    exit 0
fi
[ "$(getprop persist.sys.safemode)" = "1" ] && { echo "safe mode"; exit 0; }
[ "$(getprop ro.sys.safemode)" = "1" ] && { echo "safe mode"; exit 0; }

# 没有活动二进制时，把模块备份放进当前管理器的 bin 目录；
# 已有分支自带的 ksu_susfs 时保持不动。
BIN=$(ensure_susfs_bin)
echo "[i] ksu_susfs: ${BIN:-无}"

# 已经加载过就不再叠加
if lkm_present; then
    rm -f "$STATE/loading"
    echo "[i] susfs 已存在，跳过加载"
    BIN=$(select_susfs_bin) || fail "ksu_susfs 缺失且没有备份"
    echo "[i] 使用: $BIN"
    VERSION=$("$BIN" show version 2>/dev/null)
    [ -n "$VERSION" ] || fail "SUSFS 已存在，但 ksu_susfs 无法通信"
    echo 0 > "$STATE/fail_count"
    apply_hide_modules
    set_description "✅ LKM 已加载 | ${VERSION} | 等待应用规则"
    echo "=== load ok ==="
    exit 0
fi

REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
[ -n "$REL" ] || fail "无法读取内核版本"
. "$MODDIR/kmi.sh"
KMI=$(select_kmi "$REL" "$MODDIR") || fail "没有匹配 $REL 的 LKM"
KO="$MODDIR/lib/susfs_guard_lkm-$KMI.ko"
[ -s "$KO" ] || fail "缺少 $KMI 的 LKM 文件"
echo "[i] 内核: $REL"
echo "[i] 匹配: $KMI"
echo "[i] 加载: $KO"
: > "$STATE/loading"
if command -v timeout >/dev/null 2>&1; then
    timeout 20 "$MODDIR/bin/susfs_insmod" "$KO" expose_proc=1
else
    "$MODDIR/bin/susfs_insmod" "$KO" expose_proc=1
fi
rc=$?
rm -f "$STATE/loading"
if [ "$rc" != "0" ]; then
    fail "susfs_insmod 失败 (rc=$rc)"
fi

BIN=$(select_susfs_bin) || fail "ksu_susfs 缺失且没有备份"
echo "[i] 使用: $BIN"
VARIANT=$("$BIN" show variant 2>/dev/null)
if [ -z "$VARIANT" ] && [ -x "$MODDIR/bin/ksu_susfs_good" ] && [ "$BIN" != "$MODDIR/bin/ksu_susfs_good" ]; then
    echo "[i] 当前 ksu_susfs 无法通信，切换到模块备份"
    BIN="$MODDIR/bin/ksu_susfs_good"
    VARIANT=$("$BIN" show variant 2>/dev/null)
fi
[ -n "$VARIANT" ] || fail "LKM 已加载但 ksu_susfs 无法通信"
VERSION=$("$BIN" show version 2>/dev/null)
echo "[i] variant: $VARIANT"
echo "[i] version: $VERSION"
echo 0 > "$STATE/fail_count"
set_description "✅ LKM 已加载 | $KMI | ${VERSION:-unknown}"
echo "=== load ok ==="
exit 0
