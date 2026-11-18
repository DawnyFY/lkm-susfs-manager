#!/bin/bash
set -e
K="${KDIR:-/opt/ddk/kdir/android17-6.18}"
echo "K=$K"
ls -ld "$K"
cp -f src/generic_pid_guard.c .
make -C "$K" M="$PWD" ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 modules 2>&1 | tail -12
mkdir -p lib/android17-6.18
cp -f generic_pid_guard.ko lib/android17-6.18/generic_pid_guard.ko
ls -l lib/android17-6.18/generic_pid_guard.ko
