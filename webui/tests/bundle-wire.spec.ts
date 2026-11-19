import { describe, expect, it } from "vitest";
import { RULE_ORDER, buildBundlePayload } from "../src/api";

const NL = String.fromCharCode(10);

function b64decode(s: string): string {
  const bin = atob(s);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

function b64encode(s: string): string {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
}

const CONF = ["# 注释", "auto_load=1", "hide_sus_mnts=1", "replace_rules=0", ""].join(NL);
const RULES = {
  sus_path: "/data/adb" + NL + "# 注释" + NL + "/data/local/tmp/x" + NL,
  sus_path_loop: "",
  hide_modules: "kernelsu" + NL,
  skip_hide: "",
  sus_mount: "",
  try_umount: "",
  sus_map: "/a/b" + NL,
} as Record<(typeof RULE_ORDER)[number], string>;

describe("set_bundle 线格式（ctl.sh 契约）", () => {
  it("外层解码后必须是单行：用 | 连接的内层 base64", () => {
    const payload = buildBundlePayload(CONF, RULES);
    const inner = b64decode(payload);
    // 关键：不能有换行。ctl.sh 用 cut -d'|' 按行取段，多行就会被切碎 → 全部写空
    expect(inner.includes(NL)).toBe(false);
    expect(inner.split("|")).toHaveLength(8);
  });

  it("内层每段解出来与原文逐字节一致", () => {
    const inner = b64decode(buildBundlePayload(CONF, RULES)).split("|");
    expect(b64decode(inner[0])).toBe(CONF);
    RULE_ORDER.forEach((name, i) => {
      expect(b64decode(inner[i + 1])).toBe(RULES[name]);
    });
  });

  it("段顺序固定为 config + RULE_ORDER", () => {
    expect(RULE_ORDER).toEqual([
      "sus_path",
      "sus_path_loop",
      "hide_modules",
      "skip_hide",
      "sus_mount",
      "try_umount",
      "sus_map",
    ]);
  });

  it("含中文 / CRLF / 竖线的内容也能无损往返", () => {
    const conf = "manager_name=水行川" + NL + "fake_cmdline_value=a|b" + NL;
    const rules = { ...RULES, sus_path: "/中文/路径" + NL };
    const inner = b64decode(buildBundlePayload(conf, rules)).split("|");
    expect(b64decode(inner[0])).toBe(conf);
    expect(b64decode(inner[1])).toBe(rules.sus_path);
  });

  it("外层必须是合法 base64（ctl.sh 会先校验）", () => {
    const payload = buildBundlePayload(CONF, RULES);
    expect(payload).toMatch(/^[A-Za-z0-9+/]+={0,2}$/);
    expect(b64encode(CONF).length).toBeGreaterThan(0);
  });
});
