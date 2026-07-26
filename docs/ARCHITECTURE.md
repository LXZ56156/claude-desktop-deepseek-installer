# 架构

更新日期：2026-07-26

## D-027 当前架构

D-027 采用 Windows 11 x64 + Windows PowerShell 5.1 的窄垂直架构。目标是让用户从
解压 ZIP 和双击入口开始，依次完成 preflight、Git、Claude、VMP/重启、credential、
HKCU policy、生命周期和 Chat/Code/Cowork，而不是继续建设通用执行框架。

~~~text
.cmd (中/英)
  -> Start-Here.ps1 / PS5.1 orchestrator
     -> preflight + explicit Live confirmation
        -> narrow Windows adapters
           -> Git detect/acquire/verify/install/readback
           -> Claude acquire/verify/install/readback
           -> VMP/UAC/checkpoint/resume
           -> Credential Manager/DPAPI helper
           -> HKCU policy ownership/backup/readback/compensation
           -> Claude lifecycle/Diagnose/Repair/Restore
              -> visible Chat/Code/Cowork acceptance
~~~

Live adapters 不由默认加载触发，只能在具有外部可恢复 snapshot 的 disposable VM
或最终用户显式 Live 流程使用。TestSafe/DryRun 是窄旁路：返回计划/安全状态并确保
零真实进程、网络、注册表和外部写入，不模拟完整 OS。

现有 ExecutionContext/provider/Fake/access-ledger/HostSandbox 不是 D-027 目标架构。
可局部复用直接有助于上述垂直路径的纯合同和结果类型，但不得为了框架完整性阻塞
Git/Claude 真实路径，也不得全面重写已可用模块。

候选链为：

~~~text
clean source commit/tree
  -> one reproducible candidate ZIP + SHA-256 + length + SBOM
     -> external restore of clean Windows 11 x64 snapshot
        -> exact candidate end-to-end acceptance
           -> D027_RELEASE_READY
              -> manual merge/release decision
~~~

任何 source 修复都会废弃旧候选并完整重建/重验。D-026 P10A/P10B/P11 和多环境
正式链只保留历史。

## D-026 定位与通用 provider 架构（历史；已由 D-027 取代）

本项目独立安装和配置 Claude Desktop，不依赖独立 Claude Code CLI。目标是通过
Anthropic 官方 Third-Party managed configuration 连接 DeepSeek，固定以 Chat、
内置 Code 和 Cowork 三项全部可用为产品目标。

公开入口仍为 `Scaffold`，领域模块的 Live 动作无条件失败；D-026 授权 disposable
VM 在独立 `VmDevelopment` 通道内完成这些实现，而不是把当前脚手架误称为可用产品。
P1 已实现 ExecutionContext、十类 provider contract、default-deny fake provider、
AccessLedger、state-store provider 边界和 trusted HostSandbox。当前又完成隔离的
`LiveReadOnly` 装载合同，但调度来源仍未绑定；11 个只读 capability 在任何同名函数
调用前稳定以 `LIVE_READ_ONLY_ADAPTER_SOURCE_UNBOUND` 失败，保持零 OS I/O；
live adapter 仍不进入默认 bootstrap 或本地/CI 执行图。

当前架构采用两段式单写者模型：

~~~text
Host preparation (current exact commit/tree)
  -> Host pushes one clean handoff commit and freezes writes
     -> VmDevelopment sole writer on the existing branch / PR #1
        -> implement Live + focused synthetic tests + real user-path iteration
           -> build a clean immutable candidate
              -> read-only multi-environment and Computer Use acceptance
                 -> P12 manual publish decision
~~~

VM 开发期允许源代码变化；最终候选验收期不允许现场热修。任何验收失败都返回
`VmDevelopment`，提交新代码并重建候选。两段都不恢复 relay、Cloudflare、
control repo、Automation、scheduler 或 `codex exec resume`。

## 分层

~~~text
Entrypoints
  -> Orchestrator
     -> ExecutionContext + Policy + AccessLedger
        -> Domain services
           -> Provider interfaces
              -> Fake/Sandbox providers (local and CI)
              -> Live adapters (VM/UserLive only)

OperatorCoordination (separate development plane)
  -> Host freezes exact handoff commit/tree and its own writes
     -> user manually transfers one complete development prompt
        -> VM is the sole writer during VmDevelopment
           -> final candidate is frozen again for read-only acceptance
~~~

### Entrypoints

`.cmd` 和 `Start-Here.ps1` 只负责参数、模式、交互边界和退出码，不直接执行
领域动作。

### Orchestrator

编排顺序、补偿和阶段门只放在顶层：

~~~text
preflight
  -> fixed all-surfaces target
  -> acquire and verify artifacts
  -> ensure Git availability
  -> Cowork preparation
  -> acquire protected credential
  -> detect config sources and backup
  -> deploy one config source
  -> lifecycle
  -> Chat / Code / Cowork acceptance
  -> report / repair / restore
~~~

### ExecutionContext

所有非纯操作显式接收上下文：

