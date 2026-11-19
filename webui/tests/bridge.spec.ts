import { describe, expect, it, vi } from "vitest";
import { exec, execCode, hasKsu, parseKV } from "../src/bridge";

type Cb = (errno: number, stdout: string, stderr: string) => void;

function mockKsu(code: number, stdout: string, stderr = ""): void {
  const ksu = {
    exec: vi.fn((_cmd: string, _opts: string, cb: string) => {
      const fn = (window as unknown as Record<string, Cb>)[cb];
      // 模拟真机：异步回调
      setTimeout(() => fn(code, stdout, stderr), 0);
    }),
  };
  (window as unknown as Record<string, unknown>).ksu = ksu;
}

describe("ksu.exec 桥接", () => {
  it("没有 ksu 时明确报错", async () => {
    delete (window as unknown as Record<string, unknown>).ksu;
    expect(hasKsu()).toBe(false);
    await expect(execCode("true")).rejects.toThrow("不在 SukiSU WebUI");
  });

  it("回调转 Promise，返回 code/stdout/stderr", async () => {
    mockKsu(0, "hello");
    const r = await execCode("echo hello");
    expect(r).toEqual({ code: 0, stdout: "hello", stderr: "" });
  });

  it("非 0 退出码在 exec() 里抛错并带 stderr", async () => {
    mockKsu(1, "", "boom");
    await expect(exec("false")).rejects.toThrow("boom");
  });

  it("code=5 由调用方自行判断（exec 也抛，execCode 不抛）", async () => {
    mockKsu(5, "partial");
    const r = await execCode("apply");
    expect(r.code).toBe(5);
  });

  it("回调后的临时函数会被清理", async () => {
    mockKsu(0, "x");
    await execCode("x");
    const leftovers = Object.keys(window).filter((k) => k.startsWith("susfs_allinone_cb_"));
    expect(leftovers).toHaveLength(0);
  });

  it("parseKV 处理等号与脏行", () => {
    expect(parseKV("a=b=c\nnope\n=empty\n")).toEqual({ a: "b=c" });
  });
});
