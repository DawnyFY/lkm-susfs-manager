/* SPDX-License-Identifier: GPL-2.0-only */
"use strict";

const CTL = "sh /data/adb/modules/susfs_allinone/ctl.sh";
const ANNOUNCEMENT_URL = "https://susfs.stdawns.top/announcement.json";
const ANNOUNCEMENT_TTL = 60 * 1000;
const ANNOUNCEMENT_CACHE_KEY = "susfs_announcement_cache_v1";
const ANNOUNCEMENT_ATTEMPT_KEY = "susfs_announcement_attempt_v1";
const FILE_IDS = {
  sus_path: "susPath",
  sus_path_loop: "susPathLoop",
  hide_modules: "hideModules",
  sus_mount: "susMount",
  try_umount: "tryUmount",
  skip_hide: "skipHide",
  sus_map: "susMap",
};

let execSeq = 0;
let busy = false;
let statusData = {};
// 手动覆盖管理器显示名（配置项 manager_name）
let managerName = "";
// 当前配置原文：保存时以它为基底，保留未识别的键与注释
let rawConfigText = "";
// 加载时的 replace_rules 原值，用于保留 2（整表清空）这种 UI 无法表达的取值
let originalReplace = "0";
// 规则文件是否读取成功；失败时禁止保存
let filesLoaded = false;
let warnedReplace2 = false;

const $ = (id) => document.getElementById(id);

// 与 exec 相同，但返回 {code, stdout, stderr}；用于允许 0/5 的部分成功路径。
function execCode(cmd) {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== "function") {
      reject(new Error("当前页面不在 SukiSU WebUI 中运行"));
      return;
    }
    const cb = "susfs_allinone_cb_" + Date.now() + "_" + (execSeq++);
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
      finish(resolve, { code: Number(errno), stdout: stdout || "", stderr: stderr || "" });
    };
    try {
      window.ksu.exec(cmd, "{}", cb);
    } catch (e) {
      finish(reject, e);
    }
  });
}

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

// 把 updates 合并进原始配置文本：已知键替换值，未知键与注释原样保留
function mergeConfigText(raw, updates) {
  const seen = new Set();
  const out = [];
  const lines = String(raw || "").split(/\r?\n/);
  for (const line of lines) {
    const m = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(line);
    if (m && Object.prototype.hasOwnProperty.call(updates, m[1])) {
      out.push(`${m[1]}=${updates[m[1]]}`);
      seen.add(m[1]);
    } else {
      out.push(line);
    }
  }
  for (const key of Object.keys(updates)) {
    if (!seen.has(key)) out.push(`${key}=${updates[key]}`);
  }
  while (out.length && out[out.length - 1] === "") out.pop();
  return out.join("\n") + "\n";
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

// 弹窗打开时锁住背景滚动，避免只滑动到下层页面
let modalLock = 0;
function lockBackground() {
  modalLock += 1;
  document.body.classList.add("modal-open");
}
function unlockBackground() {
  modalLock = Math.max(0, modalLock - 1);
  if (modalLock === 0) document.body.classList.remove("modal-open");
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
      unlockBackground();
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
    text.textContent = tr(message);
    lockBackground();
    modal.classList.remove("hidden");
    ok.addEventListener("click", onOk);
    cancel.addEventListener("click", onCancel);
    modal.addEventListener("click", onBackdrop);
    document.addEventListener("keydown", onKey);
  });
}

// 高风险确认：确定按钮倒计时 seconds 秒后才可点击
function confirmDanger(title, message, seconds) {
  return new Promise((resolve) => {
    const modal = $("modal");
    if (!modal) { resolve(false); return; }
    const ok = $("modalOk");
    const cancel = $("modalCancel");
    const text = $("modalText");
    const heading = $("modalTitle");
    let timer = null;
    const cleanup = () => {
      if (timer) clearInterval(timer);
      timer = null;
      modal.classList.add("hidden");
      unlockBackground();
      ok.removeEventListener("click", onOk);
      cancel.removeEventListener("click", onCancel);
      ok.disabled = false;
      ok.textContent = tr("确定");
      heading.textContent = tr("确认操作");
    };
    const close = (v) => { cleanup(); resolve(v); };
    const onOk = () => close(true);
    const onCancel = () => close(false);
    heading.textContent = tr(title);
    text.textContent = tr(message);
    lockBackground();
    modal.classList.remove("hidden");
    let left = seconds;
    ok.disabled = true;
    ok.textContent = tr("请等待 " + left + "s");
    timer = setInterval(() => {
      left -= 1;
      if (left <= 0) {
        clearInterval(timer);
        timer = null;
        ok.disabled = false;
        ok.textContent = tr("我已了解风险，继续");
      } else {
        ok.textContent = tr("请等待 " + left + "s");
      }
    }, 1000);
    ok.addEventListener("click", onOk);
    cancel.addEventListener("click", onCancel);
  });
}

