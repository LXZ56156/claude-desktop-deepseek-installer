# 测试与质量门

更新日期：2026-07-24

## 核心原则

本地测试不能靠“运行后看起来没出事”证明安全。必须通过 fake provider、独立
sandbox、静态门和 access ledger，证明受控产品代码没有发起真实 Claude、Git、
registry、AppX、VMP、进程或网络访问。HostSandbox 不是 OS 权限隔离；不受信任
代码和 live adapter 只在 disposable VM。

完整保护合同见 `TEST_ISOLATION.md`。P1 质量入口已固定为 owner-marked
HostSandbox、双 PowerShell 引擎、精确工具授权和机器可读证据；该整套质量门已于
2026-07-14 实际通过，后续工作包必须持续保持全绿。

## 测试层级

### L0：Static

- PowerShell AST 和 JSON 语法。
- 模块依赖与无副作用加载。
- 公开函数、Mandatory 参数、Mode 和确认开关。
- 直接系统 API/live adapter 精确 allow-list。
- 编码、换行、secret 和私钥扫描。
- Release manifest 全文件精确分类。
- 文档体系完整性与交接可发现性。

### L1：Unit / Contract

- 仓库本地 Pester 5。
- 纯函数、schema、serializer、provider contract。
- 只写 `TestDrive:`。
- Registry、network、process、AppX、feature、credential 全部 fake。
- 每个公开函数变更同步 `config/public-functions.psd1`。

### L2：HostSandbox

- 独立 `-NoProfile -NonInteractive` 子进程。
- synthetic HOME、AppData、Temp、Git 和 Claude 路径。
- 唯一 owner-marked `cddsi-test-<GUID>`。
- AccessLedger、mutation spy、canary 和 forbidden-access 证据。
- 本机不加载 live provider。
- trusted harness 可以启动声明过的 pwsh/Pester/Git，但与产品 ledger 分开，
  未授权 harness 调用必须为零。

### L3：Release Simulation

- 从白名单 ZIP 解压。
- 路径包含中文、空格、`&`、`!` 和括号。
- 只运行 TestSafe/HostSandbox。
- ZIP 条目、secret、运行产物和仓库变化精确比较。

### L4：CI

- Windows 临时 runner。
- PowerShell 7 与 Windows PowerShell 5.1。
- 运行 L0-L3。
- checkout action 使用完整 commit SHA 固定，且 `persist-credentials=false`。
- 受信 harness 前置只解析 runner 已知的 pwsh、Windows PowerShell 和 Git
  可执行文件，计算 SHA-256 后把精确授权传给 HostSandbox。
- 不单独绕过 HostSandbox 运行 Pester、Git 或第二套测试命令。
- 产品 API Key 和所有 retained relay/credential 合同只使用 fake；真实 DPAPI 和
  测试 Key 只允许进入 L5 明确授权的 disposable VM 本地安全输入路径。当前不执行
  relay smoke，也不搬运通信凭据。
- 绝不运行 Live。

### L5：Disposable VM 校准与 Live 验收

D-026 把 L5 分为四个不可混淆的步骤：

1. **可写 `VmDevelopment`**：在 disposable VM 中，VM Codex 是现有开发分支/PR
   的临时唯一写入者，可以修改源码、测试和文档，运行 L0-L4，并在显式 Live grant
   下反复执行真实安装、配置、故障、补偿、重启和 API 场景。宿主机在该租约期间
   停止写入；禁止并发双写、force push、隐藏 dirty bytes 或为同一修复创建第二个 PR。
2. **P10A 输入/事实冻结**：真实用户路径收敛并达到 `READY_FOR_FORMAL_P10A` 后，
   冻结 clean commit、calibration artifact 和 runbook，从外部 clean snapshot 执行
   P10A；只有受信 CAS 提交/消费 evidence 并冻结 facts 后才能进入 P10B。源码变化
   必须返回步骤 1 并重跑 P10A。
