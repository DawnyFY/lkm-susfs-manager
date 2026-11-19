<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { computed, ref } from "vue";
import avatarUrl from "../assets/contributor.jpg";
import { reportInstall, setStats } from "../api";
import { locale, setLocale, t, type Locale } from "../i18n";
import { refreshStatus, setBanner, state, withBusy } from "../store";
import { currentTheme, setTheme, type ThemeName } from "../theme";

const theme = ref<ThemeName>(currentTheme());
const statsOn = computed(() => (state.status.anonymous_stats ?? "1") === "1");

function pickTheme(v: ThemeName): void {
  theme.value = v;
  setTheme(v);
}

function pickLocale(v: Locale): void {
  setLocale(v);
}

async function toggleStats(v: boolean): Promise<void> {
  await withBusy(async () => {
    try {
      await setStats(v);
      if (v) reportInstall().catch(() => undefined);
      setBanner("ok", v ? t("msg.stats.on") : t("msg.stats.off"));
      await refreshStatus();
    } catch (e) {
      setBanner("err", t("msg.save_failed", { e: (e as Error).message }));
    }
  });
}
</script>

<template>
  <div>
    <div class="card">
      <h2>LKM SUSFS管理器</h2>
      <p class="hint" style="margin-top: 0">{{ t("about.intro") }}</p>
      <div class="row"><span>{{ t("about.kmi") }}</span><span class="mono">android12-5.10 – android17-6.18</span></div>
      <div class="row"><span>{{ t("about.managers") }}</span><span class="mono">KernelSU / Magisk / APatch (Beta)</span></div>
      <div class="row"><span>{{ t("about.lkm") }}</span><span class="mono">{{ state.status.lkm_version || "inforcqb/susfs4ksu-lkm" }}</span></div>
      <div class="row"><span>{{ t("about.loader") }}</span><span class="mono">susfs_insmod</span></div>
      <div class="row"><span>Version</span><span class="mono">{{ state.status.module_version || "—" }}</span></div>
      <p class="warn">{{ t("about.warn") }}</p>
    </div>

    <p class="section-label">{{ t("about.prefs") }}</p>
    <div class="card">
      <div class="row">
        <span>{{ t("about.theme") }}</span>
        <div class="btn-row" style="margin: 0">
          <button :class="['btn', 'small', { primary: theme === 'cool' }]" type="button" @click="pickTheme('cool')">
            {{ t("about.theme.cool") }}
          </button>
          <button :class="['btn', 'small', { primary: theme === 'warm' }]" type="button" @click="pickTheme('warm')">
            {{ t("about.theme.warm") }}
          </button>
        </div>
      </div>
      <div class="row">
        <span>{{ t("about.lang") }}</span>
        <div class="btn-row" style="margin: 0">
          <button :class="['btn', 'small', { primary: locale === 'zh-CN' }]" type="button" @click="pickLocale('zh-CN')">中文</button>
          <button :class="['btn', 'small', { primary: locale === 'en-US' }]" type="button" @click="pickLocale('en-US')">English</button>
        </div>
      </div>
      <label class="row">
        <span>
          {{ t("about.stats") }}
          <span class="hint" style="display: block">{{ t("about.stats.sub") }}</span>
        </span>
        <span class="switch">
          <input type="checkbox" :checked="statsOn" :disabled="state.busy" @change="toggleStats(($event.target as HTMLInputElement).checked)" /><i />
        </span>
      </label>
      <details>
        <summary>{{ t("about.privacy.more") }}</summary>
        <p class="hint">{{ t("about.privacy.text") }}</p>
      </details>
    </div>

    <p class="section-label">{{ t("about.thanks") }}</p>
    <div class="card">
      <div class="credits">
        <img :src="avatarUrl" alt="contributor" width="44" height="44" />
        <span>
          旧梦一场雨
          <a class="gh" href="https://github.com/hhgbmh8-ux" rel="noopener noreferrer">@hhgbmh8-ux</a>
          <span class="hint" style="display: block">{{ t("about.credit.what") }}</span>
        </span>
      </div>
      <div class="credits">
        <span class="avatar-initials" aria-hidden="true">dh</span>
        <span>
          dhc2082
          <a class="gh" href="https://github.com/dhc2082" rel="noopener noreferrer">@dhc2082</a>
          <span class="hint" style="display: block">{{ t("about.credit.ui") }}</span>
        </span>
      </div>
      <p class="hint">simonpunk · inforcqb · sidex15 · SukiSU Ultra</p>
    </div>
  </div>
</template>
