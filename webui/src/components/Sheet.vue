<script setup lang="ts">
import { onBeforeUnmount, watch } from "vue";

// 二级窗口：1.2.7 的 #presetModal / #announceModal 交互。
// 不用 position: fixed / backdrop-filter —— 老 WebView 上这两者会导致白屏，
// 改为相对 .app 的 absolute 覆盖层（.app 已设 position: relative）。
const props = defineProps<{ open: boolean; title: string }>();
const emit = defineEmits<{ (e: "close"): void }>();

function onKey(ev: KeyboardEvent): void {
  if (ev.key === "Escape") emit("close");
}

function bind(on: boolean): void {
  if (on) {
    document.addEventListener("keydown", onKey);
    document.body.classList.add("modal-open");
  } else {
    document.removeEventListener("keydown", onKey);
    document.body.classList.remove("modal-open");
  }
}

watch(() => props.open, bind, { immediate: true });
onBeforeUnmount(() => bind(false));
</script>

<template>
  <div v-if="open" class="modal" role="dialog" aria-modal="true" @click.self="emit('close')">
    <div class="modal-box">
      <h3>{{ title }}</h3>
      <slot />
      <div class="modal-actions">
        <slot name="actions" />
      </div>
    </div>
  </div>
</template>