- RunId、Mode、Stage、EnvironmentTier。
- synthetic/live 路径。
- provider 集合。
- real-resource policy。
- access ledger。

TestSafe/DryRun 测试缺 fake provider 时失败，不能回退到真实环境。详细合同见
`TEST_ISOLATION.md`。

### Domain services

现有模块按领域保留：

- `d027-snapshot-authorization.ps1`
- `desktop-env-check.ps1`
- `desktop-msix.ps1`
- `git-for-windows.ps1`
- `cowork-readiness.ps1`
- `deepseek-api.ps1`
- `desktop-config.ps1`
- `desktop-lifecycle.ps1`
- `desktop-acceptance.ps1`

`d027-snapshot-authorization.ps1` 是 D-027 外部 clean-snapshot authority、
receipt、平台绑定和 process-scoped Git session 的窄公共核心；它在
`execution-context.ps1` 后、Claude/Git 领域模块前加载。纯 common-proof validator
只验证共享 schema、平台、时间窗、调用方绑定的 execution artifact 和 RSA proof；
它不选择 operation、不比较 domain workload pairing，也不建立 session。Git wrapper
固定 `InstallGitForWindows`，Claude wrapper 固定
`ProvisionClaudeDesktopMachineWide`，两者不接受 caller-selectable operation 或
workload token。Claude workload descriptor 绑定候选 commit/tree/ZIP/内容清单/SBOM、
credential helper 源码与 PE、Claude MSIX 内容、下载/held-file/manifest/package
identity/signature evidence token，并把 receipt 的 execution artifact 固定为候选 ZIP。
这些 evidence token 在本层只作引用绑定，形状正确不等于 signer、publisher、下载或
held-handle 已获信任。Claude process-scoped session、Enable/Assert 和 Live machine-wide
provisioning 仍未实现；production snapshot authority 仍为 `Configured=false`。

`desktop-msix.ps1` 的 D-027 manifest 纯解析结果为精确 13 字段：调用方 bytes 先
克隆成单一本地 snapshot，raw manifest SHA-256/长度与 parsed package identity
分别绑定，再组成独立 manifest binding。same-state signer evidence 纯合同为精确
30 字段，交叉绑定 run/path/download receipt/held-file/content/manifest/package、
公开 certificate DER 及其 SHA-256/长度/SHA-1 thumbprint、Subject 文本与
`SubjectName.RawData` 摘要、固定 WinVerifyTrust claim 和时间窗。manifest Publisher
原文必须与 DER 解析出的 certificate Subject 做 ordinal/case/space-sensitive 精确
相等；manifest parsed-X500 raw hash 与 certificate SubjectName raw hash 分别保留，
在真实 artifact 校准前不假设两者编码相等。证书解析使用 `EphemeralKeySet`，且输入
必须是与解析后 `RawData` 精确相等、不含 private key 的单一 DER。

这一层只验证 evidence claim 的结构与相互一致性，没有 native WinVerifyTrust、I/O、
authoritative held-handle producer、policy、session 或 Live authority，固定
Trusted/`0x00000000`/Verify→Extract→Close 仍只是被校验的自报告字段。

新增的 D-027 Claude native observation 是 script-scoped 强类型 delegate，不是
PowerShell command，也没有任何 session consumer。它只在 Win11 Workstation、
native AMD64、64-bit Windows PowerShell 5.1 下借用 caller-owned readable/seekable/
non-writable `FileStream`。native type 对 SafeHandle 保持 add-ref，由同一 handle
取得 WinTrust 所要求的 canonical path，并把 required path 与 raw handle 一起传入
`WinVerifyTrustEx` Generic Verify V2；产品代码不按路径重开。字段名
`CallerFileHandleSupplied` 是刻意的：它只证明 handle 被提供，`fOpenedFile=false`
也只证明 trust provider 未自行 open file，二者都不夸称每个 OS/SIP 内部读取一定
使用该 handle。

native observation 在同一个 WVT state 中依次取得 provider data、唯一 primary
signer index 0/non-countersigner、certificate index 0，并在 CLOSE 前把 256–12,288
byte 的公开 DER 复制到 managed memory。`WINTRUST_SIGNATURE_SETTINGS` 用非零 output
sentinel 请求 secondary-signature count，必须观察到 verified index 0、secondary
count 0；provider state 另须恰好一个 primary signer。每个已返回的 VERIFY 都必须在
`finally` CLOSE，同一 GUID/data/path/file-info/handle/signature-settings allocation
保持到 CLOSE 返回，只有 native VERIFY/CLOSE 都精确为 0 才保留 DER。no-revocation +
cache-only 只证明本次未检查吊销且不允许 WVT 网络获取，不证明证书未吊销。

