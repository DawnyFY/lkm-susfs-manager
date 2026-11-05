// SPDX-License-Identifier: GPL-2.0-only
// 轻量 i18n：首次加载按系统语言选择，用户可在「关于」页手动切换。
(function () {
  const ZH = {
    "LKM SUSFS管理器": "LKM SUSFS Manager",
    "自动匹配内核 · 一键加载 · 规则管理": "Auto-detect kernel · One-tap load · Rule management",
    "检测中": "Checking",
    "状态": "Status",
    "配置": "Config",
    "日志": "Logs",
    "关于": "About",
    "当前内核": "Current kernel",
    "读取中…": "Loading…",
    "加载并应用": "Load & Apply",
    "仅应用配置": "Apply only",
    "刷新": "Refresh",
    "LKM 状态": "LKM status",
    "sus_path 规则": "sus_path rules",
    "kernelsu 隐藏": "KernelSU hidden",
    "自动加载": "Auto load",
    "手动确认 BL 已解锁": "Confirm BL unlocked",
    "管理器": "Manager",
    "LKM 变体": "LKM variant",
    "ksu_susfs 路径": "ksu_susfs path",
    "WebUI 标记": "WebUI marker",
    "连续失败次数": "Consecutive failures",
    "模块版本": "Module version",
    "工作方式": "How it works",
    "开关": "Switches",
    "预设隐藏项": "Preset hidden items",
    "开机自动加载并应用": "Load and apply on boot",
    "隐藏 SUS 挂载点（非 root 进程）": "Hide SUS mounts (non-root)",
    "AVC 日志伪装": "AVC log spoofing",
    "应用时清理本模块上次写入的 sus_path 规则": "Clear this module's previous sus_path rules on apply",
    "隐藏 KSU LOOP 挂载": "Hide KSU LOOP mounts",
    "隐藏 REVANCED / YouTube 模块路径": "Hide REVANCED / YouTube paths",
    "隐藏自定义 ROM 路径": "Hide custom ROM paths",
    "隐藏 COMPAT MATRIX": "Hide COMPAT MATRIX",
    "隐藏 GAPPS": "Hide GAPPS",
    "强制隐藏 DEX2OAT 缓存": "Force hide DEX2OAT cache",
    "绕过 Scene 痕迹": "Bypass Scene traces",
    "重扫 Scene": "Rescan Scene",
    "自动 try_umount（模块挂载）": "Auto try_umount (module mounts)",
    "强制指定 KMI": "Force KMI",
    "自动匹配（推荐）": "Auto match (recommended)",
    "伪装 CMDLINE": "Spoof CMDLINE",
    "CMDLINE 伪装内容": "CMDLINE spoof value",
    "伪装内核版本（uname）": "Spoof kernel version (uname)",
    "保存并应用": "Save & apply",
    "保存": "Save",
    "重置": "Reset",
    "恢复默认配置": "Restore defaults",
    "操作失败": "Operation failed",
    "保存成功": "Saved",
    "已应用": "Applied",
    "运行中": "Running",
    "未加载": "Not loaded",
    "已加载": "Loaded",
    "已隐藏": "Hidden",
    "开启": "On",
    "关闭": "Off",
    "关于本模块": "About this module",
    "语言": "Language",
    "中文": "Chinese",
    "English": "English",
  };
  const EN = Object.fromEntries(Object.entries(ZH).map(([k, v]) => [k, v]));

  const dict = ZH;
  let lang = "zh";

  function detect() {
    const saved = localStorage.getItem("lang");
    if (saved === "zh" || saved === "en") return saved;
    const nav = (navigator.language || "zh").toLowerCase();
    return nav.startsWith("zh") ? "zh" : "en";
  }

  function translateText(node) {
    const raw = node.nodeValue;
    if (!raw) return;
    const t = raw.trim();
    if (!t || !ZH[t]) return;
    const translated = lang === "en" ? EN[t] : (Object.keys(ZH).find(k => ZH[k] === t) || t);
    if (translated !== t) node.nodeValue = raw.replace(t, translated);
  }

  function walk(node) {
    if (node.nodeType === 3) { translateText(node); return; }
    if (node.nodeType !== 1) return;
    for (const attr of ["placeholder", "title", "aria-label"]) {
      const v = node.getAttribute && node.getAttribute(attr);
      if (v && ZH[v.trim()]) {
        const t = v.trim();
        node.setAttribute(attr, lang === "en" ? EN[t] : t);
      }
    }
    for (const c of Array.from(node.childNodes)) walk(c);
  }

  function apply(next) {
    lang = next || detect();
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
    walk(document.body);
    localStorage.setItem("lang", lang);
  }

  window.i18n = { apply, get lang() { return lang; }, t: (s) => (lang === "en" && EN[s]) ? EN[s] : s };
  document.addEventListener("DOMContentLoaded", () => apply());
})();
