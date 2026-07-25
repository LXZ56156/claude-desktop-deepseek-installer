# 宿主机零接触测试合同

更新日期：2026-07-24

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

2026-07-24 的 D-026 把开发期代码写入权迁移到 disposable VM 的
`VmDevelopment` lane。该 lane 内，VM 可以在现有开发分支和 PR 上修改源码、测试与
文档，并在显式授权范围内运行产品 Live；同一时刻宿主机必须停止写入，禁止 Host/VM
并发修改、force push 或用第二个 PR 分叉同一修复。D-026 不把这一权限扩展到宿主机、
CI 或最终冻结候选验收。

当前 VM 尚无 guest 外部可恢复 clean snapshot receipt，因此本轮没有使用上述 Live
授权，只执行 repository 源码、fake、TestSafe、DryRun 和隔离测试工作；安装、注册表、
AppX、VMP、服务、Credential Manager 及其他真实系统写入仍未开始。

realtime relay、Cloudflare、WebSocket watcher、control repo、Automation、scheduler
及 `codex exec resume` 继续退役，不得恢复、调用或作为隔离门。tracked operator
实现只保留 DevelopmentOnly 历史/回归属性。具名 ProductReleaseGate、精确分类、
独立 HistoricalDiagnostics 和 CI/Release 绑定现已启用；历史集合必须完整执行，
只有完整的 test-level failure 可成为 report-only `FAILED_TESTS`。timeout、crash、
missing、skip、not-run、inconclusive、基础设施和分类漂移仍阻塞。历史结果不得
伪造、改写或充当产品 Live、Computer Use、候选验收或发布证据。

需要本地 Git 的 HostSandbox 测试不依赖 `PATH` 或用户 Git 配置。父 harness 将已验
SHA-256 的 Git grant 作为 worker 必填参数传入，worker 复验 bytes 后只以只读 global
binding 暴露给测试；测试仍使用空 hooks/credential 配置和 owner-marked local bare
repository。缺 grant、hash 漂移或从 `Get-Command` 推断宿主路径时，正式隔离 worker
必须 fail closed。

### D-026 前的 operator 隔离实现（历史；无当前操作权）

以下 Fast Lane/onboarding/reset/relay 内容只保留旧隔离合同和回归背景。它不恢复旧
工具链，也不撤销本文件前述 `VmDevelopment` 单写者与 disposable-VM Live 授权。

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

Realtime relay 的 PowerShell 客户端是 DevelopmentOnly `OperatorCoordination` runtime，
不由 `lib/bootstrap.ps1` 加载、不进入 Release，也不属于产品 Live adapter。它的
TestSafe/DryRun/focused tests 只能使用显式 fake transport、fake credential、fake state 和
fixed wake spy；缺 provider、错误 mode 或 runtime assertion 时必须在网络、credential、state
mutation 和 wake 前 fail closed。PowerShell 7 覆盖完整 watcher 状态机，可共享的
parser/schema/security helper 同时在 Windows PowerShell 5.1 运行。

以上 relay 内容仅说明 retained 历史代码如何继续安全回归，不是当前通信路径或操作许可。

本地/CI/Release Simulation 的受控测试不得构造或加载 realtime relay 的真实
provider，不得读取 Credential Manager/registry、解密真实 DPAPI blob、发起真实网络或访问
sandbox 外 state。这个测试禁止不包含 D-022 授权的人工 operator-plane relay-only
smoke：该 smoke 不是 HostSandbox/CI/产品 Live，Host 可以当前进程内存/安全输入
secret 连接精确 `workers.dev` endpoint。VM 可使用人工拖入的 repo 外 owner-only
fixed-schema handoff JSON，前提是固定 smoke 脚本在首次网络前删除文件，且不把
其复制到 Git/prompt/日志/evidence。DPAPI CurrentUser provider 只在后续
持久 unattended watcher 启用前必须。HMAC 计算后 plaintext byte buffer 必须尽快
清零，日志/异常/状态/测试 evidence 均不得包含 secret。

