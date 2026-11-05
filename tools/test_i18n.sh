#!/bin/sh
# 离线测试：WebUI 英文本地化（词典覆盖 index.html / app.js，并验证翻译引擎行为）
set -u
REPO="$1"
command -v node >/dev/null 2>&1 || { echo "SKIP  需要 node"; exit 0; }
fail=0
if ! node --check "$REPO/webroot/i18n.js" >/dev/null 2>&1; then
    echo "FAIL  i18n.js 语法"
    fail=1
fi
if ! node --check "$REPO/webroot/app.js" >/dev/null 2>&1; then
    echo "FAIL  app.js 语法"
    fail=1
fi
if node "$REPO/tools/i18n_audit.js" "$REPO"; then
    :
else
    fail=1
fi
exit "$fail"
