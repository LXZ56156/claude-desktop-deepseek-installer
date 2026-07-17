# Claude Desktop DeepSeek Installer

这是一个面向 Windows 的中文引导式一键安装器项目：用户双击脚本后，安装器检测
环境，从官方来源部署 Claude Desktop，确保 Git 和 Cowork 前置就绪，安全接收
DeepSeek API Key，预置官方 Third-Party 配置并完成启动与验收。

“一键”表示一次双击发起完整流程，不表示绕过 UAC、API Key 输入、必要重启、
BIOS 虚拟化或 Claude 的安全授权。

## 当前状态

产品工作流仍是 `Scaffold`，真实安装器尚未实现。P1-P9 纯/fake 合同、P10A
evidence/consumption 合同以及 P10B frozen facts、helper release、deterministic
双候选和 detached sidecar 宿主机支撑合同已经实现。P10A-0A 的宿主机 bootstrap
实现也已完成，包括 `DirectionalRepositoryPair`、固定 Git outbox runtime、
relay/state/hash、readiness resolver、deterministic onboarding bundle、fake reset、
VM-only Windows guest-reset dispatcher/provider boundary、两端分钟级 prompts/runbooks
与 synthetic rehearsal；这些 operator coordination 文件只归入 `DevelopmentOnlyFiles`。

Fast Lane 采用一个逻辑双 outbox、两个物理单向 public control repos。产品 remote
与两个 control repos 已公开；三仓均已启用禁止删除、禁止非快进并要求线性历史的
protected-history ruleset，且无 bypass actor。包含本次文档闭环的新 clean HEAD 经外部
机器完成标准全树门、Release Simulation、immutable onboarding bundle、自校验、仍暂停的
HostCoordinator hash binding、remote/PR/CI 一致性核验后，宿主机 finalization 即为
bootstrap-only ready，可派生 `CanStartVmBootstrap=true`。精确 post-commit 锚点不复制在
tracked 文档中；按 `docs/HANDOFF.md` 的条件式，由 retained owner-marked bundle output、
同一暂停 automation、PR CI 与实际 Git/remote 四方持久事实共同核验。

最小权限角色凭据、VM 对产品 remote 的负向写验证、reset provider 的 VM device/Live
evidence、VM Scheduled Task 与无人值守闭环仍未完成，因此 `CanStartVmIntegration=false`、
`P10A0AComplete=false`、`CanStartFormalP10A=false`。Formal Lane 才为 P10A/P11 接入 CAS、
签名与外部快照。本地质量门使用不可缺省
ExecutionContext、default-deny fake provider、owner-marked HostSandbox、双引擎
worker evidence 和 Release Simulation。

所有产品入口仍固定运行 TestSafe；产品系统操作、网络请求、配置写入和进程控制均未
实现，产品 `-Live` 无条件 fail closed。DevelopmentOnly 的 Windows guest-reset provider
只允许在 disposable VM 经外部 trust/ownership/one-shot authorization 后进入其 operator
Live 路径，不由默认 bootstrap 或 Release 加载，宿主机与 CI 不得执行。

当前 `config/deepseek-desktop.defaults.json`、desired state、15 项 Windows
`REG_SZ` serializer、官方 fixture 和 synthetic source precedence 已同步。配置
writer、registry/credential I/O 和真实 Desktop 验证仍关闭；边界见
`docs/EXTERNAL_CONTRACTS.md` 和 `docs/CONFIGURATION_DESIGN.md`。

## 暂定最终用户流程

1. 双击 `开始安装.cmd`。
2. 检查 Windows、架构、权限、Desktop、Git、VMP、虚拟化和 Cowork readiness。
3. 固定采用 Chat + Code + Cowork 完整功能目标，不展示功能选择页。
4. 自动规划 Cowork-compatible MSIX 范围、Git 和 VMP 前置，并只请求必要的安全
   确认。
5. 下载并严格验证 Anthropic 官方 MSIX。
6. 确保 Git 可用：合格版本直接复用，缺失或不合格时安装/升级官方 Git。
7. 为 Cowork 处理 VMP；必要时安全 checkpoint，人工重启后重新双击续跑。
8. 本地安全输入 DeepSeek API Key，以 DPAPI-backed credential helper 保存。
9. 首次启动前部署 HKCU managed configuration，固定启用三个 surface，跳过
   Anthropic 登录和
   Developer Mode。
