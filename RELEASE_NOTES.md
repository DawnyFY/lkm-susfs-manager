# LKM SUSFS管理器 v1.2.7

> 1.2.7 加入匿名安装统计开关：默认开启，首次安装或升级后申请一次版本绑定 token；只发送随机 install_id 和模块版本，不发送设备信息、路径或日志。可随时在 WebUI 关闭。

## 重点变化

- **匿名安装统计**：新增 `anonymous_stats` 开关（默认 1）。首次开机或保存配置时向 `/api/v1/install` 申请一次 token；同一 versionCode 只申请一次，失败不阻塞开机。关闭开关会删除本地 `state/server_token`，不再请求。
- **服务端只记统计**：只保存 install_id、版本、首次/最近时间；token 用服务端 HMAC 签名，绑定 versionCode 和 180 天有效期，为后续日志上传预留凭证，但本版不做日志上传接口。
- **失败日志自动上传**：只有加载/应用失败时，先在手机本地保存一份快照，再上传 load.log/apply.log 尾段（约 48KB）到 `/api/v1/failure`；成功/跳过不上传。无独立开关，关闭匿名统计即无 token，也就不会上传。
- **隐私边界**：不发送设备型号、序列号、路径、日志；安装密钥仍只在本地生成，install_id 是它的 SHA-256 前缀。

## 验证

- 34/34 离线测试通过（新增匿名统计测试：开关、同版本不重复请求、关闭删除 token）。
- 真机（Xiaomi 15 Ultra / Android 16 / 6.6.77 / SukiSU）：
  - 1.2.7 安装成功，versionCode 19
  - WebUI/ctl 申请 token 成功，`state/server_token` 600 权限
  - D1 只写入当前 install_id + 1.2.7 + 时间戳
  - 关闭开关后本地 token 删除
- 1.2.6 的 loop、日志导出、install_key 回归仍通过。

## 风险 / 限制

- 服务端只接受 1.2.7 / versionCode 19；升级后需要更新 Worker 的允许版本。
- 统计默认开启；不需要可在 WebUI 关闭，关闭不会删除服务端已写入的匿名记录。
- 统计失败不影响模块加载和规则。
- 仍不承诺过检测；APatch 实验性、Magisk 冷启动未验证、其余 KMI 未逐一实机。

## 文件

- 文件：`susfs_allinone-1.2.7.zip`
- 大小：12,645,664 B
- sha256：f7b67627cd31b845fd3b1fa83784125987070cf8110b443f84571fa655c3a140

## 升级

1.2.6 用户可覆盖安装；1.2.5 仍需先手动安装 1.2.6 或 1.2.7。
