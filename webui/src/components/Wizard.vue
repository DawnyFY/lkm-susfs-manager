<!-- SPDX-License-Identifier: GPL-2.0-only -->
<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { getBundle, listKmis, presetPaths, saveBundle, type PresetPath, type RuleName } from "../api";
import { setIni } from "../ini";
import { t } from "../i18n";
import { refreshStatus, setBanner, state, withBusy } from "../store";

// 首次配置向导（五步）：内核匹配 → 隐藏项 → 隐藏路径 → 自动加载与统计 → 加载并应用。
// 只做「写 config.ini 的若干键 + 可选追加预设路径」，写盘复用 get_bundle / set_bundle，
// 不另开一套写入路径（避免和配置页两套逻辑漂移）。
const emit = defineEmits<{ (e: "close"): void }>();

interface Props {
  /** 从关于页进入时不必再走「首次」判断，仅用于文案 */
  replay?: boolean;
}
defineProps<Props>();

const step = ref(0);
const busy = ref(false);
const err = ref("");
const kmis = ref<string[]>([]);
const presets = ref<PresetPath[]>([]);
const config = ref("");
const rules = ref<Record<string, string> | null>(null);

// 第一步：内核
const curKmi = computed(() => state.status.kmi || "");
const curKernel = computed(() => state.status.kernel || "");
const kmiChoice = ref("");

// 第二步：推荐隐藏项（默认全开，都可以关）
// 隐藏项分两档：推荐（默认开）与谨慎（默认关，改了会变语义）
// 推荐档对应「出厂默认就该这样」的项：sus 挂载、AVC 日志、KSU loop；
// 谨慎档会替换既有规则或动 vendor/挂载行为，默认关，交给用户按需勾。
const HIDE_KEYS = [
  { key: "hide_sus_mnts", on: true, risk: false },
  { key: "avc_spoof", on: true, risk: false },
  { key: "hide_ksu_loop", on: true, risk: false },
  { key: "replace_rules", on: false, risk: true },
  { key: "auto_try_umount", on: false, risk: true },
  { key: "vold_isolation", on: false, risk: true },
  { key: "hide_vendor_sepolicy", on: false, risk: true },
] as const;
const hideOn = ref<Record<string, boolean>>(
  Object.fromEntries(HIDE_KEYS.map((k) => [k.key, k.on])) as Record<string, boolean>,
);

// 第三步：隐藏路径（只列设备上存在、且还没加入 sus_path 的）
const pathPicked = ref<Record<string, boolean>>({});
const visiblePresets = computed(() => presets.value.filter((p) => p.exists && !p.configured));

// 第四步：自动加载与统计
const autoLoad = ref(true);
const statsOn = ref(state.status.anonymous_stats !== "0");

const STEP_TOTAL = 5;
const NL = String.fromCharCode(10);
const canNext = computed(() => {
  if (busy.value) return false;
  if (step.value === 0) return true; // 内核匹配只是展示，允许不选
  return true;
});

function next(): void {
  if (step.value < STEP_TOTAL - 1) step.value += 1;
}

function prev(): void {
  if (step.value > 0) step.value -= 1;
}

function finish(): void {
  emit("close");
}

/** 真正写盘的部分；不自己包 withBusy，由调用方统一包一层 */
async function writeConfig(): Promise<void> {
  let text = config.value;
  for (const k of HIDE_KEYS) text = setIni(text, k.key, hideOn.value[k.key] ? "1" : "0");
  text = setIni(text, "auto_load", autoLoad.value ? "1" : "0");
  if (kmiChoice.value) text = setIni(text, "force_kmi", kmiChoice.value);
  // 预设路径：勾选的追加到 sus_path（已存在的不重复加）
  const r: Record<string, string> = { ...(rules.value as Record<string, string>) };
  const add = visiblePresets.value.filter((p) => pathPicked.value[p.path]).map((p) => p.path);
  if (add.length) {
    const cur = (r.sus_path || "").split(NL).filter((l) => l.trim());
    for (const p of add) if (!cur.includes(p)) cur.push(p);
    r.sus_path = cur.join(NL);
  }
  const out = await saveBundle(text, r as Record<RuleName, string>);
  if (!out.includes("saved")) throw new Error(out.trim() || "save failed");
}

/** 保存并应用：只包一层 withBusy */
async function applyNow(): Promise<void> {
  await withBusy(async () => {
    try {
      await writeConfig();
      await refreshStatus();
      step.value = STEP_TOTAL - 1;
      setBanner("ok", t("wizard.done.body", { n: state.status.rules || "0" }));
    } catch (e) {
      err.value = (e as Error).message;
      setBanner("err", err.value);
    }
  });
}

onMounted(async () => {
  busy.value = true;
  try {
    const b = await getBundle();
    config.value = b.config;
    rules.value = b.rules as unknown as Record<string, string>;
    kmiChoice.value = "";
    try {
      kmis.value = await listKmis();
    } catch {
      kmis.value = [];
    }
    try {
      presets.value = await presetPaths();
    } catch {
      presets.value = [];
    }
  } catch (e) {
    err.value = (e as Error).message;
  } finally {
    busy.value = false;
  }
});
</script>