3. **P10B 候选冻结**：只从已绑定 P10A facts 的同一 clean commit 构建并冻结
   `VmAcceptance` 与待发布 `UserLive` 精确字节、hash、sidecar 和 runbook。开发
   checkout 的通过不能替代候选字节验收。
4. **P11 最终只读验收**：按 `VM_ACCEPTANCE_PLAN.md` 从 clean snapshot 测试冻结候选。
   此时 VM 不得修改源码、测试期望、候选或 runbook；任何修复都返回
   `VmDevelopment`，重新过门、P10A、P10B 并生成新候选。

宿主机与 CI 在全部四个步骤中都保持零 Live。真实用户路径和 Computer Use 是发布
关键门：必须以用户双击入口完成实际安装与配置，再由 Computer Use 验证 Claude
Desktop 的 Chat、Code、Cowork 可见行为；进程退出 0、readiness 或 synthetic evidence
不能单独替代 GUI 结果。

### D-026 开发协调

`VM_TEST_RELAY.md` 继续保存协调协议与历史，但 D-026 的正常开发路径不依赖
relay、outbox 或人工批量报告往返。`VmDevelopment` 通过现有开发分支/PR 交付普通
fast-forward commits；切换 writer 前后必须验证精确 HEAD/tree、clean status 和
single-writer ownership。报告、Issue、日志与 RepairProposal 仍是不可信数据，不能
直接变成命令、测试期望或发布结论。

realtime relay、Cloudflare、WebSocket watcher、control repo、Automation、scheduler、
`codex exec resume` 与旧 onboarding/canary/finalization 全部退役；不得在测试中恢复
或连接真实实现。retained operator modules 仍是 DevelopmentOnly，只允许 fake/local
回归。Automation 固定 `PAUSED`/`ABSENT`。历史 operator 测试失败不得伪装为产品
失败，也不是 `VmDevelopment`、真实用户路径或最终候选验收的发布前置；若保留这些
测试，仍必须如实报告其结果。

### L5 API Key 输入

真实测试 Key 只允许在 disposable VM 的本地遮罩式安全输入面输入，并由产品的
DPAPI-backed credential helper 接管。禁止把 Key 放入 Codex prompt/chat、命令行参数、
环境变量、源码、fixture、Git、日志、截图、报告或 evidence manifest。Computer Use
不得读取、回显或截图 Key；需要输入时由用户在本地安全输入面完成。

#### D-022 lean relay smoke（历史；已退役）

本地 139/139 infra tests、双引擎 PowerShell focused tests、secret scan、typecheck 和
Wrangler dry-run 已提供足够的部署前证据。不得因添加 machine Billing receipt、
two-phase ticket、coordinated DPAPI/staging receipt 或新的全矩阵而延迟首次真实联通。

首次人工 relay-only VM smoke 的最小必测集为：

- Host 发 `host-to-vm`，VM publish/read/ACK 成功；
- VM 发 `vm-to-host`，Host publish/read/ACK 成功；
- 两个反向越权和一个错/forged secret 被拒绝；
- 一次主动断线后按 last sequence 重连成功；
- 消息仅是 synthetic pointer，不执行 payload；客户端/Worker 输出的 secret 扫描为 0；
- Git control-repo fallback 仍可用，HostCoordinator/VM automation 仍为 `PAUSED`。

首次 smoke 的 Host secret 只存在当前进程内存/安全输入。VM secret 可通过
人工拖入的 repo 外 owner-only fixed-schema JSON 交接，但必须断言固定 smoke 脚本
在首次网络前已删除 package、最终清零 secret bytes，且无 Git/prompt/日志/evidence 副本。
DPAPI、轮换演练、长时运行 SLO 和完整攻击矩阵是持久 watcher 前或后续 hardening，
不是本次 smoke 的逐项前置。用户回传的 `VM_RELAY_READINESS_V1 Ready=true`
已证明 PowerShell 7、`ClientWebSocket`、时钟、出站 443 与 VM 本地工作目录就绪。
实际 Free-only postdeploy readback、Host dual-role HTTP 和跨设备双向 read/ACK 已通过；
生产 WebSocket reconnect/Hibernation 尚未真实 E2E，不能计入已通过项或把 relay 设为主路径。

