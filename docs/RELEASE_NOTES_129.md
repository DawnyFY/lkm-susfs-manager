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

3. 保存配置的线格式升级为「长度前缀」（issue #10）

- 段格式由 `<base64>` 改为 `<解码后字节数>:<base64>`，外层仍是整体 base64
- 目的：识别「base64 4 字符边界截断」——那种截断后仍是合法 base64，解出来只是内容前缀，
  重编码校验也一致，只有长度比对能发现
- 设备实测：把某段 base64 截短而长度前缀不改 → `rejected: decode sus_path.txt (长度不符：期望 18，实际 6)`，
  8 个文件零改动
- 向后兼容：不带长度前缀的旧格式（1.2.8 及更早前端）仍可写入

4. `status` 去掉大量进程启动（issue #9）

- 同一 boot 内的探测器结果缓存到 `state/.probe_cache`（ksu_branch / kernelpatch* / bootloader /
  install_id / selinux / 内核 config / ksu_susfs 版本与变体），换 boot_id 或二进制 size+mtime 变化才重算
- `pid_guard` 的 7 个状态字段、规则数统计、隐藏名单判断、`cfg_get`、`_cf_state`、`real_kernel_release`、
  `cap_ok`、`boot_stage_completed` 全部改为 shell 内建读取，不再各起一个 grep/cut/sed/awk
- 设备同条件交错 A/B（old/new 交替各 3 次 ×2 轮）：中位数 **~1.6 s → ~0.9 s**；空载最佳 0.75 s
- 未达 issue 里写的 < 0.5 s 目标：剩余开销主要是 mksh 解释约 1700 条内建命令 + 6 个外部进程，
  再往下需要把 status 挪进编译型 helper，属独立工作（issue #9 已更新说明）

5. 预设路径补充与语义修正

- 预设列表新增 `/data/local/tmp/brevent`（Brevent 的 root helper 落点）与
  `/data/local/tmp/AppRetention`、`/data/local/AppRetention`（按需出现）
- `ctl.sh preset_paths` 改为三列输出：`path<TAB>是否存在<TAB>是否已在 sus_path` ——
  原先只有「是否存在」一列，界面却当成「已加入」显示，勾选状态与实际不符
- 界面只列出设备上真实存在的路径；已加入的项标「已加入」并禁用勾选

6. 修复「kernelsu 隐藏」误报未隐藏（本轮改动的回归）

- 原因：#9 的少 fork 改造里把 `/proc/susfs_hide_modules` 的判断改成「整行等于模块名」，
  而该文件的格式是 `names: susfs_guard_lkm kernelsu generic_pid_guard`（空格分隔在同一行），
  于是 `kernelsu 隐藏` 与 `pid_guard_hidden` 恒为 0，状态页显示「未隐藏」
- 修复：抽出 `common.sh` 的 `hide_list_has()` 按词匹配，`status` 与 `pg_status_fields` 共用
- 回归测试：新增 `tools/test_hide_list.sh`（7 条断言，喂真实格式样本，含「按词不按行」和文件缺失）
- 设备实测：`hide_kernelsu=1`、`pid_guard_hidden=1`

7. 按线上失败日志修复的两个问题（1.2.8 用户实际遇到）

- **apply 锁被中断后卡 15 分钟**：锁目录里记录了持有者 PID，但 `lock_acquire` 只按 TTL 判断过期。
  上一次 apply 被杀（重启/管理器超时）后，锁留到 TTL 结束，用户连点三次都只看到
  「另一个 apply 正在运行」。现改为：持有者 PID 不存在就立即接管（`/proc/<pid>` 检查），
  TTL 900 s → 180 s，提示里带上持有者 PID 与「3 分钟后自动失效 / 重启立即释放」
- **无 Android tag 的 5.15 内核无法自动匹配**（线上日志 15 次同一内核 `5.15.223-ga3039b28d0a9`）：
  原逻辑按 SDK 精确匹配 `android<SDK>-5.15`，而 Android 16 上跑的 5.15 内核没有对应打包变体，
  于是直接跳过并要求手动指定。现增加兜底：取「不高于设备 SDK 的最高候选」试一次
  （选错只是 insmod 失败，与原来一样；选对则省掉人工操作），并在日志里注明这是推测值

8. 审计（1.2.9 候选）发现的三个缺陷

- **`cfg_get` 读不到带尾随空白的值**：`case *[![:space:]])` 在 glob 下不成立（`[:space:]` 不能被这样取反），
  于是 `auto_load=1␠␠` / `1␉` / `1␍` 这类行会被判成"全空白"并静默回落默认值。改为参数展开 + 有界循环去空白，
  设备实测 `auto_load=1␠␠␠` 现在能正确读到 `1`
- **`kernelpatch` / `apatch_userland` 恒为空**：少 fork 改造时把 `_KP=$_P_KP` 误写进了探测器内部（那里应该算
  `kernelpatch_present`），导致缓存里 `kp=` 永远为空，状态页两个字段空白、`coexist_mode` 恒 `none`
- **探测缓存半写会让整个 boot 的黑值**：缓存只校验首行 `sig=` 且非原子写。现改为 `$STATE/.probe_cache.$$` +
  原子 `mv`，并增加 `ok=1` 哨兵；文件被截断时视为未命中、当场重算

9. apply 锁改为单一互斥协议

- 审计实测：原「判定过期 → rm → mkdir」在 8 并发下会出现 **2–3 个进程同时持有**（后到者删掉前者的锁重建）
- 现所有判定与建锁都在 `state/.lock.mutex` 二级目录锁内完成；新增 `tools/test_apply_lock_race.sh`
  （8 并发 + 持锁窗口重叠检测），对旧实现可复现 3 个赢家，新实现恒为 1

10. 撤回「无 tag 内核自动猜 KMI」

- 审计证实 `bin/susfs_insmod` 会改写 `.modinfo` 的 vermagic 后**重试加载**，所以"猜错只是 insmod 失败"不成立，
  不同 android tag 的 ko 有可能真的进内核
- 改为只提示：`select_kmi` 不再自动采用兜底候选，新增 `suggest_kmi()` 用于日志建议，加载仍需用户显式指定

## 三、无变化

- WebUI、主题、语言、`get_bundle` / `pid_guard_bundle` 接口与 1.2.8 相同
- Probe PID Guard 仍为出厂关闭（`enabled=0`）；已在「PID 隐藏」页开启的配置不受影响
- 规则、隐藏项、匿名统计行为不变

## 四、已知限制（与 1.2.8 一致）

- `status` 从约 1.6 s 降到约 0.8–1.3 s（设备负载波动），重构计划见 issue #9
- `set_bundle` 检测不到 base64 4 字符边界截断，方案见 issue #10
- 冷启动首次自动装载未验证；其余 5 套 KMI 仅编译未运行；APatch 为实验性
- 不可执行 `rmmod susfs_guard_lkm`；热重启不重载 LKM，更换 ko 需冷启动
- 默认隐藏 `/data/adb`；NeoZygisk 用户需删除该行

## 五、验证

- 离线 39/39、前端 45/45、门禁 5/5、`I18N_OK keys=152`
- 设备（Android 16 / 6.6.77 / SukiSU）：`integrity=ok`，`rules` 与配置一致，日志块头与 pid_guard 记录按新格式输出
