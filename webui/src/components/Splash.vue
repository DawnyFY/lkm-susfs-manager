<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import { t } from "../i18n";

// 首次启动的开场动画：光扫 + 缓慢推近 + 变色，标题逐级浮出。
// 纯 CSS 实现（不引入视频、不依赖解码能力），约 2.6 s 后自动淡出；
// 点击 / 按 Esc 可提前跳过。只在首次打开 WebUI 时播放（见 App.vue 的标记）。
defineProps<{ version?: string }>();
const emit = defineEmits<{ (e: "done"): void }>();

const closing = ref(false);
let timer: ReturnType<typeof setTimeout> | undefined;
let exitTimer: ReturnType<typeof setTimeout> | undefined;

function finish(): void {
  if (closing.value) return;
  closing.value = true;
  exitTimer = setTimeout(() => emit("done"), 320);
}

function onKey(ev: KeyboardEvent): void {
  if (ev.key === "Escape" || ev.key === "Enter" || ev.key === " ") finish();
}

onMounted(() => {
  document.body.classList.add("splash-open");
  document.addEventListener("keydown", onKey);
  timer = setTimeout(finish, 2600);
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
    <div class="splash-bg" />
    <div class="splash-spot" />
    <div class="splash-sweep" />
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
</template>