// 白名单标记位（目前只有 force_bl_unlocked）
async function setFlag(key, value) {
  const out = (await exec(`${CTL} set_flag ${key} ${value}`)).trim();
  if (!out.includes("saved")) throw new Error(out || "set_flag failed");
  await refreshStatus();
}

function showIntegrityWarning() {
  const modal = $("integrityModal");
  if (!modal) return;
  const ok = $("integrityOk");
  const close = () => {
    modal.classList.add("hidden");
    unlockBackground();
    ok.removeEventListener("click", close);
  };
  lockBackground();
  modal.classList.remove("hidden");
  ok.addEventListener("click", close);
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

// 界面文案统一走 i18n（英文模式下翻译，中文模式下原样返回）
function tr(text) {
  return window.i18n ? window.i18n.tl(text) : text;
}

function showBanner(message, type = "ok", timeout = 0) {
  const el = $("banner");
  if (!el) return;
  el.textContent = tr(message);
  el.className = `banner ${type}`;
  if (showBanner.timer) clearTimeout(showBanner.timer);
  if (timeout) showBanner.timer = setTimeout(() => el.classList.add("hidden"), timeout);
}

function setText(id, value) {
  const el = $(id);
  if (el) el.textContent = value === undefined || value === null || value === "" ? "—" : tr(String(value));
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
  const builtin = s.susfs_kernel === "builtin" || s.backend_kind === "builtin";
  const present = s.lkm_present === "1";
  const pill = $("statusPill");
  if (pill) {
    pill.textContent = builtin ? "内置" : (present ? "运行中" : "未加载");
    pill.className = "pill " + ((builtin || present) ? "pill-on" : "pill-off");
  }
  setText("kernel", s.kernel || "未知内核");
  setText("kmiChip", "KMI " + (s.kmi || "—"));
  setText("versionChip", builtin ? "内置 SUSFS" : ("LKM " + (s.lkm_version || "—")));
  setText("statLkm", builtin ? "内置 SUSFS" : (present ? "已加载" : "未加载"));
  setState("statLkm", builtin || present);
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
  if (s.integrity === "modified" && !sessionStorage.getItem("integrityWarned")) {
    sessionStorage.setItem("integrityWarned", "1");
    showIntegrityWarning();
  }
  // APatch / KernelPatch 状态卡片（只在检测到 APatch/KernelPatch 时显示）
  const kpActive = s.kernelpatch === "1" || s.apatch_userland === "1" || s.root_manager === "APatch";
  const kpCard = $("apatchCard");
  if (kpCard) kpCard.style.display = kpActive ? "" : "none";
  if (kpActive) {
    const allow = s.allow_lkm === "1";
    setText("apatchUserland", s.apatch_userland === "1" ? "是" : "否");
    setText("kernelpatchKernel", s.kernelpatch_kernel === "1" ? ("已激活" + (s.kernelpatch_version ? " (" + s.kernelpatch_version + ")" : "")) : (s.kernelpatch_kernel || "未知"));
    setText("coexistMode", s.coexist_mode || "none");
    setText("allowLkm", allow ? "已放行" : "未放行");
    const btn = $("btnAllowLkm");
    if (btn) btn.textContent = allow ? "取消放行" : "放行 LKM";
  }
  setText("moduleVersion", s.module_version ? `v${s.module_version}` : "—");
  setText("footerVersion", s.module_version ? `模块 v${s.module_version}` : "模块版本未知");
  setText("footerKernel", s.kernel || "");
  setText("subtitle", s.description || "自动匹配内核 · 一键加载 · 规则管理");
}

// 仅解锁 BL 可用的选项：临时 root 下整组隐藏，避免误导
function applyBlVisibility() {
  const group = $("blOnlyGroup");
  if (!group) return;
  const unlocked = statusData && statusData.bootloader === "unlocked";
  group.style.display = unlocked ? "" : "none";
}

async function refreshStatus() {
  statusData = parseKV(await exec(`${CTL} status`));
  renderStatus();
  applyBlVisibility();
}

async function loadConfig() {
  rawConfigText = await exec(`${CTL} get_config`);
  const cfg = parseKV(rawConfigText);
  originalReplace = cfg.replace_rules === undefined ? "0" : cfg.replace_rules;
  const auto = cfg.auto_load === undefined ? "1" : cfg.auto_load;
  const hide = cfg.hide_sus_mnts === undefined ? "1" : cfg.hide_sus_mnts;
  const avc = cfg.avc_spoof === undefined ? "0" : cfg.avc_spoof;
  const replace = originalReplace;
  const ksuLoop = cfg.hide_ksu_loop === undefined ? "0" : cfg.hide_ksu_loop;
  const revanced = cfg.hide_revanced === undefined ? "0" : cfg.hide_revanced;
  const customRom = cfg.hide_custom_rom === undefined ? "0" : cfg.hide_custom_rom;
  const compat = cfg.hide_compat_matrix === undefined ? "0" : cfg.hide_compat_matrix;
  const gapps = cfg.hide_gapps === undefined ? "0" : cfg.hide_gapps;
  const dex2oat = cfg.hide_dex2oat === undefined ? "0" : cfg.hide_dex2oat;
  const scene = cfg.hide_scene === undefined ? "0" : cfg.hide_scene;
  const autoUmount = cfg.auto_try_umount === undefined ? "0" : cfg.auto_try_umount;
  const fakeCmd = cfg.fake_cmdline === undefined ? "0" : cfg.fake_cmdline;
  const forceKmi = cfg.force_kmi || "";
  managerName = cfg.manager_name || "";
  const spoofU = cfg.spoof_uname === undefined ? "0" : cfg.spoof_uname;
  const sepolicy = cfg.hide_vendor_sepolicy === undefined ? "0" : cfg.hide_vendor_sepolicy;
  const vold = cfg.vold_isolation === undefined ? "0" : cfg.vold_isolation;
  $("autoLoad").checked = auto === "1";
  $("hideSusMnts").checked = hide === "1";
  $("avcSpoof").checked = avc === "1";
  $("replaceRules").checked = replace === "1" || replace === "2";
  const skipDet = cfg.skip_detection_paths === undefined ? "1" : cfg.skip_detection_paths;
  $("skipDetectionPaths").checked = skipDet === "1";
  // 该标记不在 config.ini 里，由 status 输出
  $("forceBlUnlocked").checked = (statusData && statusData.force_bl_unlocked === "1");
  $("hideKsuLoop").checked = ksuLoop === "1";
  $("hideRevanced").checked = revanced === "1";
  $("hideCustomRom").checked = customRom === "1";
  $("hideCompatMatrix").checked = compat === "1";
  $("hideGapps").checked = gapps === "1";
  $("hideDex2oat").checked = dex2oat === "1";
  $("hideScene").checked = scene === "1";
  $("autoTryUmount").checked = autoUmount === "1";
  // 真实分区过滤不可关闭，始终勾选
  $("skipLegitMounts").checked = true;
  $("fakeCmdline").checked = fakeCmd === "1";
  $("hideVendorSepolicy").checked = sepolicy === "1";
  $("voldIsolation").checked = vold === "1";
  $("fakeCmdlineValue").value = cfg.fake_cmdline_value || "";

  // 强制 KMI 用下拉：选项来自模块实际打包的 .ko，避免手输拼错
  try {
    const kmis = (await exec(`${CTL} list_kmis`))
      .split("\n")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    const sel = $("forceKmi");
    sel.innerHTML = '<option value="">自动匹配（推荐）</option>';
    for (const k of kmis) {
      const opt = document.createElement("option");
      opt.value = k;
      opt.textContent = k;
      sel.appendChild(opt);
    }
    // 配过一个已不存在的 KMI 时保留显示，提醒用户
    if (forceKmi && !kmis.includes(forceKmi)) {
      const opt = document.createElement("option");
      opt.value = forceKmi;
      opt.textContent = forceKmi + "（未打包）";
      sel.appendChild(opt);
    }
    sel.value = forceKmi || "";
  } catch (e) {
    $("forceKmi").value = forceKmi || "";
  }

  // replace_rules=2 是整表清空，容易误伤其他模块，进来时显式提醒一次
  if (originalReplace === "2" && !warnedReplace2) {
    warnedReplace2 = true;
    showBanner("⚠️ 当前 replace_rules=2：每次应用都会清空整张 sus_path 表（含其他模块的规则）", "error", 9000);
  }

  let filesOk = true;
  for (const name of Object.keys(FILE_IDS)) {
    try {
      $(FILE_IDS[name]).value = await exec(`${CTL} get_file ${name}`);
    } catch (e) {
      filesOk = false;
      $(FILE_IDS[name]).value = "";
    }
  }
  // 读取失败时禁止保存：否则一次保存会用空内容覆盖四个规则文件
  filesLoaded = filesOk;
  const saveBtn = $("btnSave");
  if (saveBtn) saveBtn.disabled = !filesOk;
  if (!filesOk) showBanner("规则文件读取失败，已禁用保存以免覆盖现有内容", "error", 6000);
}

function renderAnnouncement(data) {
  if (!data || typeof data !== "object") return;
  const summary = $("announceSummary");
  if (summary && typeof data.summary === "string" && data.summary.trim()) {
    summary.textContent = data.summary.trim();
  }
  const body = $("announceBody");
  if (body && Array.isArray(data.items)) {
    body.textContent = "";
    for (const item of data.items) {
      if (typeof item !== "string" || !item.trim()) continue;
      const p = document.createElement("p");
      p.textContent = item.trim();
      body.appendChild(p);
    }
  }
  const link = $("announceLink");
  if (link && typeof data.link === "string" && data.link.startsWith("https://susfs.stdawns.top/")) {
    link.href = data.link;
  }
}

// 启动时最多每分钟拉取一次；页面重载在同分钟内只读缓存，不发网络请求。
async function loadAnnouncement() {
  if (typeof fetch !== "function") return;
  let cached = null;
  try { cached = JSON.parse(localStorage.getItem(ANNOUNCEMENT_CACHE_KEY) || "null"); } catch (_) {}
  const now = Date.now();
  if (cached && cached.ts && now - cached.ts < ANNOUNCEMENT_TTL) {
    renderAnnouncement(cached.data);
    return;
  }
  let lastAttempt = 0;
  try { lastAttempt = Number(localStorage.getItem(ANNOUNCEMENT_ATTEMPT_KEY) || "0") || 0; } catch (_) {}
  if (now - lastAttempt < ANNOUNCEMENT_TTL) {
    if (cached) renderAnnouncement(cached.data);
    return;
  }
  try { localStorage.setItem(ANNOUNCEMENT_ATTEMPT_KEY, String(now)); } catch (_) {}
  const controller = typeof AbortController === "function" ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), 6000) : null;
  try {
    const res = await fetch(ANNOUNCEMENT_URL, { cache: "no-store", signal: controller ? controller.signal : undefined });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    renderAnnouncement(data);
    try { localStorage.setItem(ANNOUNCEMENT_CACHE_KEY, JSON.stringify({ ts: now, data })); } catch (_) {}
  } catch (_) {
    // 网络/解析失败时保留内置公告，不阻塞 UI；一分钟后才允许再次尝试。
    if (cached) renderAnnouncement(cached.data);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function openAnnouncement() {
  const modal = $("announceModal");
  if (!modal) return;
  modal.classList.remove("hidden");
  lockBackground();
}

function closeAnnouncement() {
  const modal = $("announceModal");
  if (!modal) return;
  modal.classList.add("hidden");
  unlockBackground();
}

async function exportLog() {
  const ok = await ask("导出文件包含隐藏路径、模块挂载点和 install_id，分享前请检查，用完建议删除。继续导出？");
  if (!ok) return;
  const out = await exec(`${CTL} export_log`);
  const lines = String(out || "").trim().split("\n").filter(Boolean);
  const path = lines.length ? lines[lines.length - 1] : "";
  if (!path || path === "export failed") throw new Error(path || "导出失败");
  showBanner(`日志已导出：${path}`, "info", 9000);
}

async function refreshLog() {
  const out = await exec(`${CTL} log`);
  $("log").textContent = out && out.trim() ? out : tr("暂无日志。");
}

function modalAlert(title, message) {
  return new Promise((resolve) => {
    const modal = $("modal");
    if (!modal) {
      console.log(title + "\n" + message);
      resolve();
      return;
    }
    const ok = $("modalOk");
    const cancel = $("modalCancel");
    const text = $("modalText");
    const titleEl = $("modalTitle");
    if (titleEl) titleEl.textContent = tr(title);
    text.textContent = tr(message);
    text.style.whiteSpace = "pre-wrap";
    if (cancel) cancel.style.display = "none";
    const close = () => {
      modal.classList.add("hidden");
      ok.removeEventListener("click", close);
      if (cancel) cancel.style.display = "";
      resolve();
    };
    ok.addEventListener("click", close);
    modal.classList.remove("hidden");
  });
}

let loadNoticeShown = false;

const LOAD_FAIL_TEXT = {
  nomatch: "没有匹配当前内核的 KMI，LKM 未加载。",
  insmod_failed: "匹配到了 .ko，但 insmod 返回错误，加载失败。",
  not_loaded: "LKM 未加载，日志里没有明确原因。"
};

// 读 loadstatus，异常时弹窗（每次打开 WebUI 只弹一次）
async function checkLoadHealth() {
  if (loadNoticeShown) return;
  let st;
  try {
    st = parseKV(await exec(`${CTL} loadstatus`));
  } catch (e) {
    return;
  }
  if (!st || !st.result || st.result === "ok") return;
  loadNoticeShown = true;
  const lines = [LOAD_FAIL_TEXT[st.result] || "LKM 未加载。", ""];
  if (st.osrelease) lines.push("当前内核: " + st.osrelease);
  if (st.reason) lines.push("日志原因: " + st.reason);
  if (st.fail_count && st.fail_count !== "0") lines.push("累计失败次数: " + st.fail_count);
  lines.push("");
  if (st.result === "nomatch") {
    lines.push("怎么处理:");
    lines.push("1. 到「配置」页，把「强制指定 KMI」选成对应版本");
    lines.push("2. 保存后点「加载并应用」");
    lines.push("3. 仍失败就把「日志」页的 load.log 发给作者");
  } else {
    lines.push("怎么处理:");
    lines.push("1. 先在管理器里禁用本模块，重启确认能正常开机");
    lines.push("2. 把 load.log 内容反馈给作者，不要反复重试");
  }
  await modalAlert("LKM 未正常加载", lines.join("\n"));
}


// 预设隐藏项：弹窗列出候选目录（不存在的也列出并标注），勾选后追加到 sus_path
async function openPresetModal() {
  const modal = $("presetModal");
  const list = $("presetList");
  if (!modal || !list) return;

  let items = [];
  try {
    const out = await exec(`${CTL} preset_paths`);
    items = out
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line.length > 0)
      .map((line) => {
        const tab = line.lastIndexOf("\t");
        if (tab < 0) return { path: line, exists: true };
        return { path: line.slice(0, tab), exists: line.slice(tab + 1) === "1" };
      });
  } catch (e) {
    showBanner(`读取预设失败：${e.message}`, "error");
    return;
  }

  const cur = $("susPath").value.split("\n").map((x) => x.trim());
  list.innerHTML = "";

  // 全选行
  const allRow = document.createElement("label");
  allRow.className = "preset-row preset-all";
  const allCb = document.createElement("input");
  allCb.type = "checkbox";
  const allSpan = document.createElement("span");
  allSpan.textContent = "全选";
  const allTag = document.createElement("em");
  allRow.appendChild(allCb);
  allRow.appendChild(allSpan);
  allRow.appendChild(allTag);
  list.appendChild(allRow);

  // 具体项
  for (const it of items) {
    const inList = cur.includes(it.path);
    const row = document.createElement("label");
    row.className = "preset-row" + (it.exists ? "" : " preset-missing");
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = it.path;
    cb.checked = it.exists && !inList;
    cb.disabled = inList;
    cb.dataset.exists = it.exists ? "1" : "0";
    const span = document.createElement("span");
    span.textContent = it.path;
    row.appendChild(cb);
    row.appendChild(span);
    const tag = document.createElement("em");
    if (inList) tag.textContent = "（已在列表）";
    else if (!it.exists) tag.textContent = "（未发现）";
    if (tag.textContent) row.appendChild(tag);
    list.appendChild(row);
  }

  const actionable = () =>
    [...list.querySelectorAll('input[type="checkbox"]')].filter(
      (c) => c !== allCb && !c.disabled && c.dataset.exists === "1"
    );

  const syncAll = () => {
    const boxes = actionable();
    const total = boxes.length;
    const checked = boxes.filter((c) => c.checked).length;
    if (total === 0) {
      allCb.checked = false;
      allCb.indeterminate = false;
      allCb.disabled = true;
      allTag.textContent = "（没有可追加的项）";
      return;
    }
    allCb.disabled = false;
    allCb.checked = checked === total;
    allCb.indeterminate = checked > 0 && checked < total;
    allTag.textContent = `${checked}/${total}`;
  };

  allCb.addEventListener("change", () => {
    const on = allCb.checked;
    actionable().forEach((c) => {
      c.checked = on;
    });
    syncAll();
  });

  list.addEventListener("change", (event) => {
    if (event.target === allCb) return;
    syncAll();
  });

  syncAll();
  lockBackground();
  modal.classList.remove("hidden");
}

