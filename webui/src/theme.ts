export type ThemeName = "cool" | "warm";

const KEY = "ui_theme";

export const THEMES: Record<ThemeName, { light: string; dark: string }> = {
  cool: { light: "#f2f4f8", dark: "#08090c" },
  warm: { light: "#f3f3f0", dark: "#0a0a0c" },
};

export function isTheme(v: unknown): v is ThemeName {
  return v === "cool" || v === "warm";
}

export function currentTheme(): ThemeName {
  try {
    const v = localStorage.getItem(KEY);
    if (isTheme(v)) return v;
  } catch {
    /* localStorage 不可用时退回默认 */
  }
  return "cool";
}

export function applyTheme(name: ThemeName): void {
  const t = THEMES[name] ?? THEMES.cool;
  const root = document.documentElement;
  root.setAttribute("data-theme", name);
  document.querySelectorAll('meta[name="theme-color"]').forEach((m) => {
    const dark = String((m as HTMLMetaElement).media || "").includes("dark");
    m.setAttribute("content", dark ? t.dark : t.light);
  });
}

export function setTheme(name: ThemeName): void {
  applyTheme(name);
  try {
    localStorage.setItem(KEY, name);
  } catch {
    /* 忽略写入失败 */
  }
}
