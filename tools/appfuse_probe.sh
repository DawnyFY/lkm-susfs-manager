#!/system/bin/sh
# AppFuse 挂载排查 / 清理
# 用法：
#   su -c "sh /sdcard/Download/appfuse_probe.sh"           # 查看
#   su -c "sh /sdcard/Download/appfuse_probe.sh 10543"     # 查某个 uid
#   su -c "sh /sdcard/Download/appfuse_probe.sh clean 10543"  # 杀进程 + 卸挂载
# 输出：/sdcard/Download/appfuse_probe.txt

OUT=/sdcard/Download/appfuse_probe.txt
MODE="$1"
if [ "$MODE" = "clean" ] || [ "$MODE" = "watch" ]; then
    TARGET_UID="$2"
else
    TARGET_UID="$1"
fi

# UID 必须是纯数字：避免被拼进 glob（例如传入 * 会匹配并卸载多个实例）
case "$TARGET_UID" in
    '') ;;
    *[!0-9]*) echo "拒绝：UID 必须是数字，收到 '$TARGET_UID'" >&2; exit 1 ;;
esac

{
echo "=== AppFuse 挂载排查 ==="
echo "time: $(date '+%F %T')"
echo "kernel: $(uname -r)"
echo "android: $(getprop ro.build.version.release)"
echo

echo "--- 当前 appfuse 挂载 ---"
LIST=""
for f in /proc/1/mountinfo /proc/self/mountinfo; do
    if grep -q appfuse "$f" 2>/dev/null; then
        LIST="$f"
        break
    fi
done
if [ -n "$LIST" ]; then
    echo "来源: $LIST"
    grep appfuse "$LIST" 2>/dev/null | awk '{print $5, $9}' | sort -u
else
    echo "当前没有任何 appfuse 挂载"
fi
echo

echo "--- /mnt/appfuse 目录 ---"
ls -1 /mnt/appfuse 2>/dev/null | head -40
echo

echo "--- uid -> 包名 映射（当前存在的 appfuse）---"
PM=$(pm list packages -U 2>/dev/null | sed "s/package://; s/ uid:/ /")
UIDS=$(grep appfuse /proc/1/mountinfo 2>/dev/null | sed -n "s|.*/mnt/appfuse/\([0-9]*\)_.*|\1|p" | sort -un)
[ -z "$UIDS" ] && UIDS=$(ls /mnt/appfuse 2>/dev/null | sed -n "s/^\([0-9]*\)_.*/\1/p" | sort -un)
if [ -z "$UIDS" ]; then
    echo "（无）"
else
    for u in $UIDS; do
        names=$(echo "$PM" | awk -v u="$u" '$2==u {printf "%s ", $1}')
        echo "  uid $u : ${names:-未找到对应包}"
    done
fi
echo

echo "--- 指定 uid 详情 ---"
if [ -n "$TARGET_UID" ]; then
    names=$(echo "$PM" | awk -v u="$TARGET_UID" '$2==u {printf "%s ", $1}')
    echo "uid $TARGET_UID : ${names:-未找到对应包}"
    echo "该 uid 的 appfuse 实例:"
    ls -1 /mnt/appfuse 2>/dev/null | grep "^${TARGET_UID}_" || echo "  （无）"
    echo "该 uid 的进程:"
    ps -A -o PID,UID,NAME 2>/dev/null | awk -v u="$TARGET_UID" '$2==u {print "  "$0}' | head -10
else
    echo "未指定 uid；可用：sh $0 10543"
fi
echo

echo "--- 本模块是否碰过 /sdcard ---"
grep -E "sdcard|Android/data" /data/adb/modules/susfs_allinone/apply.log 2>/dev/null | tail -5 || echo "（日志中无相关记录）"
echo

echo "--- 本模块 apply 运行的 uid ---"
echo "模块脚本由 KernelSU 以 uid 0 执行（见 apply.log 的 root 行）"
grep -m1 "root:" /data/adb/modules/susfs_allinone/apply.log 2>/dev/null
} > "$OUT" 2>&1

echo "已写入: $OUT"
cat "$OUT"
if [ "$MODE" = "clean" ] && [ -n "$TARGET_UID" ]; then
    echo
    echo "=== 清理 uid $TARGET_UID ==="
    PM2=$(pm list packages -U 2>/dev/null | sed "s/package://; s/ uid:/ /")
    names=$(echo "$PM2" | awk -v u="$TARGET_UID" '$2==u {printf "%s ", $1}')
    echo "相关包: ${names:-未找到}"
    for p in $names; do
        am force-stop "$p" 2>/dev/null && echo "  force-stop $p"
    done
    echo "该 uid 残留进程:"
    ps -A -o PID,UID,NAME 2>/dev/null | awk -v u="$TARGET_UID" '$2==u {print "  "$0}' | head -10
    echo "卸载 appfuse 实例:"
    for d in /mnt/appfuse/${TARGET_UID}_*; do
        [ -e "$d" ] || continue
        if umount -l "$d" 2>/dev/null; then
            echo "  unmounted $d"
        else
            echo "  卸载失败 $d"
        fi
    done
    echo "剩余实例:"
    ls -1 /mnt/appfuse 2>/dev/null | grep "^${TARGET_UID}_" || echo "  （无）"
fi
if [ "$MODE" = "watch" ] && [ -n "$TARGET_UID" ]; then
    SECS="${3:-60}"
    echo
    echo "=== 监视 uid $TARGET_UID 的 appfuse 变化（${SECS}s）==="
    echo "uptime_start=$(cut -d. -f1 /proc/uptime)"
    _last=-1
    _i=0
    while [ "$_i" -lt "$SECS" ]; do
        _n=$(ls -1 /mnt/appfuse 2>/dev/null | grep -c "^${TARGET_UID}_")
        if [ "$_n" != "$_last" ]; then
            echo "$(date '+%T') uptime=$(cut -d. -f1 /proc/uptime) count=$_n"
            _last=$_n
        fi
        _i=$((_i + 5))
        sleep 5
    done
    echo "--- 该 uid 进程 ---"
    pm list packages -U 2>/dev/null | sed "s/package://; s/ uid:/ /" | awk -v u="$TARGET_UID" '$2==u {print "包名: "$1}'
    ps -A -o PID,UID,NAME 2>/dev/null | awk -v u="$TARGET_UID" '$2==u {print "  "$0}'
    echo "--- 哪些进程持有该 uid 的 FUSE 实例 ---"
    for d in /mnt/appfuse/${TARGET_UID}_*; do
        [ -e "$d" ] || continue
        echo "  $d"
    done
fi