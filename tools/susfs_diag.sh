#!/system/bin/sh
# SUSFS 管理器诊断脚本：一条命令收集所有相关信息
# 用法（需要 root）：
#   su -c "sh /sdcard/Download/susfs_diag.sh"
# 输出：/sdcard/Download/susfs_diag.txt

OUT=/sdcard/Download/susfs_diag.txt
if ! touch "$OUT" 2>/dev/null; then
    OUT=/sdcard/susfs_diag.txt
fi
MOD=/data/adb/modules/susfs_allinone

elf_machine() {
    _f=$1
    [ -f "$_f" ] || { echo "missing"; return 0; }
    _magic=$(od -An -tx1 -N4 "$_f" 2>/dev/null | tr -d " \n")
    [ "$_magic" = "7f454c46" ] || { echo "not-elf"; return 0; }
    _lo=$(od -An -tu1 -j18 -N1 "$_f" 2>/dev/null | tr -d " ")
    _hi=$(od -An -tu1 -j19 -N1 "$_f" 2>/dev/null | tr -d " ")
    _m=$(( ${_hi:-0} * 256 + ${_lo:-0} ))
    case "$_m" in
        183) echo "aarch64" ;;
        62)  echo "x86_64" ;;
        40)  echo "arm" ;;
        3)   echo "x86" ;;
        *)   echo "machine=$_m" ;;
    esac
}

run() {
    _o=$("$@" 2>&1)
    _rc=$?
    printf "rc=%s out=%s\n" "$_rc" "$(printf '%s' "$_o" | head -3 | tr '\n' '|')"
}

{
echo "=============================================="
echo " SUSFS 管理器诊断"
echo "=============================================="
echo "time      : $(date '+%F %T' 2>/dev/null)"
echo "uid       : $(id -u 2>/dev/null)"
echo "osrelease : $(cat /proc/sys/kernel/osrelease 2>/dev/null)"
echo "procver   : $(cat /proc/version 2>/dev/null | cut -c1-120)"
echo "selinux   : $(getenforce 2>/dev/null || echo unknown)"

echo
echo "=== 模块 ==="
if [ -f "$MOD/module.prop" ]; then
    grep -E "^(id|version|versionCode)=" "$MOD/module.prop" | sed "s/^/  /"
    echo "  dirs: $(ls "$MOD" 2>/dev/null | tr '\n' ' ')"
    echo "  bin : $(ls "$MOD/bin" 2>/dev/null | tr '\n' ' ')"
    echo "  kofiles: $(ls "$MOD/lib" 2>/dev/null | wc -l) 个"
else
    echo "  模块目录不存在: $MOD"
fi

echo
echo "=== LKM 状态 ==="
echo "proc_nodes: $(ls /proc/susfs_* 2>/dev/null | tr '\n' ' ')"
if [ -d /sys/module/susfs_guard_lkm ]; then echo "sysfs: susfs_guard_lkm 存在"; else echo "sysfs: 不存在"; fi
echo "proc_modules 中 susfs: $(grep -ic susfs /proc/modules 2>/dev/null)"

echo
echo "=== ksu_susfs 二进制对比 ==="
for b in /data/adb/ksu/bin/ksu_susfs /data/adb/ap/bin/ksu_susfs "$MOD/bin/ksu_susfs_good"; do
    [ -e "$b" ] || { echo "--- $b : 不存在"; continue; }
    echo "--- $b"
    echo "  elf_arch     : $(elf_machine "$b")"
    echo -n "  show version : "; run "$b" show version
    echo -n "  show variant : "; run "$b" show variant
    echo -n "  features head: "; "$b" show enabled_features 2>/dev/null | head -3 | tr '\n' ' '; echo ""
    echo "  sus_mount 支持: $(printf '%s\n' "$("$b" show enabled_features 2>/dev/null)" | grep -qx CONFIG_KSU_SUSFS_SUS_MOUNT && echo feature_yes || echo feature_no)（只读判定，不写规则）"
    echo "  try_umount 支持: $(printf '%s\n' "$("$b" show enabled_features 2>/dev/null)" | grep -qx CONFIG_KSU_SUSFS_TRY_UMOUNT && echo feature_yes || echo feature_no)（只读判定，不写规则）"
done

echo
echo "=== 能力缓存 ==="
[ -f "$MOD/state/caps" ] && sed "s/^/  /" "$MOD/state/caps" || echo "  无 state/caps"

echo
echo "=== 配置摘要 ==="
[ -f "$MOD/config/config.sh" ] && grep -E "^(auto_load|hide_scene|auto_try_umount|skip_legit_mounts|spoof_uname|force_kmi|manager_name)=" "$MOD/config/config.sh" | sed "s/^/  /"
echo "  sus_path 条数: $(grep -cvE '^[[:space:]]*(#|$)' "$MOD/config/sus_path.txt" 2>/dev/null)"
echo "  hide_modules : $(grep -vE '^[[:space:]]*(#|$)' "$MOD/config/hide_modules.txt" 2>/dev/null | tr '\n' ' ')"

echo
echo "=== dmesg (susfs) ==="
dmesg 2>/dev/null | grep -iE "susfs" | tail -10 || echo "  无法读取 dmesg"

echo
echo "=== load.log 最后 12 行 ==="
tail -12 "$MOD/load.log" 2>/dev/null || echo "  无 load.log"

echo
echo "=== apply.log 最后一次运行 ==="
awk '/^=== apply 20/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$MOD/apply.log" 2>/dev/null | tail -25 || echo "  无 apply.log"

echo
echo "=== 结论 ==="
A=$([ -x /data/adb/ksu/bin/ksu_susfs ] && /data/adb/ksu/bin/ksu_susfs show version 2>/dev/null)
B=$([ -x "$MOD/bin/ksu_susfs_good" ] && "$MOD/bin/ksu_susfs_good" show version 2>/dev/null)
echo "  管理器二进制: ${A:-（无响应）}"
echo "  模块备份二进制: ${B:-（无响应）}"
if [ -n "$A" ] && [ -n "$B" ]; then
    echo "  => 两个二进制都能通信"
elif [ -z "$A" ] && [ -n "$B" ]; then
    echo "  => 管理器二进制不可用，模块备份可用（ABI/版本不匹配）"
elif [ -z "$A" ] && [ -z "$B" ]; then
    echo "  => 两个二进制都不可用，检查 LKM 是否真正加载"
else
    echo "  => 模块备份不可用但管理器可用（罕见，检查模块完整性）"
fi
} > "$OUT" 2>&1

echo "已写入: $OUT"
echo "共 $(wc -l < "$OUT" 2>/dev/null) 行，可直接分享该文件"