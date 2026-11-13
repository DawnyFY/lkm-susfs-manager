#!/bin/sh
# 安装密钥：生成、持久、权限、对外 hash 稳定性
set -u
REPO=${1:-.}
[ -d "$REPO/module" ] || { echo "FAIL  repo/module missing"; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
M="$TMP/mod"; mkdir -p "$M/state" "$M/config"
( MODDIR="$M"; STATE="$M/state"; CONFIG="$M/config"; . "$REPO/module/common.sh"; ensure_install_key )
fail=0
KEY="$M/state/install_key"
[ -s "$KEY" ] && echo "PASS  密钥已生成" || { echo "FAIL  密钥未生成"; fail=1; }
LEN=$(wc -c < "$KEY" | tr -d ' ')
[ "$LEN" = "65" ] && echo "PASS  32 字节 hex" || { echo "FAIL  长度 $LEN"; fail=1; }
MODE=$(stat -c %a "$KEY" 2>/dev/null)
case "$(uname -s 2>/dev/null)" in
    *MINGW*|*MSYS*) echo "SKIP  权限检查（Windows 文件系统不支持 Unix 600 语义）" ;;
    *) [ "$MODE" = "600" ] && echo "PASS  权限 600" || { echo "FAIL  权限 $MODE"; fail=1; } ;;
esac
K1=$(cat "$KEY")
( MODDIR="$M"; STATE="$M/state"; CONFIG="$M/config"; . "$REPO/module/common.sh"; ensure_install_key )
K2=$(cat "$KEY")
[ "$K1" = "$K2" ] && echo "PASS  重复调用不重签" || { echo "FAIL  密钥被重写"; fail=1; }
ID1=$( ( MODDIR="$M"; STATE="$M/state"; CONFIG="$M/config"; . "$REPO/module/common.sh"; install_id ) )
ID2=$( ( MODDIR="$M"; STATE="$M/state"; CONFIG="$M/config"; . "$REPO/module/common.sh"; install_id ) )
[ "$ID1" = "$ID2" ] && [ ${#ID1} -eq 16 ] && echo "PASS  install_id 稳定" || { echo "FAIL  install_id=$ID1/$ID2"; fail=1; }

# 熵源失败必须 fail closed，不能生成空输入 SHA-256 的固定 key
M2DIR="$TMP/mod2"; mkdir -p "$M2DIR/state" "$M2DIR/config"
( MODDIR="$M2DIR"; STATE="$M2DIR/state"; CONFIG="$M2DIR/config"; INSTALL_KEY_RANDOM=/dev/null; . "$REPO/module/common.sh"; ensure_install_key )
RC=$?
[ "$RC" != "0" ] && [ ! -s "$M2DIR/state/install_key" ] && echo "PASS  熵源失败 fail closed" || { echo "FAIL  熵源失败仍返回 rc=$RC"; fail=1; }
exit "$fail"
