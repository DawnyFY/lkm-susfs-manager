import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

// 主题数值取自社区原版两套样式（Opus / optimized），这里锁住关键 token，
// 防止再出现「两套主题做成同一套」或「凭空发明方角」这类回退。
const css = fs.readFileSync(path.join(process.cwd(), "src", "styles", "base.css"), "utf8");

function block(selector: string): string {
  const start = css.indexOf(selector);
  if (start < 0) throw new Error("missing selector: " + selector);
  const open = css.indexOf("{", start);
  const close = css.indexOf("}", open);
  return css.slice(open + 1, close);
}

function value(sel: string, name: string): string {
  const m = block(sel).match(new RegExp(name + "\\s*:\\s*([^;]+);"));
  if (!m) throw new Error("missing var " + name + " in " + sel);
  return m[1].trim();
}

const COOL = 'html[data-theme="cool"]';
const WARM = 'html[data-theme="warm"]';

describe("主题 token 与原版一致", () => {
  it("暖灰圆角是 18/10，不是方角", () => {
    expect(value(WARM, "--radius")).toBe("18px");
    expect(value(WARM, "--radius-sm")).toBe("10px");
  });

  it("冷蓝圆角是 22/14", () => {
    expect(value(COOL, "--radius")).toBe("22px");
    expect(value(COOL, "--radius-sm")).toBe("14px");
  });

  it("按钮：暖灰 11px 方角，冷蓝 999 胶囊", () => {
    expect(value(WARM, "--btn-radius")).toBe("11px");
    expect(value(COOL, "--btn-radius")).toBe("999px");
  });

  it("两套开关都是胶囊，只是尺寸不同", () => {
    expect(value(WARM, "--switch-w")).toBe("44px");
    expect(value(COOL, "--switch-w")).toBe("48px");
    expect(css).toMatch(/\.switch i \{[^}]*border-radius: 999px/);
  });

  it("主按钮底色不同（暖灰墨黑 / 冷蓝品牌色）", () => {
    expect(value(WARM, "--primary-bg")).toBe("#18181b");
    expect(value(COOL, "--primary-bg")).toBe("var(--accent)");
  });

  it("暖灰指标是 1px 分隔的整块表格，冷蓝是独立圆角小块", () => {
    expect(value(WARM, "--stat-radius")).toBe("0");
    expect(value(COOL, "--stat-radius")).toBe("19px");
    expect(css).toMatch(/html\[data-theme="warm"\] \.grid-stats \{[^}]*gap: 1px/);
  });

  it("暖灰窄屏用固定底部导航", () => {
    expect(css).toMatch(/html\[data-theme="warm"\] \.tabs \{[^}]*position: fixed/);
  });

  it("暖灰的通用 .btn 不能覆盖主按钮（否则白底白字）", () => {
    expect(css).toContain('html[data-theme="warm"] .btn:not(.primary)');
    expect(css).not.toMatch(/html\[data-theme="warm"\] \.btn\s*\{/);
  });
});
