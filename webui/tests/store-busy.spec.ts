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

  it("两个并发任务时 busy 不能提前复位（audit M5）", async () => {
    let releaseFirst: () => void = () => {};
    const firstDone = new Promise<void>((r) => (releaseFirst = r));
    let secondSawBusy = false;

    const p1 = withBusy(async () => {
      await firstDone;
    });
    // 第二个任务在第一个还挂着时启动
    const p2 = withBusy(async () => {
      secondSawBusy = state.busy;
    });

    await p2;
    // p2 结束时 p1 仍在跑，busy 必须还是 true
    expect(secondSawBusy).toBe(true);
    expect(state.busy).toBe(true);

    releaseFirst();
    await p1;
    expect(state.busy).toBe(false);
  });

  it("先起的任务先结束时 busy 仍必须为 true（audit R2-3 的顺序）", async () => {
    const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

    const p1 = withBusy(async () => {
      await sleep(20);
    });
    const p2 = withBusy(async () => {
      await sleep(60);
    });

    await p1;
    // p1 已结束但 p2 还在跑：旧实现（外层 finally 直接置 0）这里会变 false
    expect(state.busy).toBe(true);

    await p2;
    expect(state.busy).toBe(false);
  });
});
