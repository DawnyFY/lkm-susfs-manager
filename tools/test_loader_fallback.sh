#!/bin/sh
# 静态回归：加载器必须在 kallsyms 全 0 时回退到 KernelSU 内核侧符号解析。
set -eu
ROOT=${1:-.}
cd "$ROOT"
fail=0
chk() { if grep -q "$1" module/load.sh; then echo "PASS  $2"; else echo "FAIL  $2"; fail=1; fi }
chk 'zero address' 'zero-address 分支'
chk 'kptr_restrict' 'kptr_restrict 分支'
chk 'ksud" insmod' 'ksud insmod 回退'
chk 'KSU_IOCTL_LOOKUP_SYMBOLS' '内核侧符号解析说明'
chk 'rc2' '回退返回值处理'
exit "$fail"
