import { defineConfig, type Plugin } from "vite";
import vue from "@vitejs/plugin-vue";

// 部分 KernelSU / SukiSU WebUI 用 ksu:// 加载页面，对 <script type="module"> 支持不稳。
// 这里打成 IIFE 经典脚本，并把 index.html 的 script 标签改写掉，最大化兼容。
function classicScript(): Plugin {
  return {
    name: "susfs-classic-script",
    enforce: "post",
    transformIndexHtml(html) {
      return html.replace(/<script type="module" crossorigin src="([^"]+)"><\/script>/, '<script defer src="$1"></script>');
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
