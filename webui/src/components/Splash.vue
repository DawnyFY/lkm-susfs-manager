<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import { t } from "../i18n";

// 首次启动开场（对齐参考视频前 1 秒的实际运动）：
//   黑场 → 光刃绕中心旋转（横向转到竖向，过程中带螺旋拖尾）→ 立成竖向后左右拉开 → 内容露出。
// 只用 transform / opacity，不依赖 clip-path 插值；不使用毛玻璃滤镜。
// 点击 / Esc / Enter 可提前跳过；总时长约 3.1 s。
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
  timer = setTimeout(finish, 3100);
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
    <!-- 光刃转开之后露出的内容 -->
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

    <!-- 旋转的光刃：横向转竖向，带螺旋拖尾（参考里的「螺纹」） -->
    <div class="wiper">
      <i class="wiper-thread th1" />
      <i class="wiper-thread th2" />
      <i class="wiper-thread th3" />
      <i class="wiper-blade" />
    </div>

    <!-- 光刃立成竖向后，左右两片幕沿竖缝拉开 -->
    <div class="curtain curtain-left"><i class="blade" /></div>
    <div class="curtain curtain-right"><i class="blade" /></div>
  </div>
</template>