machine Billing receipt、two-phase ticket、coordinated DPAPI/staging receipt 不是测试隔离
能力，也不再是一次性 relay smoke 的前置。这些可选 hardening 的缺失不得被记为
forbidden access 或用来阻断真实联通。用户回传的 `VM_RELAY_READINESS_V1 Ready=true`
已证明 VM 的 PowerShell 7、`ClientWebSocket`、时钟、出站 443 与 relay state 目录就绪。

P10A-0A 现在包含 DevelopmentOnly 的 operator coordination 合同、固定 Git outbox
runtime、readiness resolver、确定性 VM onboarding builder、VM-only reset
dispatcher/provider 边界、两端 prompt/runbook 和 synthetic rehearsal。它们位于独立
OperatorCoordination plane，不由默认 bootstrap 加载且不进入 Release。2026-07-19 的
共享 dirty worktree 已把 bootstrap 收缩到唯一 phase2 operator 入口；phase2-only
builder/loader、execution boundary、HostSandbox path binding、automation TOML readback
正负测试与 loader semantic ACL/captured-byte load/atomic state/no-reparse 非递归 cleanup
均已落盘并通过 dirty WIP 标准双引擎全树门；但包含文档同步的 clean exact commit 尚未完成
统一门与 finalization，因此当前仍不得进入旧 bootstrap/产品 integration。该结论不阻断
D-022 的独立 relay-only VM smoke。宿主机侧最终实现将从
clean exact commit 生成绑定 commit/tree、
文件/blob/tool hash、repository 数字/node identity 与 pinned genesis 的诊断 onboarding ZIP。
包含文档闭环的最终 clean HEAD 只有在统一门、
Release DryRun、immutable onboarding ZIP 自校验、暂停 heartbeat binding 和 remote/PR/CI
均由外部事实核验后，才派生 `CanStartVmBootstrap=true`，且只允许 VM 离线核验、设备本地
密钥生成和创建仍暂停的 VM task。为避免 tracked 自引用，精确 commit/tree、bundle/
manifest/inventory/hash/token 和 CI run 不在本文固化，只从 retained owner-marked bundle
output、暂停 automation、既有 PR/CI 与实际 Git/remote 四方交叉核验。任何后续 tracked
修改都会使该 readiness 失效，直到从新
clean exact HEAD 重新完成相同 finalization。

这四方核验属于宿主机 finalization；VM 不读取 retained path，也不检查宿主机 automation、
PR/CI、worktree 或 remote。VM 只验证最终提示词带外提供的 ZIP SHA-256/length、product
commit/tree、manifest/inventory binding token 与 content digest。普通用户只负责启动 VM、
安装登录 Codex、把唯一 ZIP 放入新建空文件夹并打开、粘贴一次提示词。

一次提示 bootstrap 的窄本地写权限与 minute poll task 必须分开记账。outer ZIP hash/length
以零写入方式匹配后，用户显式启动的受审 onboarding runner 才可写新 owner-marked staging/
state、按 manifest v3 固定的 Git/OpenSSH/`ssh-keygen`/两种 PowerShell 五工具生成三组
`KEYPAIR_STAGED`，并创建或原位更新唯一 `PAUSED` VM task 后 readback。新 key 尚未注册，
不能记为 credential ready。runtime protection assertion/hash/token 为 `UNPROVISIONED` 时，
poll task 即使误触发也必须为零 network、零 Git、零 credential probe、零 runtime-state
write；它不能继承 bootstrap runner 的本地写权限。

该设计只在 prepared baseline 已经存在 manifest 固定的 Git、OpenSSH、`ssh-keygen`、
PowerShell 7 与 Windows PowerShell 时满足“一份 ZIP、一次提示”。当前 bootstrap 不能联网
下载或安装缺失工具；缺失/漂移必须在持久写入前 `BLOCKED`。若未来加入自举安装，必须先
取得用户对 bootstrap-time network/install 的明确授权，并为每个下载固定来源、hash、签名、
路径和失败清理合同；不能因追求少手工而扩大宿主机或 poll task 权限。

