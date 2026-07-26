# AGENTS.md

本仓库执行 D-027 practical：先打通普通 Windows 11 用户的真实安装路径，再只针对
VM 中出现的失败补实现。禁止重新引入 D-026、P10A/P10B/P11、snapshot RSA、
relay/outbox、Automation、通用 evidence framework 或重复质量门。

## 产品范围

- 支持 Windows 11 x64 与 64 位 Windows PowerShell 5.1。
- 双击入口检查并复用可信 Git for Windows；缺失或损坏时安装官方最新版。
- 下载、验证并为当前用户安装官方最新版 Claude Desktop x64 MSIX。
- 在遮罩提示中读取一次 DeepSeek API Key，以 DPAPI CurrentUser 持久化。
- 写入项目拥有的最小 `HKCU\SOFTWARE\Policies\Claude` 第三方推理配置。
- 提供只读诊断和仅删除项目拥有配置的恢复入口。
- 首个 practical MVP 不负责 machine-wide Claude provisioning、VMP、重启恢复或
  Cowork 可用性；不得把这些描述成已验证。

## 强制安全边界

- 宿主机和 CI 不执行 Live 安装、AppX、注册表、凭据、真实进程关闭或产品网络路径。
  真实 Live 只在 disposable Windows VM 中由用户确认后运行。
- 永不定位、读取、枚举、哈希、备份或修改 `.claude\settings.json`。
- API Key 不得进入参数、环境变量、日志、异常、状态、报告、测试、截图或 Git。
- 安装器持久化的 Key 只能是 DPAPI CurrentUser 密文；helper 无参数、stdout 仅 token。
- Git 只接受 Git for Windows 官方 GitHub immutable release metadata、官方 SHA-256、
  受信任的预期 signer，并在执行前重新哈希。
- Claude 只接受官方 endpoint、`downloads.claude.ai`、预期 Anthropic signer、
  x64 `Claude` MSIX identity、manifest publisher 一致性，并在安装前重新哈希。
- 不修改全局 Git 配置、用户/系统 PATH、Windows Feature、服务或计划任务。
- 配置只写项目固定 allow-list 的 HKCU REG_SZ；冲突时 fail closed。
- Restore 必须先验证 ownership state 的固定 allow-list，且 ownership 最后删除。
- 用户取消、UAC 取消、下载/签名/readback 失败不得报告成功。

## 模块与入口

- `lib/bootstrap.ps1` 只按顺序加载 `common.ps1`、`installer.ps1`、
  `configuration.ps1`、`workflow.ps1`；顶层不得执行 Live 行为。
- `Start-Here.ps1` 默认 DryRun；只有六个 `.cmd` 用户入口显式传入 `-Live`。
- 不新增通用 provider、ledger、stage、receipt、snapshot 或 orchestrator 抽象。
  只有 VM 复现出的具体失败才允许增加窄实现与回归。
- 公开函数仅以 `config/public-functions.psd1` 为准；变更时同步聚焦测试。

## 测试与 Release

- 使用仓库锁定的 Pester 5.6.1；不得联网安装测试依赖。
- 唯一阻塞门是 64 位 Windows PowerShell 5.1 下的 `scripts/check.ps1`：
  一次 Pester、PS5.1 parser、Release DryRun、`git diff --check`。
- 测试不得触发真实网络、进程、注册表、AppX、凭据或系统修改。
- `scripts/release-manifest.psd1` 必须精确分类每个当前文件；ZIP 只包含
  `PackageFiles`，不得包含 tests、scripts、docs、`.dev` 或临时证据。
- 新增、删除或重命名文件时同步更新 manifest、测试和必要文档，并运行：
  `scripts/check.ps1`、`scripts/build-release.ps1 -DryRun`、`git diff --check`。

## 编码

- `.cmd` 必须 ASCII、无 BOM、CRLF；不得使用 `chcp 65001`。
- 面向 Windows PowerShell 5.1 的 `.ps1/.psd1` 使用 UTF-8 BOM、CRLF。
- Markdown/JSON/YAML/C# 使用 UTF-8、LF；所有文本有末尾换行、无尾随空格。

## Git 与 VM

- 唯一分支：`codex/repair/p10a-0a-fast-lane`；唯一 PR：#1。
- 不 force push、不改写历史、不创建重复 PR、不自动 merge/release/promotion。
- 推送前重新 fetch；remote 或 PR head 出现未知漂移时停止。
- VM 首先测试无 Git、无 Claude 的 happy path、真实 Chat、重复运行和 Restore；
  之后只对可复现失败补丁。Key 仅由用户在 VM 遮罩输入框本地输入。
