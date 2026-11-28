# LKM SUSFS管理器 v1.3.3

> 1.3.3 是 fork 上游 LKM 的第一版：把 `/proc/susfs_path` 的 `add_loop` 打通，
> 让没有 `ksu_susfs` 的设备也能下发 loop 规则；另外补了配置补键与 dmesg 崩溃取证。

## 新增：`add_loop`（fork 补丁 P1）

上游 `/proc/susfs_path` 原本只接受 `add` / `del` / `clear`，而 loop 语义（路径稍后出现时自动隐藏）
只有 supercall 的 `CMD_SUSFS_ADD_SUS_PATH_LOOP` 能触发。1.3.3 给节点加了 `add_loop <path>`：

```sh
echo "add_loop /data/adb/modules/xxx" > /proc/susfs_path
```

内核侧只是把 supercall 里那段逻辑抽成 `sus_path_add_entry(pathname, allow_pending, self_protect)`，
再让节点解析器调用它（补丁 `source/upstream-lkm/patches/0001-proc-add-loop.patch`，+54/-39）。
shell 侧 `susfs_path_loop_node_add()` 已接入 apply：loop 规则按「ksu_susfs → 节点 add_loop → 退化成普通 sus_path」三级下发。

## 新增：配置补键

老配置缺的新键（例如 `susfs_log`）会在首次 apply 时按 `config.ini.default` 补齐：
只追加缺失项，用户已设的值不动、注释不抄、已有键不重复写。

## 新增：dmesg 崩溃取证

本模块所在的设备上 `pstore` 往往是空的（WARN 不落盘、panic 走 Qualcomm minidump），
所以开机与 apply 时会扫 `dmesg`，把 `cut here` / `Kernel panic` / `BUG:` 的上下文与调用栈存进
`state/crash_dmesg.txt`，可用 `ctl.sh crash_dmesg` 查看。

## 升级影响

- 新增配置键自动补齐，无需手动改配置
- loop 规则在旧内核（未打补丁的 LKM）上仍然退化成普通 sus_path，不会报失败
- 1.3.2 的 AVC 默认值、节点权限、上游 LKM 同步等行为保持不变

产物 18,678,821 B / `30b39df1dd9c364cb9e93a9d004ad94a562290909e88e081dc72cd4fbf0ac51f` / manifest `d352087b…`（60 文件）
