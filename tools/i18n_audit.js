#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0-only
// 检查 WebUI 英文本地化：词典覆盖 index.html / app.js，并跑一遍翻译引擎的行为用例。
// 用法：node tools/i18n_audit.js <repo>
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const repo = process.argv[2] || path.resolve(__dirname, "..");
const WEB = path.join(repo, "webroot");
const i18nSrc = fs.readFileSync(path.join(WEB, "i18n.js"), "utf8");
const html = fs.readFileSync(path.join(WEB, "index.html"), "utf8");
const appSrc = fs.readFileSync(path.join(WEB, "app.js"), "utf8");

let fail = 0;
function ok(name) { console.log("PASS  " + name); }
function bad(name, detail) { console.log("FAIL  " + name + (detail ? " :: " + detail : "")); fail = 1; }
function chk(name, actual, expected) {
  if (actual === expected) ok(name);
  else bad(name, "expect=[" + expected + "] got=[" + actual + "]");
}

function hasHan(s) {
  for (let n = 0; n < s.length; n++) {
    const c = s.charCodeAt(n);
    if ((c >= 0x4e00 && c <= 0x9fff) || (c >= 0x3000 && c <= 0x303f)) return true;
  }
  return false;
}
function collapse(s) { return s.replace(/\s+/g, " ").trim(); }

// ---------- 1. 取出 DICT ----------
const start = i18nSrc.indexOf("var DICT = {");
if (start < 0) { bad("找不到 DICT"); process.exit(1); }
const braceAt = i18nSrc.indexOf("{", start);
let depth = 0;
let end = braceAt;
for (; end < i18nSrc.length; end++) {
  const c = i18nSrc[end];
  if (c === "{") depth++;
  else if (c === "}") { depth--; if (depth === 0) { end++; break; } }
}
const dict = eval("(" + i18nSrc.slice(braceAt, end) + ")");
const keys = Object.keys(dict);
const exact = {};
const pats = [];
for (const k of keys) {
  if (k.indexOf("%s") >= 0) pats.push(k);
  else exact[k] = dict[k];
}
pats.sort((a, b) => b.split("%s")[0].length - a.split("%s")[0].length);

function covered(text) {
  const core = collapse(text);
  if (!core || !hasHan(core)) return true;
  if (exact[core] !== undefined) return true;
  for (const p of pats) {
    const parts = p.split("%s");
    if (core.indexOf(parts[0]) !== 0) continue;
    let pos = parts[0].length, okp = true;
    const args = [];
    for (let j = 1; j < parts.length; j++) {
      const seg = parts[j];
      const at = j === parts.length - 1 ? (seg === "" ? core.length : core.lastIndexOf(seg)) : core.indexOf(seg, pos);
      if (at < pos) { okp = false; break; }
      args.push(core.slice(pos, at));
      pos = at + seg.length;
    }
    if (okp && pos === core.length && args.every((a) => covered(a))) return true;
  }
  return false;
}

// ---------- 2. 词典自身 ----------
let badVal = 0;
for (const k of keys) {
  if (typeof dict[k] !== "string" || !dict[k]) { bad("译文为空：" + k); badVal = 1; continue; }
  if (hasHan(dict[k])) { bad("译文仍是中文：" + k + " -> " + dict[k]); badVal = 1; }
}
if (!badVal) ok("译文均为非中文（" + keys.length + " 条）");

// ---------- 3. index.html 覆盖 ----------
function decode(s) {
  return s.replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, String.fromCharCode(34)).replace(/&#39;/g, String.fromCharCode(39)).replace(/&amp;/g, "&");
}
const stripped = html.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ")
  .replace(/<!--[\s\S]*?-->/g, " ");
