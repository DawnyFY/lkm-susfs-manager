<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { onMounted, ref } from "vue";
import { clearLog, exportLog, getLogs } from "../api";
import { t } from "../i18n";
import { runSerial, setBanner, state, withBusy } from "../store";

const text = ref("");
const ready = ref(false);

const err = ref("");

async function load(): Promise<void> {
  err.value = "";
  try {
    await runSerial(async () => {
      text.value = await getLogs();
    });
  } catch (e) {
    err.value = (e as Error).message;
    setBanner("err", err.value);
  } finally {
    ready.value = true;
  }
}

onMounted(load);

// 清理：两段式（第一次点击变成「确认清理」，3 秒内再点才执行），
// 避免误触把排查线索清掉；日志会轮转成 .1，不是直接删除。
const confirmClear = ref(false);
let confirmTimer: ReturnType<typeof setTimeout> | undefined;

async function doClear(): Promise<void> {
  if (!confirmClear.value) {
    confirmClear.value = true;
    if (confirmTimer) clearTimeout(confirmTimer);
    confirmTimer = setTimeout(() => (confirmClear.value = false), 3000);
    return;
  }
  confirmClear.value = false;
  if (confirmTimer) clearTimeout(confirmTimer);
  await withBusy(async () => {
    try {
      const out = (await clearLog()).trim();
      if (!out.includes("cleared=")) throw new Error(out || "clear failed");
      setBanner("ok", t("log.clear.done"), 5000);
      await load();
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}

async function doExport(): Promise<void> {
  await withBusy(async () => {
    try {
      const out = (await exportLog()).trim();
      const path = out.split(/\r?\n/).filter(Boolean).pop() || out;
      setBanner("ok", t("msg.exported", { p: path }), 8000);
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}
</script>

<template>
  <div class="card">
    <h2>{{ t("log.title") }}</h2>
    <div v-if="!ready" class="hint">{{ t("common.loading") }}</div>
    <div v-else-if="err" class="hint">{{ t("common.load_failed") }}：{{ err }}</div>
    <template v-else>
      <pre v-if="text.trim()" class="mono" style="white-space: pre-wrap; word-break: break-all; margin: 0;">{{ text }}</pre>
      <p v-else class="hint">{{ t("log.empty") }}</p>
      <div class="btn-row">
        <button class="btn ghost" type="button" :disabled="state.busy" @click="load">{{ t("common.refresh") }}</button>
        <button class="btn ghost" type="button" :disabled="state.busy" @click="doExport">{{ t("status.export") }}</button>
        <button
          :class="['btn', 'ghost', { danger: confirmClear }]"
          type="button"
          :disabled="state.busy"
          @click="doClear"
        >
          {{ confirmClear ? t("log.clear.confirm") : t("log.clear") }}
        </button>
      </div>
    </template>
  </div>
</template>
