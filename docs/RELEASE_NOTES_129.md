# LKM SUSFS管理器 1.2.9 发布说明

**副标题：预设路径 / 强制指定 KMI / 公告改回二级窗口；修复日志重复与时间戳异常；其余与 1.2.8 相同**

覆盖安装保留 `config/` 与 `state/` 中的现有文件，配置格式与 1.2.8 相同，无需重新配置。

## 一、界面

1. 「预设路径」改回二级窗口：列出当前设备真实存在的路径，勾选后「追加所选」写入 `sus_path`；
   已在规则里的项标「已存在」并禁用勾选（与 1.2.7 的 `#presetModal` 一致）
2. 「强制指定 KMI」改回二级窗口：选项来自 `ctl.sh list_kmis`（模块实际打包的 `.ko`），
   首项为「自动匹配（推荐）」；配置过但已不打包的 KMI 显示「（未打包）」以提醒，避免手输拼错
3. 「公告」改回二级窗口：状态页只保留一行摘要 +「详情」，点开为窗口，内含条目列表、日期、
   「发布页」与「关闭」（与 1.2.7 的 `#announceModal` 一致）
4. 二级窗口用半透明遮罩 + 居中卡片，支持点遮罩关闭与 Esc 关闭；不使用毛玻璃滤镜
   （1.2.8 的白屏来自给外壳布局用 fixed，与弹窗无关，弹窗在 1.2.7 即为 fixed）

## 二、修复

1. `load.log` 中「Loaded kernel module」每行出现两次

- 原因：`ksud insmod` 自身会输出 `Loaded kernel module: <path>`，而 `pid_guard.sh` 又用同一句话写了一条日志
- 现改为独立文案：`[i] pid_guard 已加载（KMI 6.6，参数已生效）`
- Magisk / APatch 路径下这条日志仍然存在（该路径没有 ksud 的原话可依赖）
- 测试同步：断言新文案，并反向断言不再出现 ksud 原话

2. 冷启动日志出现 `1970-03-07 18:44:38` 这类时间戳

- 原因：开机早期 RTC 未同步，`date` 返回 1970 年
- 现改为年份不可信时输出开机时长：`=== SUSFS 管理器 load 开机+2997s（RTC 未同步） ===`
- 覆盖 `load.sh`、`apply.sh` 的块头与 `pid_guard.status` 的 `ts=`

3. `[=] pid_guard 未加载，无需卸载` 连续出现两次

- 原因：`load.sh` 与 `apply.sh` 都会调用 `pid_guard.sh`，卸载函数在「本来没加载」时也写日志
- 现改为无操作时不写日志，状态文件仍记录 `result=skipped`

## 三、无变化

- WebUI、主题、语言、`get_bundle` / `pid_guard_bundle` 接口与 1.2.8 相同
- Probe PID Guard 仍为出厂关闭（`enabled=0`）；已在「PID 隐藏」页开启的配置不受影响
- 规则、隐藏项、匿名统计行为不变

## 四、已知限制（与 1.2.8 一致）

- `status` 仍约 1.6–1.8 s，重构计划见 issue #9
- `set_bundle` 检测不到 base64 4 字符边界截断，方案见 issue #10
- 冷启动首次自动装载未验证；其余 5 套 KMI 仅编译未运行；APatch 为实验性
- 不可执行 `rmmod susfs_guard_lkm`；热重启不重载 LKM，更换 ko 需冷启动
- 默认隐藏 `/data/adb`；NeoZygisk 用户需删除该行

## 五、验证

- 离线 37/37、前端 44/44、门禁 5/5、`I18N_OK keys=141`
- 设备（Android 16 / 6.6.77 / SukiSU）：`integrity=ok`，`rules` 与配置一致，日志块头与 pid_guard 记录按新格式输出
