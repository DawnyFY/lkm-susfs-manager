// config.ini 是纯 KEY=VALUE（不会被 source）。这里只做文本级读写，
// 保留注释与未知键，避免 WebUI 保存时把用户手写的内容抹掉。

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function getIni(text: string, key: string, fallback = ""): string {
  const re = new RegExp("^" + escapeRe(key) + "=(.*)$", "m");
  const m = String(text || "").match(re);
  return m ? m[1].trim() : fallback;
}

export function setIni(text: string, key: string, value: string): string {
  const lines = String(text || "").replace(/\r\n/g, "\n").split("\n");
  const re = new RegExp("^" + escapeRe(key) + "=");
  let hit = false;
  const out = lines.map((line) => {
    if (!hit && re.test(line)) {
      hit = true;
      return key + "=" + value;
    }
    return line;
  });
  if (!hit) {
    while (out.length && out[out.length - 1] === "") out.pop();
    out.push(key + "=" + value, "");
  }
  return out.join("\n");
}

// 非注释、非空行计数（规则文件的「N 条」用它）
export function countRules(text: string): number {
  return String(text || "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#")).length;
}

// PID 配置写回：保持固定键顺序与注释，只替换值
export function pidConfBuild(base: {
  enabled: number;
  uids: string;
  comms: string;
  excludes: string;
}): string {
  return (
    [
      "# Probe PID Guard（可选组件，默认关闭；打开后开机自动加载）",
      "# 1.2.8 起默认 0：需要时在 WebUI「PID 隐藏」页开启，或在下面改成 1",
      "enabled=" + (base.enabled ? 1 : 0),
      "# comma-separated UID ranges",
      "target_uids=" + base.uids,
      "# comma-separated comm prefixes, * suffix allowed",
      "target_comms=" + base.comms,
      "# never match these comms",
      "exclude_comms=" + base.excludes,
    ].join("\n") + "\n"
  );
}