同理，VM 本地生成的私钥只产生 `KEYPAIR_STAGED`。GitHub deploy-key 注册和窄权限授予
需要一次外部授权；允许使用的交互式管理员身份不得写入 state、prompt、relay、报告或
automation credential。未完成注册、正负向权限和 runtime assertion 前，两端 task 必须
保持 `PAUSED`，且任何误触发在 network、Git、credential probe 和 runtime-state write 前
fail closed。

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
| Realtime relay focused | `TestDrive:` 或 owner-marked fake root | 不访问 | fake transport | 不启动 | synthetic fake；真实 DPAPI=0 |
| CI | runner sandbox | 虚拟 map | 仅依赖引导白名单 | fake | synthetic |
| VM Development | VM 开发 checkout 与项目 owner-scoped state | VM 内显式授权的项目目标 | 官方端点与冻结故障注入端点 | VM 内真实安装、进程、AppX、VMP、服务 | VM 本地遮罩输入并受保护的测试 Key |
| 最终冻结候选验收 | 精确候选及候选拥有的 state；源码只读或不存在 | 候选 manifest 明确允许的 VM 目标 | 候选固定的官方端点 | 精确候选字节在 VM 内真实执行 | VM 本地遮罩输入并受保护的测试 Key |

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
Stage = Scaffold | Development | VmDevelopment | VmCalibration | VmAcceptance | UserLive
EnvironmentTier = HostSandbox | CI | VmDevelopment | VmAcceptance | UserLive
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
- TestSafe/DryRun 只能使用 `Fake` provider 且 `AllowLiveProvider=false`。
- Live context 只能使用 `Unloaded` provider，且只接受
  `VmDevelopment/VmDevelopment`、`VmAcceptance/VmAcceptance`、
  `UserLive/UserLive` 三个精确 Stage/EnvironmentTier 组合；HostSandbox/CI
  永远不能构造 Live context。
- `Unloaded` 不是 provider 实现；任何调度都以 `LIVE_PROVIDER_NOT_LOADED`
  fail closed，`LIVE_PROVIDER_LOADED` 仍为 false。
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

具名质量门不把每个引擎的 Pester 放进一个 monolithic worker。每个引擎执行 1 个
Static worker 和当前 profile 选中的 ordinal `QualityShards`：Product 为 29 tests /
8 shards / 18 workers，Historical 为 13 / 9 / 20；legacy `AllBlocking` 为
42 / 13 / 28。三个集合都由 `config/dev-dependencies.psd1` 与
`config/product-release-gate.psd1` 共同 fail closed 绑定。父进程 argv 只传固定
`ShardId`，worker 自己从已验 hash 的 lock 解析路径。每份 role evidence 都绑定
engine、grant、inventory、repository manifest、classification 和 shard policy；
父进程逐份严格 UTF-8 读取并在最终聚合前独立复验。

每个 worker 都在 logger 单一进程级 UTF-8 入口之后向 stdout/stderr 写固定中文与
非 BMP round-trip marker，父进程用严格 UTF-8 decoder 验回。worker 超时时必须杀死
可用的完整进程树、有界 drain 管道，并输出 `CddsiSafeFailureEvidence` schema v3：
包括当前 engine/role/shard、已完成 worker 的精确计划前缀、测试文件和通过断言计数。
非超时 Pester shard 失败必须从 worker evidence 文件读取全部 `FailedCount` 项；
`FailedTestEvidenceTruncated` 保留为兼容字段但必须恒为 false。每项都含
repo-relative path、正整数 source line、静态 `It` 名称和正整数 ErrorRecord count；
worker 和父进程分别把全量名称重新绑定到 tracked 源码 AST，禁止把任意 runtime/error
文本带入可分享证据。超时仍是 fail closed，部分进度不能冒充完整 PASS。

