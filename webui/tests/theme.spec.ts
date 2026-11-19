import { beforeEach, describe, expect, it } from "vitest";
import { applyTheme, currentTheme, isTheme, setTheme } from "../src/theme";

describe("主题", () => {
  beforeEach(() => {
    localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
  });

  it("非法值不认", () => {
    expect(isTheme("cool")).toBe(true);
    expect(isTheme("dark")).toBe(false);
    expect(isTheme(null)).toBe(false);
  });

  it("默认冷蓝", () => {
    expect(currentTheme()).toBe("cool");
  });

  it("写入后能读回并落到 data-theme", () => {
    setTheme("warm");
    expect(currentTheme()).toBe("warm");
    expect(document.documentElement.getAttribute("data-theme")).toBe("warm");
  });

  it("applyTheme 不改 localStorage", () => {
    applyTheme("warm");
    expect(localStorage.getItem("ui_theme")).toBeNull();
  });
});