10. 产品报告配置/API/readiness、secret 和资源级补偿；Chat/Code/Cowork UI E2E
   由后续 VM Codex 验证。
11. 输出中文脱敏报告。

完整产品规格见 `docs/PRODUCT_SPEC.md`。

## 产品边界

- 不安装独立 Claude Code CLI、Node.js、npm、WSL 或 VS Code。
- 技术上 Git 由内置 Code 需要；由于本产品固定包含 Code，Git 是产品必备前置。
  合格版本复用，缺失或不合格版本才安装/升级。
- 首版不提供 Chat/Code/Cowork 功能开关，也不在依赖失败时静默退化成 Chat-only。
- 不读取、Test-Path、哈希、备份、写入或删除
  `%USERPROFILE%\.claude\settings.json`。
- 不直接或静默修改全局 Git 配置、用户 PATH 或全局/CurrentUser PowerShell
  模块配置；官方 Git 安装器的精确 PATH 变化只有在披露、独立确认和补偿合同
  齐全后才可接受。
- 不绕过或降级 MSIX/EXE 签名验证。
- 不把 Key 写入命令行、registry/configLibrary 明文、环境变量、日志、状态、
  报告或 Release。
- 不修改 Claude MSIX/Electron 资源做非官方汉化。安装器和文档中文，但 Claude
  本体当前没有官方中文 UI。

## 宿主机零接触

本项目开发期间，本地自动化只允许 fake/provider 驱动的 TestSafe、DryRun、
HostSandbox 和 Release Simulation。真实 MSIX、Git、registry、VMP、API、Claude
配置和进程首次执行只允许在专用 disposable VM：先执行 P10A 窄范围校准并冻结
事实，再构建双候选，最后在 P11 对候选精确字节做全面验收。

P1 Sandbox Foundation 已完成；后续每个工作包必须持续保持其隔离证据全绿。
这不授权宿主机 Live，也不代表 OS 权限隔离。权威合同见
`docs/TEST_ISOLATION.md`。

## 当前入口

- `开始安装.cmd` / `Start-Install.cmd`
- `一键诊断.cmd` / `Run-Diagnostics.cmd`
- `恢复配置.cmd` / `Restore-Config.cmd`
- `Start-Here.ps1 -Action Install|Diagnose|Repair|Restore -TestSafe`

这些入口当前只返回 `scaffold_only`，不会执行真实动作。

## 开发验证

标准验证必须显式绑定 PowerShell 7、Windows PowerShell 和 Git 的绝对路径及
SHA-256；完整命令见 `docs/TESTING.md` 的“P1 标准检查”。`scripts/check.ps1`
在 HostSandbox 内运行双引擎 Pester、隔离 Git inventory、working-tree/cached
`diff --check` 并返回 machine-readable evidence。只有 clean quality evidence 后
才能运行 `scripts/build-release.ps1 -DryRun`。

`scripts/bootstrap-dev.ps1` 只校验仓库固定 Pester tree，不下载、安装或修改用户
PowerShell 配置。依赖缺失或漂移时普通质量门 fail closed；不得退回继承真实
HOME/Git 配置的直跑命令。

## 文档入口

- 未来正式包用户指南：`USER_GUIDE.md`
- 故障处理：`TROUBLESHOOTING.md`
- 隐私边界：`PRIVACY.md`
- 当前任务交接：`docs/HANDOFF.md`
- 完整文档地图：`docs/README.md`
- 分阶段开发方案：`docs/IMPLEMENTATION_PLAN.md`
- 宿主机隔离：`docs/TEST_ISOLATION.md`
- 双机测试中继：`docs/VM_TEST_RELAY.md`
- 窄范围 VM 校准：`docs/VM_CALIBRATION_PLAN.md`
- 后续全面 VM 验收：`docs/VM_ACCEPTANCE_PLAN.md`

下一任务以 `docs/HANDOFF.md` 记录的外部核验结果为门：若包含文档闭环的新 clean HEAD
尚未完成全树门、Release、bundle、自校验、暂停 automation 重绑和最终 CI，先在宿主机
完成这些步骤；只有 `CanStartVmBootstrap=true` 后才进入 disposable VM。VM 首步只做离线
bundle 校验、设备本地窄权限密钥和初始暂停的 VM 分钟级任务，并停在
`VM_BOOTSTRAP_STAGED`。protected history 已部署；窄凭据、device-bound reset trust、负向
权限与无人值守闭环仍是 integration 门。宿主机不得执行 Live，VM 不得修改产品代码。