const textNodes = stripped.split(/<[^>]*>/).map(decode).map((s) => s.trim()).filter(Boolean);
// 昵称不翻译
const NAME_ALLOW = ["旧梦一场雨"];
const missHtml = textNodes.filter((t) => NAME_ALLOW.indexOf(t) < 0 && !covered(t));
chk("index.html 文案全部有译文", missHtml.length, 0);
missHtml.slice(0, 12).forEach((t) => console.log("      未覆盖：" + JSON.stringify(t)));

const ATT_ALLOW = ["页面导航", "留空不生效", "如 6.6.99-custom", "如 #1 SMP PREEMPT",
  "# 每行一个挂载前缀", "# 每行一个路径", "# 每行一个文件路径，如 /data/adb/modules/xxx/lib.so"];
const attrRe = /\b(placeholder|title|aria-label)="([^"]*)"/g;
const missAttr = [];
let m;
while ((m = attrRe.exec(stripped))) {
  const t = decode(m[2]).trim();
  if (hasHan(t) && ATT_ALLOW.indexOf(t) < 0) missAttr.push(t);
}
chk("index.html 占位符有译文", missAttr.length, 0);
missAttr.slice(0, 8).forEach((t) => console.log("      未覆盖：" + JSON.stringify(t)));

// ---------- 4. app.js 覆盖 ----------
// 这两类是拼在别处的片段，整段由 tr()/模式覆盖，单独不翻译：
const FRAGMENT_ALLOW = ["请等待", "当前内核:", "日志原因:", "累计失败次数:"];
function literals(src) {
  const out = [];
  let n = 0;
  const TICK = String.fromCharCode(96);
  const DQ = String.fromCharCode(34);
  const SQ = String.fromCharCode(39);
  const BS = String.fromCharCode(92);
  while (n < src.length) {
    const c = src[n];
    if (c === "/" && src[n + 1] === "/") { while (n < src.length && src[n] !== String.fromCharCode(10)) n++; continue; }
    if (c === "/" && src[n + 1] === "*") { n += 2; while (n + 1 < src.length && !(src[n] === "*" && src[n + 1] === "/")) n++; n += 2; continue; }
    if (c === DQ || c === SQ || c === TICK) {
      const q = c;
      const st = ++n;
      while (n < src.length && src[n] !== q) { if (src[n] === BS) n++; n++; }
      out.push(src.slice(st, n));
      n++;
      continue;
    }
    n++;
  }
  return out;
}
const BS = String.fromCharCode(92);
const missApp = [];
for (const raw of literals(appSrc).filter(hasHan)) {
  let s = raw.replace(/\$\{[^}]*\}/g, "%s");
  s = s.replace(new RegExp(BS + BS + "n", "g"), String.fromCharCode(10));
  s = s.replace(/<[^>]*>/g, " ");
  for (const line of s.split(String.fromCharCode(10))) {
    const core = collapse(line);
    if (!core || !hasHan(core)) continue;
    if (FRAGMENT_ALLOW.indexOf(core) >= 0) continue;
    if (!covered(core)) missApp.push(core);
  }
}
chk("app.js 渲染文案全部有译文", missApp.length, 0);
missApp.slice(0, 15).forEach((t) => console.log("      未覆盖：" + JSON.stringify(t)));

