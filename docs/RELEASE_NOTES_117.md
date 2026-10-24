## 1.1.7

### 新增
- **5 个隐藏开关**（WebUI 配置页，默认全关）：
  - 隐藏 KSU LOOP 挂载
  - 隐藏 REVANCED / YouTube / MicroG 模块路径
  - 隐藏自定义 ROM 路径（lineage / evolution / pixel / derpfest）
  - 隐藏 COMPAT MATRIX
  - 伪装 CMDLINE（`set_cmdline_or_bootconfig`）
- 所有开关**只隐藏实际存在的路径**，找不到时在 `apply.log` 写明原因，不会假装成功

### 修复
- **热重启后 `kernelsu` 隐藏丢失**：`load.sh` 加载成功后自动调用 `apply_hide_modules()`，`apply.sh` 每次应用也做幂等补写
- **配置文件末尾无换行时最后一条规则被静默丢弃**：4 处读取循环改为 `read ... || [ -n "$x" ]`
- **升级会覆盖用户配置**：构建与合并流程排除 `config/`
- **WebUI 卡在「读取中」**：`app.js` 曾因选择器缺括号整体语法错误，已修复并在构建时加 `node --check` 门禁

### 新增：内核特性门控
按 `ksu_susfs show enabled_features` 实际能力决定是否调用，不再静默失败：
- `HIDE_SUS_MNTS`、`AVC_LOG_SPOOFING`、`SUS_PATH_LOOP` 在部分 LKM 中不存在，会明确跳过并记日志

```
[i] 内核未启用 HIDE_SUS_MNTS，跳过（当前 LKM 不支持）
[i] 内核未启用 AVC_LOG_SPOOFING，跳过（当前 LKM 不支持）
```

### 验证
- 冷启动（无 root）→ 注入临时 root：LKM 自动加载，KMI `android15-6.6`，8 条规则，`kernelsu` 自动隐藏
- 热重启：状态全部保持，`fail_count=0`

### 与上游功能对照
`模拟 VOLD 应用数据隔离` 与 `隐藏 VENDOR SEPOLICY` **刻意不移植**——两者依赖开机早期阶段，late-load 环境下不可靠。详见 README「与上游功能的差异」。