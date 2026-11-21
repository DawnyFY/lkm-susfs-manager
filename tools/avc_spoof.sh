#!/system/bin/sh
# ============================================================================
# AVC 日志伪装开关（独立脚本，适用于 1.2.9 及更早版本）
#
# 背景：官方 KernelSU 的 ksu_susfs 没有 enable_avc_log_spoofing 命令，
#       所以 1.2.9 里把 avc_spoof=1 也不会生效（日志会提示「二进制没有该命令」）。
#       SUSFS LKM 本身暴露了内核参数 avc_su_ctx，直接写它就能开启，本脚本负责这件事。
#
# 用法（root shell）：
#   sh avc_spoof.sh                 # 开启（本次开机有效）
#   sh avc_spoof.sh off             # 关闭并还原
#   sh avc_spoof.sh status          # 只看当前状态
#   sh avc_spoof.sh install-boot    # 写入 /data/adb/service.d，每次开机自动开启
#   sh avc_spoof.sh remove-boot     # 删除上面的开机脚本
#
# 说明：
#   · 只改内核参数 /sys/module/susfs_guard_lkm/parameters/avc_su_ctx
#   · 不改模块文件、不改 config.ini（避免与模块的完整性校验冲突）
#   · 重启后参数会重置；需要长期生效请用 install-boot
# ============================================================================

PARAM=/sys/module/susfs_guard_lkm/parameters/avc_su_ctx
REAL_CTX="u:r:ksu:s0"
SPOOF_CTX="u:r:priv_app:s0:c512,c768"
BOOT_SCRIPT=/data/adb/service.d/avc_spoof.sh
MOD=/data/adb/modules/susfs_allinone

say() { printf '%s\n' "$*"; }
die() { say "[!] $*"; exit 1; }

[ "$(id -u 2>/dev/null)" = "0" ] || die "需要 root：请用 su -c 'sh $0 ...' 运行"

cur() { cat "$PARAM" 2>/dev/null; }

do_status() {
    if [ ! -e "$PARAM" ]; then
        say "[!] 找不到 $PARAM"
        say "    说明：当前 LKM 没有暴露 avc_su_ctx 参数（可能是老版本 SUSFS），无法用本方式开启"
        return 1
    fi
    _c=$(cur)
    say "参数：$PARAM"
    say "当前值：${_c:-（空）}"
    if [ "$_c" = "$SPOOF_CTX" ]; then
        say "状态：已开启伪装（AVC 日志里的 ksu 域会被改写成 priv_app）"
    elif [ "$_c" = "$REAL_CTX" ]; then
        say "状态：未开启（原始上下文）"
    else
        say "状态：未知值（可能是其它工具设定；关闭时会写回 $REAL_CTX）"
    fi
    if [ -x "$BOOT_SCRIPT" ]; then
        say "开机保持：已安装（$BOOT_SCRIPT）"
    else
        say "开机保持：未安装（重启后会恢复未开启）"
    fi
    return 0
}

do_on() {
    [ -e "$PARAM" ] || die "找不到 $PARAM：当前 LKM 未暴露该参数，无法开启"
    # 有新版 CLI 命令就优先用命令（更官方），否则写内核参数
    for c in "$MOD/bin/ksu_susfs" "$MOD/bin/ksu_susfs_good" /data/adb/ksu/bin/ksu_susfs; do
        if [ -x "$c" ] && "$c" --help 2>/dev/null | grep -q enable_avc_log_spoofing; then
            if "$c" enable_avc_log_spoofing 1 >/dev/null 2>&1; then
                say "[i] 已通过 ksu_susfs 命令开启：$c"
                return 0
            fi
        fi
    done

    _before=$(cur)
    printf '%s\n' "$SPOOF_CTX" > "$PARAM" 2>/dev/null || die "写入 $PARAM 失败（被拒绝）"
    _after=$(cur)
    if [ "$_after" = "$SPOOF_CTX" ]; then
        say "[i] 已开启：$_before → $_after"
        say "[i] 仅本次开机有效；如需长期生效执行：sh $0 install-boot"
        return 0
    fi
    die "写入后读回是 [$_after]，未生效"
}

do_off() {
    [ -e "$PARAM" ] || die "找不到 $PARAM"
    # 命令通道也关一次，避免两套机制并存
    for c in "$MOD/bin/ksu_susfs" "$MOD/bin/ksu_susfs_good" /data/adb/ksu/bin/ksu_susfs; do
        [ -x "$c" ] && "$c" enable_avc_log_spoofing 0 >/dev/null 2>&1
    done
    _before=$(cur)
    if [ "$_before" = "$REAL_CTX" ]; then
        say "[i] 当前已是原始上下文（$REAL_CTX），无需还原"
        return 0
    fi
    printf '%s\n' "$REAL_CTX" > "$PARAM" 2>/dev/null || die "写入 $PARAM 失败"
    _after=$(cur)
    [ "$_after" = "$REAL_CTX" ] || die "还原后读回是 [$_after]"
    say "[i] 已关闭：$_before → $_after"
}

do_install_boot() {
    [ -e "$PARAM" ] || die "找不到 $PARAM，装开机脚本也没用"
    mkdir -p /data/adb/service.d 2>/dev/null
    cat > "$BOOT_SCRIPT" <<EOF
#!/system/bin/sh
# 由 avc_spoof.sh 安装：开机后把 AVC 日志上下文改写为 priv_app
# 删除本文件即可取消（或执行 avc_spoof.sh remove-boot）
P=$PARAM
[ -w "\$P" ] || exit 0
[ "\$(cat "\$P" 2>/dev/null)" = "$SPOOF_CTX" ] && exit 0
printf '%s\n' "$SPOOF_CTX" > "\$P" 2>/dev/null
EOF
    chmod 755 "$BOOT_SCRIPT" 2>/dev/null
    if [ -f "$BOOT_SCRIPT" ]; then
        say "[i] 已安装开机脚本：$BOOT_SCRIPT"
        say "[i] 下次开机起自动开启；取消：sh $0 remove-boot"
        return 0
    fi
    die "写入 $BOOT_SCRIPT 失败"
}

do_remove_boot() {
    if [ -f "$BOOT_SCRIPT" ]; then
        rm -f "$BOOT_SCRIPT" && say "[i] 已删除开机脚本：$BOOT_SCRIPT"
    else
        say "[i] 没有找到开机脚本，无需删除"
    fi
}

case "${1:-on}" in
    on|enable|1)    do_on ;;
    off|disable|0)  do_off ;;
    status)         do_status ;;
    install-boot)   do_install_boot ;;
    remove-boot)    do_remove_boot ;;
    *)              say "用法：sh $0 [on|off|status|install-boot|remove-boot]"; exit 1 ;;
esac
