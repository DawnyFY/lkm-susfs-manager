#!/bin/bash
set -e
K="$TARGET"
OUT="$OUTDIR"
echo "K=$K OUT=$OUT"
ls -ld "$K"
cp -f src/generic_pid_guard.c .
make -C "$K" M="$PWD" ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 modules 2>&1 | tail -8
mkdir -p "lib/$OUT"
cp -f generic_pid_guard.ko "lib/$OUT/generic_pid_guard.ko"
ls -l "lib/$OUT/generic_pid_guard.ko"
