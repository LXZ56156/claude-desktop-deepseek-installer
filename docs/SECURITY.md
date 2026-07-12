# 安全设计

## 默认拒绝

执行模式为 `TestSafe`、`DryRun`、`Live`。默认是 TestSafe；Live 需要独立确认，
而 `Scaffold` 阶段无条件拒绝 Live。环境变量不能单独授权真实操作。

## 供应链

- Claude Desktop MSIX 只接受 Anthropic 官方来源。
- Git for Windows 只接受官方来源。
- 下载、安装、升级必须分阶段；安装函数必须消费有效的签名证据。
- 签名证据未来同时覆盖 artifact type、路径绑定 token、当前文件 SHA-256、
  Authenticode 状态、可信证书链、预期 Publisher、包身份和来源元数据。安装前
  必须重新计算并匹配 SHA-256；没有跳过验签参数。
- 官方 URL、Publisher 和包身份尚未确认，因此 defaults 中保持 `null`，不得在
  未核验前启用下载。

## API Key

- 不接受明文命令行参数，不静默 Trim。
- 拒绝空白、多行、控制字符和不符合固定格式的输入。
- 未来返回 SecureString 或不可序列化 credential handle；明文只允许出现在最短
  的 API/配置适配器边界，并立即清理可清理的非托管内存。
- 日志 sink、异常、状态、报告和 Release 扫描采用完整脱敏，不保留末尾字符。
- TestSafe/DryRun 文件日志只能显式写入 OS 临时目录下本次运行唯一、尚不存在且
  祖先无重解析点的 `cddsi-<GUID>` 目录；脚手架阶段拒绝 Live 文件日志。
- 测试中的 Key 只能在运行时用片段构造；Fixtures 不得包含看似真实的 token。

## 配置与备份

- 写入目标只能是 configLibrary，拒绝任何 `.claude/settings.json` 目标。
- 原子写合同：同目录唯一临时文件、严格序列化、重读 schema、flush、原子
  Replace/Move、写后哈希、失败回滚。
- 可恢复备份含敏感材料时必须加密并限制 ACL；状态只记录 ID/hash。
- 脱敏快照不含凭据且不可作为恢复源。

## 报告与隐私

默认只生成中文脱敏报告。不得记录原始配置、用户名、完整本机路径、代理口令、
Authorization header、API 响应正文中的敏感字段或 Claude Code 配置内容。

## 当前未决风险

- configLibrary 的官方 schema 与 Claude Desktop 版本兼容性。
- Anthropic MSIX 和 Git 安装包的官方固定身份。
- Cowork 服务名和 Windows 功能依赖。
- DPAPI 恢复包的生命周期与跨重启清理。
- settings.json 零读取政策与前后哈希要求的冲突。