VERIFY 前与 CLOSE 后从同一 handle 比较 file attributes、creation/write time、
volume/file index、size、link count，并重新解析 final path、重算 path binding。
stream position 随后恢复，caller handle 不由 primitive 关闭。这里仍不是完整 artifact
authority：read-only stream 无法反推 caller 使用的 share mode，稳定 file facts 也
不是 byte-level hash equality。未来真实 downloader 必须在内部以 `FileShare.Read`
创建并持有最终 handle，在该锁定 stream 上做 pre/post SHA-256、raw manifest、
download receipt、held identity/content、publisher/signer policy 的完整组合；成功
CLOSE 后才能创建 30 字段 evidence。只有该 downloader-owned、未外泄 producer 以及
真实 policy 完成后，后续 Claude process-scoped session 才可能消费其结果。当前
unsigned 负路径与 ABI/static lifecycle 已验证，真实官方 MSIX 的 positive
provider-reopen、secondary/primary signer、DER/publisher 行为仍是 disposable VM
clean-snapshot calibration gate。

在该 native observation 之上的私有 correlation core 固定在同一个 stream 上执行
identity A → SHA-256 A → raw manifest → same-state WVT → SHA-256 B → identity B，
不按路径重开。同一 native type 通过 handle 额外取得 NTFS、volume serial、file
index、attributes、creation/write time、size、link count 与 final-path binding；
`GetVolumeInformationByHandleW` 的 serial 必须与 `GetFileInformationByHandle`
精确相等，全部不透明 facts 再进入私有 binding token。

任意 caller-supplied `FileStream` 仍只能调用
`CallerHeldReadOnlyFileStreamCorrelation` wrapper。即使
hash/length/path/full-facts/WVT readback 全部相等，它也固定以
`CALLER_FILE_SHARE_POLICY_UNPROVEN` 停止且 material 为空，因为
`FileStream.CanWrite=false` 不能反推出原始 share flags。新增的唯一 construction-site
wrapper 自己用精确 `FileMode.Open/FileAccess.Read/FileShare.Read` 打开最终文件，并
向 core 传入同一 script scope 的 reference capability；只有该路径能得到
`CORRELATED` material。material 只是 held identity/content、manifest 与 same-state
signer observation 的瞬态关联，不是 Anthropic identity 或安装 authority。任一失败，
包括最终 stream position restore 失败，都把状态改回 `FAILED` 并清空全部 material；
wrapper 返回前关闭自己创建的 stream。

同一文件新增的 bounded body-writer 也是 script-scoped delegate。它只接受直属于
canonical staging root、名称为 `claude-<16 lowercase hex>.partial` 的新路径，以
`CreateNew/Write/FileShare.None/WriteThrough` 创建文件，从调用方 stream 以 64 KiB
buffer 读取，强制 64 bytes–1 GiB 的精确 declared length，增量计算 SHA-256，并在
成功前执行 `Flush(true)`。它不关闭 caller stream，不删除或移动 partial，也不执行
HTTP、redirect、manifest、WVT、receipt 或安装；失败只返回 path binding 和 allowlisted
阶段码，不返回异常或原始路径。

这两个 primitive 仍没有把真实 transport 组合成 downloader。最终 outer producer
必须先验证 fixed NTFS、全祖先非 reparse、owner-only writer ACL，手动验证官方
redirect/header 后调用 body-writer，原子提交，再在一个仍保持打开的
`FileShare.Read` scope 内调用 core、把 body hash/length 与 final correlation 精确
比较，构造并纯验证 download receipt、held observation 与 30 字段 evidence，最后
才关闭句柄。当前 construction-site wrapper 只是未绑定 ownership 的观察 primitive，
因其返回前已
关闭句柄，不能直接作为公开 `Save` handoff；也没有网络/header validator、原子提交、
receipt/evidence bundle、policy、session 或 installer consumer。source descriptor
的 Anthropic SHA/signer/publisher/identity 仍未冻结，verify-to-install 的重新锁定与
执行前重验也未实现，因此当前没有可传给安装或发布门的 authoritative 正向结果。

领域模块之间不形成循环依赖，也不能直接调用系统 cmdlet/.NET I/O。跨域协调只在
orchestrator。acceptance 消费结果，不成为安装实现的依赖。

### Providers 与 Live adapters

Provider 覆盖 FileSystem、Environment、Registry、Network、Process、Package、
Feature、Service、Credential、Clock。

- fake/sandbox provider 是本地和 CI 唯一可加载实现。
- live adapter 使用精确文件 allow-list，不能由默认 bootstrap 加载。
- VmDevelopment 授权骨架先构造不可执行的 `Unloaded` provider set；只有
  stage manifest、精确 stage/tier/profile、独立 `LoadLiveProviders` 确认和已提交
  single-use CAS receipt 全部匹配时才能到达 adapter 边界。装载成功只会产生绑定
  run/stage/tier/profile、调用方声明的 adapter SHA-256 字段、load operation-use ID/receipt 和
  capability-set digest 的 `LiveReadOnly` provider set；它不授予 mutation capability。
  当前 SHA-256 字段只做格式和传递校验；在受信规范化路径、实际文件重新哈希和组合
  load receipt 实现前，不得称为 package-bound adapter identity。
