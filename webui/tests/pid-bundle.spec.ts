import { describe, expect, it } from "vitest";
import { parsePidBundle } from "../src/api";

const b64 = (s: string) => {
  const bytes = new TextEncoder().encode(s);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
};
const NL = String.fromCharCode(10);

describe("pid_guard_bundle 解析", () => {
  it("首行出配置，其余解析成状态字段", () => {
    const conf = ["enabled=0", "target_uids=99000-99999", "target_comms=probe-*", "exclude_comms="].join(NL) + NL;
    const raw = [
      "conf:" + b64(conf),
      "pid_guard_enabled=0",
      "pid_guard_loaded=0",
      "pid_guard_visible=0",
      "pid_guard_hidden=0",
      "pid_guard_result=unloaded",
      "pid_guard_uids=99000-99999",
      "pid_guard_comms=probe-*",
    ].join(NL);
    const { conf: c, status } = parsePidBundle(raw);
    expect(c).toBe(conf);
    expect(status.pid_guard_result).toBe("unloaded");
    expect(status.pid_guard_loaded).toBe("0");
    expect(status.pid_guard_comms).toBe("probe-*");
  });

  it("没有 conf 行 / 坏 base64 时配置为空，状态仍可解析", () => {
    const { conf, status } = parsePidBundle("conf:@@@" + NL + "pid_guard_enabled=1");
    expect(conf).toBe("");
    expect(status.pid_guard_enabled).toBe("1");
  });

  it("空输出不炸", () => {
    const { conf, status } = parsePidBundle("");
    expect(conf).toBe("");
    expect(status).toEqual({});
  });
});