当前本地实现与测试映射：

- `lib/vm-test-relay.ps1` 是纯函数合同；`tests/Unit/VmTestRelay.Tests.ps1` 覆盖
  canonical/hash、方向与身份、expiry、重复/乱序/篡改、状态转换和 STOP。
- `lib/vm-reset.ps1` 只实现 fake/TestSafe/DryRun 合同；
  `tests/Contract/VmReset.Tests.ps1` 覆盖 ownership、baseline、plan/receipt、
  `CLEAN_READY` 与需外部快照的 fail-closed 分支。
- `operator/fast-lane/invoke-git-outbox.ps1` 固定 Git/SSH/tool hash、最小进程环境、
  pinned-genesis/linear-history 校验、canonical message path、原子本地 state/lock 和
  fast-forward-only append；HostSandbox 测试只能使用 owner-marked local transport。
- `lib/vm-fast-lane-readiness.ps1` 分开计算宿主实现、VM bootstrap、VM integration、
  P10A-0A 和 Formal P10A；protected history 或窄凭据缺失不能被 bootstrap 状态吞掉。
- `operator/fast-lane/build-vm-onboarding.ps1` 从 clean exact commit 生成确定性 Store ZIP，
  绑定 commit/tree、committed blob、working bytes、工具 hash、repository identity 和
  genesis。输出是 diagnostic onboarding，不是 evidence CAS 对象或产品候选。
- `operator/fast-lane/invoke-vm-reset-live.ps1` 与
  `operator/fast-lane/providers/windows-vm-reset.ps1` 冻结 VM-only dispatcher/provider
  边界。宿主机/CI/伪造上下文必须在任何真实 provider dispatch 前失败；设备 trust、
  real system evidence 与 development-retest Live smoke 仍由 disposable VM 验证。
- `operator/realtime-relay/realtime-relay-client.ps1` 是独立 operator coordination
  PowerShell 客户端入口；`tests/Contract/RealtimeRelay.Tests.ps1` 当前 68 个用例在
  PowerShell 7 与 Windows PowerShell 5.1 下覆盖 fake transport、publisher/watcher、
  断线重连与 resume、原子 state、ACL/no-reparse、DPAPI provider、固定 wake adapter
  和不执行 payload。所有产品 Live、真实 network/registry/process、outside-sandbox、
  unexpected-ledger 与 mutation spy 指标必须为 0。
- `operator/realtime-relay/invoke-foreground-cycle.ps1` 是 D-024 的前台
  Status/Wait/Publish 入口；`RealtimeRelayForegroundCycle.Tests.ps1` 在两引擎均以
  12/12 覆盖双向权限、未知 MessageId wait、重连、ACK 丢失后的过期重放、跨 sequence
  MessageId 拒绝、固定 CLI 失败输出和 non-execution。纯
  `foreground-control.ps1`/`RealtimeRelayForegroundControl.Tests.ps1` 在两引擎均以
  60/60 覆盖原始 strict UTF-8/no-BOM bytes、未转义 control characters、canonical bytes、
  lane/kind/result 语义、
  TTL、evidence path/hash、schema
  drift 与 parser 不执行正文；这些入口仍只属于 DevelopmentOnly operator plane。
- `tests/Contract/FastLanePolicy.Tests.ps1` 冻结两 repository 拓扑、角色权限和
  diagnostic-only 边界；`tests/Contract/OperatorCoordinationBoundary.Tests.ps1` 证明
  realtime relay 在内的 operator modules 和入口具有固定 execution capability 边界，
  是 DevelopmentOnly、非默认 bootstrap、非 ProductCore、非 Release 且不能越界加载 Live。
- `tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1` 通过
  `operator/fast-lane/invoke-synthetic-rehearsal.ps1` 演练本地双 outbox。该演练必须为
  零产品 Live、零网络、零真实 Git、零 registry/AppX/VMP/credential/process 探测和
  零 secret；结果只作诊断，不能证明 P10A-0A 已完成。