- `LiveReadOnly` 每个 provider contract 都显式包含 `Access=ReadOnly`。provider 分区内
  capability 的精确字段为 `SchemaVersion=1/Operation/ResourceToken/ArgumentNames/ResultSchemaId`；
  capability-set digest 将分区 Provider 名与后四个 capability 字段组成五段 canonical
  line，并做 ordinal sort 后绑定。它只接受
  以下 11 个精确 tuple；Operation 均为 `Inspect`，Arguments 必须是空 dictionary：

  | Provider | ResourceToken | ResultSchemaId |
  | --- | --- | --- |
  | `Environment` | `<ENVIRONMENT:WINDOWS>` | `WindowsEnvironmentObservation/v1` |
  | `Environment` | `<ENVIRONMENT:HARDWARE_VIRTUALIZATION>` | `HardwareVirtualizationObservation/v1` |
  | `Environment` | `<KNOWN_FOLDERS:CURRENT_USER>` | `CurrentUserKnownFoldersObservation/v1` |
  | `Package` | `<PACKAGE:CLAUDE_DESKTOP>` | `ClaudeDesktopPackageInventory/v1` |
  | `Process` | `<PROCESS:GIT_FOR_WINDOWS>` | `GitForWindowsInventory/v2` |
  | `Feature` | `<FEATURE:VIRTUAL_MACHINE_PLATFORM>` | `VirtualMachinePlatformObservation/v1` |
  | `Service` | `<SERVICE:COWORK>` | `CoworkServiceObservation/v1` |
  | `Registry` | `<HKLM_MANAGED_POLICY>` | `ClaudeConfigSourceMetadata/v1` |
  | `Registry` | `<HKCU_MANAGED_POLICY>` | `ClaudeConfigSourceMetadata/v1` |
  | `FileSystem` | `<CONFIG_LIBRARY>` | `ClaudeConfigSourceMetadata/v1` |
  | `Process` | `<PROCESS:CLAUDE_DESKTOP>` | `ClaudeDesktopProcessInventory/v1` |

- 本批不实现任何 tuple 的系统读取。当前 provider set 尚未绑定 adapter 的规范化绝对
  路径、函数定义 SHA-256 与 load receipt 组合摘要，因此合法 tuple 也会在查询或调用
  任何 ambient 同名函数、写入 ledger 或改变 context 前抛出
  `LIVE_READ_ONLY_ADAPTER_SOURCE_UNBOUND`。adapter 内的精确
  `ProviderFailure/LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED` 分支只受静态合同约束，
  不是当前 dispatcher 可达的产品路径。未装载、越界 tuple、非空参数或绑定漂移同样
  在 provider 调用前 fail closed。
- adapter 静态策略绝对禁止定位或接触真实
  `%USERPROFILE%\.claude\settings.json`，包括 `Test-Path`、枚举、哈希、读取、备份、
  写入和删除；known folders 只能作为结构化观察返回，不得转化为该禁区的访问能力。
- D-026 下 live adapter 的实现和首次真实执行只在 disposable VM 的
  `VmDevelopment` stage；最终 acceptance 只消费重新冻结的候选。
- trusted test harness 使用另一份精确 allow-list，只能创建自有 sandbox、启动
  pwsh/Pester/Git 质量门并单独记账，不属于产品 provider。

### 当前 VmDevelopment coordination plane

D-026 的权威协调合同见 `VM_TEST_RELAY.md`。宿主机提交 clean handoff 后停止产品写入，
VM 在现有 `codex/repair/p10a-0a-fast-lane` 和 PR #1 上取得唯一写入租约，按共同根因
实现、测试、普通 commit 并 fast-forward push。认证只在 VM 内通过官方交互登录完成，
任何 token、API Key 或其他 credential 都不进入 prompt。

发布必过门覆盖产品 Unit/Contract、安装、配置、签名、凭据、补偿、恢复、Release
inventory/secret scan 和实际用户路径；已退役 relay/outbox/Automation 传输与旧
evidence-plumbing 回归只作为非阻塞历史诊断，正式 P10A/P11 candidate evidence 永不
退役。development ZIP 先由 Computer Use 验证 Chat、Code、Cowork，达到
`READY_FOR_FORMAL_P10A` 后才进入事实冻结、候选构建和 P11；P11 正式通过才产生
`RELEASE_READY` 并进入 P12 人工决定，不自动 merge 或发布。

### Operator coordination plane（历史；由 D-026 取代）

双机测试闭环属于独立 OperatorCoordination development plane，权威合同见
`VM_TEST_RELAY.md`。以下只描述 D-025 及更早设计：当时只通过用户人工搬运完整提示词和
`VM_BATCH_TEST_REPORT_V1`；Host 唯一写代码，VM 只读。报告先按 commit/tree、矩阵、
零指标与 evidence manifest 校验，再按共同根因批修。该平面不进入产品 bootstrap、
ProductCore、Release 或 trusted harness runtime，也不充当正式证据验证器。

