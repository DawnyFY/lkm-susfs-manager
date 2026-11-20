import { CTL, PG_CTL, b64Encode, exec, execCode, parseKV, splitLines, type ExecResult } from "./bridge";

export type RuleName =
  | "sus_path"
  | "sus_path_loop"
  | "hide_modules"
  | "skip_hide"
  | "sus_mount"
  | "try_umount"
  | "sus_map";

// set_bundle 的段顺序，必须与 ctl.sh 注释一致
export const RULE_ORDER: RuleName[] = [
  "sus_path",
  "sus_path_loop",
  "hide_modules",
  "skip_hide",
  "sus_mount",
  "try_umount",
  "sus_map",
];

export type Status = Record<string, string>;

export async function getStatus(): Promise<Status> {
  return parseKV(await exec(`${CTL} status`));
}

export async function applyRules(): Promise<ExecResult> {
  // 0 = 全成功；5 = 部分规则失败（前端按部分成功展示）
  return execCode(`${CTL} apply`);
}

export async function getConfigText(): Promise<string> {
  return exec(`${CTL} get_config`);
}

export async function getRuleText(name: RuleName): Promise<string> {
  return exec(`${CTL} get_file ${name}`);
}

const EMPTY_RULES = (): Record<RuleName, string> => ({
  sus_path: "",
  sus_path_loop: "",
  hide_modules: "",
  skip_hide: "",
  sus_mount: "",
  try_umount: "",
  sus_map: "",
});

// ctl.sh get_bundle 的输出：每行 name:b64（base64 去掉了换行）
export function parseBundle(raw: string): { config: string; rules: Record<RuleName, string> } {
  const rules: Record<RuleName, string> = EMPTY_RULES();
  let config = "";
  for (const line of splitLines(raw)) {
    const i = line.indexOf(":");
    if (i <= 0) continue;
    const name = line.slice(0, i).trim();
    const b64 = line.slice(i + 1).trim();
    let text = "";
    if (b64) {
      try {
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let k = 0; k < bin.length; k++) bytes[k] = bin.charCodeAt(k);
        text = new TextDecoder().decode(bytes);
      } catch {
        text = "";
      }
    }
    if (name === "config") config = text;
    else if (name in rules) rules[name as RuleName] = text;
  }
  return { config, rules };
}

export async function getBundle(): Promise<{ config: string; rules: Record<RuleName, string> }> {
  return parseBundle(await exec(`${CTL} get_bundle`));
}

// 线格式必须是双层编码：每段先 base64（得到不含换行的单行），再用 | 拼接，最后整体 base64。
// ctl.sh 那边是「整体解码 → cut -d| 取段 → 每段再 base64 -d」，而 cut 是行敏感的：
// 若只做单层编码，config 里的换行会把 bundle 拆成多行，cut 逐行取段 → 每段都是垃圾，
// toybox 的 base64 -d 对垃圾输入仍返回 0 → 8 个文件全被写成 0 字节（1.2.8 曾出现此回归）。
export function buildBundlePayload(configText: string, rules: Record<RuleName, string>): string {
  const inner = [configText, ...RULE_ORDER.map((r) => rules[r] ?? "")].map((v) => b64Encode(v)).join("|");
  return b64Encode(inner);
}

export async function saveBundle(configText: string, rules: Record<RuleName, string>): Promise<string> {
  return exec(`${CTL} set_bundle '${buildBundlePayload(configText, rules)}'`);
}

export async function getLogs(): Promise<string> {
  return exec(`${CTL} log`);
}

export async function exportLog(): Promise<string> {
  return exec(`${CTL} export_log`);
}

export interface PresetPath {
  path: string;
  configured: boolean;
}

// 强制指定 KMI 的候选：模块实际打包的 .ko，避免手输拼错（与 1.2.7 的 list_kmis 一致）
export async function listKmis(): Promise<string[]> {
  return splitLines(await exec(`${CTL} list_kmis`))
    .map((l) => l.trim())
    .filter(Boolean);
}