function closePresetModal() {
  $("presetModal").classList.add("hidden");
  unlockBackground();
}

function applyPresetSelection() {
  const list = $("presetList");
  const picked = [...list.querySelectorAll("input[type=checkbox]")]
    .filter((c) => c.checked)
    .map((c) => c.value);
  const ta = $("susPath");
  const cur = ta.value.split("\n").map((x) => x.trim()).filter((x) => x.length > 0);
  const fresh = picked.filter((p) => !cur.includes(p));
  if (!fresh.length) { toast("没有需要追加的项"); closePresetModal(); return; }
  ta.value = [...cur, ...fresh].join("\n");
  closePresetModal();
  toast(`已追加 ${fresh.length} 项，记得点保存`);
}

async function runLoad() {
  showBanner("正在加载 LKM 并应用配置…", "info");
  const r = await execCode(CTL + " load");
  if (r.code !== 0 && r.code !== 5) {
    throw new Error((r.stderr || r.stdout || ("命令失败 (" + r.code + ")")).trim());
  }
  await refreshStatus();
  await loadConfig();
  loadNoticeShown = false;
  if (r.code === 5) {
    showBanner("加载完成，但部分规则失败；详情见日志。", "warn", 6000);
    toast("部分规则失败，详情见日志");
  } else {
    showBanner("加载并应用完成。", "ok", 5000);
    toast("加载并应用完成");
  }
  await checkLoadHealth();
}

