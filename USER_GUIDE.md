# 用户指南

> 当前状态：本仓库尚未提供可用的 Live 安装器，也没有可供真实安装的候选包。
> 现有入口只会返回 `scaffold_only`。仓库内的 VmDevelopment 授权骨架只能验证
> 独立确认、CAS、调用方声明的 adapter identity 字段和 `LiveReadOnly` provider
> 装载结构。该字段尚未与受信包内文件重新哈希绑定。冻结的
> 11 个只读探测 capability 尚未绑定到受信 adapter 定义，通用 dispatcher 当前会在
> 调用任何 provider 函数前以 `LIVE_READ_ONLY_ADAPTER_SOURCE_UNBOUND` 终止；本批没有真实系统探测，也不会
> 安装软件、修改系统、写入配置或发送 API 请求。本文件描述未来候选通过 P11
> 虚拟机验收后，正式发布包必须遵守的用户合同。

## 使用前

- 只使用项目正式发布页提供的原始 ZIP，并核对随发布提供的版本、SHA-256 和签名
  证据。校验失败时不要继续，也不要关闭、跳过或降级验签。
- 查看该版本的 Windows、Claude Desktop、Git 和 Cowork 支持矩阵。未经该版本实际
  验证的环境不应被理解为受支持。
- 保存正在进行的工作。流程可能请求 UAC、关闭或重启 Claude Desktop，以及手动
  重启 Windows；这些步骤都不能被“一键”自动越过。
- DeepSeek API Key 只在安装器的本地安全输入界面中输入。不要把 Key 放进命令行、
  环境变量、脚本、配置文件、聊天或支持工单。

## 安装流程

1. 解压完整 ZIP，不要单独复制入口脚本或修改包内文件。
2. 双击 `开始安装.cmd`。一次双击会发起完整流程，但不会代表用户自动同意提权、
   重启、覆盖配置或其他安全操作。
3. 阅读环境检查与变更计划。首版目标固定为 `Chat`、`Code`、`Cowork` 三项，不
   提供功能选择页，也不会因依赖失败而静默改成 Chat-only 成功。
4. 按提示分别确认必要操作。可能包括：安装或升级已验签的 Claude Desktop、确保
   Git for Windows 可用、处理 Virtual Machine Platform（VMP）、写入项目拥有的
   HKCU managed policy、关闭或重新启动 Claude Desktop。
5. 在本地安全输入 DeepSeek API Key。未来发布包必须使用受限 ACL、DPAPI
   CurrentUser 和已签名 credential helper；Claude 配置中只引用 helper，不保存
   明文 Key。
6. 等待写入后的重读验证、readiness 检查和分层验收。不要把中途出现的
   `READY`、已下载或已安装单项结果当成整体完成。

Git 是固定 Code surface 的必备前置。合格且路径唯一的 Git for Windows 会被复用；
缺失、过旧或损坏时才进入官方安装或升级流程。路径歧义、来源不明或必要确认被
拒绝时，安装器必须停止并报告非成功状态。

## 重启与续跑

- VMP 等步骤需要重启时，安装器应使用 `-NoRestart`，先创建不含凭据的受保护
  checkpoint，再返回 `RESTART_REQUIRED`。
- 保存工作并由用户手动重启 Windows。首版不创建计划任务或 RunOnce，也不自动
  重启。
- 重启后使用同一 Windows 用户、同一未经修改的发布包，再次双击
  `开始安装.cmd`。安装器必须验证 checkpoint 的所有权、版本、候选 hash 和续跑
  次数；损坏、陈旧或不匹配时会拒绝续跑。
- 不要手工编辑 checkpoint、registry 或 Claude 配置来强行越过阻断。

## 如何理解结果

整体运行状态：

- `SUCCEEDED`：固定三项 surface 的必需运行、能力和 UI 证据均满足该版本通过标准。
- `PARTIAL`：部分步骤或 surface 可用，但整体没有成功；按照报告完成后续动作。
- `RESTART_REQUIRED`：已安全停在重启点；手动重启后按“重启与续跑”继续。
- `ACTION_REQUIRED`：需要用户、管理员、IT 或支持人员处理明确阻断条件。
- `CANCELLED`：用户取消了必要确认，流程未完成。
- `FAILED`：安全验证、操作或恢复失败；停止继续安装并保留脱敏报告。

中英文 `.cmd` 和非 `-PassThru` PowerShell 入口都会输出固定四行：
`Status`、`ErrorCode`、`Changed`、`NextStep`。进程退出码固定为
`SUCCEEDED=0`、`FAILED=1`、`PARTIAL=2`、`RESTART_REQUIRED=3`、
`ACTION_REQUIRED=4`、`CANCELLED=5`；退出 0 只能表示整体 `SUCCEEDED`。

每个 surface 还会分别报告：

- 能力状态：`READY`、`BLOCKED`、`PENDING_RESTART`、`UNSUPPORTED` 或 `UNKNOWN`。
- UI 证据：`PASS`、`FAIL` 或 `NOT_TESTED`。`NOT_TESTED` 只表示没有 UI 验证证据，
  不表示通过。

`EffectiveSurfaces` 只反映本次实际 ready 的项目，不会改变固定的
`RequestedSurfaces=Chat,Code,Cowork`，也不能把部分可用包装成整体成功。

## 诊断、修复与恢复

- 正式发布包可通过 `一键诊断.cmd` 生成中文脱敏诊断，不应隐式修改系统。
- `恢复配置.cmd` 只能恢复项目拥有且有完整所有权证据的配置和凭据；执行前仍需
  独立确认与重读验证。
- 恢复是逐资源报告的：项目拥有资源应为 `FULL` 或 `FAILED`；Desktop/Git 升级、
  VMP、PATH 等共享资源可能是 `PARTIAL` 或 `UNSUPPORTED`。它不承诺把整个 Windows
  恢复到安装前。
- 不要手工编辑 `%USERPROFILE%\.claude\settings.json`。本项目对该文件执行严格
  零读取、零修改政策，也不依赖它完成安装或恢复。

遇到问题时请参阅 `TROUBLESHOOTING.md`；数据和凭据边界见 `PRIVACY.md`。
