#!/bin/sh
# 离线测试：WebUI 多语言词典 + 构建产物（1.2.9 起前端换为 Vite + Vue + TS）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
command -v node >/dev/null 2>&1 || { echo "SKIP  need node"; exit 0; }

UI="$ROOT/webui"
fail=0

# 1) 词典：中英键集合一致、无空值、模板覆盖、占位符对齐
if node - "$UI" <<'JS'
const fs = require("fs"), path = require("path");
const dir = path.join(process.argv[2], "src", "locales");
const rd = (n) => JSON.parse(fs.readFileSync(path.join(dir, n), "utf8"));
const zh = rd("zh-CN.json"), en = rd("en-US.json"), tpl = rd("template.json");
const zk = Object.keys(zh).sort(), ek = Object.keys(en).sort(), tk = Object.keys(tpl).sort();
const bad = [];
if (JSON.stringify(zk) !== JSON.stringify(ek)) bad.push("zh/en key mismatch");
if (JSON.stringify(zk) !== JSON.stringify(tk)) bad.push("template key mismatch");
const ph = (s) => (String(s).match(/\{\w+\}/g) || []).sort().join(",");
for (const k of zk) {
  if (!String(zh[k]).trim()) bad.push("empty zh: " + k);
  if (!String(en[k]).trim()) bad.push("empty en: " + k);
  if (/[\u4e00-\u9fff]/.test(String(en[k]))) bad.push("CJK in en: " + k);
  if (ph(zh[k]) !== ph(en[k])) bad.push("placeholder mismatch: " + k);
}
if (bad.length) { console.log(bad.slice(0, 10).join("\n")); process.exit(1); }
console.log("I18N_OK keys=" + zk.length);
JS
then :; else echo "FAIL  词典审计"; fail=1; fi

# 2) 构建产物必须真的落到 module/webroot
for f in index.html assets/app.js assets/app.css; do
    [ -f "$REPO/webroot/$f" ] || { echo "FAIL  missing webroot/$f (run tools/build_webui.sh)"; fail=1; }
done
if [ -f "$REPO/webroot/index.html" ]; then
    n=$(grep -c 'src="/' "$REPO/webroot/index.html" 2>/dev/null || true)
    [ "$n" = "0" ] || { echo "FAIL  index.html uses absolute asset paths"; fail=1; }
fi
if [ -f "$REPO/webroot/assets/app.js" ]; then
    grep -q '/data/adb/modules/susfs_allinone/ctl.sh' "$REPO/webroot/assets/app.js" || {
        echo "FAIL  bundle missing ctl path"; fail=1; }
fi

# 3) 旧产物必须已下线（避免两套前端并存）
for old in app.js i18n.js style.css style-alt.css; do
    [ -f "$REPO/webroot/$old" ] && { echo "FAIL  legacy webroot/$old still present"; fail=1; }
done

[ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