async function runApply() {
  showBanner("正在应用配置…", "info");
  const r = await execCode(CTL + " apply");
  if (r.code !== 0 && r.code !== 5) {
    throw new Error((r.stderr || r.stdout || ("命令失败 (" + r.code + ")")).trim());
  }
  await refreshStatus();
  if (r.code === 5) {
    showBanner("配置已应用，但部分规则失败；详情见日志。", "warn", 6000);
    toast("部分规则失败，详情见日志");
  } else {
    showBanner("配置已应用。", "ok", 5000);
    toast("配置已应用");
  }
}

async function saveConfig() {
  if (!filesLoaded) {
    showBanner("规则文件未成功读取，已阻止保存", "error", 6000);
    return;
  }
  showBanner("正在保存并应用…", "info");
  const auto = $("autoLoad").checked ? 1 : 0;
  // 保留用户手写的未识别键与注释：以现有配置为基底，只更新已知键。
  // replace_rules：勾选=1；取消勾选=0；原本是 2（整表清空）且用户没取消时保留 2。
  let newReplace = $("replaceRules").checked ? "1" : "0";
  if (originalReplace === "2" && $("replaceRules").checked) newReplace = "2";
  const updates = {
    auto_load: auto,
    hide_sus_mnts: $("hideSusMnts").checked ? 1 : 0,
    avc_spoof: $("avcSpoof").checked ? 1 : 0,
    replace_rules: newReplace,
    hide_ksu_loop: $("hideKsuLoop").checked ? 1 : 0,
    hide_revanced: $("hideRevanced").checked ? 1 : 0,
    hide_custom_rom: $("hideCustomRom").checked ? 1 : 0,
    hide_compat_matrix: $("hideCompatMatrix").checked ? 1 : 0,
    hide_gapps: $("hideGapps").checked ? 1 : 0,
    hide_dex2oat: $("hideDex2oat").checked ? 1 : 0,
    hide_scene: $("hideScene").checked ? 1 : 0,
    auto_try_umount: $("autoTryUmount").checked ? 1 : 0,
    skip_legit_mounts: 1,
    skip_detection_paths: $("skipDetectionPaths").checked ? 1 : 0,
    fake_cmdline: $("fakeCmdline").checked ? 1 : 0,
    fake_cmdline_value: $("fakeCmdlineValue").value.trim(),
    force_kmi: $("forceKmi").value.trim(),
    manager_name: managerName,
    spoof_uname: $("spoofUname").checked ? 1 : 0,
    spoof_uname_release: $("spoofUnameRelease").value.trim(),
    spoof_uname_version: $("spoofUnameVersion").value.trim(),
    hide_vendor_sepolicy: $("hideVendorSepolicy").checked ? 1 : 0,
    vold_isolation: $("voldIsolation").checked ? 1 : 0,
  };
  const configText = mergeConfigText(rawConfigText, updates);

  // 一次提交 config + 5 个规则文件：避免 apply 在多次调用之间读到中间状态
  const bundleOrder = [
    configText,
    $("susPath").value,
    $("susPathLoop").value,
    $("hideModules").value,
    $("skipHide").value,
    $("susMount").value,
    $("tryUmount").value,
    $("susMap").value,
  ];
  const bundle = b64EncodeUnicode(bundleOrder.map((v) => b64EncodeUnicode(v)).join("|"));
  await exec(CTL + " set_bundle '" + bundle + "'");
  const r = await execCode(CTL + " apply");
  if (r.code !== 0 && r.code !== 5) {
    throw new Error((r.stderr || r.stdout || ("命令失败 (" + r.code + ")")).trim());
  }
  await refreshStatus();
  await loadConfig();
  if (r.code === 5) {
    showBanner("配置已保存并应用，但部分规则失败；详情见日志。", "warn", 7000);
    toast("部分规则失败，详情见日志");
  } else {
    showBanner("配置已保存并应用。", "ok", 5000);
    toast("配置已保存并应用");
  }
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

// 重新扫描 /dev 下的 Scene 痕迹并补充隐藏
async function rescanScene() {
  try {
    const out = (await exec(`${CTL} rescan_scene`)).trim();
    const hidden = out.split("\n").filter((l) => l.startsWith("hidden "));
    if (!hidden.length) {
      showBanner("没有发现新的 Scene 痕迹。", "ok", 4000);
      return;
    }
    const list = hidden.map((l) => l.replace(/^hidden\s+/, "")).join("\n");
    showBanner(`已补充隐藏 ${hidden.length} 项：\n${list}`, "ok", 6000);
    await refreshStatus();
  } catch (e) {
    showBanner(`重扫失败：${e.message}`, "error");
  }
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
      if (btn.dataset.tab === "about" && revealCheck) {
        setTimeout(revealCheck, 80);
      }
      if (btn.dataset.tab === "log") {
        refreshLog().catch((e) => {
          $("log").textContent = `读取日志失败：${e.message}`;
        });
      }
    });
  });
}

