# SUSFS 管理器配置
# auto_load=1：开机自动加载 LKM 并应用规则；0：只在手动操作时加载
auto_load=1
# 非 root 进程隐藏 SUS 挂载点
hide_sus_mnts=1
# AVC 日志伪装（默认关闭）
avc_spoof=0
# 应用前清空未列出的普通 sus_path 规则，让删除规则立即生效
# 如果还有其他模块/工具在写 sus_path，可改为 0
replace_rules=1
