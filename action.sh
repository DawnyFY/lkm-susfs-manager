#!/system/bin/sh
# 模块 Action：手动加载并应用，不依赖开机自动加载。
# 兼容 KernelSU 官方版及 SukiSU / ReSukiSU / KernelSU Next 等分支。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"

echo "***************************************"
echo " SUSFS 管理器"
echo "***************************************"
echo "[i] 管理器: $(ksu_branch)"

sh "$MODDIR/load.sh" manual
sh "$MODDIR/apply.sh"
rc=$?

BIN=$(select_susfs_bin)
if lkm_present; then
    echo "[OK] LKM 已加载"
    [ -n "$BIN" ] && "$BIN" show version
    printf "[i] 用户 sus_path 规则: "
    grep '^path=' /proc/susfs_path 2>/dev/null | grep -v '\[ours:' | sed 's/^path=//' | awk '{print $1}' | sort -u | wc -l
    printf "[i] kernelsu 隐藏: "
    if grep -qw kernelsu /proc/susfs_hide_modules 2>/dev/null; then echo "是"; else echo "否"; fi
    echo "[i] ksu_susfs: ${BIN:-无}"
    echo "[i] 日志: $MODDIR/apply.log"
    clear_boot_guard
    echo "[i] 完成，不需要重启。"
else
    echo "[!] 加载失败 (rc=$rc)"
    echo "----- load.log 最后 20 行 -----"
    tail -n 20 "$MODDIR/load.log" 2>/dev/null
fi
