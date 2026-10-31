#!/system/bin/sh
# 挂载可见性检测（普通应用权限，无需 root / shell）
# 用法：在 MT 管理器的终端里执行  sh /sdcard/Download/mountcheck.sh
# 结果：/sdcard/Download/mountcheck.txt（若不可写则退到应用私有目录）

OUT=/sdcard/Download/mountcheck.txt
if ! touch "$OUT" 2>/dev/null; then
    OUT=/sdcard/Android/data/bin.mt.plus/files/mountcheck.txt
    mkdir -p /sdcard/Android/data/bin.mt.plus/files 2>/dev/null
fi

{
echo "=== 挂载可见性检测 ==="
echo "time: $(date '+%F %T' 2>/dev/null)"
echo "uid: $(id -u 2>/dev/null)"
echo "context: $(id -Z 2>/dev/null || echo unknown)"
echo "selinux: $(getenforce 2>/dev/null || echo unknown)"
echo

echo "--- LSPosed dex2oat 挂载（关键）---"
if [ -r /proc/self/mountinfo ]; then
    N=$(grep -c dex2oat /proc/self/mountinfo 2>/dev/null)
    echo "count: ${N:-0}"
    grep dex2oat /proc/self/mountinfo 2>/dev/null | while read -r line; do
        echo "  $(echo "$line" | awk '{print $5}')"
    done
else
    echo "count: unreadable"
fi
echo

echo "--- 路径可见性 ---"
for p in /apex/com.android.art/bin/dex2oat64 \
         /apex/com.android.art/bin/dex2oat32 \
         /apex/com.android.art/bin/dex2oat \
         /data/adb/lspd \
         /data/data/org.lsposed.manager; do
    if [ -e "$p" ]; then
        echo "  exists   $p"
    else
        echo "  absent   $p"
    fi
done
echo

echo "--- 结论 ---"
if [ -r /proc/self/mountinfo ]; then
    N=$(grep -c dex2oat /proc/self/mountinfo 2>/dev/null)
    if [ "${N:-0}" -gt 0 ] 2>/dev/null; then
        echo "dex2oat 挂载对普通应用可见 = 挂载隐藏未生效"
    else
        echo "dex2oat 挂载不可见 = 挂载隐藏生效"
    fi
fi
} > "$OUT" 2>&1

echo "已写入: $OUT"
cat "$OUT"