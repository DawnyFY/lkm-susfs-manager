#!/system/bin/sh
# LKM SUSFS管理器 —— 暴露面自检（只读，不修改任何文件）
#
# 用法（root shell）：
#   sh /data/adb/modules/susfs_allinone/detect_self.sh
#   或任意位置：  sh detect_self.sh [模块目录]
#
# 用途：把第三方检测 App（Duck Detector 等）报告里的条目，按「本模块 / root 管理器 / ROM」
#      拆分归属，避免把 KernelSU 自己的痕迹算到本模块头上。
#
# 注意：本脚本在 root shell 里运行，看到的比普通 App 多；若某项在此显示 visible，
#      不代表 App 也能看到（反之才更值得关注）。

MOD=${1:-${MOD:-/data/adb/modules/susfs_allinone}}
CONF="$MOD/config"
CFG="$CONF/config.ini"
NL='
'

say() { printf '%s\n' "$*"; }
kv() { printf '%-22s %s\n' "$1" "$2"; }

say "=================================================================="
say " LKM SUSFS管理器 · 暴露面自检"
say "=================================================================="

# ---------- 0. 环境 ----------
VER=$(sed -n 's/^version=//p' "$MOD/module.prop" 2>/dev/null | head -1)
VC=$(sed -n 's/^versionCode=//p' "$MOD/module.prop" 2>/dev/null | head -1)
[ -n "$VER" ] || VER="未找到（$MOD/module.prop 不存在？）"
kv "模块版本" "$VER (versionCode ${VC:-?})"
kv "自检时间" "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"

KREL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
kv "内核(uname -r)" "${KREL:-读取失败}"
kv "LKM 已加载" "$([ -d /sys/module/susfs_guard_lkm ] && echo yes || echo no)"
if [ -x "$MOD/bin/ksu_susfs" ]; then
    kv "ksu_susfs 版本" "$("$MOD/bin/ksu_susfs" show version 2>/dev/null || echo '无法通信')"
fi

# ---------- 1. 内核模块列表（/proc/modules） ----------
say ""
say "-- 1) /proc/modules（hide_modules 生效时本模块与 kernelsu 都不该出现）"
if [ -r /proc/modules ]; then
    for tok in susfs_guard_lkm kernelsu ksu; do
        n=$(grep -c "$tok" /proc/modules 2>/dev/null)
        case "$tok" in
            susfs_guard_lkm) kv "  本模块 $tok" "$([ "${n:-0}" -gt 0 ] && echo VISIBLE || echo hidden)" ;;
            *)               kv "  root $tok"   "$([ "${n:-0}" -gt 0 ] && echo VISIBLE || echo hidden)" ;;
        esac
    done
else
    kv "  /proc/modules" "不可读"
fi

# ---------- 2. /proc/kallsyms ----------
say ""
say "-- 2) /proc/kallsyms（符号名无法由本模块清除，属内核/root 管理器侧）"
if [ -r /proc/kallsyms ]; then
    ksu=$(awk '$3 ~ /^__?ksu_/ {c++} END{print c+0}' /proc/kallsyms 2>/dev/null)
    sfs=$(awk '$3 ~ /^susfs_/ {c++} END{print c+0}' /proc/kallsyms 2>/dev/null)
    nz=$(awk '$1 != "0000000000000000" {c++; if (c > 2) exit} END{print (c > 0 ? "yes" : "no")}' /proc/kallsyms 2>/dev/null)
    kv "  ksu_* 符号数" "${ksu:-?}"
    kv "  susfs_* 符号数" "${sfs:-?}"
    kv "  地址可见" "${nz:-?}（app 视角通常读到 0）"
else
    kv "  /proc/kallsyms" "不可读（本就该如此）"
fi

# ---------- 3. uname 伪装 ----------
say ""
say "-- 3) uname（可被本模块 spoof_uname 改写）"
SPOOFC=0
SPOOFV=""
if [ -r "$CFG" ]; then
    SPOOFC=$(sed -n 's/^spoof_uname=//p' "$CFG" 2>/dev/null | tail -1)
    SPOOFV=$(sed -n 's/^spoof_uname_release=//p' "$CFG" 2>/dev/null | tail -1)
fi
kv "  spoof_uname" "${SPOOFC:-0}"
kv "  伪装值" "${SPOOFV:-（空）}"
if [ "${SPOOFC:-0}" = "1" ]; then
    kv "  结论" "已开启：App 读 uname 看到的是伪装串"
else
    kv "  结论" "未开启：App 读到真实内核串（如需掩盖，WebUI 配置页打开）"
fi

# ---------- 4. 隐藏面 ----------
say ""
say "-- 4) 隐藏面（sus_path / hide_modules）"
if [ -r "$CONF/sus_path.txt" ]; then
    cnt=$(grep -c -v -E '^[[:space:]]*(#|$)' "$CONF/sus_path.txt" 2>/dev/null)
    kv "  sus_path 规则数" "${cnt:-0}"
    grep -qx "/data/adb" "$CONF/sus_path.txt" 2>/dev/null && kv "  /data/adb" "在 sus_path 中" || kv "  /data/adb" "未加入（App 侧可能可遍历）"
    grep -qx "/data/local/tmp" "$CONF/sus_path.txt" 2>/dev/null && kv "  /data/local/tmp" "在 sus_path 中" || kv "  /data/local/tmp" "未加入"
else
    kv "  sus_path.txt" "不存在"
fi
if [ -r /proc/susfs_hide_modules ]; then
    hm=$(sed -n 's/^names:[[:space:]]*//p' /proc/susfs_hide_modules 2>/dev/null)
    [ -n "$hm" ] || hm=$(sed -n 's/^[[:space:]]*names:[[:space:]]*//p' /proc/susfs_hide_modules 2>/dev/null)
    kv "  hide_modules 实际" "${hm:-（空）}"
else
    kv "  /proc/susfs_hide_modules" "不可读"
fi

# ---------- 5. 结论与归属 ----------
say ""
say "-- 5) 归属与建议"
cat <<'EOF'
  本模块负责的项（若显示 VISIBLE / 未加入，改配置即可）：
    · /proc/modules 里的 susfs_guard_lkm      → 配置页打开 hide_modules
    · /proc/modules 里的 kernelsu             → 同上（hide_modules 会一起藏）
    · /data/adb、/data/local/tmp 可遍历        → 加入 sus_path 预设
    · uname 暴露真实内核串                     → 配置页打开 spoof_uname
    · 老 SUSFS 杀子进程导致的侧信道            → LKM v2.3.0 已不存在

  不属本模块、模块无法解决的项：
    · /proc/kallsyms 中的 ksu_* 符号           → KernelSU 本体，由管理器提供
    · "ksu_driver 只读命中"、直接 syscall 命中  → KernelSU 本体；在管理器里给该 App
                                                关闭 SU 授权 + 打开「卸载模块」才有效
    · netlink 泄漏 wlan0 MAC / ARP 邻居        → ROM 的 SELinux 策略没做 AOSP 要求的拒绝
    · 临时 root / 自定义内核的 uname 特征       → 属内核与 root 方案，非本模块

  说明：模块的目标是「自己不留痕」，不承诺让检测 App 全绿；
        本模块相关项全 hidden/Clean 即说明模块侧已尽责。
EOF

say ""
say "（以上为 root shell 视角；App 能看到的通常更少）"
