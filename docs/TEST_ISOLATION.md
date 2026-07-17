# 宿主机零接触测试合同

更新日期：2026-07-18

本文件是开发机和 CI 测试隔离的唯一权威合同。目标不仅是“不写真实配置”，而是
让受控的产品代码没有项目发起的读取、探测、枚举或修改保护资源的路径。

HostSandbox 与当前用户使用相同 Windows 权限，不是 AppContainer 或 OS 安全
边界，不能抵御恶意代码、原生注入或未知静态门绕过。强保证由以下组合成立：

- 被测产品只加载 fake provider。
- live adapter 不进入本地执行图。
- trusted test harness 只有精确 allow-list。
- 任何需要不受信任二进制或真实 adapter 的测试进入 disposable VM。

因此本文保证“项目控制的自动化不会发起保护资源访问”，不声称同用户子进程在
操作系统权限上无法访问。需要 OS 级隔离的场景只能在 Windows Sandbox/VM。

## 当前状态

P1 Sandbox Foundation 已于 2026-07-14 满足本文件针对“项目控制自动化”的退出
门：产品测试只加载 fake provider；Pester/Git 在 owner-marked HostSandbox 的
最小环境中运行；工具路径、SHA-256、参数、环境、顺序和次数均精确授权；产品与
trusted harness 分平面记账；worker evidence、仓库快照和 Release Simulation
均为机器可读实测值。

需要本地 Git 的 HostSandbox 测试不依赖 `PATH` 或用户 Git 配置。父 harness 将已验
SHA-256 的 Git grant 作为 worker 必填参数传入，worker 复验 bytes 后只以只读 global
binding 暴露给测试；测试仍使用空 hooks/credential 配置和 owner-marked local bare
repository。缺 grant、hash 漂移或从 `Get-Command` 推断宿主路径时，正式隔离 worker
必须 fail closed。

Fast Lane outbox 的 state leaf 固定为短格式 `fl-<32 lowercase hex>`，以便在
质量 worker 的 owner-marked 临时根内再次嵌套 synthetic fixture 时仍满足 Git for
Windows 的 `$GIT_DIR` 路径预算。runner 仅通过每条命令的
`-c core.longpaths=true` 支持长路径，不读取或修改 global Git config，也不把 Git
目录加入 `PATH`；短 repository directory token 只用于 cache 定位，state 仍绑定完整
repository identity/URI hash，碰撞必须 fail closed；失败诊断只返回调用序号与数值
exit code。

这一结论不改变本文开头的限制：HostSandbox 不是 OS 权限边界，不能抵御恶意代码
或未知静态门绕过。后续阶段可以开始纯领域/provider/fake 开发，但宿主机仍不得
加载 live adapter、执行 Live 或发起 sandbox 外产品 I/O。

P10A-0A 现在包含 DevelopmentOnly 的 operator coordination 合同、固定 Git outbox
runtime、readiness resolver、确定性 VM onboarding builder、VM-only reset
dispatcher/provider 边界、两端 prompt/runbook 和 synthetic rehearsal。它们位于独立
OperatorCoordination plane，不由默认 bootstrap 加载且不进入 Release。宿主机侧实现
可以生成绑定精确 commit/tree、文件/blob/tool hash、repository 数字/node identity 与
pinned genesis 的诊断 onboarding ZIP。包含文档闭环的最终 clean HEAD 只有在统一门、
Release DryRun、immutable onboarding ZIP 自校验、暂停 heartbeat binding 和 remote/PR/CI
均由外部事实核验后，才派生 `CanStartVmBootstrap=true`，且只允许 VM 离线核验、设备本地
密钥生成和创建仍暂停的 VM task。为避免 tracked 自引用，精确 commit/tree、bundle/
manifest/inventory/hash/token 和 CI run 不在本文固化，只从 retained owner-marked bundle
output、暂停 automation、既有 PR/CI 与实际 Git/remote 四方交叉核验。任何后续 tracked
修改都会使该 readiness 失效，直到从新
clean exact HEAD 重新完成相同 finalization。

