import { reactive } from "vue";
import { getStatus } from "./api";

export type BannerKind = "" | "ok" | "err" | "info";

export interface AppState {
  status: Record<string, string>;
  wizard: { open: boolean; replay: boolean };
  busy: boolean;
  banner: { kind: BannerKind; text: string };
  loaded: boolean;
}

export const state = reactive<AppState>({
  status: {},
  wizard: { open: false, replay: false },
  busy: false,
  banner: { kind: "", text: "" },
  loaded: false,
});

let bannerTimer = 0;

/** 打开配置向导；replay=true 表示从关于页手动进来 */
export function openWizard(replay = true): void {
  state.wizard.replay = replay;
  state.wizard.open = true;
}

export function closeWizard(): void {
  state.wizard.open = false;
  state.wizard.replay = false;
}

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
// 任务执行期间置位：用于识别「withBusy 里再套 withBusy」。
// runSerial 是串行队列，内层会等外层结束 → 自己等自己 → busy 永远为 true（界面卡在"处理中"）。
let insideTask = false;

export async function withBusy<T>(fn: () => Promise<T>): Promise<T> {
  if (insideTask) return fn();
  state.busy = true;
  try {
    return await runSerial(async () => {
      insideTask = true;
      try {
        return await fn();
      } finally {
        insideTask = false;
      }
    });
  } finally {
    state.busy = false;
  }
}
