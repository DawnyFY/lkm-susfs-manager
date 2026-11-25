// SPDX-License-Identifier: GPL-3.0-only
// 向导的配置拼装逻辑抽成纯函数：可单测，且把「规则没加载成功」变成硬错误。
// 背景（audit B1）：getBundle 失败时 rules 为 null，旧实现展开成 {} 后照旧写盘，
// 线格式出现 7 个空段，ctl.sh 仍回 saved → 用户的规则文件被清空。
import { setIni } from "./ini";

export interface WizardEdits {
  /** 要写入 config.ini 的键值 */
  patch: Record<string, string>;
  /** 要追加到 sus_path 的路径 */
  addPaths: string[];
}

/** 规则未加载成功时直接抛错，绝不允许拿空对象去覆盖设备上的规则 */
export function assertRulesReady(rules: Record<string, string> | null | undefined): Record<string, string> {
  if (!rules || Object.keys(rules).length === 0) {
    throw new Error("规则未加载（get_bundle 失败），已阻止写入以免清空设备上的规则");
  }
  return rules;
}

/** 校验能否进入「写盘」这一步 */
export function rulesReady(rules: Record<string, string> | null | undefined): boolean {
  return !!rules && Object.keys(rules).length > 0;
}

/** 拼装向导要提交的 config + rules；rules 不合格时抛错 */
export function buildWizardBundle(
  base: string,
  rules: Record<string, string> | null | undefined,
  edits: WizardEdits,
): { config: string; rules: Record<string, string> } {
  const r = { ...assertRulesReady(rules) };
  let config = base;
  for (const [k, v] of Object.entries(edits.patch)) config = setIni(config, k, v);

  const add = edits.addPaths.map((p) => p.trim()).filter((p) => p.length > 0);
  if (add.length > 0) {
    const cur = (r.sus_path || "").split("\n").filter((line) => line.trim());
    for (const p of add) if (!cur.includes(p)) cur.push(p);
    r.sus_path = cur.join("\n");
  }
  return { config, rules: r };
}