真实 protected history 已通过 public ruleset/effective-rules receipt 部署；窄权限角色凭据、
runtime protection assertion、VM 负向权限证据、VM provider/device trust、reset smoke 与
unattended acceptance 尚未完成，所以 `CanStartVmIntegration=false`；VM task 也尚未从 VM
设备创建，所以 `P10A0AComplete=false`。这些 operator runtime 不解除宿主机 Live 边界，
也不授权 VM 修改产品代码。Formal Lane 的外部 snapshot receipt、独立
CAS/signature/receipt authority 仍未就绪，`CanStartFormalP10A=false`，不能据此声称
P10A-0A 或 P10A 完成。三个
远端现均为 public；公开不放松 secret、Authorization、credential 或宿主机零接触边界。

## 零接触定义

本地开发和 CI 自动化不得对保护资源执行以下任何动作：

- 读取、Test-Path、stat、枚举、哈希或 watcher。
- 备份、解析、复制、移动、写入、删除或修改 ACL。
- 启动相关程序、调用真实 API、注册服务或触发系统动作。

“只读”不是例外。证明安全依赖 provider 调用账本和静态门，不依赖读取真实配置
前后算 hash。

## 保护区

至少包括：

- `%USERPROFILE%\.claude\**`。
- `%LOCALAPPDATA%\Claude-3p\**` 和其他 Claude Desktop 用户数据。
- `HKCU\SOFTWARE\Policies\Claude`、`HKLM\SOFTWARE\Policies\Claude`。
- `%USERPROFILE%\.gitconfig`、`%USERPROFILE%\.config\git\**`、系统 Git 配置。
- 用户 PATH、系统 PATH 和 Git 安装目录。
- Windows Credential Manager、真实 DPAPI 用户凭据存储。
- 已安装 AppX/MSIX、Windows Features、服务、计划任务和系统 registry。
- 真实 Claude Desktop、Git 安装器和其他用户进程。
- DeepSeek、Anthropic、GitHub 或其他外部网络服务。

`%USERPROFILE%\.claude\settings.json` 的项目政策正式选择零读取。宿主机测试不
计算它的 hash；完整性证据由“无 provider 调用、无 live adapter 装载、VM 基线”
组成。

## 允许资源矩阵

| 测试层 | 文件 | Registry | 网络 | 进程/AppX/VMP/服务 | 凭据 |
|---|---|---|---|---|---|
| Unit/Contract | 仅 `TestDrive:` | 内存 fake | fake handler | fake | 运行时 synthetic |
| HostSandbox | 本次唯一 sandbox | 虚拟 map | 默认拒绝/fake | 记录型 fake | fake DPAPI |
| Release Simulation | 本次唯一解压 sandbox | 虚拟 map | 拒绝 | fake | synthetic |
| Fast Lane synthetic rehearsal | 本次唯一 sandbox 双 outbox | 不访问 | 拒绝 | 不启动真实进程 | synthetic/no secret |
| CI | runner sandbox | 虚拟 map | 仅依赖引导白名单 | fake | synthetic |
| VM Live | VM 内显式授权范围 | VM registry | 官方端点 | VM 内真实 | VM 专用 Key |

仓库内 `.dev/modules` 只允许固定开发依赖，不得作为一般测试工作区。其他行为测试
只使用 `TestDrive:` 或 OS 临时目录中的 `cddsi-test-<GUID>`。

## Trusted Test Harness

测试外壳与被测产品是两个执行平面。只有精确 allow-list 的 harness 可以直接：

- 在允许临时根创建和清理 owner-marked sandbox。
- 启动固定绝对路径的 `pwsh`/`powershell.exe`、仓库 Pester 和 Git 只读质量门。
- 读取仓库文件、Release manifest 和 sandbox 证据。
- 在单独、显式的 dependency-bootstrap 步骤访问固定依赖来源。

Harness 不得读取保护区、registry、AppX、VMP、服务、凭据或 Claude 进程。它的
进程和网络调用单独记账，不能混入产品 AccessLedger。参数、工作目录、环境、
可执行文件 hash 和预期调用次数必须精确匹配。

Fast Lane 的部署 runtime 不是 trusted test harness。质量门只允许精确列名的
`operator/fast-lane/invoke-synthetic-rehearsal.ps1` 作为 harness 支持，在 owner-marked
sandbox 内调用 operator contracts 并生成 synthetic evidence；不得访问真实 Git
remote、网络、registry、AppX、VMP、service、credential、用户配置或产品进程，也不得
加载 Live adapter。演练前后必须断言 secret、真实探测、外部写入和产品 mutation 为零。

