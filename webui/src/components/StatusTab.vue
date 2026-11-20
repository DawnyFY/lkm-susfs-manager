<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import Sheet from "./Sheet.vue";
import { applyRules, exportLog, getAnnouncement, loadAndApply, type Announcement } from "../api";
import { t } from "../i18n";
import { refreshStatus, setBanner, state, withBusy } from "../store";

const s = computed(() => state.status);
const announce = ref<Announcement | null>(null);
const announceOpen = ref(false);

onMounted(async () => {
  announce.value = await getAnnouncement();
});

// 状态圆点：值命中 ok 列表为绿，命中 bad 列表为红，其余灰
function dotClass(v: string, okList: string[], badList: string[]): string {
  if (okList.includes(v)) return "dot ok";
  if (badList.includes(v)) return "dot bad";
  return "dot";
}

const backendText = computed(() => {
  const k = s.value.susfs_kernel || "";
  if (k === "builtin") return t("status.builtin");
  if (k === "lkm") return t("status.lkmkind");
  return t("common.none");
});

const lkmState = computed(() => {
  const v = s.value.lkm_present;
  if (v === "1") return t("status.loaded");
  if (v === "0") return t("status.not_loaded");
  return t("common.none");
});

async function doLoadApply(): Promise<void> {
  await withBusy(async () => {
    try {
      const r = await loadAndApply();
      if (r.code === 0) setBanner("ok", t("msg.applied"));
      else if (r.code === 5) setBanner("info", t("msg.partial"));
      else setBanner("err", (r.stderr || r.stdout || "").trim() || t("msg.apply_failed", { e: r.code }));
      await refreshStatus();
    } catch (e) {
      setBanner("err", t("msg.apply_failed", { e: (e as Error).message }));
    }
  });
}

async function doApplyOnly(): Promise<void> {
  await withBusy(async () => {
    try {
      const r = await applyRules();
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
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}

async function doExport(): Promise<void> {
  await withBusy(async () => {
    try {
      const out = (await exportLog()).trim();
      const path = out.split(String.fromCharCode(10)).filter(Boolean).pop() || out;
      setBanner("ok", t("msg.exported", { p: path }), 8000);
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}
</script>

<template>
  <div>
    <!-- hero：当前内核 + 两个 chip + 主动作 -->
    <div class="card hero">
      <p class="hero-label">{{ t("status.current_kernel") }}</p>
      <p class="hero-kernel mono">{{ s.kernel || "—" }}</p>
      <div class="chips">
        <span class="chip mono">{{ t("status.kmi") }} {{ s.kmi || "—" }}</span>
        <span class="chip mono lkm">LKM {{ s.lkm_version || "—" }}</span>
      </div>
      <div class="hero-actions">
        <button class="btn primary" type="button" :disabled="state.busy" @click="doLoadApply">
          {{ state.busy ? t("common.busy") : t("status.load_apply") }}
        </button>
        <button class="btn" type="button" :disabled="state.busy" @click="doApplyOnly">
          {{ t("status.apply_only") }}
        </button>
        <button class="btn" type="button" :disabled="state.busy" @click="doRefresh">
          {{ t("common.refresh") }}
        </button>
      </div>
    </div>

    <!-- 公告行：点击打开二级窗口（1.2.7 的 #announceModal） -->
    <div v-if="announce && announce.summary" class="card announce">
      <span class="badge-mini">{{ t("status.announce") }}</span>
      <span class="announce-text">{{ announce.summary }}</span>
      <button class="link-btn" type="button" @click="announceOpen = true">{{ t("status.detail") }}</button>
    </div>
    <Sheet v-if="announce" :open="announceOpen" :title="t('status.announce')" @close="announceOpen = false">
      <p class="announce-text">{{ announce.summary }}</p>
      <ul v-if="announce.items && announce.items.length" class="announce-list">
        <li v-for="(item, i) in announce.items" :key="i">{{ item }}</li>
      </ul>
      <p v-if="announce.updated" class="hint">{{ announce.updated }}</p>
      <template #actions>
        <a class="btn" href="https://susfs.stdawns.top/" target="_blank" rel="noopener">{{ t("status.release_page") }}</a>
        <button class="btn primary" type="button" @click="announceOpen = false">{{ t("common.close") }}</button>
      </template>
    </Sheet>

    <!-- 指标：2 列，标签在上、值在下、带状态圆点 -->
    <div class="grid-stats">
      <div class="stat">
        <b>{{ t("status.lkm_state") }}</b>
        <span><i :class="dotClass(s.lkm_present || '', ['1'], ['0'])" />{{ lkmState }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.rules") }}</b>
        <span class="mono">{{ s.rules || "0" }}</span>
      </div>
      <div class="stat">
        <b>kernelsu {{ t("status.hidden") }}</b>
        <span><i :class="dotClass(s.hide_kernelsu || '', ['1'], ['0'])" />{{ s.hide_kernelsu === "1" ? t("status.hidden_yes") : t("status.hidden_no") }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.autoload") }}</b>
        <span>{{ s.auto_load === "1" ? t("common.on") : t("common.off") }}</span>
      </div>
      <div class="stat">
        <b>ksu_susfs</b>
        <span><i :class="dotClass(s.ksu_bin || '', ['ok'], ['missing'])" />{{ s.ksu_bin || t("common.none") }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.selinux") }}</b>
        <span class="mono">{{ s.selinux || "—" }}</span>
      </div>
      <div class="stat">
        <b>{{ t("status.backend") }}</b>
        <span>{{ backendText }}</span>
      </div>
      <div class="stat" :class="{ bad: s.integrity && s.integrity !== 'ok' }">
        <b>{{ t("status.integrity") }}</b>
        <span><i :class="dotClass(s.integrity || '', ['ok'], [])" />{{ s.integrity || "—" }}</span>
      </div>
    </div>

    <!-- 运行环境 -->
    <p class="section-label">{{ t("status.env") }}</p>
    <div class="card">
      <div class="row"><span>{{ t("status.manager") }}</span><span>{{ s.root_manager || "—" }}</span></div>
      <div class="row"><span>{{ t("status.lkm_variant") }}</span><span class="mono">{{ s.lkm_variant || "—" }}</span></div>
      <div class="row"><span>ksu_susfs {{ t("status.path") }}</span><span class="mono">{{ s.ksu_bin_path || "—" }}</span></div>
      <div class="row"><span>WebUI {{ t("status.marker") }}</span><span>{{ s.marker || t("status.not_created") }}</span></div>
      <div class="row"><span>{{ t("status.fail_count") }}</span><span class="mono">{{ s.fail_count || "0" }}</span></div>
      <div class="row"><span>{{ t("status.module_version") }}</span><span class="mono">{{ s.module_version || "—" }}</span></div>
      <p v-if="s.description" class="hint">{{ s.description }}</p>
      <div class="btn-row">
        <button class="btn ghost" type="button" :disabled="state.busy" @click="doExport">
          {{ t("status.export") }}
        </button>
      </div>
    </div>
  </div>
</template>
