## 1.1.8

### 新增
- **内核诊断** `ctl.sh kmiinfo`：输出 osrelease、自动匹配结果、已打包 KMI、版本号推测、内核配置（LOCALVERSION / MODVERSIONS / CFI_CLANG），以及开机时记录的真实内核快照。
- **强制指定 KMI**：WebUI 配置页改为下拉，选项来自模块实际打包的 `.ko`，避免手输拼错；匹配失败时模块**照常安装**并写入 `install_kmi.txt`，模块描述同步标注“⚠️ 未匹配内核”。
- **uname 伪装 + 救援**：可伪装 `uname -r/-v`（仅影响用户态，不能跨版本加载 `.ko`）；开机时把真实内核写入 `state/real_uname.txt`，出错可执行 `ctl.sh restore_uname` 一键还原，无需重启。关闭开关后会自动还原并刷新快照。
- **加载失败自动弹窗**：WebUI 读取 `ctl.sh loadstatus`，判定 `nomatch` / `insmod_failed` / `not_loaded` 后弹窗给出原因与处理建议。

### 修复（本轮审计）
- 配置文件里的 `#` 注释行被当作规则下发（严重），新增 `clean_entry()` 统一过滤。
- 模块描述写入改为 `awk -v`，描述含 `#`、`&` 等字符不再破坏 `module.prop`。
- `force_kmi` 增加字符白名单，防止路径穿越。
- `ctl.sh set_config` 增加内容校验，含命令替换/分隔符的配置直接拒绝。
- `set_sdcard_root_path` 失败却报成功，改为按返回码如实记录。
- 构建不再把 `RELEASE_NOTES*` / `CHANGELOG*` 打进模块包。
- `check_zip.py` 版本断言改为与 `module.prop` 对比，`dist/` 取最新产物。
- 新增 `tools/check_no_crlf.py`，CI 覆盖 `.sh/.prop/.js/.css/.html/.json/.txt`。

### 验证
- 冷启动（无 root）：模块零执行，`verifiedbootstate=green`。
- 注入临时 root：`load.sh` 自动加载，`init_module(2489936 bytes, 102 symbols absolutized)`。
- 热重启：状态保持，`fail_count=0`。
- 设备：Xiaomi 15 Ultra / Android 16 / 6.6.77-android15-6.6 / SukiSU。

### 已知限制
- 本 LKM 未启用 `HIDE_SUS_MNTS`、`AVC_LOG_SPOOFING`、`SUS_PATH_LOOP`，对应开关会明确跳过。
- `模拟 VOLD 应用数据隔离` 与 `隐藏 VENDOR SEPOLICY` 刻意不移植（依赖开机早期阶段）。