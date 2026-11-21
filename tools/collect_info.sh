#!/system/bin/sh
# ============================================================================
# LKM SUSFS管理器 —— 设备信息采集脚本（独立版，不依赖模块内部文件）
#
# 用途：把这个脚本给需要求助的用户跑一次，得到一份结构化的设备信息，
#      贴到群里 / 附在 GitHub issue 里，省掉十几个来回问。
#
# 用法：
#   root shell：  su -c 'sh collect_info.sh'
#   普通 shell：  sh collect_info.sh            （会缺一部分 root 才能读的信息）
#   指定输出目录：sh collect_info.sh /sdcard/Download
#
# 说明：
#   · 纯只读，不改任何系统/模块文件
#   · 不含账号、IMEI、序列号、应用列表；install_id 自动打码
#   · 生成的 txt 里含设备路径信息，发出去前建议自己过一眼
# ============================================================================

OUT_DIR=${1:-/sdcard/Download}
STAMP=$(date '+%Y%m%d_%H%M%S' 2>/dev/null)
[ -n "$STAMP" ] || STAMP=unknown
MOD=/data/adb/modules/susfs_allinone

say() { printf '%s\n' "$*"; }
kv()  { printf '  %-22s %s\n' "$1" "$2"; }
sec() { printf '\n=== %s ===\n' "$*"; }