// 把说明文字和它所属的那一行视觉归组：描边移到说明下方
function attachRowHints() {
  document.querySelectorAll(".row-hint").forEach((hint) => {
    const prev = hint.previousElementSibling;
    if (!prev || !prev.classList.contains("switch-row")) return;
    prev.style.borderBottom = "none";
    hint.classList.add("hint-attached");
  });
}

function bind() {
  $("btnLoad").addEventListener("click", (e) => withBusy(e.currentTarget, runLoad));
  $("btnApply").addEventListener("click", (e) => withBusy(e.currentTarget, runApply));
  $("forceBlUnlocked").addEventListener("change", async (e) => {
    const box = e.currentTarget;
    if (!box.checked) {
      try {
        await setFlag("force_bl_unlocked", "0");
        showBanner("已关闭手动解锁标记，BL 判定恢复为读取系统属性", "ok", 5000);
      } catch (err) {
        box.checked = true;
        showBanner("写入失败：" + err.message, "error");
      }
      return;
    }
    box.checked = false;
    const ok = await confirmDanger(
      "⚠️ 确认 BL 已解锁",
      "打开后模块会永久记住「BL 已解锁」，并允许执行 vendor sepolicy 隐藏与 VOLD 隔离。\n\n" +
      "这两项会改变系统可见状态：应用可能读不到自己的 Android/data，出现异常时需关闭本开关并重新应用配置。\n\n" +
      "只在你确认设备确实已解锁 bootloader（伪回锁）时继续。",
      10
    );
    if (!ok) return;
    box.checked = true;
    try {
      await setFlag("force_bl_unlocked", "1");
      await exec(`${CTL} apply`);
      await refreshStatus();
      showBanner("已写入配置并应用：BL 视为已解锁", "ok", 6000);
    } catch (err) {
      box.checked = false;
      showBanner("写入失败：" + err.message, "error");
    }
  });
  $("btnRefresh").addEventListener("click", (e) => withBusy(e.currentTarget, async () => {
    await refreshStatus();
    showBanner("状态已刷新。", "ok", 3000);
  }));
  const btnAllowLkm = $("btnAllowLkm");
  if (btnAllowLkm) btnAllowLkm.addEventListener("click", (e) => withBusy(e.currentTarget, async () => {
    const allow = statusData.allow_lkm === "1";
    if (!allow) {
      const ok = await ask("放行后允许在 APatch/KernelPatch 内核上外挂 SUSFS LKM。这是实验性共存路径，可能与 kpimg 冲突导致启动异常；仅在明确知道风险时继续。");
      if (!ok) return;
    }
    await exec(CTL + " " + (allow ? "disallow_lkm" : "allow_lkm"));
    await refreshStatus();
    showBanner(allow ? "已取消 LKM 放行。" : "已放行 LKM；下次加载/应用会生效。", "ok", 5000);
  }));

  $("btnSave").addEventListener("click", (e) => withBusy(e.currentTarget, saveConfig));
  $("btnPreset").addEventListener("click", (e) => withBusy(e.currentTarget, openPresetModal));
  $("btnRescanScene").addEventListener("click", (e) => withBusy(e.currentTarget, rescanScene));
  $("presetCancel").addEventListener("click", closePresetModal);
  $("presetOk").addEventListener("click", applyPresetSelection);
  $("btnImport").addEventListener("click", (e) => withBusy(e.currentTarget, importLegacy));
  $("btnReset").addEventListener("click", (e) => withBusy(e.currentTarget, resetDefaults));
  $("btnAnnounce").addEventListener("click", openAnnouncement);
  $("announceClose").addEventListener("click", closeAnnouncement);
  $("announceModal").addEventListener("click", (e) => {
    if (e.target === $("announceModal")) closeAnnouncement();
  });
  $("btnLog").addEventListener("click", (e) => withBusy(e.currentTarget, refreshLog));
  $("btnExportLog").addEventListener("click", (e) => withBusy(e.currentTarget, exportLog));
}

