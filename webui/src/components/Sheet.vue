<script setup lang="ts">
import { onBeforeUnmount, watch } from "vue";

// 二级窗口：1.2.7 的 #presetModal / #announceModal 交互。
// 覆盖层用 position: fixed（1.2.7 的弹窗即如此，目标机型验证过）；不使用毛玻璃滤镜。
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
