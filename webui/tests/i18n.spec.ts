import { describe, expect, it } from "vitest";
import en from "../src/locales/en-US.json";
import template from "../src/locales/template.json";
import zh from "../src/locales/zh-CN.json";

const zhKeys = Object.keys(zh).sort();
const enKeys = Object.keys(en).sort();

describe("多语言词典", () => {
  it("中英键集合完全一致", () => {
    expect(enKeys).toEqual(zhKeys);
  });

  it("模板覆盖全部键", () => {
    expect(Object.keys(template).sort()).toEqual(zhKeys);
  });

  it("没有空译文", () => {
    for (const k of zhKeys) {
      expect(String((zh as Record<string, string>)[k]).trim().length, "zh:" + k).toBeGreaterThan(0);
      expect(String((en as Record<string, string>)[k]).trim().length, "en:" + k).toBeGreaterThan(0);
    }
  });

  it("英文词典不含中文（保留专有名词除外）", () => {
    const cjk = /[\u4e00-\u9fff]/;
    const allow = new Set(["主题 / Theme", "语言 / Language"]);
    for (const k of enKeys) {
      if (allow.has(k)) continue;
      expect(cjk.test((en as Record<string, string>)[k]), "含中文: " + k).toBe(false);
    }
  });

  it("占位符在两语言中对齐", () => {
    const ph = (s: string) => (s.match(/\{\w+\}/g) || []).sort().join(",");
    for (const k of zhKeys) {
      expect(ph((en as Record<string, string>)[k]), "占位符不一致: " + k).toBe(ph((zh as Record<string, string>)[k]));
    }
  });
});
