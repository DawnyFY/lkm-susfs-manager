#!/bin/sh
# 离线测试：WebUI 保存配置时保留未知键/注释/特殊取值（1.2.9 起逻辑在 webui/src/ini.ts）
# 行为本身由 webui/tests/ini.spec.ts 覆盖（vitest）；这里做离线可跑的静态与源码级断言，
# 保证不装 node_modules 也能拦住「把保留逻辑改坏」。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

INI="$ROOT/webui/src/ini.ts"
CFG="$ROOT/webui/src/components/ConfigTab.vue"
SPEC="$ROOT/webui/tests/ini.spec.ts"

# ini.ts：必须按行改写、保留注释与未知键、不重复插入
chk "ini.ts 存在" "$([ -f "$INI" ] && echo yes || echo no)" "yes"
chk "按行改写" "$(grep -c 'map((line)' "$INI" 2>/dev/null)" "1"
chk "命中即替换不追加" "$(grep -c 'if (!hit)' "$INI" 2>/dev/null)" "1"
chk "未命中才追加" "$(grep -c 'out.push(key' "$INI" 2>/dev/null)" "1"

# 行为断言在 vitest 里，静态检查确认用例还在
ge1() { [ "${2:-0}" -ge 1 ] && echo yes || echo no; }
chk "spec 覆盖未知键" "$(ge1 x "$(grep -c 'brand_new' "$SPEC" 2>/dev/null)")" "yes"
chk "spec 覆盖注释保留" "$(ge1 x "$(grep -c 'replace_rules=9' "$SPEC" 2>/dev/null)")" "yes"

# UI 必须暴露 skip_detection_paths 与三态 replace_rules
chk "UI 有跳过检测器开关" "$(ge1 x "$(grep -c 'skip_detection_paths' "$CFG" 2>/dev/null)")" "yes"
chk "UI 有 replace_rules 三态" "$(grep -c 'value="2"' "$CFG" 2>/dev/null)" "1"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
