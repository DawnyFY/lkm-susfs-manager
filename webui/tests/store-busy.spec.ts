// SPDX-License-Identifier: GPL-2.0-only
// withBusy 的回归：嵌套调用不能自锁。
// 曾经的 bug：向导的「保存并应用」在 withBusy 里又调了一个包着 withBusy 的函数，
// runSerial 是串行队列 → 内层等外层 → 自己等自己 → busy 永远 true（界面卡在"处理中"）。
import { describe, expect, it } from "vitest";
import { state, withBusy } from "../src/store";

describe("withBusy", () => {
  it("嵌套调用会直接执行，不会自锁", async () => {
    let inner = false;
    const out = await withBusy(async () => {
      const v = await withBusy(async () => {
        inner = true;
        return 42;
      });
      return v + 1;
    });
    expect(inner).toBe(true);
    expect(out).toBe(43);
    expect(state.busy).toBe(false);
  });

  it("任务抛错后 busy 仍复位", async () => {
    await expect(
      withBusy(async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");
    expect(state.busy).toBe(false);
  });

  it("任务内部能读到 busy=true", async () => {
    let seen = false;
    await withBusy(async () => {
      seen = state.busy;
    });
    expect(seen).toBe(true);
    expect(state.busy).toBe(false);
  });
});
