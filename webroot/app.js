"use strict";

const CTL = "sh /data/adb/modules/susfs_allinone/ctl.sh";
const FILE_IDS = {
  sus_path: "susPath",
  hide_modules: "hideModules",
  sus_mount: "susMount",
  try_umount: "tryUmount",
};

let execSeq = 0;
let busy = false;
let statusData = {};

const $ = (id) => document.getElementById(id);

function exec(cmd) {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== "function") {
      reject(new Error("当前页面不在 SukiSU WebUI 中运行"));
      return;
    }
    const cb = `susfs_allinone_cb_${Date.now()}_${execSeq++}`;
    let settled = false;
    let timer = 0;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      try { delete window[cb]; } catch (_) {}
      fn(value);
    };
    timer = setTimeout(() => finish(reject, new Error("命令超时（90 秒）")), 90000);
    window[cb] = (errno, stdout, stderr) => {
      if (Number(errno) === 0) finish(resolve, stdout || "");
      else finish(reject, new Error((stderr || stdout || `命令失败 (${errno})`).trim()));
    };
    try {
      window.ksu.exec(cmd, "{}", cb);
    } catch (e) {
      finish(reject, e);
    }
  });
}

function toast(message) {
  try {
    if (window.ksu && typeof window.ksu.toast === "function") window.ksu.toast(message);
  } catch (_) {}
}