// ---------- 4b. 行内标签拼接后的英文空格 ----------
// 中文可以「仅用于<b>伪回锁</b>设备」直接拼接，英文必须在片段之间留空格。
const srcTrans = {};
const startIdx = i18nSrc.indexOf("var DICT = {");
const braceIdx = i18nSrc.indexOf("{", startIdx);
let d2 = 0;
let e2 = braceIdx;
for (; e2 < i18nSrc.length; e2++) {
  const c = i18nSrc[e2];
  if (c === "{") d2++;
  else if (c === "}") { d2--; if (d2 === 0) { e2++; break; } }
}
const dict2 = eval("(" + i18nSrc.slice(braceIdx, e2) + ")");
function trEn(t) {
  const core = collapse(t);
  if (!core || !hasHan(core)) return core;
  if (typeof dict2[core] === "string") return dict2[core];
  for (const k of Object.keys(dict2)) {
    if (k.indexOf("%s") < 0) continue;
    const pre = k.split("%s")[0];
    if (pre && core.indexOf(pre) === 0) return dict2[k].replace("%s", core.slice(pre.length));
  }
  return core;
}
const HTML_BLOCKS = html.match(/<(?:p|li|h2)\b[^>]*>[\s\S]*?<\/(?:p|li|h2)>/gi) || [];
const HAN = (s) => hasHan(s);
let joinBad = 0;
for (const blk of HTML_BLOCKS) {
  const inner = blk.replace(/^<[^>]*>/, "").replace(/<\/[^>]*>$/, "");
  const toks = [];
  const re = /<([a-zA-Z0-9]+)[^>]*>([\s\S]*?)<\/\1>|([^<]+)/g;
  let mm;
  while ((mm = re.exec(inner))) {
    const text = mm[2] !== undefined ? mm[2].replace(/<[^>]*>/g, " ") : mm[3];
    if (text === undefined || !text.trim()) continue;
    toks.push({ raw: text, en: trEn(text) });
  }
  for (let n = 0; n + 1 < toks.length; n++) {
    const a = toks[n];
    const b = toks[n + 1];
    const gap = /\s$/.test(a.raw) || /^\s/.test(b.raw);
    if (gap) continue;
    const left = a.en;
    const right = b.en;
    if (!left || !right) continue;
    if (!HAN(a.raw) && !HAN(b.raw)) continue;
    if (/[A-Za-z]$/.test(left) && /^[A-Za-z]/.test(right)) {
      joinBad++;
      console.log("      缺空格：" + JSON.stringify(left.slice(-24)) + " + " + JSON.stringify(right.slice(0, 24)));
    }
  }
}
chk("行内标签拼接后英文有空格", joinBad, 0);

// ---------- 5. 翻译引擎行为 ----------
const store = {};
const sandbox = {
  window: {},
  navigator: { language: "en-US" },
  localStorage: { getItem: (k) => (store[k] === undefined ? null : store[k]), setItem: (k, v) => { store[k] = String(v); } },
  document: {
    body: null,
    title: "LKM SUSFS管理器",
    documentElement: { setAttribute() {} },
    addEventListener() {},
  },
  MutationObserver: function () { this.observe = function () {}; },
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(i18nSrc, sandbox);
const i18n = sandbox.window.i18n;
if (!i18n) { bad("i18n 未导出"); process.exit(1); }

i18n.apply();
chk("默认语言跟随系统（en）", i18n.lang, "en");
chk("单条翻译", i18n.t("确定"), "OK");
chk("带数字的整句", i18n.tl("已追加 3 项，记得点保存"), "Added 3 item(s); remember to save");
chk("嵌套错误文案", i18n.tl("操作失败：命令超时（90 秒）"), "Operation failed: Command timed out (90s)");
chk("版本号模式", i18n.tl("模块 v1.2.2"), "Module v1.2.2");
chk("运行描述模式", i18n.tl("✅ 运行中 | 3 条规则 | 6.6.77 | v2.3.0-r18.8"), "✅ Running | 3 rules | 6.6.77 | v2.3.0-r18.8");
chk("未收录中文保持原样", i18n.tl("这句没翻译"), "这句没翻译");
chk("英文原样返回", i18n.tl("Load & apply"), "Load & apply");
chk("多行逐行翻译", i18n.tl("怎么处理:" + String.fromCharCode(10) + "确定"), "How to fix:" + String.fromCharCode(10) + "OK");
chk("前后空白保留", i18n.tl(" 确定 "), " OK ");
i18n.apply("zh");
chk("切回中文时不做替换", i18n.t("确定"), "确定");
chk("中文模式语言值", i18n.lang, "zh");

if (fail) { console.log("I18N_FAIL"); process.exit(1); }
console.log("I18N_OK");