产品测试期间 dependency-bootstrap 网络计数必须为零。固定 Pester tree 已随仓库
锁定并由普通质量门只读验证；若缺失或漂移，普通质量门 fail closed。恢复依赖只能
走独立、受审、固定 hash 的离线/受限流程，不能混入产品测试。

## ExecutionContext 与 Provider

每个非纯函数必须显式接收不可缺省的执行上下文。当前 exact 顶层字段：

~~~text
SchemaVersion
RunId
Mode
EnvironmentTier = HostSandbox | CI | VmAcceptance | UserLive
SandboxRoot
Paths
Providers
Policy
AccessLedger
~~~

Provider 至少覆盖：

- FileSystem
- Environment/KnownFolder
- Registry
- Process
- Network
- Package
- Feature
- Service
- Credential/DPAPI
- Clock

规则：

- TestSafe 或自动化 DryRun 缺 Context/fake provider 时立即失败。
- 不允许从 fake 回退到真实系统。
- 领域模块不得直接调用系统 cmdlet 或 .NET 系统 API。
- live adapter 位于独立允许列表，不由本地测试 bootstrap 加载。
- 只有顶层 Live orchestrator 可以构造真实 known-folder 和 live provider。

## Sandbox Root

HostSandbox runner 必须：

1. 在 OS 临时目录下生成此前不存在的 `cddsi-test-<GUID>`。
2. 解析绝对路径，验证祖先无重解析点且目标位于允许临时根。
3. 写入包含 schema、runId 和随机 ownership token 的 owner marker。
4. 所有 synthetic HOME、AppData、ProgramData、Temp、download、state、backup 和
   report 都位于该根。
5. 清理前重新验证路径和 owner marker。
6. 只删除本次 token 所属目录；禁止对字符串拼接目录做递归删除。

失败时只能保留含假数据的证据。当前本机控制台可以显示 sandbox 绝对路径帮助
维护者定位，但该文本不得持久化或分享；持久/可分享证据必须替换为
`<SANDBOX_ROOT>`、`<TEMP_ROOT>` 等逻辑 token。

ownership token 只用于清理验证，不进入控制台、日志、报告或可分享证据。

## 独立测试子进程

L2/L3 不能在父进程临时修改环境后继续执行，而应以 `-NoProfile` 和
`-NonInteractive` 启动子进程，并从最小环境表构造：

- `USERPROFILE`、`HOME`、`HOMEDRIVE`、`HOMEPATH`。
- `LOCALAPPDATA`、`APPDATA`、`PROGRAMDATA`。
- `TEMP`、`TMP`、`XDG_CONFIG_HOME`、`XDG_DATA_HOME`。

以上全部指向 sandbox。必须清除 API Key、代理、云凭据和 Claude 相关环境变量。
`PSModulePath` 只包含仓库 Pester 与 `$PSHOME\Modules`。

环境重定向不能隔离 registry/AppX，因此仍必须使用 fake provider 和静态门。

## Git 和开发依赖隔离

所有测试质量门中的 Git 子进程设置：

- `GIT_CONFIG_NOSYSTEM=1`。
- `GIT_CONFIG_GLOBAL` 指向 sandbox 空配置或 Windows null device。
- `GIT_OPTIONAL_LOCKS=0`。
- synthetic HOME/XDG。

`bootstrap-dev.ps1` 已收敛为 verify-only 校验器：只检查仓库固定 Pester lock 与
runtime tree，不下载、安装、导入或修改 PowerShellGet repository、CurrentUser
module 和持久 `PSModulePath` 配置。

## Fake Provider 与调用账本

每个 fake 记录：

- 文件 read/stat/enumerate/create/write/flush/replace/delete。
- registry read/write/enumerate。
- 网络请求。
- 进程启动和终止。
- AppX、Git、feature、服务和重启请求。
- Credential/DPAPI 调用。

默认策略全部拒绝。每个测试场景声明精确允许序列，结束时核对无额外调用。

Sandbox 中建立 synthetic canary：

- fake `profile\.claude\settings.json`。
- fake Git global/XDG config。
- fake Claude policy/configLibrary。
- fake credential store。