function parseKV(text) {
  const out = {};
  String(text || "").split(/\r?\n/).forEach((line) => {
    const i = line.indexOf("=");
    if (i > 0) out[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  });
  return out;
}

function b64EncodeUnicode(str) {
  const bytes = new TextEncoder().encode(String(str));
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function ask(message) {
  return new Promise((resolve) => {
    const modal = $("modal");
    if (!modal) {
      resolve(false);
      return;
    }
    const ok = $("modalOk");
    const cancel = $("modalCancel");
    const text = $("modalText");
    const close = (value) => {
      modal.classList.add("hidden");
      ok.removeEventListener("click", onOk);
      cancel.removeEventListener("click", onCancel);
      modal.removeEventListener("click", onBackdrop);
      document.removeEventListener("keydown", onKey);
      resolve(value);
    };
    const onOk = () => close(true);
    const onCancel = () => close(false);
    const onBackdrop = (event) => {
      if (event.target === modal) close(false);
    };
    const onKey = (event) => {
      if (event.key === "Escape") close(false);
    };
    text.textContent = message;
    modal.classList.remove("hidden");
    ok.addEventListener("click", onOk);
    cancel.addEventListener("click", onCancel);
    modal.addEventListener("click", onBackdrop);
    document.addEventListener("keydown", onKey);
  });
}

function setBusy(btn, on) {
  if (!btn) return;
  if (on) {
    if (!btn.dataset.originalText) btn.dataset.originalText = btn.textContent;
    btn.textContent = "处理中…";
    btn.disabled = true;
  } else {
    btn.disabled = false;
    if (btn.dataset.originalText) {
      btn.textContent = btn.dataset.originalText;
      delete btn.dataset.originalText;
    }
  }
}

function showBanner(message, type = "ok", timeout = 0) {
  const el = $("banner");
  if (!el) return;
  el.textContent = message;
  el.className = `banner ${type}`;
  if (showBanner.timer) clearTimeout(showBanner.timer);
  if (timeout) showBanner.timer = setTimeout(() => el.classList.add("hidden"), timeout);
}

function setText(id, value) {
  const el = $(id);
  if (el) el.textContent = value === undefined || value === null || value === "" ? "—" : String(value);
}

function setState(id, ok) {
  const el = $(id);
  if (el) el.dataset.state = ok ? "ok" : "bad";
}

function waitForKsu(timeout = 2500) {
  if (window.ksu) return Promise.resolve(true);
  return new Promise((resolve) => {
    const start = Date.now();
    const timer = setInterval(() => {
      if (window.ksu || Date.now() - start > timeout) {
        clearInterval(timer);
        resolve(!!window.ksu);
      }
    }, 50);
  });
}

function renderStatus() {
  const s = statusData;
  const present = s.lkm_present === "1";
  const pill = $("statusPill");
  if (pill) {
    pill.textContent = present ? "运行中" : "未加载";
    pill.className = `pill ${present ? "pill-on" : "pill-off"}`;
  }
  setText("kernel", s.kernel || "未知内核");
  setText("kmiChip", `KMI ${s.kmi || "—"}`);
  setText("versionChip", `LKM ${s.lkm_version || "—"}`);
  setText("statLkm", present ? "已加载" : "未加载");
  setState("statLkm", present);
  setText("statRules", s.rules || "0");
  setText("statHide", s.hide_kernelsu === "1" ? "已隐藏" : "未隐藏");
  setState("statHide", s.hide_kernelsu === "1");
  setText("statAuto", s.auto_load === "1" ? "开启" : "关闭");
  const binOk = s.ksu_bin === "ok";
  setText("statBin", binOk ? "正常" : s.ksu_bin === "incompatible" ? "不兼容" : "缺失");
  setState("statBin", binOk);
  setText("statSelinux", s.selinux || "—");
  setText("rootManager", s.root_manager || "—");
  setText("variant", s.lkm_variant || "—");
  setText("binPath", s.ksu_bin_path || "—");
  setText("marker", s.marker === "1" ? "已创建" : "未创建");
  setText("fails", s.fail_count || "0");
  setText("moduleVersion", s.module_version ? `v${s.module_version}` : "—");
  setText("footerVersion", s.module_version ? `模块 v${s.module_version}` : "模块 v1.1.0");
  setText("footerKernel", s.kernel || "");
  setText("subtitle", s.description || "自动匹配内核 · 一键加载 · 规则管理");
}

async function refreshStatus() {
  statusData = parseKV(await exec(`${CTL} status`));
  renderStatus();
}

async function loadConfig() {
  const cfg = parseKV(await exec(`${CTL} get_config`));
  const auto = cfg.auto_load === undefined ? "1" : cfg.auto_load;
  const hide = cfg.hide_sus_mnts === undefined ? "1" : cfg.hide_sus_mnts;
  const avc = cfg.avc_spoof === undefined ? "0" : cfg.avc_spoof;
  const replace = cfg.replace_rules === undefined ? "1" : cfg.replace_rules;
  $("autoLoad").checked = auto === "1";
  $("hideSusMnts").checked = hide === "1";
  $("avcSpoof").checked = avc === "1";
  $("replaceRules").checked = replace === "1";

  for (const name of Object.keys(FILE_IDS)) {
    try {
      $(FILE_IDS[name]).value = await exec(`${CTL} get_file ${name}`);
    } catch (e) {
      $(FILE_IDS[name]).value = "";
    }
  }
}

async function refreshLog() {
  const out = await exec(`${CTL} log`);
  $("log").textContent = out && out.trim() ? out : "暂无日志。";
}

async function runLoad() {
  showBanner("正在加载 LKM 并应用配置…", "info");
  await exec(`${CTL} load`);
  await refreshStatus();
  await loadConfig();
  showBanner("加载并应用完成。", "ok", 5000);
  toast("加载并应用完成");
}

async function runApply() {
  showBanner("正在应用配置…", "info");
  await exec(`${CTL} apply`);
  await refreshStatus();
  showBanner("配置已应用。", "ok", 5000);
  toast("配置已应用");
}

async function saveConfig() {
  showBanner("正在保存并应用…", "info");
  const auto = $("autoLoad").checked ? 1 : 0;
  const configText = [
    "# LKM SUSFS管理器配置",
    `auto_load=${auto}`,
    `hide_sus_mnts=${$("hideSusMnts").checked ? 1 : 0}`,
    `avc_spoof=${$("avcSpoof").checked ? 1 : 0}`,
    `replace_rules=${$("replaceRules").checked ? 1 : 0}`,
    "",
  ].join("\n");

  await exec(`${CTL} set_config '${b64EncodeUnicode(configText)}'`);
  await exec(`${CTL} set_auto ${auto}`);
  for (const name of Object.keys(FILE_IDS)) {
    await exec(`${CTL} set_file ${name} '${b64EncodeUnicode($(FILE_IDS[name]).value)}'`);
  }
  await exec(`${CTL} apply`);
  await refreshStatus();
  await loadConfig();
  showBanner("配置已保存并应用。", "ok", 5000);
  toast("配置已保存并应用");
}

async function importLegacy() {
  if (!(await ask("导入旧 susfs4ksu 配置会覆盖当前的 sus_path / sus_mount / try_umount，继续？"))) return;
  showBanner("正在导入旧配置…", "info");
  await exec(`${CTL} import_legacy`);
  await loadConfig();
  await refreshStatus();
  showBanner("旧配置已导入。检查后点“保存并应用”即可生效。", "ok", 7000);
  toast("旧配置已导入");
}

async function resetDefaults() {
  if (!(await ask("恢复默认会覆盖当前所有规则配置，继续？"))) return;
  showBanner("正在恢复默认…", "info");
  await exec(`${CTL} reset_defaults`);
  await loadConfig();
  await refreshStatus();
  showBanner("已恢复默认配置。点“保存并应用”可立即生效。", "ok", 7000);
  toast("已恢复默认");
}

async function withBusy(btn, fn) {
  if (busy) return;
  busy = true;
  setBusy(btn, true);
  try {
    await fn();
  } catch (e) {
    showBanner(`操作失败：${e.message}`, "error");
  } finally {
    busy = false;
    setBusy(btn, false);
  }
}

function initTabs() {
  document.querySelectorAll(".tab").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab").forEach((b) => b.classList.toggle("active", b === btn));
      document.querySelectorAll(".tab-panel").forEach((p) => {
        p.classList.toggle("active", p.id === `tab-${btn.dataset.tab}`);
      });
      if (btn.dataset.tab === "log") {
        refreshLog().catch((e) => {
          $("log").textContent = `读取日志失败：${e.message}`;
        });
      }
    });
  });
}

function bind() {
  $("btnLoad").addEventListener("click", (e) => withBusy(e.currentTarget, runLoad));
  $("btnApply").addEventListener("click", (e) => withBusy(e.currentTarget, runApply));
  $("btnRefresh").addEventListener("click", (e) => withBusy(e.currentTarget, async () => {
    await refreshStatus();
    showBanner("状态已刷新。", "ok", 3000);
  }));
  $("btnSave").addEventListener("click", (e) => withBusy(e.currentTarget, saveConfig));
  $("btnImport").addEventListener("click", (e) => withBusy(e.currentTarget, importLegacy));
  $("btnReset").addEventListener("click", (e) => withBusy(e.currentTarget, resetDefaults));
  $("btnLog").addEventListener("click", (e) => withBusy(e.currentTarget, refreshLog));
}

async function init() {
  initTabs();
  bind();
  if (!(await waitForKsu())) {
    showBanner("请在 SukiSU 的 WebUI 中打开本页面。", "error");
    $("log").textContent = "无法连接 root 通道。";
    return;
  }
  try {
    await refreshStatus();
    await loadConfig();
    await refreshLog();
  } catch (e) {
    showBanner(`初始化失败：${e.message}`, "error");
  }
}

document.addEventListener("DOMContentLoaded", init);
