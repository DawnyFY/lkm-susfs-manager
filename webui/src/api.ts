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

export async function saveBundle(configText: string, rules: Record<RuleName, string>): Promise<string> {
  const joined = [configText, ...RULE_ORDER.map((r) => rules[r] ?? "")].join("|");
  return exec(`${CTL} set_bundle '${b64Encode(joined)}'`);
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

export async function pgSave(confText: string): Promise<string> {
  return exec(`${PG_CTL} set_b64 '${b64Encode(confText)}'`);
}

export async function pgReload(): Promise<ExecResult> {
  return execCode(`${CTL} pid_guard_reload`);
}