Claude Code 和 Git 配置 canary 的访问计数必须为零。canary 内容出现在 stdout、
stderr、日志、状态、报告或临时文件时立即失败。

## 必需证据

每次 HostSandbox/Release Simulation 至少断言：

~~~text
LIVE_PROVIDER_LOADED = false
FORBIDDEN_RESOURCE_ACCESS_COUNT = 0
OUTSIDE_SANDBOX_WRITE_COUNT = 0
PRODUCT_LIVE_PROCESS_SPAWN_COUNT = 0
PRODUCT_NETWORK_REQUEST_COUNT = 0
REAL_REGISTRY_ACCESS_COUNT = 0
UNAPPROVED_HARNESS_PROCESS_COUNT = 0
UNAPPROVED_HARNESS_NETWORK_COUNT = 0
SECRET_FINDINGS = 0
UNEXPECTED_LEDGER_ENTRY_COUNT = 0
REPOSITORY_CONTENT_CHANGED = false
~~~

`TRUSTED_HARNESS_PROCESS_COUNT` 可以大于零，但必须与场景声明的 pwsh/Pester/Git
精确序列一致。dependency bootstrap 独立运行，不计入产品测试通过证据。

TestSafe/DryRun 的每个 mutation spy 调用次数必须为零，返回结果必须
`Changed=false`。

## 静态门

`scripts/check.ps1` 和 Pester Contract 当前强制：

- 只有精确列出的 live adapter 可以引用产品系统 API。
- 只有精确列出的 trusted harness 可以创建 sandbox、启动测试工具或执行受限
  dependency bootstrap。
- 领域模块、测试和入口不得解析真实 UserProfile/LocalAppData。
- 禁止动态命令调用、`Invoke-Expression`、shell 字符串拼接和隐式 provider。
- live adapter 不能由 TestSafe bootstrap 导入。
- 测试 fixtures、docs、代码和 Release 全量 secret scan。

新增 live adapter 或 trusted harness 文件时，必须同时增加对应 allow-list、
provider/harness contract、故障注入和证据；不能只放宽 AST 规则。

当前 P1 证明由 `config/execution-boundaries.psd1` 的执行文件归属与 allow-list、
全仓 AST/静态门、不可缺省 ExecutionContext、default-deny fake provider、运行时
AccessLedger/mutation spy、双引擎 worker evidence、trusted-harness ledger、仓库
全树快照和 Release 四层扫描共同组成。它可以证明项目控制自动化遵守本合同，但
仍不能作为 OS 权限隔离证明。

## 故障注入

Fake 层必须覆盖：

- 文件：磁盘满、flush/replace/rollback 失败、重解析点、路径逃逸、TOCTOU。
- 下载：DNS、TLS、超时、截断、非法重定向、大小超限、hash 错误。
- 验签：换包、artifact type、Publisher、identity、chain 和路径绑定失败。
- 进程：启动失败、超时、非零退出、大量输出和子进程树。
- 配置：来源冲突、部分 registry 写入、重读不一致和恢复失败。
- 凭据：DPAPI/helper 失败、错误用户、非法输出、超时和泄露。
- checkpoint：损坏 schema、陈旧 runId、owner 不匹配和清理失败。
- Chat/Code/Cowork：能力分别注入 `BLOCKED/UNKNOWN`，UI 证据分别注入
  `FAIL/NOT_TESTED`；不得混用两个层级。

## 本地与 VM 的分界

- 本地开发和 CI 只运行 L0-L4，永不执行 Live provider。
- 双机 operator coordination 以 `VM_TEST_RELAY.md` 为权威，并与产品执行平面、
  trusted harness runtime 和正式证据平面隔离。operator modules 是 DevelopmentOnly、
  非默认 bootstrap、非 Release；harness 只可按 execution-boundaries 的精确 allow-list
  调用 synthetic、owner-marked local Git/onboarding 与 fake/reset contract 测试入口，
  不得访问 remote、真实 credential 或 VM/system Live。宿主机 Codex 是唯一代码写入者；
  VM Codex 只测试、分析和回传，没有产品仓库写权限。
- P10A 在 Release Candidate 之前先进入专用 disposable VM；只有限域 calibration
  runner/provider 可以执行真实校准操作，产品 Live adapter 仍不得加载；每轮必须
  绑定精确 commit、校准 artifact/hash 和 runbook，不跟随移动分支头。
