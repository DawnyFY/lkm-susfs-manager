import { describe, expect, it } from "vitest";
import { countRules, getIni, pidConfBuild, setIni } from "../src/ini";
import { parseKV, b64Encode } from "../src/bridge";

describe("config.ini 文本操作", () => {
  const raw = "# 注释\nauto_load=1\nhide_sus_mnts=1\n# replace_rules=9\nreplace_rules=0\n";

  it("读取已有键", () => {
    expect(getIni(raw, "auto_load")).toBe("1");
    expect(getIni(raw, "replace_rules")).toBe("0");
  });

  it("缺省值", () => {
    expect(getIni(raw, "missing", "7")).toBe("7");
  });

  it("改写已有键且不动注释与未知键", () => {
    const out = setIni(raw, "auto_load", "0");
    expect(out).toContain("auto_load=0");
    expect(out).toContain("# 注释");
    expect(out).toContain("# replace_rules=9");
  });

  it("新增键追加到末尾并保留换行", () => {
    const out = setIni(raw, "brand_new", "5");
    expect(out.trimEnd().endsWith("brand_new=5")).toBe(true);
  });

  it("只改第一个匹配，不会被注释行干扰", () => {
    const out = setIni(raw, "replace_rules", "2");
    expect(out).toContain("# replace_rules=9");
    expect(out).toContain("replace_rules=2");
  });
});

describe("规则计数", () => {
  it("忽略注释与空行", () => {
    expect(countRules("/a\n#c\n\n  /b  \n")).toBe(2);
  });
  it("空文本为 0", () => {
    expect(countRules("")).toBe(0);
  });
});

describe("PID 配置生成", () => {
  it("默认关闭写 0 且键顺序固定", () => {
    const s = pidConfBuild({ enabled: 0, uids: "99000-99999", comms: "probe-*", excludes: "" });
    const lines = s.trimEnd().split("\n");
    expect(lines.filter((l) => l.startsWith("enabled="))[0]).toBe("enabled=0");
    expect(lines).toEqual(
      expect.arrayContaining(["target_uids=99000-99999", "target_comms=probe-*", "exclude_comms="])
    );
  });
});

describe("status 解析与 base64", () => {
  it("KEY=VALUE 解析", () => {
    const kv = parseKV("a=1\nb=x=y\nbad\n");
    expect(kv.a).toBe("1");
    expect(kv.b).toBe("x=y");
    expect(kv.bad).toBeUndefined();
  });

  it("中文 base64 往返", () => {
    const b64 = b64Encode("中文|管道");
    expect(b64.length).toBeGreaterThan(0);
    // 不用 Node 的 Buffer：测试环境是 happy-dom，保持与浏览器一致
    const bin = atob(b64);
    const bytes = Array.from(bin, (c) => c.charCodeAt(0));
    expect(new TextDecoder().decode(new Uint8Array(bytes))).toBe("中文|管道");
  });
});