realtime relay、Cloudflare、WebSocket watcher、control repo、Automation、scheduler、
`codex exec resume` 和旧 onboarding/canary/finalization 已退役，无操作权。以下截至
2026-07-22 的实现说明只保留 DevelopmentOnly 历史/回归背景：宿主机侧
Git transport/runtime、onboarding 和 readiness 合同已实现，三仓 public visibility 与
服务端 protected history 已部署；Cloudflare realtime accelerator 的产品侧纯 PowerShell
合同、独立 infra 实现和离线测试也已完成。Free-only 外部步骤虽已获授权，既有 Cloudflare
credential 的本任务 adoption/provenance、GET-only preflight 与 Edge Billing dashboard
人工核对也已完成；Workers Paid 未列出。D-022 已决定不等待 machine Billing
receipt/ticket/coordinated DPAPI receipt，直接完成 lean provisioning 与一次性
relay-only VM smoke。用户回传的 `VM_RELAY_READINESS_V1` 已表明 VM `Ready=true`；Free-only
Worker/SQLite Durable Object、两项 secret binding、postdeploy 精确回读、Host HTTP 与跨设备
relay-only smoke 已完成。生产 WebSocket reconnect/Hibernation 尚未真实 E2E：

~~~text
Fast Lane logical control plane:
  HostCoordinator -> public protected host-to-VM repository -> VmTester (read only)
  HostCoordinator <- public protected VM-to-host repository <- VmTester (write only)
Realtime notification accelerator (pointer only):
  HostCoordinator -> host-to-vm lane -> Worker/RelayRoom -> VmTester
  HostCoordinator <- vm-to-host lane <- Worker/RelayRoom <- VmTester
  disconnect/replay fallback -> public protected control repositories
Formal Lane: external clean snapshot + exact artifact
             -> independent CAS/signature/receipt validators
~~~

- `config/fast-lane-policy.psd1` 冻结两个物理单向 public protected repository、产品 remote、
  角色、分钟级轮询、reset allow-list 和禁止 promotion 的策略。之所以不用同一仓库
  两个目录，是因为 GitHub deploy key 是 repository-scoped，不提供 path-scoped 写
  capability。
- `lib/vm-test-relay.ps1` 是 pure Fast Lane canonical validator/state machine，负责
  双 repository/outbox identity、CycleId/sequence/previous hash、CAS、单 active
  cycle、STOP 和 fail-closed transition；它没有 Git/network transport。
- `operator/fast-lane/invoke-git-outbox.ps1` 是 DevelopmentOnly 的固定 transport
  runner：清空继承环境、绑定 Git/SSH/key/known-hosts hash、验证 repository 数字/node
  identity、protected-history evidence、pinned genesis 和线性 commit chain，只允许
  bounded fast-forward poll/append，不执行 payload。protection observation 还必须与
  operator-plane `control-protection-trust` owner marker、receipt-specific authority
  assertion、独立预置的 assertion SHA-256/authority token 及单调 previous-receipt
  chain 交叉绑定，不能用 receipt 或 relay 自举信任。
- 独立 sibling workspace `../cddsi-relay-infra` 才承载固定版本 Node/Wrangler、
  TypeScript、Cloudflare Worker 和 SQLite-backed `RelayRoom` Durable Object；这些
  工具、配置与源码不进入产品仓库、安装器或 Release package。
- `operator/realtime-relay/realtime-relay-client.ps1` 是 DevelopmentOnly 的 PowerShell 7
  watcher/publisher/provider：长连接使用 `ClientWebSocket`，断线从最后确认的 sequence
  恢复；状态根必须 owner-marked、本用户 ACL 且无 reparse，状态更新采用原子替换。
  它只由精确 OperatorCoordination 入口或 fake/local 测试加载，不进入 bootstrap、
  ProductCore、Release 或 trusted harness runtime。
- Realtime relay 只传递固定 schema 的 immutable notification pointer，包括 repository、
  ref、commit 和 payload hash；代码、prompt、shell/PowerShell、日志正文与自由文本均不
  进入可执行路径。protected-history control repositories 继续承担持久审计、断线重放
  和低频 fallback，relay ACK 或消息不能替代其历史，也不能替代 Formal evidence。
- HostCoordinator 与 VmTester 使用两组独立 256-bit HMAC capability：Host 仅写
  `host-to-vm`、读 `vm-to-host`，VM 权限相反。请求签名绑定 client、method、canonical
  path/lane、timestamp、nonce 和 body SHA-256；消费端还逐项验证 sequence、previous
  hash、TTL、MessageId 和 payload hash，任何缺口、重放、错 lane 或 schema 漂移均
  fail closed。
- 客户端 runtime secret 不得进入日志、异常、state 或 health output。一次性
  manual smoke 可从当前进程内存/安全输入取得；VM 还可由固定 smoke 脚本
  读取人工拖入的 repo 外 owner-only fixed-schema JSON，并在首次网络前立即删除。
  该 JSON 不进入 Git/prompt/日志/evidence，不是长期存储。持久 unattended watcher 才必须
  经 DPAPI CurrentUser provider 取得。wake 仅调用预绑定的 fixed adapter，绝不把 payload
  拼接成命令、参数或 prompt。Cloudflare OAuth/deploy credential 与两端 runtime HMAC
  credential 仍分离。
