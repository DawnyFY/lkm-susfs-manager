#!/usr/bin/env node
// WebUI 多语言审计（1.2.9 起前端为 Vite + Vue + TS，词典改为 JSON）
// 用法: node tools/i18n_audit.js <repo-root | module-dir>
const fs = require("fs");
const path = require("path");

const arg = process.argv[2] || ".";
const root = fs.existsSync(path.join(arg, "module", "module.prop")) ? path.join(arg, "webui") : path.join(arg, "..", "webui");
const dir = path.join(root, "src", "locales");

function rd(name) {
  return JSON.parse(fs.readFileSync(path.join(dir, name), "utf8"));
}

try {
  const zh = rd("zh-CN.json");
  const en = rd("en-US.json");
  const tpl = rd("template.json");
  const zk = Object.keys(zh).sort();
  const ek = Object.keys(en).sort();
  const tk = Object.keys(tpl).sort();
  const bad = [];
  if (JSON.stringify(zk) !== JSON.stringify(ek)) bad.push("zh/en key sets differ");
  if (JSON.stringify(zk) !== JSON.stringify(tk)) bad.push("template key set differs");
  const ph = (s) => (String(s).match(/\{\w+\}/g) || []).sort().join(",");
  for (const k of zk) {
    if (!String(zh[k] || "").trim()) bad.push("empty zh: " + k);
    if (!String(en[k] || "").trim()) bad.push("empty en: " + k);
    if (/[一-鿿]/.test(String(en[k] || ""))) bad.push("CJK in en: " + k);
    if (ph(zh[k]) !== ph(en[k])) bad.push("placeholder mismatch: " + k);
  }
  if (bad.length) {
    console.log("FAIL  " + bad.length + " issue(s)");
    bad.slice(0, 15).forEach((b) => console.log("  - " + b));
    console.log("I18N_FAIL");
    process.exit(1);
  }
  console.log("I18N_OK keys=" + zk.length);
} catch (e) {
  console.log("FAIL  " + e.message);
  console.log("I18N_FAIL");
  process.exit(1);
}