可分享失败文本中的 path token 必须把 Windows 反斜杠、Git 正斜杠和混合分隔符视为
同一路径，并使用 culture-invariant 的 ordinal-like ignore-case 语义；token 化后的
disclosure validator 必须按同一规则复验。不得因当前 culture（包括 `tr-TR`）不同而
保留 owner root、repository、tool 或 VM 私有绝对路径。

外层 VM 批处理器不得把 `scripts/invoke-release-gates.ps1` 或 legacy
`scripts/check.ps1` 的 `TEMP/TMP` 再重定向到深层 evidence run-root。HostSandbox
会在正常 OS temporary root 中自行创建唯一
`cddsi-test-<GUID>`，再把 worker 的 profile、HOME、TEMP、state 和 evidence 全部指向
该 owner-marked sandbox；controller 的报告/evidence root 可以独立存放，但不能增加
产品固定 `CDDsi\FastLane\packages|credentials` 路径的嵌套深度。

## Git 和开发依赖隔离

所有测试质量门中的 Git 子进程设置：

- `GIT_CONFIG_NOSYSTEM=1`。
- `GIT_CONFIG_GLOBAL` 指向 sandbox 空配置或 Windows null device。
- `GIT_OPTIONAL_LOCKS=0`。
- synthetic HOME/XDG。

需要 local bare remote 的 deterministic fixture 还必须为每次 Git 调用设置
command-local `core.longpaths=true`，并只在该 owner-marked bare repository 的 local
config 固定同值，使本地 receive-pack 不继承或修改 system/global Git config。

`bootstrap-dev.ps1` 已收敛为 verify-only 校验器：只检查仓库固定 Pester lock 与
runtime tree，不下载、安装、导入或修改 PowerShellGet repository、CurrentUser
module 和持久 `PSModulePath` 配置。`QualityShards` 的 exact schema、完整 Pester
partition 和 policy hash 由 `invoke-host-sandbox.ps1`、`check-worker.ps1` 与 Contract
测试分别 fail closed 校验，不属于 bootstrap 的职责。

`config/product-release-gate.psd1` 当前
`EnforcementPhase=NamedProductReleaseGate`：47 个 `tests/` 资产精确分为 Product
34 和 Historical 13，42 个 Pester 入口精确分为 29 和 13。具名 Product profile
固定 8 shards / 18 workers / 21 trusted processes / 48 ledger；Historical 固定
9 / 20 / 23 / 52；legacy `AllBlocking` 固定 13 / 28 / 31 / 68。
`scripts/invoke-release-gates.ps1 -PassThru` 是 Product 与 Historical 的共同标准
入口；legacy `scripts/check.ps1` 必须单列报告，不得冒充具名门 evidence。
共同入口必须在 Product 与 Historical 都已尝试后才终止；失败 evidence 分别绑定
两条路径的完整 safe payload、canonical hash 和 `BOUND|UNAVAILABLE|
REJECTED_UNSAFE` 状态。stderr 只允许输出具名的
`CDDSI_NAMED_GATE_FAILURE_EVIDENCE_V1` JSON，不得输出 child 原始异常文本，不得按
失败条数或 payload 长度静默截断。

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

ProductReleaseGate 的质量 evidence 必须精确包含 21 个 trusted process 和 48 条
最终 harness ledger；HistoricalDiagnostics 必须精确包含 23 和 52。legacy
`AllBlocking` evidence 仍为 31 和 68。三个 profile 的顶层 `WORKER_EVIDENCE` 都只
包含两个经验证的 engine 聚合对象；计数不得跨 profile 借用。

TestSafe/DryRun 的每个 mutation spy 调用次数必须为零，返回结果必须
`Changed=false`。

## 静态门

