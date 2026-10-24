# 变更记录

| 版本 | 摘要 |
|---|---|
| 1.1.8 | 内核诊断 `kmiinfo`；强制 KMI 下拉；匹配失败仍可安装；uname 伪装与自动还原、开机真实内核快照；加载失败自动弹窗；修注释行被当规则下发、描述写入转义、`force_kmi` 白名单、配置内容校验 |
| 1.1.7 | 新增 5 个隐藏开关（KSU LOOP / REVANCED / 自定义 ROM / COMPAT MATRIX / CMDLINE）；修复热重启后 hide_modules 丢失；内核特性门控；构建增加 JS 语法检查 |
| 1.1.6 | 第三方声明补充 SUSFS 原始作者 simonpunk；构建可复现（固定时间戳） |
| 1.1.5 | 显示名改为 LKM SUSFS管理器；移除 WebUI 页头图标 |
| 1.1.4 | 修复 1.1.3 的 CRLF 缺陷；构建期 CR 门禁 |
| 1.1.2 | 开源协议合规：AGPL 全文、NOTICE、provenance 扩展 |
| 1.1.1 | 启动加固：load.sh 超时、半加载保护 |
| 1.1.0 | 首个整合版本 |