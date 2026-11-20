import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

// 静态护栏：模板里用到的 PascalCase 组件必须在同一文件里 import。
// 漏 import 时 Vue 会把标签当成原生元素，slot 内容直接摊在页面上 ——
// 1.2.9 的「预设路径 / 强制指定 KMI 没弹窗」就是这个原因，控制台只有一条 warning。
const SRC = join(process.cwd(), "src");

function vueFiles(dir: string): string[] {
  const out: string[] = [];
  for (const name of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, name.name);
    if (name.isDirectory()) out.push(...vueFiles(full));
    else if (name.name.endsWith(".vue")) out.push(full);
  }
  return out;
}

describe("组件引用", () => {
  const files = [...vueFiles(SRC), join(SRC, "App.vue")];

  it("每个模板里的自定义组件都有对应 import", () => {
    const missing: string[] = [];
    for (const file of new Set(files)) {
      const text = readFileSync(file, "utf8");
      const tpl = text.split("<template>")[1] ?? "";
      const tags = new Set(
        [...tpl.matchAll(/<([A-Z][A-Za-z0-9]+)/g)].map((m) => m[1]),
      );
      for (const tag of tags) {
        const imported =
          text.includes(`import ${tag} from`) || text.includes(`${tag},`) || text.includes(`{ ${tag}`);
        if (!imported) missing.push(`${file.split(/[\\/]/).pop()}: <${tag}>`);
      }
    }
    expect(missing).toEqual([]);
  });
});
