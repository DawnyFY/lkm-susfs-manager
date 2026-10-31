#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
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

# 尽早记录真实内核：此处一定还没被本模块伪装过
save_real_uname

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
    # 走到这里说明是确定性失败（KMI 不匹配 / 缺文件 / insmod 报错），
    # 系统本身能正常开机，不应留下守卫把下次自动加载永久暂停
    clear_boot_guard
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

# 互斥：开机与手动可能同时触发 load
if ! lock_acquire "$STATE/load.lock" 300; then
    echo "[!] 另一个 load 正在运行，跳过本次"
    exit 0
fi
trap 'lock_release "$STATE/load.lock"' EXIT

# 选择可用的 ksu_susfs：优先管理器自带的，缺失时用模块内置备份（不写盘）
BIN=$(ensure_susfs_bin)

# 管理器自带的二进制可能架构不符/损坏：本次改用模块备份运行，不改写管理器文件。
if [ -n "$BIN" ] && [ -x "$BIN" ] && ! susfs_bin_runnable "$BIN"; then
    _bak="$MODDIR/bin/ksu_susfs_good"
    if [ -x "$_bak" ] && susfs_bin_runnable "$_bak"; then
        echo "[!] $BIN 无法执行（架构 $(elf_machine "$BIN")），本次改用模块备份运行"
        echo "[i] 模块备份架构: $(elf_machine "$_bak")；不修改管理器目录下的文件"
        BIN="$_bak"
    fi
fi
echo "[i] ksu_susfs: ${BIN:-无}"

# 自动路径：若上次加载后未能完成启动，本次不再尝试
if autoload_paused && [ "$1" != "manual" ]; then
    echo "[!] 自动加载已暂停（守卫标记存在），跳过本次加载"
    set_description "⚠️ 自动加载已暂停，请在 WebUI 恢复"
    exit 0
fi

# 已经加载过就不再叠加
if lkm_present; then
    rm -f "$STATE/loading"
    echo "[i] susfs 已存在，跳过加载"
    BIN=$(select_susfs_bin) || fail "ksu_susfs 缺失且没有备份"
    echo "[i] 使用: $BIN"
    VERSION=$("$BIN" show version 2>/dev/null)
    if [ -z "$VERSION" ]; then
        # 管理器自带的二进制可能与内核 susfs ABI 不匹配，先试模块备份
        _bak="$MODDIR/bin/ksu_susfs_good"
        if [ -x "$_bak" ] && [ "$BIN" != "$_bak" ]; then
            _bv=$("$_bak" show version 2>/dev/null)
            if [ -n "$_bv" ]; then
                BIN="$_bak"
                VERSION="$_bv"
                echo "[i] 当前 ksu_susfs 无法通信，改用模块备份: $BIN"
            fi
        fi
    fi
    if [ -z "$VERSION" ]; then
        # LKM 已加载但工具通信失败：属环境/版本问题，不当作加载失败
        echo "[!] ksu_susfs 无法通信（可能与内核 ABI 不匹配），规则由 apply 用备份尝试"
        set_description "⚠️ LKM 已加载，但 ksu_susfs 无法通信"
        echo 0 > "$STATE/fail_count"
        echo "=== load skip-tooling ==="
        exit 0
    fi
    echo 0 > "$STATE/fail_count"
    apply_hide_modules
    set_description "✅ LKM 已加载 | ${VERSION} | 等待应用规则"
    echo "=== load ok ==="
    exit 0
fi

restore_config_if_missing

# 用真实内核选 KMI：/proc/sys/kernel/osrelease 可能被本模块的 uname 伪装改写，
# 直接拿它匹配会在伪装开启时选错 .ko（例如 6.12 内核选成 android15-6.6）。
REL=$(real_kernel_release 2>/dev/null)
[ -n "$REL" ] || REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
[ -n "$REL" ] || fail "无法读取内核版本"
if kernel_release_spoofed; then
    echo "[!] 检测到内核版本伪装：osrelease=$(cat /proc/sys/kernel/osrelease 2>/dev/null) 真实=$REL"
    echo "[i] 按真实内核选择 KMI，避免加载不匹配的 LKM"
