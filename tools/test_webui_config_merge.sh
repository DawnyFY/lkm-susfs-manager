#!/bin/sh
# 离线测试：WebUI 保存配置时保留未知键与特殊取值（node 执行真实函数）
set -u
REPO="$1"
command -v node >/dev/null 2>&1 || { echo "SKIP  需要 node"; exit 0; }
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8");
const m = /function mergeConfigText[\s\S]*?\n}/.exec(src);
if (!m) { console.log("MISSING"); process.exit(2); }
eval(m[0]);
const raw = [
  "# 用户注释",
  "auto_load=1",
  "replace_rules=2",
  "my_custom_key=keepme",
  "skip_hide_note=保留我",
  "",
].join("\\n");
const out = mergeConfigText(raw, { auto_load: 1, replace_rules: "2", skip_detection_paths: 1 });
const has = (s) => out.includes(s);
console.log(has("my_custom_key=keepme") ? "KEEP_OK" : "KEEP_LOST");
console.log(has("skip_hide_note=") ? "CJK_OK" : "CJK_LOST");
console.log(has("# 用户注释") ? "COMMENT_OK" : "COMMENT_LOST");
console.log(has("replace_rules=2") ? "TWO_OK" : "TWO_LOST");
console.log(has("skip_detection_paths=1") ? "ADDED_OK" : "ADDED_LOST");
console.log(out.split("\\n").filter(l => l.startsWith("auto_load=")).length === 1 ? "NO_DUP" : "DUP");
' "$REPO/webroot/app.js" > /tmp/merge_out.$$ 2>&1

chk "保留未知键" "$(grep -c KEEP_OK /tmp/merge_out.$$)" "1"
chk "保留中文值" "$(grep -c CJK_OK /tmp/merge_out.$$)" "1"
chk "保留注释" "$(grep -c COMMENT_OK /tmp/merge_out.$$)" "1"
chk "保留 replace_rules=2" "$(grep -c TWO_OK /tmp/merge_out.$$)" "1"
chk "补写新键" "$(grep -c ADDED_OK /tmp/merge_out.$$)" "1"
chk "不产生重复键" "$(grep -c NO_DUP /tmp/merge_out.$$)" "1"
rm -f /tmp/merge_out.$$

# 集成断言：UI 必须暴露 skip_detection_paths 与三态 replace 处理
chk "UI 有跳过检测器开关" "$(grep -c 'id="skipDetectionPaths"' "$REPO/webroot/index.html")" "1"
chk "保存保留 2" "$(grep -q 'newReplace = "2"' "$REPO/webroot/app.js" && echo yes || echo no)" "yes"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"