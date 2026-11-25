<!-- SPDX-License-Identifier: GPL-3.0-only -->
<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import AboutTab from "./components/AboutTab.vue";
import ConfigTab from "./components/ConfigTab.vue";
import LogTab from "./components/LogTab.vue";
import PidTab from "./components/PidTab.vue";
import Wizard from "./components/Wizard.vue";
import StatusTab from "./components/StatusTab.vue";
import { hasKsu } from "./bridge";
import { t } from "./i18n";
import { clearBanner, closeWizard, openWizard, refreshStatus, state, withBusy } from "./store";

const WIZARD_KEY = "wizard_done_v1";
function readWizardFlag(): boolean {
  try {
    return localStorage.getItem(WIZARD_KEY) === "1";
  } catch {
    return true;
  }
}
function markWizardSeen(): void {
  try {
    localStorage.setItem(WIZARD_KEY, "1");
  } catch {
    /* 存不下就算了 */
  }
  closeWizard();
}

function maybeAutoWizard(): void {
  // 还没走完向导就自动进入一次
  if (!readWizardFlag()) openWizard(false);
}

const ICONS = {
  status: '<path d="M22 12h-4l-3 7-4-14-3 7H2"/>',
  config: '<line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="12" x2="20" y2="12"/><line x1="4" y1="17" x2="20" y2="17"/>',
  pidguard: '<path d="M12 3l7.5 3.2v5.4c0 4.6-3.2 8.7-7.5 9.9-4.3-1.2-7.5-5.3-7.5-9.9V6.2L12 3z"/>',
  log: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3"/><path d="M13 15h4"/>',
  about: '<circle cx="12" cy="12" r="9"/><path d="M12 10v6"/>',
};

type TabId = "status" | "config" | "pidguard" | "log" | "about";

const TABS: { id: TabId; key: string; comp: unknown; icon: string }[] = [
  { id: "status", key: "nav.status", comp: StatusTab, icon: ICONS.status },
  { id: "config", key: "nav.config", comp: ConfigTab, icon: ICONS.config },
  { id: "pidguard", key: "nav.pidguard", comp: PidTab, icon: ICONS.pidguard },
  { id: "log", key: "nav.log", comp: LogTab, icon: ICONS.log },
  { id: "about", key: "nav.about", comp: AboutTab, icon: ICONS.about },
];

const tab = ref<TabId>(tabFromHash());
const contentEl = ref<HTMLElement | null>(null);

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
  return t("status.running");
});

function pick(id: TabId): void {
  tab.value = id;
  // 切页后滚动位置必须归零：继承上一页的 scrollTop 会让新页面看起来「跳」一下
  if (contentEl.value) contentEl.value.scrollTop = 0;
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
  maybeAutoWizard();
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

    <main ref="contentEl" class="content">
      <component :is="current" v-if="!noKsu" />
    </main>

    <nav class="tabs">
      <button
        v-for="item in TABS"
        :key="item.id"
        type="button"
        :class="['tab', { active: tab === item.id }]"
        @click="pick(item.id)"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" v-html="item.icon" />
        <span>{{ t(item.key) }}</span>
      </button>
    </nav>
    <Wizard v-if="state.wizard.open" :replay="state.wizard.replay" @close="markWizardSeen" />
  </div>
</template>
