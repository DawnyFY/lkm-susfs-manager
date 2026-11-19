<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import {
  RULE_ORDER,
  getConfigText,
  getRuleText,
  importLegacy,
  presetPaths,
  resetDefaults,
  rescanScene,
  saveBundle,
  type PresetPath,
  type RuleName,
} from "../api";
import { t } from "../i18n";
import { countRules, getIni, setIni } from "../ini";
import { refreshStatus, runSerial, setBanner, state, withBusy } from "../store";

const BOOL_KEYS = [
  "auto_load",
  "hide_sus_mnts",
  "avc_spoof",
  "auto_try_umount",
  "skip_detection_paths",
] as const;

const PATH_KEYS = [
  "hide_ksu_loop",
  "hide_revanced",
  "hide_custom_rom",
  "hide_compat_matrix",
  "hide_gapps",
  "hide_dex2oat",
  "hide_scene",
] as const;

const raws = reactive({ config: "" });
const rules = reactive<Record<RuleName, string>>({
  sus_path: "",
  sus_path_loop: "",
  hide_modules: "",
  skip_hide: "",
  sus_mount: "",
  try_umount: "",
  sus_map: "",
});
const cfg = reactive<Record<string, string>>({});
const presets = ref<PresetPath[]>([]);
const ruleTab = ref<"sus_path" | "sus_path_loop" | "hide_modules" | "skip_hide" | "advanced">("sus_path");
const ready = ref(false);

function isOn(key: string): boolean {
  return (cfg[key] || "0") === "1";
}
function setOn(key: string, v: boolean): void {
  cfg[key] = v ? "1" : "0";
}

const ruleTabs = computed(() => [
  { id: "sus_path" as const, label: "sus_path" },
  { id: "sus_path_loop" as const, label: "sus_path_loop" },
  { id: "hide_modules" as const, label: "hide_modules" },
  { id: "skip_hide" as const, label: "skip_hide" },
  { id: "advanced" as const, label: t("config.rules.advanced") },
]);

const currentCount = computed(() => {
  if (ruleTab.value === "advanced") {
    return countRules(rules.sus_mount) + countRules(rules.try_umount) + countRules(rules.sus_map);
  }
  return countRules(rules[ruleTab.value as RuleName] || "");
});

async function loadAll(): Promise<void> {
  const text = await getConfigText();
  raws.config = text;
  for (const k of [...BOOL_KEYS, ...PATH_KEYS, "replace_rules", "fake_cmdline", "fake_cmdline_value", "force_kmi", "spoof_uname", "spoof_uname_release", "spoof_uname_version", "hide_vendor_sepolicy", "vold_isolation"]) {
    cfg[k] = getIni(text, k, k === "replace_rules" ? "0" : "");
  }
  for (const name of RULE_ORDER) {
    rules[name] = await getRuleText(name);
  }
  ready.value = true;
}

const err = ref("");

// 首屏加载走串行队列（不占用全局 busy），并且无论如何都要结束「读取中」
async function bootstrap(): Promise<void> {
  err.value = "";
  ready.value = false;
  try {
    await runSerial(loadAll);
  } catch (e) {
    err.value = (e as Error).message;
    setBanner("err", err.value);
  } finally {
    ready.value = true;
  }
}

onMounted(bootstrap);

function retry(): void {
  void bootstrap();
}

