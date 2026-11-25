// SPDX-License-Identifier: GPL-3.0-only
// 向导写盘的回归（audit B1）：规则没加载成功时，绝不能生成"空规则"的 payload。
import { describe, expect, it } from "vitest";
import { assertRulesReady, buildWizardBundle, rulesReady } from "../src/wizard";

const RULES: Record<string, string> = {
  sus_path: "/data/adb",
  sus_path_loop: "",
  hide_modules: "kernelsu",
  skip_hide: "",
  sus_mount: "",
  try_umount: "",
  sus_map: "",
};

describe("wizard 写盘守卫", () => {
  it("rules 为 null 时必须抛错（否则会清空设备规则）", () => {
    expect(() => assertRulesReady(null)).toThrow(/规则未加载/);
    expect(rulesReady(null)).toBe(false);
  });

  it("rules 为空对象时同样抛错（null 展开的典型结果）", () => {
    expect(() => assertRulesReady({})).toThrow(/规则未加载/);
    expect(rulesReady({})).toBe(false);
  });

  it("正常拼装：写入 patch 与追加路径", () => {
    const out = buildWizardBundle("[general]\nauto_load=0\n", RULES, {
      patch: { auto_load: "1", avc_spoof: "1" },
      addPaths: ["/data/local/tmp/brevent"],
    });
    expect(out.config).toContain("auto_load=1");
    expect(out.config).toContain("avc_spoof=1");
    expect(out.rules.sus_path).toContain("/data/adb");
    expect(out.rules.sus_path).toContain("/data/local/tmp/brevent");
  });

  it("追加路径去重，且不改动其它规则", () => {
    const out = buildWizardBundle("", RULES, { patch: {}, addPaths: ["/data/adb", "/data/adb"] });
    const lines = out.rules.sus_path.split("\n");
    expect(lines.filter((l) => l === "/data/adb")).toHaveLength(1);
    expect(out.rules.hide_modules).toBe("kernelsu");
  });

  it("不修改传入的 rules 对象（避免副作用）", () => {
    const before = { ...RULES };
    buildWizardBundle("", RULES, { patch: {}, addPaths: ["/x"] });
    expect(RULES).toEqual(before);
  });

  it("空 addPaths 时保持 sus_path 原样", () => {
    const out = buildWizardBundle("", RULES, { patch: {}, addPaths: [] });
    expect(out.rules.sus_path).toBe("/data/adb");
  });
});
