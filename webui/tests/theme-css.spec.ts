import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const css = fs.readFileSync(path.join(process.cwd(), "src", "styles", "base.css"), "utf8");

// 两套主题必须在「结构」上可区分，而不是只换色号：
// 早期版本把它们压成同一套样式，手机上几乎看不出差别（用户实测反馈）。
function block(selector: string): string {
  const start = css.indexOf(selector);
  if (start < 0) throw new Error("missing selector: " + selector);
  const open = css.indexOf("{", start);
  const close = css.indexOf("}", open);
  return css.slice(open + 1, close);
}

function value(sel: string, name: string): string {
  const m = block(sel).match(new RegExp(name + "\s*:\s*([^;]+);"));
  if (!m) throw new Error("missing var " + name + " in " + sel);
  return m[1].trim();
}

const COOL = 'html[data-theme="cool"]';
const WARM = 'html[data-theme="warm"]';

describe("主题结构差异", () => {
  it("圆角不同", () => {
    expect(value(COOL, "--radius")).not.toBe(value(WARM, "--radius"));
  });

  it("主按钮底色不同（暖灰是黑底，冷蓝是品牌色）", () => {
    expect(value(COOL, "--btn-primary-bg")).not.toBe(value(WARM, "--btn-primary-bg"));
  });

  it("阴影不同（暖灰无阴影）", () => {
    expect(value(WARM, "--shadow")).toBe("none");
    expect(value(COOL, "--shadow")).not.toBe("none");
  });

  it("开关形状不同", () => {
    expect(value(COOL, "--switch-radius")).toBe("999px");
    expect(value(WARM, "--switch-radius")).not.toBe("999px");
  });

  it("页签激活态不同（暖灰用下划线）", () => {
    expect(value(WARM, "--tab-active-ring")).toContain("inset 0 -2px 0 0");
    expect(value(COOL, "--tab-active-ring")).not.toContain("-2px");
  });

  it("暖灰的通用 .btn 不能覆盖主按钮（否则白底白字）", () => {
    expect(css).toContain('html[data-theme="warm"] .btn:not(.primary)');
    expect(css).not.toMatch(/html\[data-theme="warm"\] \.btn\s*\{/);
  });
});
