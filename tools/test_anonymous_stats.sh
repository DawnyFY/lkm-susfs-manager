#!/bin/sh
# 匿名统计：开关、一次请求、版本绑定、关闭删除 token
set -u
REPO=${1:-.}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
M="$TMP/mod"; mkdir -p "$M/config" "$M/state"
printf 'version=1.2.7\nversionCode=19\n' > "$M/module.prop"
printf 'anonymous_stats=1\n' > "$M/config/config.ini"
cat > "$TMP/fake-curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"token":"ZmFrZS5wYXlsb2Fk.c2ln","version":"1.2.7","version_code":19,"expires_at":"2027-01-01T00:00:00Z"}
JSON
EOF
chmod +x "$TMP/fake-curl"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
( MODDIR="$M"; CONFIG="$M/config"; STATE="$M/state"; STATS_CURL="$TMP/fake-curl"; STATS_URL="https://example.invalid/api"; . "$REPO/module/common.sh"; report_install )
chk "开关开启时写 token" "$(grep -c '^token=ZmFrZS5wYXlsb2Fk.c2ln$' "$M/state/server_token")" "1"
chk "记录版本号" "$(grep -c '^version_code=19$' "$M/state/server_token")" "1"
# 第二次调用应直接复用，不依赖 fake curl（即使 fake curl 被删也能成功）
mv "$TMP/fake-curl" "$TMP/fake-curl.off"
( MODDIR="$M"; CONFIG="$M/config"; STATE="$M/state"; STATS_CURL="$TMP/fake-curl"; STATS_URL="https://example.invalid/api"; . "$REPO/module/common.sh"; report_install )
chk "同版本不重复请求" "$(grep -c '^token=ZmFrZS5wYXlsb2Fk.c2ln$' "$M/state/server_token")" "1"
# 失败时才上传日志
printf '=== apply.log ===\nfailed test line\n' > "$M/apply.log"
printf '=== load.log ===\nload test line\n' > "$M/load.log"
mkdir -p "$TMP/Download"
( MODDIR="$M"; CONFIG="$M/config"; STATE="$M/state"; FAILURE_LOCAL_DIR="$TMP/Download"; STATS_CURL="$TMP/fake-curl.off"; STATS_URL="https://example.invalid/api"; . "$REPO/module/common.sh"; report_failure apply_failed )
chk "失败时写本地快照" "$(ls "$TMP/Download"/susfs_allinone-failure-*.txt 2>/dev/null | wc -l | tr -d " ")" "1"
chk "失败时写上传标记" "$(grep -c 'apply_failed' "$M/state/failure_reported" 2>/dev/null)" "1"

# 首次请求失败、第二次成功：必须还能拿到 token（锁住“一次重试”）
rm -f "$M/state/server_token"
cat > "$TMP/flaky-curl" <<'EOF'
#!/bin/sh
if [ ! -e "__FLAKY__" ]; then : > "__FLAKY__"; exit 7; fi
cat <<'JSON'
{"token":"RkxBS1kuVE9LRU4.c2ln","version":"1.2.7","version_code":19,"expires_at":"2027-01-01T00:00:00Z"}
JSON
EOF
sed -i "s#__FLAKY__#$TMP/flaky.state#g" "$TMP/flaky-curl"
chmod +x "$TMP/flaky-curl"
( MODDIR="$M"; CONFIG="$M/config"; STATE="$M/state"; STATS_CURL="$TMP/flaky-curl"; STATS_URL="https://example.invalid/api"; . "$REPO/module/common.sh"; report_install )
chk "首次失败后重试成功仍写 token" "$(grep -c '^token=RkxBS1kuVE9LRU4.c2ln$' "$M/state/server_token" 2>/dev/null)" "1"
chk "确实请求了两次" "$([ -e "$TMP/flaky.state" ] && echo yes || echo no)" "yes"

# 关闭开关必须删除 token
printf 'anonymous_stats=0\n' > "$M/config/config.ini"
( MODDIR="$M"; CONFIG="$M/config"; STATE="$M/state"; STATS_CURL="$TMP/fake-curl"; STATS_URL="https://example.invalid/api"; . "$REPO/module/common.sh"; report_install )
chk "关闭后删除 token" "$([ -e "$M/state/server_token" ] && echo exists || echo gone)" "gone"
exit "$fail"