function buildConfig(): string {
  let out = raws.config;
  for (const k of BOOL_KEYS) out = setIni(out, k, isOn(k) ? "1" : "0");
  for (const k of PATH_KEYS) out = setIni(out, k, isOn(k) ? "1" : "0");
  out = setIni(out, "replace_rules", cfg.replace_rules || "0");
  out = setIni(out, "fake_cmdline", isOn("fake_cmdline") ? "1" : "0");
  out = setIni(out, "fake_cmdline_value", (cfg.fake_cmdline_value || "").trim());
  out = setIni(out, "force_kmi", (cfg.force_kmi || "").trim());
  out = setIni(out, "spoof_uname", isOn("spoof_uname") ? "1" : "0");
  out = setIni(out, "spoof_uname_release", (cfg.spoof_uname_release || "").trim());
  out = setIni(out, "spoof_uname_version", (cfg.spoof_uname_version || "").trim());
  out = setIni(out, "hide_vendor_sepolicy", isOn("hide_vendor_sepolicy") ? "1" : "0");
  out = setIni(out, "vold_isolation", isOn("vold_isolation") ? "1" : "0");
  // 旧键：兼容保留，始终写 1（真实分区过滤始终生效）
  out = setIni(out, "skip_legit_mounts", "1");
  raws.config = out;
  return out;
}

async function doSave(): Promise<void> {
  await withBusy(async () => {
    try {
      const out = await saveBundle(buildConfig(), rules);
      if (!out.includes("saved")) throw new Error(out.trim() || "save failed");
      setBanner("ok", t("msg.saved"));
      await refreshStatus();
    } catch (e) {
      setBanner("err", t("msg.save_failed", { e: (e as Error).message }));
    }
  });
}

