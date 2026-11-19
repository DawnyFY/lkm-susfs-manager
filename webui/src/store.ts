import { reactive } from "vue";
import { getStatus } from "./api";

export type BannerKind = "" | "ok" | "err" | "info";

export interface AppState {
  status: Record<string, string>;
  busy: boolean;
  banner: { kind: BannerKind; text: string };
  loaded: boolean;
}

export const state = reactive<AppState>({
  status: {},
  busy: false,
  banner: { kind: "", text: "" },
  loaded: false,
});

let bannerTimer = 0;

export function setBanner(kind: BannerKind, text: string, ms = 4000): void {
  state.banner = { kind, text };
  if (bannerTimer) clearTimeout(bannerTimer);
  if (ms > 0) {
    bannerTimer = window.setTimeout(() => {
      state.banner = { kind: "", text: "" };
    }, ms);
  }
}

export function clearBanner(): void {
  state.banner = { kind: "", text: "" };
}

// 只更新部分字段（例如 PID 页只关心 pid_guard_*），避免为了一页跑完整 status
export function mergeStatus(patch: Record<string, string>): void {
  state.status = { ...state.status, ...patch };
  state.loaded = true;
}

export async function refreshStatus(): Promise<void> {
  const s = await getStatus();
  state.status = s;
  state.loaded = true;
}

// 串行队列：并发调用排队执行，绝不丢弃。
// 之前这里是「busy 时直接 return」，导致切页签时 onMounted 的加载被悄悄丢掉，
// 组件永远停在「读取中…」。
let queue: Promise<unknown> = Promise.resolve();

export function runSerial<T>(fn: () => Promise<T>): Promise<T> {
  const next = queue.then(fn, fn);
  queue = next.then(
    () => undefined,
    () => undefined
  );
  return next;
}

// 用户主动操作（按钮）：串行 + 全局 busy 用于禁用按钮
export async function withBusy<T>(fn: () => Promise<T>): Promise<T> {
  state.busy = true;
  try {
    return await runSerial(fn);
  } finally {
    state.busy = false;
  }
}