- sibling `cddsi-relay-infra` workspace 的 139/139 本地测试、69-file secret scan、guarded
  TypeScript typecheck、Wrangler dry-run，以及实际 workerd/SQLite/Hibernation forced-eviction
  integration 为独立 Cloudflare infra evidence；本地 runtime 证明 eviction 后 SQLite 恢复与原
  WebSocket 继续投递，但不证明生产 idle 调度或公网平台行为。它们不是本产品仓库的 L0-L4、
  Release Simulation 或可发布包证据，也不进入 Release。
- generation-1 OAuth adoption 与固定四 GET Cloudflare preflight 只证明 encrypted keyring、单一
  receipt-bound account、既有 workers.dev subdomain、目标 Worker在初始 preflight 时不存在及已知 usage model；实际
  返回 `STANDARD / BillingPlanVerified=false / BILLING_VERIFICATION_REQUIRED`。它不证明 Free
  subscription 或平台日志；资源 provisioning、secret binding、部署、Host HTTP 与跨设备 relay
  smoke 现在由各自真实回读证明，但不外推为生产 WebSocket reconnect/Hibernation 通过。

截至 2026-07-22，本轮 foreground 最终字节的完整 HostSandbox quality gate 在 PowerShell 7
与 Windows PowerShell 5.1 均发现并通过 605/605，全部 zero metrics 成立；39-file Release
Simulation DryRun 同样通过且 `Changed=false`。该数量只是当次测试清单快照，不是永久 API、
schema 或发布合同。上述映射已证明 clean exact commit 可制作 VM
onboarding 并验证 PUBLIC 合同。tracked 文档不嵌入会自引用的最终 commit/tree/hash；只有同一
暂停 automation、PR CI、实际 Git/remote 与 immutable bundle 的外部机器事实全部匹配，
才派生 bootstrap-only 的 `CanStartVmBootstrap=true`。真实 ruleset/effective-rules receipt
已证明 protected history 生效；本地测试覆盖 public-protected 正向、visibility
mismatch、缺保护、public-outbox secret 与错误角色写入负向合同，但仍不证明 VM reset、
公网 WebSocket 权限负测或 unattended loop 已通过。D-024 的前台 canary 与后续只读 offline
diagnostic 不以创建 minute task 为门；Host task 继续 `PAUSED`，VM task 可为 `ABSENT`。首次
P10A 另需外部 snapshot receipt、独立 CAS 与签名，Fast Lane 测试绝不能替代。

Release secret scanner 只证明当前 PackageFiles 的 source/staging/ZIP/extracted bytes；它不
覆盖 Git history/metadata、DevelopmentOnly 文档、PR、Actions logs/artifacts 或 control-repo
history。用户已接受未审计的存量范围且 cutover 已完成；public outbox 对
credential/Authorization/secret 和未脱敏自由文本的禁令及负向测试仍必须通过。

## 本地依赖

Pester 固定为 5.6.1。精确的 `.dev/modules/Pester/5.6.1` runtime tree 随仓库
提交；`.dev/modules` 的其他内容仍被忽略，也不得用作一般测试输出目录。
`config/dev-dependencies.psd1` 固定版本、文件数、总字节数、manifest SHA-256 和
整树 SHA-256。

`scripts/bootstrap-dev.ps1` 是只读校验器：只核对上述 lock 和 runtime tree，
不下载、不修复、不安装、不导入 Pester，也不修改 PowerShellGet、`PSModulePath`
或用户级模块配置。任何文件缺失、额外文件、reparse point 或 hash 漂移都必须
fail closed，并从可信仓库 checkout 恢复；普通本地与 CI 质量门保持零网络。

## P1 标准检查

调用者必须先显式选定三个受信工具的绝对路径。项目代码不得搜索 PATH 或自行
选择替代工具；下面的占位路径必须替换为本机已明确选定的路径：

~~~powershell
$pwsh7 = 'C:\absolute\path\to\pwsh.exe'
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$git = 'C:\absolute\path\to\git.exe'