async function loadPresets(): Promise<void> {
  await withBusy(async () => {
    try {
      presets.value = (await presetPaths()).filter((p) => !p.configured);
      if (!presets.value.length) setBanner("info", t("config.presets.hint"));
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}

function addPreset(p: string): void {
  const cur = rules.sus_path.trimEnd();
  if (cur.split(/\r?\n/).some((l) => l.trim() === p)) return;
  rules.sus_path = (cur ? cur + "\n" : "") + p + "\n";
  presets.value = presets.value.filter((x) => x.path !== p);
  setBanner("ok", t("msg.preset_added", { p }));
}

async function doRescan(): Promise<void> {
  await withBusy(async () => {
    try {
      const out = await rescanScene();
      setBanner("ok", (out.trim() || t("msg.rescanned")).split(/\r?\n/).slice(-3).join(" · "));
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}

async function doImport(): Promise<void> {
  await withBusy(async () => {
    try {
      await importLegacy();
      await loadAll();
      setBanner("ok", t("msg.imported"));
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}

async function doReset(): Promise<void> {
  await withBusy(async () => {
    try {
      await resetDefaults();
      await loadAll();
      setBanner("ok", t("msg.reset"));
    } catch (e) {
      setBanner("err", (e as Error).message);
    }
  });
}
</script>

<template>
  <div>
    <div v-if="!ready" class="card"><p class="hint">{{ t("common.loading") }}</p></div>
    <div v-else-if="err" class="card">
      <p class="hint">{{ t("common.load_failed") }}：{{ err }}</p>
      <div class="btn-row"><button class="btn" type="button" @click="retry">{{ t("common.retry") }}</button></div>
    </div>

    <template v-else>
      <div class="card">
        <h2>{{ t("config.strategy") }}</h2>
        <label class="row">
          <span>{{ t("config.auto_load") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('auto_load')" @change="setOn('auto_load', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <label class="row">
          <span>{{ t("config.hide_sus_mnts") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('hide_sus_mnts')" @change="setOn('hide_sus_mnts', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <label class="row">
          <span>{{ t("config.avc_spoof") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('avc_spoof')" @change="setOn('avc_spoof', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <label class="row">
          <span>{{ t("config.auto_try_umount") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('auto_try_umount')" @change="setOn('auto_try_umount', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <label class="row">
          <span>{{ t("config.skip_detection_paths") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('skip_detection_paths')" @change="setOn('skip_detection_paths', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <div class="field">
          <label>{{ t("config.replace_rules") }}</label>
          <select v-model="cfg.replace_rules">
            <option value="0">{{ t("config.replace_rules.0") }}</option>
            <option value="1">{{ t("config.replace_rules.1") }}</option>
            <option value="2">{{ t("config.replace_rules.2") }}</option>
          </select>
        </div>
      </div>

      <div class="card">
        <h2>{{ t("config.paths") }}</h2>
        <label v-for="k in PATH_KEYS" :key="k" class="row">
          <span>{{ t("config." + k) }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn(k)" @change="setOn(k, ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <div class="btn-row">
          <button class="btn ghost" type="button" :disabled="state.busy" @click="doRescan">{{ t("config.rescan") }}</button>
          <button class="btn ghost" type="button" :disabled="state.busy" @click="loadPresets">{{ t("config.presets") }}</button>
        </div>
        <div v-if="presets.length" class="btn-row">
          <button v-for="p in presets" :key="p.path" class="btn" type="button" @click="addPreset(p.path)">
            + {{ p.path }}
          </button>
        </div>
      </div>

      <div class="card">
        <h2>{{ t("config.kernel") }}</h2>
        <div class="field">
          <label>{{ t("config.force_kmi") }}</label>
          <input v-model="cfg.force_kmi" type="text" :placeholder="t('config.force_kmi.auto')" />
        </div>
        <label class="row">
          <span>{{ t("config.fake_cmdline") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('fake_cmdline')" @change="setOn('fake_cmdline', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <div class="field">
          <label>{{ t("config.fake_cmdline_value") }}</label>
          <input v-model="cfg.fake_cmdline_value" type="text" :placeholder="t('config.fake_cmdline_value.ph')" />
        </div>
        <label class="row">
          <span>{{ t("config.spoof_uname") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('spoof_uname')" @change="setOn('spoof_uname', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <div class="field">
          <label>{{ t("config.spoof_uname_release") }}</label>
          <input v-model="cfg.spoof_uname_release" type="text" placeholder="6.6.99-custom" />
        </div>
        <div class="field">
          <label>{{ t("config.spoof_uname_version") }}</label>
          <input v-model="cfg.spoof_uname_version" type="text" placeholder="#1 SMP PREEMPT" />
        </div>
      </div>

      <div class="card">
        <h2>{{ t("config.blonly") }}</h2>
        <label class="row">
          <span>{{ t("config.hide_vendor_sepolicy") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('hide_vendor_sepolicy')" @change="setOn('hide_vendor_sepolicy', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
        <label class="row">
          <span>{{ t("config.vold_isolation") }}</span>
          <span class="switch"><input type="checkbox" :checked="isOn('vold_isolation')" @change="setOn('vold_isolation', ($event.target as HTMLInputElement).checked)" /><i /></span>
        </label>
      </div>

      <div class="card">
        <h2>{{ t("config.rules") }}</h2>
        <div class="rule-tabs">
          <button
            v-for="rt in ruleTabs"
            :key="rt.id"
            type="button"
            :class="['rule-tab', { active: ruleTab === rt.id }]"
            @click="ruleTab = rt.id"
          >
            {{ rt.label }}
          </button>
        </div>
        <p class="pane-caption">
          <span>{{ t("config.rules.count", { n: currentCount }) }}</span>
        </p>
        <textarea v-if="ruleTab === 'advanced'" v-model="rules.sus_mount" placeholder="sus_mount" />
        <template v-if="ruleTab === 'advanced'">
          <p class="pane-caption"><span>try_umount</span></p>
          <textarea v-model="rules.try_umount" />
          <p class="pane-caption"><span>sus_map</span></p>
          <textarea v-model="rules.sus_map" />
        </template>
        <textarea v-else v-model="rules[ruleTab as RuleName]" />
      </div>

      <div class="btn-row">
        <button class="btn primary" type="button" :disabled="state.busy" @click="doSave">
          {{ state.busy ? t("common.busy") : t("common.save") }}
        </button>
        <button class="btn ghost" type="button" :disabled="state.busy" @click="doImport">{{ t("config.import") }}</button>
        <button class="btn ghost" type="button" :disabled="state.busy" @click="doReset">{{ t("config.reset") }}</button>
      </div>
    </template>
  </div>
</template>
