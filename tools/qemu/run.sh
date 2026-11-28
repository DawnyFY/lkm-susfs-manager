#!/bin/bash
# 一键：编 init → 打包 initramfs → 起 QEMU → 只打印断言行
#
# 前置：
#   1) 内核树里已把上游模块运行时解析的 5 个符号导出（仅测试用，见 README）
#   2) Image 已编译：$KDIR/arch/arm64/boot/Image
#   3) 被测模块：$MODULE_KO
set -u

KDIR=${KDIR:-/root/kb/6.6}
MODULE_KO=${MODULE_KO:-$KDIR/../up2/susfs_guard_lkm.ko}
WORK=${WORK:-/root/kb/qemu-run}
NDK=${NDK:-/d/ndk/android-ndk-r27c/toolchains/llvm/prebuilt/windows-x86_64/bin}
SRC_DIR=${SRC_DIR:-/mnt/d/aimod/ksu-audit/release-repo/tools/qemu}

[ -f "$KDIR/arch/arm64/boot/Image" ] || { echo "缺 $KDIR/arch/arm64/boot/Image"; exit 1; }
[ -f "$MODULE_KO" ] || { echo "缺模块 $MODULE_KO"; exit 1; }

echo "=== 1. 编译 init（静态 aarch64）==="
"$NDK/clang.exe" --target=aarch64-linux-android29 -static -O1 \
    -o "$WORK_init" "$SRC_DIR/init.c" 2>/dev/null || {
  mkdir -p "$WORK"
  "$NDK/clang.exe" --target=aarch64-linux-android29 -static -O1 -o "$WORK/init" "$SRC_DIR/init.c" || exit 1
}
cp -f "$WORK_init" "$WORK/init" 2>/dev/null || true

echo "=== 2. 打包 initramfs ==="
rm -rf "$WORK/root"; mkdir -p "$WORK/root"/{proc,sys,dev,tmp}
cp -f "$WORK/init" "$WORK/root/init"; chmod +x "$WORK/root/init"
cp -f "$MODULE_KO" "$WORK/root/susfs_guard_lkm.ko"
( cd "$WORK/root" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$WORK/initrd.cpio.gz" )
ls -l "$WORK/initrd.cpio.gz" | awk '{print "initramfs:", $5, "字节"}'

echo "=== 3. QEMU ==="
timeout ${TIMEOUT:-180} qemu-system-aarch64 \
  -M virt,gic-version=2 -cpu cortex-a72 -smp 2 -m 2048 \
  -kernel "$KDIR/arch/arm64/boot/Image" \
  -initrd "$WORK/initrd.cpio.gz" \
  -append "console=ttyAMA0 rdinit=/init loglevel=4 panic=1" \
  -net none -nographic -no-reboot 2>&1 \
  | grep -aE "^\[init\]|^\[app|^    path=|^    pend:|^    dirent:|^    hide_from" | head -40