- 当前外部授权限定 Free-only。用户在知悉既有 encrypted keyring `default` profile 有 29 项
  scope、包含四项必需 scope 且另有 25 项后，明确授权直接复用；认证门验证必需项存在而不再
  要求 scope 集合精确相等，额外 scope 也不扩大本任务允许的资源或动作。本地已实现 owner-only
  crash recovery、过期 receipt 原子续期及 account-bound credential snapshot。真实精确 infra
  root 的 exact/inherited binding absence 已证明，generation-1 owner-marked receipt 已绑定
  `default.enc`、account 与 permission hashes；初始四 GET preflight 已确认单一 account、既有
  workers.dev subdomain、目标 Worker当时不存在，并报告 `WorkersUsageModel=STANDARD` 与
  `BillingPlanVerified=false`。当前状态为 `PROVISIONED / CROSS_DEVICE_SMOKE_PASSED /
  NOT_PRIMARY / AUTOMATION_PAUSED`；usage model
  不是 subscription receipt。经用户授权复用个人 Edge 既有登录态的只读 Billing → Subscriptions
  核对未列出 Workers/Workers Paid；active Teams Free Base 与无关 R2 Paid 不改变 Workers 的独立
  计划边界、不授权 relay 使用 R2，也不把整个账号称为 Free。
- credential 采用后和部署后读回必须验证单一 account、workers.dev、Worker/DO 配置
  与 active deployment；明文 profile 必须不存在，OAuth/deploy credential 与 runtime HMAC
  credential 必须继续分离。machine Billing receipt validator/recorder、owner/SYSTEM-only ACL、
  fresh observation 绑定与两阶段 ticket 仅是 optional hardening，不再是写门。
  SQLite-backed Durable Objects 支持 Workers Free，Free 超限后操作失败而非计费。Cloudflare
  runtime secret bindings 与 Worker 已 provision；Host 明文 frame 在 DPAPI CurrentUser round-trip
  后已删除，只保留仓库外 owner-only blob。VM 未安装持久 secret/watcher，任一 unattended watcher
  均未启用；这不影响已完成的一次性内存-secret smoke。
- `lib/vm-fast-lane-readiness.ps1` 明确区分 `CanStartVmBootstrap` 与
  `CanStartVmIntegration`。前者只授权离线 bundle/key/task staging；后者还要求 protected
  history、窄 HostCoordinator credential 和保持暂停的 host task。policy 与 onboarding
  manifest 同时冻结 host/VM 两端的初始状态为 `PAUSED`。
- `operator/fast-lane/build-vm-onboarding.ps1` 从 clean exact commit 构造 deterministic
  Store ZIP，并绑定 tree/blob/working bytes、工具 hash、repository identity、genesis、
  prompt 和 runbook。ZIP 为 diagnostic-only，不是产品候选或 Formal evidence。
- `lib/vm-reset.ps1` 是 pure/fake deterministic-reset 合同：冻结 owner receipt、
  精确 allow-list、baseline、升级原因和 `CLEAN_READY`。TestSafe/DryRun 只消费声明的
  fake provider，Scaffold Live 在 provider dispatch 前失败。
- `operator/fast-lane/invoke-vm-reset-live.ps1` 与 `providers/windows-vm-reset.ps1`
  冻结 VM-only dispatcher/provider 和 device-trust boundary；只有 disposable VM、精确
  trust/evidence、DevelopmentRetest 及单独 real-change acknowledgement 才可进入真实
  dispatch，且必须在 runtime 注册前独占复验并原子消费由外部 supervisor 签发、
  SYSTEM-owned、共同绑定本轮全部事实的 one-shot anchor/grant pair；每次 Live 都必须
  使用全新 pair。宿主机/CI/里程碑场景均 fail closed。
- `operator/fast-lane/*` 还保存固定的 host/VM prompt 与纯 synthetic 双 outbox 演练；
  prompt 不携带凭据，relay 自由文本只作为数据，不能成为 shell、PowerShell 或 Codex
  操作指令。
- 宿主机完成修复、本地门、提交/推送和候选重建；VM 没有产品仓库写权限，只能向
  VM-to-host repository 写结构化结果。宿主机不得执行 product Live，VM 不得编辑、
  提交或推送产品代码。
- P10A 消费精确 commit/calibration artifact；P11 消费精确 candidate bytes/hash，
  不跟随移动分支头。
- Fast Lane 由 VM 按精确 allow-list 做 deterministic reset：只卸载本项目产物、
  清除项目拥有的 HKCU policy/credential/checkpoint/owner-marked 目录并核验 baseline；
  不以 WORM、message signing 或每轮快照为前置，结果只用于诊断。
- Formal Lane 才为 P10A/P11 使用外部 clean snapshot 与独立 CAS/receipts/signatures。
  VMP/重启/卸载、未知补偿、baseline drift 或 reset 失败升级到 Formal Lane；VM
  不能恢复自身快照。
- relay 只传输状态、脱敏结果和证据引用，不替代 WORM/CAS、签名、snapshot receipt
  或 acceptance receipt；消息正文和日志永不作为 shell/PowerShell 指令执行。
