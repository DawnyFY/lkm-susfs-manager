<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import { t } from "../i18n";

// 首次启动开场（对齐参考视频前 0.7 s 的那段动画）：
//   黑场 → 一道光刃从左斜切而过 → 上下两片幕沿斜缝张开、露出内容 → 标题浮出。
// 只用 transform / opacity / width 动，不依赖 clip-path 插值，老 WebView 也能正常退化。
// 点击 / Esc / Enter 可提前跳过；总时长约 3.0 s。
defineProps<{ version?: string }>();
const emit = defineEmits<{ (e: "done"): void }>();

const closing = ref(false);
let timer: ReturnType<typeof setTimeout> | undefined;
let exitTimer: ReturnType<typeof setTimeout> | undefined;

function finish(): void {
  if (closing.value) return;
  closing.value = true;
  exitTimer = setTimeout(() => emit("done"), 340);
}

function onKey(ev: KeyboardEvent): void {
  if (ev.key === "Escape" || ev.key === "Enter" || ev.key === " ") finish();
}

onMounted(() => {
  document.body.classList.add("splash-open");
  document.addEventListener("keydown", onKey);
  timer = setTimeout(finish, 3000);
});

onBeforeUnmount(() => {
  document.body.classList.remove("splash-open");
  document.removeEventListener("keydown", onKey);
  if (timer) clearTimeout(timer);
  if (exitTimer) clearTimeout(exitTimer);
});
</script>

<template>
  <div class="splash" :class="{ closing }" @click="finish">
    <!-- 光刃张开后露出的内容 -->
    <div class="splash-content">
      <div class="splash-glow" />
      <div class="splash-grain" />
      <div class="splash-body">
        <p class="splash-eyebrow">{{ t("splash.eyebrow") }}</p>
        <h1 class="splash-title">LKM SUSFS管理器</h1>
        <div class="splash-line" />
        <p class="splash-sub">{{ t("app.subtitle") }}</p>
        <p v-if="version" class="splash-ver">v{{ version }}</p>
      </div>
      <p class="splash-skip">{{ t("splash.skip") }}</p>
    </div>

    <!-- 第一道光刃：从左斜切进入，划过之后拉起第一层幕 -->
    <div class="splash-spark" />

    <!-- 上下两片幕，沿斜缝向两侧退开；内侧边缘带白色光带 -->
    <div class="curtain curtain-top"><i class="blade" /></div>
    <div class="curtain curtain-bottom"><i class="blade" /></div>
  </div>
</template>
