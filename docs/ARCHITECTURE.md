# 架构

## 定位

本项目独立安装和配置 Claude Desktop，不依赖 Claude Code CLI。目标配置目录是
`%LOCALAPPDATA%\Claude-3p\configLibrary`；Claude Code 的
`%USERPROFILE%\.claude\settings.json` 不属于本项目的配置域。

当前阶段为 `Scaffold`。所有领域模块仅公开合同、数据结构和 TODO，任何 Live
动作都会在公共安全门中失败。

## 依赖方向

```text
Start-Here / future orchestrator
  -> bootstrap
     -> logger
     -> common
     -> state
     -> desktop-env-check
     -> desktop-msix
     -> git-for-windows
     -> cowork-readiness
     -> deepseek-api
     -> desktop-config
     -> desktop-lifecycle
     -> desktop-acceptance
```

领域模块不彼此调用真实动作。编排器未来负责阶段顺序，acceptance 只消费结果。

## 统一结果结构

领域操作统一返回：

- `Operation`
- `Status`
- `Success`
- `Changed`
- `Mode`
- `ErrorCode`
- `MessageSafe`
- `Data`
- `RestartRequired`
- `PlannedChanges`
- `Warnings`

当前 TestSafe/DryRun 的潜在修改操作必须 `Changed=false`。状态与报告不得包含
凭据。

## 未来阶段流

```text
preflight
  -> Claude Desktop MSIX detect/download/signature/install-or-upgrade
  -> Git for Windows detect/signature/silent install if missing
  -> Cowork readiness
     -> optional Windows feature change
     -> explicit restart acknowledgement
     -> checkpoint and resume
  -> secure DeepSeek credential acquisition and validation
  -> protected backup + configLibrary atomic write
  -> Claude Desktop lifecycle (explicit Live only)
  -> Chat / Code / Cowork acceptance
  -> redacted Chinese report + rollback metadata
```

签名验证是安装/升级的强制前置证据，不存在 bypass 参数。证据 schema 包含
artifact type、路径绑定 token、文件 SHA-256、Authenticode、证书链、Publisher、
身份与官方来源策略；安装前必须对当前文件重算 SHA-256。网络来源只允许官方
元数据解析器返回的地址。

## 状态与续跑

状态位于未来的 `%LOCALAPPDATA%\ClaudeDesktopDeepSeekInstaller\state.json`，
使用 schema 版本、runId、阶段、已完成步骤、pending action、重启原因和恢复阶段。
状态只保存备份 ID/hash 等元数据，绝不保存 API Key、Authorization header 或
原始 configLibrary 内容。字段使用精确白名单，阶段/步骤/备份 ID 只允许有界安全
标识符，UTC 时间与重启关联不变量必须成立。写入将采用 sibling temp、重读校验、
flush 和原子替换。

## 配置与备份

- 目标路径必须精确解析为 `%LOCALAPPDATA%\Claude-3p\configLibrary`。
- Desired state 固定模型列表、关闭 model discovery，并启用 Chat、Code、Cowork。
- 可恢复备份未来使用 DPAPI CurrentUser 或经安全评审的等效机制。
- 脱敏快照用于诊断分享，不能恢复真实凭据。
- 原子写失败必须保留原配置与可诊断证据。

## Claude Code settings 完整性矛盾

“完全不读取 settings.json”与“计算前后 SHA-256”在物理上冲突。脚手架当前只
比较调用方提供的不透明 token，不解析、不定位、不读取该文件。后续需由产品决策
选择：允许隔离 provider 只哈希字节，或继续零读取并使用文件系统变更监控/外部
审计证据。未决策前不得实现真实文件读取。