<template>
  <div class="modal wizard-modal">
    <div class="modal-box wizard-box">
      <div class="wizard-head">
        <h2>{{ t("wizard.title") }}</h2>
        <span class="hint">{{ step + 1 }} / {{ STEP_TOTAL }}</span>
      </div>

      <div class="wizard-dots">
        <i v-for="n in STEP_TOTAL" :key="n" :class="{ on: n - 1 <= step }" />
      </div>

      <div class="wizard-body">
        <!-- 1. 内核匹配 -->
        <template v-if="step === 0">
          <p class="wizard-h">{{ t("wizard.kmi.title") }}</p>
          <div class="row"><span>{{ t("wizard.kmi.kernel") }}</span><span class="mono">{{ curKernel || "—" }}</span></div>
          <div class="row"><span>KMI</span><span class="mono">{{ curKmi || "—" }}</span></div>
          <p class="hint">{{ curKmi ? t("wizard.kmi.ok") : t("wizard.kmi.miss") }}</p>
          <p class="section-mini">{{ t("wizard.kmi.force") }}</p>
          <div class="btn-row wrap">
            <button
              v-for="k in kmis"
              :key="k"
              type="button"
              :class="['btn', 'small', { primary: kmiChoice === k }]"
              @click="kmiChoice = kmiChoice === k ? '' : k"
            >
              {{ k }}
            </button>
            <span v-if="!kmis.length" class="hint">{{ t("wizard.kmi.none") }}</span>
          </div>
        </template>

        <!-- 2. 隐藏项 -->
        <template v-else-if="step === 1">
          <p class="wizard-h">{{ t("wizard.hide.title") }}</p>
          <p class="hint">{{ t("wizard.hide.desc") }}</p>
          <p class="section-mini">{{ t("wizard.hide.rec") }}</p>
          <label v-for="k in HIDE_KEYS.filter((x) => !x.risk)" :key="k.key" class="row wizard-check">
            <span class="mono">{{ k.key }}</span>
            <span class="switch"><input type="checkbox" v-model="hideOn[k.key]" /><i /></span>
          </label>

          <p class="section-mini">{{ t("wizard.hide.risk") }}</p>
          <p class="hint">{{ t("wizard.hide.risk.desc") }}</p>
          <label v-for="k in HIDE_KEYS.filter((x) => x.risk)" :key="k.key" class="row wizard-check">
            <span class="mono">{{ k.key }}</span>
            <span class="switch"><input type="checkbox" v-model="hideOn[k.key]" /><i /></span>
          </label>
        </template>

        <!-- 3. 隐藏路径 -->
        <template v-else-if="step === 2">
          <p class="wizard-h">{{ t("wizard.path.title") }}</p>
          <p class="hint">{{ t("wizard.path.desc") }}</p>
          <label v-for="p in visiblePresets" :key="p.path" class="row wizard-check">
            <span>
              <span class="mono">{{ p.path }}</span>
              <span v-if="p.configured" class="hint" style="display: block">{{ t("wizard.path.added") }}</span>
            </span>
            <span class="switch">
              <input type="checkbox" v-model="pathPicked[p.path]" /><i />
            </span>
          </label>
          <p v-if="!visiblePresets.length" class="hint">{{ t("wizard.path.none") }}</p>
        </template>

        <!-- 4. 自动加载 / 统计 -->
        <template v-else-if="step === 3">
          <p class="wizard-h">{{ t("wizard.misc.title") }}</p>
          <label class="row wizard-check">
            <span>
              {{ t("wizard.misc.autoload") }}
              <span class="hint" style="display: block">{{ t("wizard.misc.autoload.sub") }}</span>
            </span>
            <span class="switch"><input type="checkbox" v-model="autoLoad" /><i /></span>
          </label>
          <label class="row wizard-check">
            <span>
              {{ t("wizard.misc.stats") }}
              <span class="hint" style="display: block">{{ t("wizard.misc.stats.sub") }}</span>
            </span>
            <span class="switch"><input type="checkbox" v-model="statsOn" /><i /></span>
          </label>
        </template>

        <!-- 5. 完成 -->
        <template v-else>
          <p class="wizard-h">{{ t("wizard.done.title") }}</p>
          <p class="hint">{{ t("wizard.done.body", { n: state.status.rules || "0" }) }}</p>
          <div class="row"><span>{{ t("wizard.done.integrity") }}</span><span class="mono">{{ state.status.integrity || "—" }}</span></div>
          <p class="hint">{{ t("wizard.done.next") }}</p>
        </template>

        <p v-if="err" class="warn">{{ err }}</p>
      </div>

      <div class="wizard-actions">
        <!-- 上一步：只在中间步骤出现 -->
        <button v-if="step > 0 && step < STEP_TOTAL - 1" type="button" class="btn small" :disabled="busy" @click="prev">
          {{ t("wizard.prev") }}
        </button>

        <!-- 结果页：重新应用 + 完成 -->
        <template v-if="step === STEP_TOTAL - 1">
          <button type="button" class="btn small" :disabled="busy" @click="applyNow">
            {{ t("wizard.reapply") }}
          </button>
          <button type="button" class="btn primary" :disabled="busy" @click="finish">
            {{ t("wizard.close") }}
          </button>
        </template>

        <!-- 中间步骤：跳过 + 下一步；第 4 步（最后一步之前）就是「应用并完成」 -->
        <template v-else>
          <button type="button" class="btn small" :disabled="busy" @click="finish">
            {{ t("wizard.skip") }}
          </button>
          <button
            v-if="step < STEP_TOTAL - 2"
            type="button"
            class="btn primary"
            :disabled="!canNext"
            @click="next"
          >
            {{ t("wizard.next") }}
          </button>
          <button v-else type="button" class="btn primary" :disabled="busy" @click="applyNow">
            {{ t("wizard.apply") }}
          </button>
        </template>
      </div>
    </div>
  </div>
</template>