$pwsh7Sha256 = (Get-FileHash -LiteralPath $pwsh7 -Algorithm SHA256).Hash
$windowsPowerShellSha256 = (Get-FileHash -LiteralPath $windowsPowerShell -Algorithm SHA256).Hash
$gitSha256 = (Get-FileHash -LiteralPath $git -Algorithm SHA256).Hash

.\scripts\bootstrap-dev.ps1
$evidence = .\scripts\check.ps1 `
    -PowerShell7Executable $pwsh7 `
    -PowerShell7Sha256 $pwsh7Sha256 `
    -WindowsPowerShellExecutable $windowsPowerShell `
    -WindowsPowerShellSha256 $windowsPowerShellSha256 `
    -GitExecutable $git `
    -GitSha256 $gitSha256 `
    -PassThru

if ($evidence.Scenario -cne 'Quality' -or $evidence.CLEANUP_OUTCOME -cne 'Succeeded') {
    throw 'Isolated quality evidence is not clean.'
}

$releaseEvidence = .\scripts\build-release.ps1 -DryRun
if ($releaseEvidence.Status -cne 'SUCCEEDED' -or $releaseEvidence.Changed -ne $false) {
    throw 'Release Simulation evidence is not clean.'
}
~~~

标准检查覆盖：

- PowerShell AST、双版本模块加载和双版本 Pester。
- 公开函数/参数合同。
- Pester Unit/Contract/HostSandbox/Release Simulation 合同。
- operator coordination plane、DevelopmentOnly、非 bootstrap/非 Release 和 synthetic
  零外部访问合同。
- Host/CI 对 Live provider 的构造、加载和执行保持 fail closed；VM Live surface
  仍须满足精确 allow-list、stage/grant 和 provider 合同。
- JSON、编码、换行、secret scan。
- 隔离 Git inventory、工作区与暂存区 `diff --check`。
- Release manifest 与 DryRun。
- 文档索引、隔离合同、实施计划和 HANDOFF 可发现性。

双引擎质量门的执行拓扑固定为每个引擎 1 个 Static worker 加 13 个
`QualityShards`。分片由 `config/dev-dependencies.psd1` 冻结，42 个 test files 精确
覆盖一次；父进程只传 `ShardId`，逐份验证 strict UTF-8 role evidence 后再聚合。
每个 worker 都实际输出中文/emoji/非 BMP round-trip marker，父进程同时验证 stdout
与 stderr。成功 evidence 精确为 31 个 trusted process、68 条最终 harness ledger 和
两个 engine aggregate。

`ProcessTimeoutSeconds` 是每个冻结 worker 的上限，不是整套双引擎的一刀切预算。
超时杀死可用进程树并有界 drain，外部 stderr 输出
`CDDSI_SAFE_FAILURE_EVIDENCE_V3=<json>`；JSON 包含当前 engine/role/shard、已完成
worker 计划前缀、test-file 与 passed counts。非超时 Pester 失败另含最多 32 个由
worker/parent 双重绑定到 tracked static `It` 源码的 repo-relative path、source line
和测试名；不包含任意错误正文。部分证据只能诊断，不能冒充 PASS。

`check.ps1` 只接受绝对工具路径与对应 SHA-256，并由 HostSandbox runner 间接
运行 Pester 和 Git；不继承真实用户 HOME/AppData/Temp、Git 配置或一般
`PSModulePath`。它已经覆盖 Windows PowerShell 5.1，因此禁止在外部再直接导入
Pester 运行一遍。

HostSandbox 内需要构造本地 bare repository 的测试必须消费父 harness 传入并由
worker 再验 hash 的固定 Git grant，不能依赖 worker `PATH`。该 grant 只允许本地
fixture/CAS 质量验证，不授权网络 remote；缺少固定 binding 时正式 worker 失败。

`build-release.ps1` 必须在同一工作流的 clean quality evidence 之后运行，只接受
`-DryRun`。省略 `-DryRun`、传入 `-SkipQualityGate` 或指定输出目录都必须
fail closed；Release Simulation 只在自有 sandbox 中暂存、打 ZIP、解压、比对并
清理，不发布产物。

## Git 隔离

HostSandbox/CI 中运行 Git 时设置：

~~~text
GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL=<sandbox empty config or Windows null device>
GIT_OPTIONAL_LOCKS=0
HOME=<sandbox>
XDG_CONFIG_HOME=<sandbox>
~~~

这些设置防止读取系统/用户 Git 配置；它们不能替代 provider 隔离。

## 必需断言

每个 L0-L4 TestSafe/DryRun 场景：

- `Changed=false`。
- mutation spy 全部为零。
- live provider 未加载。
- 产品 process/network/registry/package/feature/service 调用为零。
- outside-sandbox write 和 unexpected ledger entry 为零。
- trusted harness 调用与声明精确相等，未授权 harness 调用为零。
- secret findings 为零。

精确证据字段只在 `TEST_ISOLATION.md` 维护。持久/可分享报告只记录 logical
token 和 sandbox 相对路径；本机临时控制台可以显示 sandbox 绝对路径，但不能
持久化或分享。

## 故障注入

### 文件和状态

- 目录创建、磁盘满、flush、重读、replace、rollback 和 cleanup 失败。
- 路径逃逸、reparse point、owner marker 和 TOCTOU。
- checkpoint 损坏、过期、未知 schema 和 runId 冲突。
- P10A consumption 与 release-facts freeze 的 raw proposal 回放、错 store/epoch、
  错 authority key、旧 revision、CAS 竞争、跨 session 与过期 commit receipt。

### 下载和验签

- DNS/TLS/timeout/cancel。
- 截断、超限、非法重定向和缓存污染。
- hash、artifact type、arch、signer、chain、Publisher、identity 失败。
- 验签后同路径换包。
- Release sidecar 的空/伪造 RSA-PSS 签名、换 key/证书、claims 篡改、错 request
  nonce、未来/过期 signer assertion 和 manifest bytes/hash 漂移。
- P11 receipt 缺失时 promotion 构造与验证必须始终失败。

### 进程和系统

- 启动失败、非零退出、超时、大量输出和子进程树。
- AppX/VMP/service/registry fake 的拒绝、部分成功和补偿失败。
- 明确证明没有 bypass 参数。

### 凭据和配置

- Key 格式、SecureString、DPAPI、ACL、helper timeout/非法输出。
- `CLAUDE_HELPER_CONTEXT` 五种精确值；`mid-session-refresh=20s`、其他 context
  `=60s`，非交互调用不得提示或等待输入。
- helper 根目录的 `.`/`..`、尾随点/空格、设备名、superscript COM/LPT alias、
  reparse 和最终解析路径漂移。
- HKLM/HKCU/local precedence、冲突、部分写、重读和恢复失败。
- configLibrary 首版只测检测、precedence 和冲突；sibling temp/flush/replace 仅在
  未来单独批准 local writer 后启用。
- 日志、状态、报告、备份和 Release 的泄露扫描。

### 验收

- 没有 capability selector，三个 surface 的 serializer 值始终为 true。
- Git 合格复用、缺失、过旧、损坏、多路径歧义和用户取消。
- 运行、能力、UI 证据三层状态分别验证；`NOT_TESTED` 只用于 UI 证据。
- Chat、Code、Cowork readiness 分别 READY/BLOCKED/PENDING_RESTART 等状态。
- 不支持 content block。
- Repair/Restore 失败。
- 一个子项不能提升其他子项状态。
- 禁止通过关闭 Code/Cowork 把 PARTIAL/ACTION_REQUIRED 提升成 SUCCEEDED。
- `VmDevelopment` 每次源码修改后重新运行 focused tests、完整 L0-L4 和相应 Live
  场景；只允许修复已证明的 test defect，不得删除或放宽真实用户行为断言。
- 最终冻结验收拒绝 moving-ref、dirty source、候选 hash 漂移和运行中热补丁。
- 用户双击中英文入口、UAC/重启续跑、本地遮罩式 Key 输入、实际安装/配置、
  重复运行、Repair/Restore 都必须使用待发布用户路径验证。
- Computer Use 必须分别观察 Chat、Code、Cowork 的实际 Desktop 行为，并将
  `PASS/FAIL/NOT_TESTED` 与结构化 readiness 分开记录；任何发布必需项
  `NOT_TESTED` 都不构成发布 PASS。
- 历史 relay/outbox、`VM_BATCH_TEST_REPORT_V1` 或模型文字只能作诊断，不能自证
  最终候选或 P11 PASS。
- 正式发布结论必须绑定声明支持的多环境 clean-snapshot 结果和精确 candidate
  bytes/hash；缺少实际镜像时收窄支持声明，不得用同一个 VM 外推。

## 特殊路径

所有入口、process runner、Release Simulation 覆盖：

- 中文。
- 空格。
- `& | < > ^ % !`。
- 括号。
- 空参数与空字符串。
- 长路径和拒绝路径。

`.cmd` 仍必须 ASCII/no-BOM/CRLF，不使用 `chcp`。

## 测试数据

- Key 在运行时分片构造，fixture 中不放看似真实的 token。
- 不使用真实用户名、真实用户路径、真实日志或真实配置。
- MSIX/EXE 使用 synthetic signed/unsigned fixture metadata；本地不下载上游包。
- API 使用 fake handler，不连接 DeepSeek/Anthropic。
- Registry 使用内存 map，不使用“测试子键”触碰真实 HKCU/HKLM。
- 上述 synthetic 规则适用于 L0-L4；L5 真实 Key 仍只能由用户在 VM 本地遮罩式
  输入，绝不进入自动化 prompt、fixture 或可分享 evidence。

## 每阶段质量门

每个工作包必须：

1. 先更新测试和故障矩阵。
2. 运行适用的 L0-L3。
3. 取得 clean `check.ps1 -PassThru` 证据，再运行 Release DryRun；隔离
   `git diff --check` 已由 check 质量门执行。
4. 检查 manifest、secret、docs 和 HANDOFF。
5. 记录通过数量、失败/跳过/未运行；任何 skipped/not-run/inconclusive 都不算干净。

不得用 `-SkipPester`、`-SkipQualityGate` 或放宽安全规则交付完成状态。

`VmDevelopment` 每批修改还必须运行命中模块的 focused tests 和受影响的真实用户
场景；准备候选前统一运行完整 L0-L4、Release DryRun、diff/编码/secret scan。最终
冻结候选必须在声明支持的 clean VM 环境中重新走用户入口和 Computer Use；该轮禁止
源码修改。全部通过只表示“可提交 P12 人工决定”，不授权自动 merge、promotion 或
release。

## P1 交付判定（已满足）

- 不增加或加载真实 provider、live adapter 或系统探测。
- 不直接调用缺少显式 synthetic path/ExecutionContext 的产品函数。
- vendored Pester 校验、双引擎 quality evidence、HostSandbox 清理和 Release
  Simulation 必须全部 clean。
- 任一工具 identity/hash、依赖 lock、sandbox owner、证据 schema、测试计数或
  Release allow-list 漂移都 fail closed，不能用额外直跑命令替代失败证据。
- 以下 2026-07-14 数字是 P1 首次退出门的历史快照；当前全树证据以
  `HANDOFF.md` 为准。双引擎各 124 项全部通过，固定 suite 为 16/10/6；5 个
  trusted process 与 16 项 harness ledger 精确匹配；全部必需零值、mutation spy、
  repository unchanged 和 cleanup 通过。Release DryRun 的 29 个 PackageFiles 在
  四层扫描、清单、内容 hash 和 16 项 filesystem ledger 上全部 clean。
- 该判定只覆盖项目控制的宿主机自动化，不代表 OS 隔离、CI/L4、VM Live 或发布
  候选已完成。完整易变证据见 `HANDOFF.md`。
