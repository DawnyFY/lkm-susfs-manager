<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { pgGet, pgReload, pgSave } from "../api";
import { t } from "../i18n";
import { pidConfBuild } from "../ini";
import { refreshStatus, setBanner, state, withBusy } from "../store";

const form = reactive({ enabled: false, uids: "", comms: "", excludes: "" });
const ready = ref(false);

const st = computed(() => state.status);
const RESULT: Record<string, string> = {
  ok: "ok",
  unloaded: "unloaded",
  failed: "failed",
  unload_failed: "unload_failed",
  stale: "stale",
  no_ko: "no_ko",
  bad_conf: "bad_conf",
  unsupported: "unsupported",
};

onMounted(async () => {
  await withBusy(async () => {
    try {
      const conf = await pgGet();
      form.enabled = (conf.enabled ?? "0") === "1";
      form.uids = conf.target_uids || "";
      form.comms = conf.target_comms || "";
      form.excludes = conf.exclude_comms || "";
      ready.value = true;
      await refreshStatus();
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
});

async function doSave(): Promise<void> {
  await withBusy(async () => {
    try {
      const text = pidConfBuild({
        enabled: form.enabled ? 1 : 0,
        uids: form.uids.trim(),
        comms: form.comms.trim(),
        excludes: form.excludes.trim(),
      });
      // 写入前由 pid_guard_ctl.sh 校验：非法值返回 rejected:，旧配置不会被覆盖
      const out = await pgSave(text);
      if (!out.includes("saved")) throw new Error(out.trim() || "save failed");
      await pgReload();
      await refreshStatus();
      const res = (state.status.pid_guard_result || "").trim();
      if (res && res !== "ok" && res !== "unloaded") setBanner("info", res);
      else setBanner("ok", form.enabled ? t("msg.pg_on") : t("msg.pg_off"));
    } catch (e) {
      setBanner("err", t("msg.save_failed", { e: (e as Error).message }));
    }
  });
}

async function doRefresh(): Promise<void> {
  await withBusy(async () => {
    try {
      const conf = await pgGet();
      form.enabled = (conf.enabled ?? "0") === "1";
      form.uids = conf.target_uids || "";
      form.comms = conf.target_comms || "";
      form.excludes = conf.exclude_comms || "";
      await refreshStatus();
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}
</script>

<template>
  <div>
    <div class="grid-stats">
      <div class="stat" :class="{ ok: st.pid_guard_enabled === '1' }">
        <b>{{ t("pid.enabled") }}</b><span>{{ st.pid_guard_enabled === "1" ? t("common.yes") : t("common.no") }}</span>
      </div>
      <div class="stat" :class="{ ok: st.pid_guard_loaded === '1' }">
        <b>{{ t("pid.loaded") }}</b><span>{{ st.pid_guard_loaded === "1" ? t("common.yes") : t("common.no") }}</span>
      </div>
      <div class="stat" :class="{ bad: st.pid_guard_visible === '1' }">
        <b>{{ t("pid.visible") }}</b><span>{{ st.pid_guard_visible === "1" ? t("common.yes") : t("common.no") }}</span>
      </div>
      <div class="stat" :class="{ ok: st.pid_guard_hidden === '1' }">
        <b>{{ t("pid.hidden") }}</b><span>{{ st.pid_guard_hidden === "1" ? t("common.yes") : t("common.no") }}</span>
      </div>
      <div class="stat" :class="{ bad: st.pid_guard_result && st.pid_guard_result !== 'ok' && st.pid_guard_result !== 'unloaded' }">
        <b>{{ t("pid.result") }}</b><span>{{ RESULT[st.pid_guard_result] || st.pid_guard_result || "—" }}</span>
      </div>
      <div class="stat">
        <b>{{ t("pid.matches") }}</b><span class="mono">{{ st.pid_guard_comms || "—" }}</span>
      </div>
    </div>

    <div class="card">
      <h2>{{ t("pid.rules") }} <span class="hint">Beta</span></h2>
      <div v-if="!ready" class="hint">{{ t("common.loading") }}</div>
      <template v-else>
        <label class="row">
          <span>{{ t("pid.rules.enable") }}</span>
          <span class="switch"><input v-model="form.enabled" type="checkbox" /><i /></span>
        </label>
        <div class="field">
          <label>{{ t("pid.rules.uids") }}</label>
          <input v-model="form.uids" type="text" placeholder="99000-99999" />
        </div>
        <div class="field">
          <label>{{ t("pid.rules.comms") }}</label>
          <input v-model="form.comms" type="text" placeholder="probe-*,canProbe*" />
        </div>
        <div class="field">
          <label>{{ t("pid.rules.excludes") }}</label>
          <input v-model="form.excludes" type="text" placeholder="nqiunativecheck" />
        </div>
        <p class="hint">{{ t("pid.rules.hint") }}</p>
        <div class="btn-row">
          <button class="btn primary" type="button" :disabled="state.busy" @click="doSave">
            {{ state.busy ? t("common.busy") : t("common.save") }}
          </button>
          <button class="btn ghost" type="button" :disabled="state.busy" @click="doRefresh">
            {{ t("common.refresh") }}
          </button>
        </div>
      </template>
    </div>
  </div>
</template>
