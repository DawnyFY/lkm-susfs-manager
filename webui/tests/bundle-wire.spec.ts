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

function byteLen(s: string): number {
  return new TextEncoder().encode(s).length;
}

const CONF = ["# 注释", "auto_load=1", "hide_sus_mnts=1", "replace_rules=0", ""].join(NL);
const RULES: Record<string, string> = {
  sus_path: "/data/adb" + NL + "# 注释" + NL + "/data/local/tmp/x" + NL,
  sus_path_loop: "",
  hide_modules: "kernelsu" + NL,
  skip_hide: "",
  sus_mount: "",
  try_umount: "",
  sus_map: "/a/b" + NL,
};

describe("set_bundle 线格式（ctl.sh 契约 v2）", () => {
  it("外层解码后必须是单行：8 段用 | 连接", () => {
    const inner = b64decode(buildBundlePayload(CONF, RULES));
    // ctl.sh 用 cut -d'|' 按行取段，内层一旦有换行就会被切碎 → 8 个文件写空
    expect(inner.includes(NL)).toBe(false);
    expect(inner.split("|")).toHaveLength(8);
  });

  it("每段是 <字节数>:<base64>，且声明长度等于实际解码长度", () => {
    const segs = b64decode(buildBundlePayload(CONF, RULES)).split("|");
    const values = [CONF, ...RULE_ORDER.map((r) => RULES[r] ?? "")];
    expect(segs).toHaveLength(values.length);
    segs.forEach((seg, i) => {
      const idx = seg.indexOf(":");
      expect(idx).toBeGreaterThan(0);
      const declared = Number(seg.slice(0, idx));
      const text = b64decode(seg.slice(idx + 1));
      expect(declared).toBe(byteLen(text));
      expect(text).toBe(values[i]);
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

  it("中文内容按字节数计长（ctl.sh 用 wc -c 比对）", () => {
    const conf = "manager_name=水行川" + NL + "fake_cmdline_value=a|b" + NL;
    const first = b64decode(buildBundlePayload(conf, RULES)).split("|")[0];
    const idx = first.indexOf(":");
    const declared = Number(first.slice(0, idx));
    const text = b64decode(first.slice(idx + 1));
    expect(text).toBe(conf);
    expect(declared).toBe(byteLen(conf));
    // 「水行川」每个汉字 3 字节：按字符数计长会少 6
    expect(declared).toBe([...conf].length + 6);
  });

  it("外层必须是合法 base64（ctl.sh 会先校验）", () => {
    const payload = buildBundlePayload(CONF, RULES);
    expect(payload).toMatch(/^[A-Za-z0-9+/]+={0,2}$/);
    expect(b64encode(CONF).length).toBeGreaterThan(0);
  });
});
