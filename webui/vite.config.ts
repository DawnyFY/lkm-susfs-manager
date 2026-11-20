import { createHash } from "node:crypto";
import { defineConfig, type Plugin } from "vite";
import vue from "@vitejs/plugin-vue";

// 部分 KernelSU / SukiSU WebUI 用 ksu:// 加载页面，对 <script type="module"> 支持不稳。
// 这里打成 IIFE 经典脚本，并把 index.html 的 script 标签改写掉，最大化兼容。
//
// 同时给 app.js / app.css 加上内容哈希查询串：WebView 会缓存这两个固定文件名的资源，
// 模块升级后仍加载旧 bundle，出现过「改了界面但设备上没变化」的情况。
// 哈希取产物内容的 sha256 前 8 位 —— 内容不变则 URL 不变，构建仍可复现。
function classicScript(): Plugin {
  return {
    name: "susfs-classic-script",
    enforce: "post",
    transformIndexHtml(html, ctx) {
      const bundle = ctx.bundle ?? {};
      const digest = (fileName: string): string | null => {
        const item = bundle[fileName] as { type: string; code?: string; source?: string | Uint8Array } | undefined;
        if (!item) return null;
        const body =
          typeof item.code === "string"
            ? item.code
            : typeof item.source === "string"
              ? item.source
              : item.source instanceof Uint8Array
                ? Buffer.from(item.source)
                : null;
        if (body === null) return null;
        return createHash("sha256").update(body).digest("hex").slice(0, 8);
      };

      const js = digest("assets/app.js");
      const css = digest("assets/app.css");

      let out = html.replace(
        /<script type="module" crossorigin src="([^"]+)"><\/script>/,
        '<script defer src="$1"></script>',
      );
      if (js) out = out.replace(/(src="\.\/assets\/app\.js)(?=")/, `$1?v=${js}`);
      if (css) out = out.replace(/(href="\.\/assets\/app\.css)(?=")/, `$1?v=${css}`);
      return out;
    },
  };
}

// WebUI 由 ksu:// 或 file:// 加载：必须用相对路径，且不能依赖任何外链
export default defineConfig({
  base: "./",
  plugins: [vue(), classicScript()],
  build: {
    outDir: "../module/webroot",
    emptyOutDir: true,
    target: "es2019",
    sourcemap: false,
    cssCodeSplit: false,
    modulePreload: false,
    polyfillModulePreload: false,
    assetsInlineLimit: 8192,
    rollupOptions: {
      output: {
        format: "iife",
        inlineDynamicImports: true,
        // 固定文件名，保证重建字节一致（release_manifest 依赖产物哈希稳定）
        entryFileNames: "assets/app.js",
        chunkFileNames: "assets/[name].js",
        assetFileNames: (info) => {
          const n = info.name || "";
          if (n.endsWith(".css")) return "assets/app.css";
          return "assets/[name][extname]";
        },
      },
    },
  },
  test: {
    environment: "happy-dom",
    include: ["tests/**/*.spec.ts"],
  },
});
