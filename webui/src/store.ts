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

export async function refreshStatus(): Promise<void> {
  const s = await getStatus();
  state.status = s;
  state.loaded = true;
}

// 单一出口：所有按钮共用一个 busy 标记，避免并发命令把设备上的锁打满
export async function withBusy<T>(fn: () => Promise<T>): Promise<T | undefined> {
  if (state.busy) return undefined;
  state.busy = true;
  try {
    return await fn();
  } finally {
    state.busy = false;
  }
}
