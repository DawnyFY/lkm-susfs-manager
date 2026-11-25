<!-- SPDX-License-Identifier: GPL-3.0-only -->
<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import avatarHhgbmh from "../assets/contributor.jpg";
import { reportInstall, setStats } from "../api";
import { locale, setLocale, t, type Locale } from "../i18n";
import { openWizard, refreshStatus, setBanner, state, withBusy } from "../store";
import { currentTheme, setTheme, type ThemeName } from "../theme";

const theme = ref<ThemeName>(currentTheme());


// 交流群：群号与加群链接（qm.qq.com 的短链，点开由 QQ 接管）
const GROUP_ID = "1019737433";
const GROUP_URL = "https://qm.qq.com/q/I1aYPXoIiy";

// 第一位贡献者用随包的图片（离线也稳），其余用 GitHub 头像链接（不进包）；
// 链接加载失败（离线 / 被管理器 CSP 拦）时回退首字母，避免出现破图图标。
const CREDITS = [
  {
    name: "旧梦一场雨",
    handle: "hhgbmh8-ux",
    url: avatarHhgbmh,
    initials: "旧",
    what: "about.credit.what",
  },
  {
    name: "dhc2082",
    handle: "dhc2082",
    url: "https://github.com/dhc2082.png?size=96",
    initials: "dh",
    what: "about.credit.ui",
  },
];
const avatarFailed = reactive<Record<string, boolean>>({});
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

    <p class="section-label">{{ t("about.wizard") }}</p>
    <div class="card">
      <div class="row">
        <span>
          {{ t("about.wizard") }}
          <span class="hint" style="display: block">{{ t("about.wizard.sub") }}</span>
        </span>
        <button type="button" class="btn small" @click="openWizard(true)">{{ t("about.wizard.btn") }}</button>
      </div>
    </div>

    <p class="section-label">{{ t("about.group") }}</p>
    <div class="card">
      <div class="row">
        <span>
          {{ t("about.group.name") }}
          <span class="hint" style="display: block">{{ t("about.group.id") }} · {{ GROUP_ID }}</span>
        </span>
        <a class="btn primary small" :href="GROUP_URL" target="_blank" rel="noopener noreferrer">
          {{ t("about.group.join") }}
        </a>
      </div>
      <p class="hint">{{ t("about.group.desc") }}</p>
    </div>

    <p class="section-label">{{ t("about.thanks") }}</p>
    <div class="card">
      <div v-for="c in CREDITS" :key="c.handle" class="credits">
        <img
          v-if="!avatarFailed[c.handle]"
          :src="c.url"
          :alt="c.handle"
          width="44"
          height="44"
          referrerpolicy="no-referrer"
          @error="avatarFailed[c.handle] = true"
        />
        <span v-else class="avatar-initials" aria-hidden="true">{{ c.initials }}</span>
        <span>
          {{ c.name }}
          <a class="gh" :href="'https://github.com/' + c.handle" rel="noopener noreferrer">@{{ c.handle }}</a>
          <span class="hint" style="display: block">{{ t(c.what) }}</span>
        </span>
      </div>
      <p class="hint">simonpunk · inforcqb · sidex15 · SukiSU Ultra</p>
    </div>
  </div>
</template>