// 启动守卫：上次加载后未能完成启动时会暂停自动加载，这里提示并支持恢复
async function checkBootGuard() {
  if (!statusData || statusData.autoload !== "paused") return;
  const yes = await ask(
    "检测到上次加载 LKM 后设备未能完成启动，已自动暂停加载。\n\n" +
    "要继续自动加载吗？如果上次是加载了不匹配的 .ko 导致重启，请先到「配置」页选对 KMI。"
  );
  if (!yes) return;
  try {
    await exec(`${CTL} resume_autoload`);
    await refreshStatus();
    showBanner("已恢复自动加载。下次开机会重新尝试。", "ok", 5000);
    toast("已恢复自动加载");
  } catch (e) {
    showBanner(`恢复失败：${e.message}`, "error");
  }
}

// 滚动/切页时触发一次进入动画（关于页贡献者）
let revealCheck = null;

function setupReveal() {
  const els = Array.from(document.querySelectorAll(".reveal"));
  if (!els.length) return;

  const show = (el) => el.classList.add("in");
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    return r.top < window.innerHeight && r.bottom > 0;
  };

  if (!("IntersectionObserver" in window)) {
    els.forEach(show);
    return;
  }

  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      show(entry.target);
      io.unobserve(entry.target);
    });
  }, { threshold: 0.18 });
  els.forEach((el) => io.observe(el));

  // 切到「关于」页时补一次检查：display 切换不一定会触发 observer
  revealCheck = () => {
    els.forEach((el) => {
      if (!el.classList.contains("in") && visible(el)) show(el);
    });
  };
}