# ---------- 采集 ----------
COLLECT() {
say "=================================================================="
say " LKM SUSFS管理器 · 设备信息采集"
say " 生成时间：$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null)"
say "=================================================================="

sec "1. 设备与系统"
kv "机型"        "$(getprop ro.product.model 2>/dev/null)"
kv "品牌/厂商"   "$(getprop ro.product.brand 2>/dev/null) / $(getprop ro.product.manufacturer 2>/dev/null)"
kv "设备代号"    "$(getprop ro.product.device 2>/dev/null)"
kv "Android"     "$(getprop ro.build.version.release 2>/dev/null)（API $(getprop ro.build.version.sdk 2>/dev/null)）"
kv "ROM/构建"    "$(getprop ro.build.display.id 2>/dev/null)"
kv "构建类型"    "$(getprop ro.build.type 2>/dev/null)"
kv "指纹"        "$(getprop ro.build.fingerprint 2>/dev/null)"
kv "安全补丁"    "$(getprop ro.build.version.security_patch 2>/dev/null)"
kv "ABI"         "$(getprop ro.product.cpu.abi 2>/dev/null)"

sec "2. 内核"
kv "uname -r"    "$(uname -r 2>/dev/null)"
kv "uname -v"    "$(uname -v 2>/dev/null)"
kv "osrelease"   "$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
kv "内核串含 tag" "$(case "$(uname -r 2>/dev/null)" in *android[0-9]*) echo yes ;; *) echo "no（需要手动指定 KMI）" ;; esac)"
_ki_rel=$(uname -r 2>/dev/null)
_ki_tag=$(printf '%s\n' "$_ki_rel" | sed -n 's/.*-\(android[0-9][0-9]*\)-.*/\1/p')
_ki_mm=$(printf '%s\n' "$_ki_rel" | sed -n 's/^\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1.\2/p')
if [ -n "$_ki_tag" ] && [ -n "$_ki_mm" ]; then
    kv "KMI 推断" "$_ki_tag-$_ki_mm"
else
    kv "KMI 推断" "无法从内核串推断（到 WebUI 配置页强制指定）"
fi

sec "3. Root 方案"
if [ -d /data/adb/ksu ] || [ -x /data/adb/ksud ] || [ -x /data/adb/ksu/bin/ksud ]; then
    kv "管理器" "KernelSU 系列"
    if [ -x /data/adb/ksu/bin/ksud ]; then
        kv "ksud 版本" "$(/data/adb/ksu/bin/ksud -V 2>/dev/null || echo '无法读取')"
    fi
    [ -f /data/adb/ksu/version ] && kv "版本文件" "$(cat /data/adb/ksu/version 2>/dev/null)"
elif [ -d /data/adb/ap ] || [ -d /data/adb/apd ]; then
    kv "管理器" "APatch"
elif [ -d /data/adb/magisk ]; then
    kv "管理器" "Magisk"
    [ -x /data/adb/magisk/magisk ] && kv "Magisk 版本" "$(/data/adb/magisk/magisk -v 2>/dev/null)"
else
    kv "管理器" "未识别（/data/adb 下没有已知目录）"
fi
kv "当前 uid"    "$(id -u 2>/dev/null)（0 表示 root shell）"
kv "SELinux"     "$(getenforce 2>/dev/null)"
kv "verifiedboot" "$(getprop ro.boot.verifiedbootstate 2>/dev/null) / flash.locked=$(getprop ro.boot.flash.locked 2>/dev/null)"

sec "4. 模块状态"
if [ -f "$MOD/module.prop" ]; then
    kv "已安装版本" "$(sed -n 's/^version=//p' "$MOD/module.prop" 2>/dev/null) (versionCode $(sed -n 's/^versionCode=//p' "$MOD/module.prop" 2>/dev/null))"
    kv "模块目录"   "$MOD"
    [ -f /sys/fs/pstore/console-ramoops-0 ] && kv "pstore" "有转储（崩溃过，见报告）" || kv "pstore" "无"
    kv "LKM 已加载" "$([ -d /sys/module/susfs_guard_lkm ] && echo yes || echo no)"
    if [ -x "$MOD/bin/ksu_susfs" ]; then
        kv "ksu_susfs" "$("$MOD/bin/ksu_susfs" show version 2>/dev/null || echo '无法通信')"
    fi
    # 只取关键字段，避免整份 status 太长
    if [ -r "$MOD/ctl.sh" ]; then
        say "  --- ctl.sh status（关键字段）---"
        sh "$MOD/ctl.sh" status 2>/dev/null | grep -E '^(module_version|kmi|kernel|lkm_present|lkm_version|lkm_variant|integrity|rules|hide_kernelsu|apply_result|apply_fails|fail_count|auto_load|autoload|pid_guard_enabled|pid_guard_loaded|pid_guard_hidden|selinux|root_manager|crash_evidence|anonymous_stats)=' | sed 's/^/    /'
    fi
else
    kv "模块" "未安装（$MOD 不存在）"
fi

sec "5. 配置摘要"
CFG="$MOD/config/config.ini"
if [ -r "$CFG" ]; then
    # install_id 之类敏感值打码；其余是开关，不影响隐私
    grep -E '^[a-z_]+=' "$CFG" 2>/dev/null | grep -v '^install_id=' | sed 's/^/  /' | head -40
else
    kv "config.ini" "不可读"
fi
if [ -r "$MOD/config/sus_path.txt" ]; then
    n=$(grep -c -v -E '^[[:space:]]*(#|$)' "$MOD/config/sus_path.txt" 2>/dev/null)
    kv "sus_path 规则数" "${n:-0}"
    say "  --- sus_path 前 8 条 ---"
    grep -v -E '^[[:space:]]*(#|$)' "$MOD/config/sus_path.txt" 2>/dev/null | head -8 | sed 's/^/    /'
fi

sec "6. 隐藏与限制状态"
if [ -r /proc/susfs_hide_modules ]; then
    kv "hide_modules 名单" "$(sed -n 's/^names:[[:space:]]*//p' /proc/susfs_hide_modules 2>/dev/null)"
fi
kv "modules_disabled" "$(cat /proc/sys/kernel/modules_disabled 2>/dev/null)"
kv "kptr_restrict"    "$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null)"
kv "lockdown"         "$(cat /sys/kernel/security/lockdown 2>/dev/null || echo '不可读')"
if [ -r /proc/modules ]; then
    kv "proc/modules 含本模块" "$(grep -c susfs_guard_lkm /proc/modules 2>/dev/null)"
    kv "proc/modules 含 kernelsu" "$(grep -ci kernelsu /proc/modules 2>/dev/null)"
fi

sec "7. 日志尾部"
for f in load apply; do
    L="$MOD/$f.log"
    if [ -r "$L" ]; then
        say "  --- $f.log 最后 25 行 ---"
        tail -n 25 "$L" 2>/dev/null | sed 's/^/    /'
    else
        say "  --- $f.log 不可读（需要 root）---"
    fi
done

sec "8. 崩溃证据（pstore）"
if [ -d /sys/fs/pstore ]; then
    ls -l /sys/fs/pstore 2>/dev/null | sed 's/^/  /'
    for f in /sys/fs/pstore/*; do
        [ -f "$f" ] || continue
        say "  --- $(basename "$f")：触发行 + 出错函数 ---"
        grep -nE 'Kernel panic|Oops|Unable to handle kernel|BUG:|Internal error' "$f" 2>/dev/null | tail -1 | sed 's/^/    /'
        grep -m1 -E ' (pc|lr) *: ' "$f" 2>/dev/null | sed 's/^/    /'
    done
else
    kv "pstore" "目录不存在"
fi

say ""
say "=================================================================="
say " 采集完成。把上面内容（或输出的 txt）贴到群里 / issue 里即可。"
say " 提示：文件里含设备路径；install_id 未包含。需要更详细的可附 WebUI 日志导出。"
}
# ---------- 输出 ----------

COLLECT | tee "$OUT_DIR/susfs_info_$STAMP.txt" 2>/dev/null || COLLECT

if [ -s "$OUT_DIR/susfs_info_$STAMP.txt" ]; then
    printf '\n已保存：%s\n' "$OUT_DIR/susfs_info_$STAMP.txt"
fi