export async function presetPaths(): Promise<PresetPath[]> {
  const raw = await exec(`${CTL} preset_paths`);
  return splitLines(raw)
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => {
      const parts = l.split(String.fromCharCode(9));
      return { path: parts[0] || "", configured: parts[1] === "1" };
    })
    .filter((p) => p.path);
}

export async function rescanScene(): Promise<string> {
  return exec(`${CTL} rescan_scene`);
}

export async function importLegacy(): Promise<string> {
  return exec(`${CTL} import_legacy`);
}

export async function resetDefaults(): Promise<string> {
  return exec(`${CTL} reset_defaults`);
}

export async function setStats(on: boolean): Promise<string> {
  return exec(`${CTL} set_stats ${on ? "1" : "0"}`);
}

export async function reportInstall(): Promise<ExecResult> {
  return execCode(`${CTL} report_install`);
}

export async function pgGet(): Promise<Record<string, string>> {
  return parseKV(await exec(`${PG_CTL} get`));
}

// ctl.sh pid_guard_bundle 的输出：首行 conf:<b64>，其后是 pid_guard_* 状态字段
export function parsePidBundle(raw: string): { conf: string; status: Record<string, string> } {
  const lines = splitLines(raw);
  let conf = "";
  const rest: string[] = [];
  for (const line of lines) {
    if (line.startsWith("conf:")) {
      const b64 = line.slice(5).trim();
      if (b64) {
        try {
          const bin = atob(b64);
          const bytes = new Uint8Array(bin.length);
          for (let k = 0; k < bin.length; k++) bytes[k] = bin.charCodeAt(k);
          conf = new TextDecoder().decode(bytes);
        } catch {
          conf = "";
        }
      }
      continue;
    }
    rest.push(line);
  }
  return { conf, status: parseKV(rest.join(String.fromCharCode(10))) };
}

// PID 隐藏页原来要 2 次往返（pid_guard_ctl get + 完整 status），且 status 很重
export async function getPidBundle(): Promise<{ conf: string; status: Record<string, string> }> {
  return parsePidBundle(await exec(`${CTL} pid_guard_bundle`));
}

export async function pgSave(confText: string): Promise<string> {
  return exec(`${PG_CTL} set_b64 '${b64Encode(confText)}'`);
}

export async function pgReload(): Promise<ExecResult> {
  return execCode(`${CTL} pid_guard_reload`);
}

export async function loadAndApply(): Promise<ExecResult> {
  // 「加载并应用」= 先 load 再 apply；load 的失败不回滚，交给 apply 的结果表达
  await execCode(`${CTL} load`);
  return execCode(`${CTL} apply`);
}

export interface Announcement {
  summary?: string;
  items?: string[];
  updated?: string;
  link?: string;
}

// 公告：60 秒缓存 + 静默失败（离线/无网时不影响任何功能）
const ANNOUNCE_URL = "https://susfs.stdawns.top/announcement.json";
const ANNOUNCE_TTL = 60 * 1000;

export async function getAnnouncement(): Promise<Announcement | null> {
  try {
    const raw = localStorage.getItem("announce_cache");
    if (raw) {
      const cached = JSON.parse(raw) as { at: number; data: Announcement };
      if (Date.now() - cached.at < ANNOUNCE_TTL) return cached.data;
    }
  } catch {
    /* 缓存损坏就重新拉 */
  }
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 6000);
    const res = await fetch(ANNOUNCE_URL, { cache: "no-store", signal: ctrl.signal });
    clearTimeout(timer);
    if (!res.ok) return null;
    const data = (await res.json()) as Announcement;
    try {
      localStorage.setItem("announce_cache", JSON.stringify({ at: Date.now(), data }));
    } catch {
      /* 存不下就算了 */
    }
    return data;
  } catch {
    return null;
  }
}
