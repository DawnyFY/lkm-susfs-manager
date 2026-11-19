// KernelSU / SukiSU WebUI 的 exec 是回调式 API（v1）：
//   window.ksu.exec(cmd, "{}", cbName)  然后 window[cbName](errno, stdout, stderr)
// 直接按 Promise 写会在真机上拿不到结果，这里保持与 1.2.8 已验证实现一致。

export interface ExecResult {
  code: number;
  stdout: string;
  stderr: string;
}

export const CTL = "sh /data/adb/modules/susfs_allinone/ctl.sh";
export const PG_CTL = "sh /data/adb/modules/susfs_allinone/pid_guard_ctl.sh";

let seq = 0;
const TIMEOUT_MS = 90000;

type Ksu = {
  exec?: (cmd: string, opts: string, cb: string) => void;
  toast?: (msg: string) => void;
};

function ksu(): Ksu | undefined {
  return (window as unknown as { ksu?: Ksu }).ksu;
}

export function hasKsu(): boolean {
  const k = ksu();
  return !!k && typeof k.exec === "function";
}

// 允许 0（成功）与 5（部分成功，apply 用）由调用方自行判断
export function execCode(cmd: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const k = ksu();
    if (!k || typeof k.exec !== "function") {
      reject(new Error("当前页面不在 SukiSU WebUI 中运行"));
      return;
    }
    const name = "susfs_allinone_cb_" + Date.now() + "_" + seq++;
    let settled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const finish = (fn: (v: unknown) => void, value: unknown) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      try {
        delete (window as unknown as Record<string, unknown>)[name];
      } catch {
        /* 某些 WebView 禁止 delete，忽略 */
      }
      fn(value);
    };
    timer = setTimeout(() => finish(reject as (v: unknown) => void, new Error("命令超时（90 秒）")), TIMEOUT_MS);
    (window as unknown as Record<string, unknown>)[name] = (errno: number, stdout: string, stderr: string) => {
      finish(resolve as (v: unknown) => void, {
        code: Number(errno) || 0,
        stdout: stdout || "",
        stderr: stderr || "",
      });
    };
    try {
      k.exec(cmd, "{}", name);
    } catch (e) {
      finish(reject as (v: unknown) => void, e);
    }
  });
}

export async function exec(cmd: string): Promise<string> {
  const r = await execCode(cmd);
  if (r.code !== 0) throw new Error(r.stderr.trim() || r.stdout.trim() || "命令失败（code " + r.code + "）");
  return r.stdout;
}

export function toast(msg: string): void {
  const k = ksu();
  if (k && typeof k.toast === "function") {
    try {
      k.toast(msg);
    } catch {
      /* 忽略 */
    }
  }
}

// 换行拆分：不用正则转义写法，避免多层转义把控制字符写进源码
const LF = String.fromCharCode(10);
const CR = String.fromCharCode(13);
export function splitLines(text: string): string[] {
  return String(text || "").split(CR).join("").split(LF);
}

// KEY=VALUE 解析（status / pid_guard_ctl get 都是这种格式）
export function parseKV(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of splitLines(text)) {
    const i = line.indexOf("=");
    if (i <= 0) continue;
    out[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return out;
}

// UTF-8 安全的 base64（WebView 的 btoa 只吃 latin1）
export function b64Encode(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
}