- product/control repositories 均已切换为 public；三个 active ruleset 已对 control
  `main`、产品 `main` 与 `codex/repair/*` 实际施加禁止删除、禁止非快进和线性历史，
  且没有 bypass actor。tracked 文档不嵌入会自引用的最终 commit/tree/hash；当前 clean
  HEAD 只有在同一暂停 automation、PR CI、实际 Git/remote 与 immutable bundle 的外部
  机器事实全部匹配时，才派生 `CanStartVmBootstrap=true`，且只授权 bootstrap-only。
  最小角色凭据、运行时 protection assertion、VM 产品 remote 只读负向验证、real guest
  reset、两端任务和 unattended 执行仍是 integration 阻断项。VM bootstrap 不等于
  P10A-0A 完成。

## 当前加载顺序

现有 bootstrap 顺序保持：

~~~text
bootstrap
  -> logger
  -> common
  -> state
  -> execution-context
  -> fake-providers
  -> state-store
  -> domain modules
  -> acceptance
~~~

bootstrap 顶层仍只定义函数和常量，不得探测系统、访问网络、写文件、提权或控制
进程。HostSandbox runner 属于独立 trusted-harness 执行平面，不进入产品
bootstrap 加载顺序。`config/fast-lane-policy.psd1`、`lib/vm-test-relay.ps1`、
`lib/vm-reset.ps1`、`operator/fast-lane/*` 与 `operator/realtime-relay/*` 只由
OperatorCoordination 的精确入口或测试显式加载，也不进入 ProductCore 或 Release；
独立 sibling infra 更不进入此加载图。

## 统一结果

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

TestSafe/DryRun 的潜在修改操作必须 `Changed=false`。结果、异常、ledger、状态和
报告不得包含凭据、原始配置、真实用户名或非必要绝对路径。

`Status` 是运行状态，只能取
`SUCCEEDED/PARTIAL/RESTART_REQUIRED/ACTION_REQUIRED/CANCELLED/FAILED`；
`Success=true` 只对应 `SUCCEEDED`。`Data` 分别携带每项能力的
`READY/BLOCKED/PENDING_RESTART/UNSUPPORTED/UNKNOWN` 和 UI 的
`PASS/FAIL/NOT_TESTED`，不得把三个层级压成一个布尔值。

非 `-PassThru` 的公开 CLI 入口必须输出固定四行 `Status`、`ErrorCode`、
`Changed`、`NextStep`，并使用稳定退出码：
`SUCCEEDED=0`、`FAILED=1`、`PARTIAL=2`、`RESTART_REQUIRED=3`、
`ACTION_REQUIRED=4`、`CANCELLED=5`。中英文 `.cmd` 只转发该退出码，不重新解释
结构化状态。

## 固定完整功能流程

~~~text
preflight -> fixed target: Chat + Code + Cowork
  -> Git qualified? reuse : verified official install/upgrade
  -> Cowork-compatible MSIX scope
  -> admin / hardware virtualization / VMP readiness
       -> if needed: independent confirmation + checkpoint + manual restart + resume
  -> deploy -> all three surface flags enabled
  -> separate readiness and acceptance results
~~~

用户不选择 surface。Git 每次都检测并确保合格，但已有合格版本不会重复安装。
VMP 是固定 Cowork 目标的前置，只有 readiness 表明需要修改且用户独立确认后才进入。
任何前置失败都不能通过关闭 Code/Cowork 把总结果提升为 PASS。

## 配置架构

首版唯一 writer 是当前用户 HKCU managed policy。HKLM policy 和 configLibrary
只检测：HKLM 存在时阻断，因为它会覆盖 HKCU；local source 存在时报告冲突。
configLibrary 不支持首版所需的 MDM-only helper/chooser，不能作为安全回退。

编排器先做 source inventory 和 ownership 决策，再写入完整无凭据 HKCU payload。
内部 desired state 与 registry serializer 分离。

P2 已冻结纯合同：Desktop 最低版本 `1.20186.0`、Windows policy 不合并门槛
`1.19367.0`、15 个直接 `REG_SZ` value、V4 Pro/Flash 固定列表和八组 synthetic
source resolution。此阶段没有 registry provider 调用；写入、备份与恢复仍关闭。
DeepSeek 服务端 alias mapping 与 Desktop family-tier serializer 分开建模，未确认的
重复 model ID 语义不进入 payload。

Key 由 DPAPI-backed credential helper 提供，不进入 policy/configLibrary。
完整设计见 `CONFIGURATION_DESIGN.md`。

## 供应链

获取、验证和执行是分层合同。未来真实 adapter 必须在同一受控安装操作内重新
hash、重验并安装，避免“验证后换包”的调用间 TOCTOU；编排器只消费结构化证据：

- official source policy；
- artifact type 与架构；
- 绝对路径绑定 token；
- SHA-256；
- Authenticode 和可信链；
- Publisher/package identity；
- 适用版本。