- P10A evidence 返回宿主机后，必须由受信外部 CAS 原子提交并冻结事实；只有随后
  构建并冻结 P10B `VmAcceptance` 与 `UserLive` 双候选，才能进入 P11。
- 产品 Live adapter 的首次真实执行和首次全面产品验收只允许在 P11 disposable VM；
  P10A 的窄范围事实校准不能替代 P11。P11 只测试请求中绑定的 candidate exact
  bytes/hash，不以源码 checkout 替换 artifact。
- VM 内 Codex 的授权不扩展到宿主机，也不允许自行扩大测试范围。
- Fast Lane（日常自动修复）由 VM Codex 按精确 allow-list 卸载本项目产物，清除
  项目拥有的 HKCU policy、credential、checkpoint 和 owner-marked
  `cddsi-vm-test-<GUID>` 资源，再核验 baseline。宿主机已冻结 pure/fake reset、
  VM-only dispatcher/provider、device trust 和 fail-closed receipt 合同；实际 VM
  provisioning、Live development-retest smoke 与系统证据仍必须在 disposable VM 完成。
  MVP 使用一个逻辑双 outbox、
  两个物理单向 control repository：`host-to-vm` 仅 HostCoordinator 写/VM 读，
  `vm-to-host` 仅 VM 写/HostCoordinator 读。
- 两端分钟级 Codex automation 属于外部 operator coordination，不是产品 Scheduled
  Task，不能扩大宿主机 Live 或让 VM 修改产品代码。repository pair、固定
  outbox runtime、prompt、onboarding 和 synthetic 演练已实现；宿主机 heartbeat 已
  创建且暂停。VM task 必须从 VM 设备创建并先保持暂停。protected history 已部署；
  最小 credentials、runtime assertion、任务安全启用和 unattended acceptance 尚未完成。
- Formal Lane 用于 P10A/P11 正式证据，必须由 VM 外部的 hypervisor supervisor
  恢复固定快照并签发 receipt，并使用独立 CAS/receipts/signatures。VMP/重启/卸载、
  补偿未知、baseline drift 或 reset 失败必须从 Fast Lane 升级；VM Codex 不能恢复
  自身正在运行的快照，正式 P11 PASS 必须绑定 clean-snapshot receipt。
- P11 失败后只能由宿主机修复、过门、提交/推送，再回到 P10B 重建并签名新候选；
  VM 不直接拉取修复源码重测。relay 消息不等于 CAS、签名或 acceptance receipt，
  也不得触发自动 merge/P12。

两道 VM 门分别见 `VM_CALIBRATION_PLAN.md` 与 `VM_ACCEPTANCE_PLAN.md`；双机协调见
`VM_TEST_RELAY.md`。

## P1 退出条件（已满足）

只有同时满足以下条件，才能开始环境探测或安装实现：

1. ExecutionContext 和全部 provider 接口已定义。
2. fake provider、access ledger、sandbox runner 和 owner cleanup 已实现。
3. Unit/Contract/HostSandbox/Release Simulation 使用 synthetic 环境。
4. AST 门阻止领域代码和测试绕过 provider。
5. 产品和未授权 harness 指标全部为零，受信任 harness 调用与声明精确一致。
6. 当前入口在 PowerShell 7 和 5.1 中均通过。
7. 文档、Release manifest、secret scan 和 `git diff --check` 通过。

以下是 2026-07-14 P1 首次退出门的历史快照；当前全树证据以 `HANDOFF.md` 为准。
PowerShell 7 与 Windows PowerShell 5.1 worker 各 124 项
Pester 全部通过，固定 suite 为 16/10/6；5 个受信任进程和 16 项 harness ledger
精确匹配；必需零值、全部 mutation spy 和 repository-changed 均为安全值；97 文件/
26 目录前后相同并清理成功。Release DryRun 对 29 个 PackageFiles 完成 source、
staging、ZIP、extracted 四层无 secret 且清单/内容 hash 精确比对，16 项 filesystem
ledger 精确匹配并清理成功。完整易变证据以 `HANDOFF.md` 为准。

P1 通过只解除后续纯 fake/provider 工作包的阻断，不授权宿主机 Live、真实探测、
VM 验收或发布。
