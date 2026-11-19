import { describe, expect, it } from "vitest";
import { parseBundle } from "../src/api";

const b64 = (s: string) => {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
};
const NL = String.fromCharCode(10);

describe("get_bundle 解析", () => {
  it("按 name:b64 解析出 config 与 7 个规则文件", () => {
    const raw = [
      "config:" + b64("auto_load=1" + NL),
      "sus_path:" + b64("/data/adb" + NL),
      "sus_path_loop:",
      "hide_modules:" + b64("kernelsu" + NL),
      "skip_hide:",
      "sus_mount:",
      "try_umount:",
      "sus_map:" + b64("/x/y" + NL),
    ].join(NL);
    const { config, rules } = parseBundle(raw);
    expect(config).toBe("auto_load=1" + NL);
    expect(rules.sus_path).toBe("/data/adb" + NL);
    expect(rules.hide_modules).toBe("kernelsu" + NL);
    expect(rules.sus_map).toBe("/x/y" + NL);
    expect(rules.sus_mount).toBe("");
  });

  it("缺段与坏 base64 不抛错，退化为空串", () => {
    const { config, rules } = parseBundle("config:!!!notbase64" + NL + "sus_path:" + b64("a"));
    expect(config).toBe("");
    expect(rules.sus_path).toBe("a");
    expect(rules.sus_map).toBe("");
  });

  it("空输出不炸", () => {
    const { config, rules } = parseBundle("");
    expect(config).toBe("");
    expect(Object.values(rules).every((v) => v === "")).toBe(true);
  });
});