安装前对同一文件重新计算 hash 并重验身份。没有 bypass 参数。

## Stage 与授权生命周期

~~~text
Scaffold
  -> Development
     -> VmDevelopment in disposable VM (mutable, VM is sole writer)
        -> development ZIP + real user paths -> READY_FOR_FORMAL_P10A
           -> freeze exact source/calibration input
              -> P10A calibration + trusted facts
                 -> P10B build/sign VmAcceptance + unpublished UserLive candidates
                    -> end writer lease
                       -> P11 read-only exact-candidate acceptance -> RELEASE_READY
                          -> P12 publish the exact tested UserLive bytes
~~~

- stage/profile 不由环境变量或 `-Mode Live` 单独决定。
- `VmDevelopment` 必须由 package-bound manifest、disposable-VM preflight、独立交互
  确认和 operation-specific grant 共同授权；它不授权宿主机/CI Live。
- `VmDevelopment` 可以改代码和重建 development ZIP；P10A 先消费冻结的源/
  calibration 输入并冻结事实，P10B 才能生成最终候选。从 P10B 候选冻结开始，P11
  不允许修改源码、测试或 ZIP。失败后回到开发 stage，而不是热补丁被测字节。
- embedded manifest v2 绑定版本、commit、profile、排除自身的 content digest，
  以及来自 sidecar 外部的 signer 证书/public-key 指纹、request ID、nonce 和最大
  签名年龄。
- detached sidecar v2 绑定最终 ZIP SHA-256、profile 和 content digest，并携带实际
  X509 DER 与 RSA-PSS-SHA256 签名字节；验证器对 canonical claims bytes 做真实
  公钥验签，不信任自报 `VALID` 字段。
- VmAcceptance grant 绑定 sidecar hash、runId、operation allow-list、expiry、nonce
  和交互确认。
- 同用户进程无法可靠证明自己处于 VM；grant 只防误触，真正隔离依赖 VM 操作流程。
- P12 不重建 ZIP，只发布 P11 已测试的 UserLive 原字节。
- P11 exact acceptance receipt 与 promotion CAS 未实现前，P12 promotion 构造始终
  fail closed。
- P11 失败后返回 VM 的 `VmDevelopment` 单写者循环，修复、过门、提交/推送，再从
  新 commit 的 P10A 输入/事实冻结开始，重做 P10B 和 P11；relay PASS 不自动 merge，
  也不自动进入 P12。

## 状态与重启

未来状态根位于项目专属 LocalAppData，但本地测试使用 synthetic path。状态包含：

- schema/contract version；
- runId、phase、completed steps；
- pending action；
- restart reason、resume phase、expiry；
- artifact/config backup metadata；
- safe error。

状态不保存 Key、Authorization、原始配置、可逆密钥或 helper stdout。写入采用
owner-checked sibling temp、flush、重读和原子替换。

VMP 首版使用 `-NoRestart` 和人工重启后重新双击续跑，不创建计划任务或 RunOnce。

## 配置备份

- 首版一个运行只拥有 HKCU policy。
- 非本项目配置默认冲突停止。
- 可恢复备份与脱敏快照是两个合同。
- 可恢复敏感材料使用 DPAPI/ACL；脱敏快照不能恢复。
- HKCU registry 采用精确 value/type 补偿；首版没有 configLibrary writer。
- 失败后必须重读证明恢复，而不是只报告“已回滚”。

## Claude Code settings

项目正式选择绝对零接触政策：任何 stage/mode/provider 都不定位、不 Test-Path、
不枚举、不读取、不哈希、不监视、不备份、不写入或删除
`%USERPROFILE%\.claude\settings.json`。disposable VM、真实用户验收和 known-folder
探测都没有例外；只能对不指向该真实文件的 synthetic 项目资源建立测试基线。

## 架构不变量

- 默认 bootstrap 无副作用。
- 领域模块不直接访问真实系统。
- 缺 Context/provider fail closed。
- 本机/CI 默认 bootstrap 不加载 live adapter；contract tests 只解析其 AST，运行时
  loaded-context/dispatcher 覆盖也只能走零-I/O 绑定/失败路径。
- trusted test harness 与产品 provider 使用独立 allow-list/ledger。
- 验签先于安装。
- 凭据先保护后持久化配置。
- 备份先于配置写入。
- checkpoint 先于 VMP 变更。
- 子能力分别验收。
- VM Live 先于正式发布。
- 正式发布字节必须与 VM 测试字节相同。
- D-026 每一时刻只有一个 writer：handoff 前是宿主机，handoff 后是
  `VmDevelopment` VM；最终候选验收阶段没有代码 writer。
- OperatorCoordination 本地合同不得隐式获得 Git transport、真实系统 adapter、
  product Live 或无人值守执行权限；prompt 和自由文本不得携带凭据或被直接执行。
- clean-start tier 必须与风险匹配；正式 P11 PASS 必须由外部 hypervisor 的 clean
  snapshot receipt 证明，日常 guest reset 不可替代。
- relay/control-plane 状态不得替代 CAS、签名或 acceptance receipt。