async function init() {
  initTabs();
  bindLanguageButtons();
  setupReveal();
  attachRowHints();
  bind();
  if (!(await waitForKsu())) {
    showBanner("请在 SukiSU 的 WebUI 中打开本页面。", "error");
    $("log").textContent = tr("无法连接 root 通道。");
    return;
  }
  try {
    await refreshStatus();
    await loadConfig();
    await refreshLog();
    loadAnnouncement().catch(() => {});
    await checkLoadHealth();
    await checkBootGuard();
  } catch (e) {
    showBanner(`初始化失败：${e.message}`, "error");
  }
}


// 语言切换（i18n.js 提供 window.i18n）
// 语言切换写 localStorage 后重载页面，静态与动态文案都由页面重新渲染，避免中英混排。
function bindLanguageButtons() {
  const zh = $("langZh"), en = $("langEn");
  if (!window.i18n || !zh || !en) return;
  const cur = window.i18n.lang;
  zh.classList.toggle("primary", cur === "zh");
  en.classList.toggle("primary", cur === "en");
  const pick = (lang) => {
    try { localStorage.setItem("lang", lang); } catch (e) {}
    location.reload();
  };
  zh.addEventListener("click", () => pick("zh"));
  en.addEventListener("click", () => pick("en"));
}
document.addEventListener("DOMContentLoaded", init);