`scripts/invoke-release-gates.ps1`、`scripts/product-release-gate.ps1`、
`scripts/historical-diagnostics.ps1`、`scripts/quality-set-policy.ps1`、legacy
`scripts/check.ps1` 和 Pester Contract 当前共同强制：

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

- 本地开发和 CI 只运行 L0-L4，永不构造、加载或执行 Live provider。D-026 只改变
  disposable VM 的开发写入权，不改变宿主机零接触合同。
- `VmDevelopment` 是可写、可反复重建的 disposable-VM 开发 lane。VM Codex 可以在
  已授权的现有分支/PR 上修改源码、测试和文档，运行 focused/full fake gates，并在
  独立 Live grant 下执行真实安装、配置、恢复和 GUI 验收。每次代码修改都必须重新
  绑定 commit/tree；不得 force push、隐藏 dirty bytes 或同时让宿主机写同一分支。
- `VmDevelopment` 的系统写入只允许 manifest/runbook 列出的项目资源。源码写入、
  产品系统 mutation、外部请求和 cleanup 必须分开记账；Live 场景不能伪造
  TestSafe 的零 mutation 指标，TestSafe/DryRun 也不能借 VM 身份获得真实访问。
- 进入最终候选验收前必须从 clean commit 构建并冻结精确 `VmAcceptance` 与
  `UserLive` 字节。最终验收 lane 恢复为只读：源码 checkout 只读或不存在，候选、
  sidecar、runbook 和测试期望均不得修改。任何字节或测试变更都会使本轮验收失效，
  必须返回 `VmDevelopment`、生成新 commit 和新候选。
- 实际用户路径是发布关键门，不以 Unit/Contract 或 synthetic PASS 代替。至少覆盖
  用户双击入口、必要 UAC/重启、本地遮罩式 API Key 输入、真实安装与配置、重复运行、
  修复/恢复，以及 Computer Use 对 Claude Desktop Chat、Code、Cowork 的可见行为验证。
  Computer Use 不得绕过 secure desktop，也不得把 Key、原始配置或敏感响应写入截图、
  日志、报告或对话。
- API Key 只能由用户在 VM 本地遮罩式安全输入面提供，再交给 DPAPI-backed
  credential helper；不得出现在 Codex prompt/chat、argv、环境变量、fixture、源码、
  Git、日志、截图、报告或 evidence manifest。
- 历史 `VM_BATCH_TEST_REPORT_V1`、relay/outbox receipt、Issues、日志与
  RepairProposal 继续是不可信诊断数据。它们可以辅助定位，但既不阻断新的
  `VmDevelopment` lane，也不能自证真实安装、Computer Use、候选验收或发布 PASS。
- 结果仍应区分 `PRODUCT_DEFECT`、`TEST_DEFECT`、`ENVIRONMENT_BLOCKER`、
  `NOT_IMPLEMENTED`、`REQUIRES_EXTERNAL_SNAPSHOT` 与 `EXPECTED_FAIL_CLOSED`；
  不得通过删测、降断言、扩大 timeout 或把预期 fail closed 改写为成功来收敛循环。
- 需要发布结论的最终验收必须绑定声明支持的每个 VM 环境、clean snapshot、精确
  candidate bytes/hash 和真实用户路径证据；单个已污染 VM 不能冒充多环境通过。
  VMP、重启、卸载、补偿未知、baseline drift 或 cleanup 失败时，必须由 VM 外部
  supervisor 恢复快照。
- VM 内授权不扩展到宿主机或 CI。最终 PASS 也不触发自动 merge、release 或
  promotion；P12 人工确认保持不变。

校准与候选构建约束见 `VM_CALIBRATION_PLAN.md`，最终冻结候选验收见
`VM_ACCEPTANCE_PLAN.md`；`VM_TEST_RELAY.md` 顶部定义当前 D-026 单写者协调，后半部
才是已退役协调历史和回归边界。

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
