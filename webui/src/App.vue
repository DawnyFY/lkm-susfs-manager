<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import AboutTab from "./components/AboutTab.vue";
import ConfigTab from "./components/ConfigTab.vue";
import LogTab from "./components/LogTab.vue";
import PidTab from "./components/PidTab.vue";
import StatusTab from "./components/StatusTab.vue";
import { hasKsu } from "./bridge";
import { t } from "./i18n";
import { clearBanner, refreshStatus, state, withBusy } from "./store";

type TabId = "status" | "config" | "pidguard" | "log" | "about";

const TABS: { id: TabId; key: string; comp: unknown }[] = [
  { id: "status", key: "nav.status", comp: StatusTab },
  { id: "config", key: "nav.config", comp: ConfigTab },
  { id: "pidguard", key: "nav.pidguard", comp: PidTab },
  { id: "log", key: "nav.log", comp: LogTab },
  { id: "about", key: "nav.about", comp: AboutTab },
];

const tab = ref<TabId>(tabFromHash());

function tabFromHash(): TabId {
  const h = (location.hash || "").replace("#", "");
  return TABS.some((x) => x.id === h) ? (h as TabId) : "status";
}

const current = computed(() => TABS.find((x) => x.id === tab.value)?.comp);
const noKsu = ref(!hasKsu());
const pillClass = computed(() => {
  const s = state.status;
  if (!state.loaded) return "pill";
  if (s.integrity && s.integrity !== "ok") return "pill bad";
  if (s.apply_result && s.apply_result !== "success" && s.apply_result !== "not_tested") return "pill bad";
  return "pill ok";
});
const pillText = computed(() => {
  if (!state.loaded) return t("app.detecting");
  const s = state.status;
  if (s.susfs_kernel === "none" || s.lkm_present === "0") return t("common.off");
  return "OK";
});

function pick(id: TabId): void {
  tab.value = id;
  try {
    history.replaceState(null, "", "#" + id);
  } catch {
    /* 忽略 */
  }
}

window.addEventListener("hashchange", () => {
  tab.value = tabFromHash();
});

onMounted(async () => {
  if (noKsu.value) return;
  await withBusy(async () => {
    try {
      await refreshStatus();
    } catch {
      /* 状态读取失败不阻塞页面 */
    }
  });
});
</script>

<template>
  <div class="app">
    <header class="topbar">
      <div class="brand-text">
        <h1>LKM SUSFS管理器</h1>
        <p>{{ t("app.subtitle") }}</p>
      </div>
      <div :class="pillClass">{{ pillText }}</div>
    </header>

    <div v-if="noKsu" class="banner err">{{ t("common.no_ksu") }}</div>
    <div v-if="state.banner.text" :class="['banner', state.banner.kind || 'info']" @click="clearBanner()">
      {{ state.banner.text }}
    </div>

    <nav class="tabs">
      <button
        v-for="item in TABS"
        :key="item.id"
        type="button"
        :class="['tab', { active: tab === item.id }]"
        @click="pick(item.id)"
      >
        {{ t(item.key) }}
      </button>
    </nav>

    <component :is="current" v-if="!noKsu" />
  </div>
</template>