fi
. "$MODDIR/kmi.sh"
cfg_ensure
cfg_load
# 配置不能改变这些路径（防御任意脚本/二进制加载）
MODDIR=/data/adb/modules/susfs_allinone
CONFIG=$MODDIR/config
STATE=$MODDIR/state
force_kmi=${force_kmi:-}
# 只允许 KMI 名称字符，防止路径穿越
case "$force_kmi" in *[!A-Za-z0-9._-]*) force_kmi="" ;; esac
KMI=$(select_kmi "$REL" "$MODDIR" 2>/dev/null)
if [ -n "$force_kmi" ] && [ -s "$MODDIR/lib/susfs_guard_lkm-$force_kmi.ko" ]; then
    echo "[!] 使用强制指定的 KMI: $force_kmi"
    KMI="$force_kmi"
fi
if [ -z "$KMI" ]; then
    echo "[!] 未能匹配内核: $REL"
    echo "[i] 已打包 KMI: $(list_kmis "$MODDIR" | tr '\n' ' ')"
    echo "[i] 版本号疑似: $(guess_kmis "$REL" "$MODDIR" | tr '\n' ' ')"
    echo "[i] 可在 WebUI 配置页强制指定 KMI 后再次加载"
    set_description "⚠️ 未匹配内核 | $REL | 请在 WebUI 指定 KMI"
    # 没有尝试加载，不属于"加载后未能启动"，不能留下守卫把下次自动加载暂停
    clear_boot_guard
    echo "=== load skip ==="
    exit 0
fi
KO="$MODDIR/lib/susfs_guard_lkm-$KMI.ko"
[ -s "$KO" ] || fail "缺少 $KMI 的 LKM 文件"
echo "[i] 内核: $REL"
echo "[i] 匹配: $KMI"
echo "[i] 加载: $KO"
: > "$STATE/loading"
# 捕获加载输出：内核拒绝时需要给出可执行的诊断提示
if command -v timeout >/dev/null 2>&1; then
    _ins_out=$(timeout 20 "$MODDIR/bin/susfs_insmod" "$KO" expose_proc=1 2>&1); rc=$?
else
    _ins_out=$("$MODDIR/bin/susfs_insmod" "$KO" expose_proc=1 2>&1); rc=$?
fi
printf '%s\n' "$_ins_out"
rm -f "$STATE/loading"
if [ "$rc" != "0" ]; then
    case "$_ins_out" in
        *"errno 1"*|*EPERM*)
            echo "[!] 内核拒绝加载模块（EPERM / Operation not permitted）"
            echo "    常见原因（按概率）:"
            echo "    1) /proc/sys/kernel/modules_disabled=1 —— 模块加载已被内核锁定"
            echo "    2) 内核启用了强制模块签名（CONFIG_MODULE_SIG_FORCE）"
            echo "    3) 内核 lockdown 处于 integrity/confidentiality"
            echo "    4) 管理器策略拒绝 finit_module"
            echo "[i] 可执行诊断:"
            echo "    cat /proc/sys/kernel/modules_disabled"
            echo "    cat /sys/kernel/security/lockdown 2>/dev/null"
            echo "    zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_MODULE_SIG|CONFIG_SECURITY_LOCKDOWN'"
            echo "[i] 若 modules_disabled=1，LKM 路线不可行，需要改用内核内置 SUSFS 的版本"
            ;;
    esac
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
# 本次是真实加载，清掉可能由"未加载时"的探测、旧 LKM 写下的能力缓存
rm -f "$STATE/caps" "$STATE/hide_sus_unsupported" "$STATE/avc_unsupported" 2>/dev/null
set_description "✅ LKM 已加载 | $KMI | ${VERSION:-unknown}"
echo "=== load ok ==="
exit 0