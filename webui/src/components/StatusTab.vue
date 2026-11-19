<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { computed } from "vue";
import { applyRules, exportLog } from "../api";
import { t } from "../i18n";
import { refreshStatus, setBanner, state, withBusy } from "../store";

const s = computed(() => state.status);

function backendText(): string {
  const k = s.value.susfs_kernel || "";
  if (k === "builtin") return t("status.builtin");
  if (k === "lkm") return t("status.lkmkind");
  return t("common.none");
}

async function doApply(): Promise<void> {
  await withBusy(async () => {
    try {
      const r = await applyRules();
      // 0 = 全成功；5 = 部分规则失败（ctl.sh 的约定），其余按失败
      if (r.code === 0) setBanner("ok", t("msg.applied"));
      else if (r.code === 5) setBanner("info", t("msg.partial"));
      else setBanner("err", (r.stderr || r.stdout || "").trim() || t("msg.apply_failed", { e: r.code }));
      await refreshStatus();
    } catch (e) {
      setBanner("err", t("msg.apply_failed", { e: (e as Error).message }));
    }
  });
}

async function doRefresh(): Promise<void> {
  await withBusy(async () => {
    try {
      await refreshStatus();
      setBanner("ok", t("msg.applied"));
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
  <div>
    <div class="grid-stats">
      <div class="stat">
        <b>{{ t("status.kernel") }}</b><span class="mono">{{ s.kernel || "—" }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.kmi") }}</b><span class="mono">{{ s.kmi || "—" }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.backend") }}</b><span>{{ backendText() }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.lkm") }}</b><span class="mono">{{ s.lkm_version || "—" }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.rules") }}</b><span>{{ s.rules || "0" }}</span>
      </div>
      <div class="stat" :class="{ ok: s.integrity === 'ok', bad: s.integrity && s.integrity !== 'ok' }">
        <b>{{ t("status.integrity") }}</b><span>{{ s.integrity || "—" }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.autoload") }}</b>
        <span>{{ s.auto_load === "1" ? t("common.on") : t("common.off") }}</span>
      </div>
      <div class="stat" :class="{ bad: s.apply_result && s.apply_result !== 'success' && s.apply_result !== 'not_tested' }">
        <b>{{ t("status.result") }}</b><span>{{ s.apply_result || "—" }}</span>
      </div>
    </div>

    <div class="card">
      <h2>{{ t("status.title") }}</h2>
      <div class="row"><span>{{ t("status.manager") }}</span><span class="mono">{{ s.root_manager || "—" }}</span></div>
      <div class="row"><span>{{ t("status.selinux") }}</span><span class="mono">{{ s.selinux || "—" }}</span></div>
      <p v-if="s.description" class="hint">{{ s.description }}</p>
      <div class="btn-row">
        <button class="btn primary" type="button" :disabled="state.busy" @click="doApply">
          {{ state.busy ? t("common.busy") : t("status.apply") }}
        </button>
        <button class="btn ghost" type="button" :disabled="state.busy" @click="doRefresh">
          {{ t("common.refresh") }}
        </button>
        <button class="btn ghost" type="button" :disabled="state.busy" @click="doExport">
          {{ t("status.export") }}
        </button>
      </div>
    </div>
  </div>
</template>
