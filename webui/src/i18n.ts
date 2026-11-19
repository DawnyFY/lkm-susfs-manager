import { ref } from "vue";
import en from "./locales/en-US.json";
import zh from "./locales/zh-CN.json";

export type Locale = "zh-CN" | "en-US";

const DICTS: Record<Locale, Record<string, string>> = {
  "zh-CN": zh as Record<string, string>,
  "en-US": en as Record<string, string>,
};

const KEY = "lang";
export const locale = ref<Locale>("zh-CN");

export function isLocale(v: unknown): v is Locale {
  return v === "zh-CN" || v === "en-US";
}

export function initI18n(): void {
  try {
    const v = localStorage.getItem(KEY);
    if (isLocale(v)) locale.value = v;
  } catch {
    /* 忽略 */
  }
  document.documentElement.setAttribute("lang", locale.value);
}

export function setLocale(v: Locale): void {
  locale.value = v;
  document.documentElement.setAttribute("lang", v);
  try {
    localStorage.setItem(KEY, v);
  } catch {
    /* 忽略 */
  }
}

// 找不到键时回退到中文，再回退到键名本身：宁可露出 key，也不要空白
export function t(key: string, params?: Record<string, string | number>): string {
  const dict = DICTS[locale.value] || DICTS["zh-CN"];
  let s = dict[key] ?? DICTS["zh-CN"][key] ?? key;
  if (params) {
    for (const [k, v] of Object.entries(params)) s = s.replace(new RegExp("\{" + k + "\}", "g"), String(v));
  }
  return s;
}

// 供单测使用
export function dictFor(v: Locale): Record<string, string> {
  return DICTS[v];
}
