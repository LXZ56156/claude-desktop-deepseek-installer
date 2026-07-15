# 宿主机与 VM Codex 测试中继协议

更新日期：2026-07-15

## 定位与权威范围

本文是开发期“双机测试、宿主修复、重新制品化、VM 重测”协调协议的唯一权威
文档。它定义角色、信任边界、消息状态机、证据引用、干净环境恢复和失败闭环，
供 P10A 校准与 P11 全面验收共同使用。

本文不授予任何 Live 权限，不改变 `TEST_ISOLATION.md`，也不把中继组件加入产品、
Release ZIP、默认 bootstrap 或 trusted test harness。relay 是独立的 operator
coordination plane；产品平面、测试执行平面、证据平面和协调平面必须分离记账。

截至 2026-07-15，本仓库已经实现 Fast Lane 的本地合同和纯 synthetic 演练：
`lib/vm-test-relay.ps1` 提供 canonical JSON、hash、envelope/state/transition 的纯函数
合同；`lib/vm-reset.ps1` 提供 fake/TestSafe/DryRun 的 ownership、baseline、plan、
receipt 与 fail-closed reset 合同；`operator/fast-lane/prompts/` 提供两端轮询模板，
`operator/fast-lane/invoke-synthetic-rehearsal.ps1` 提供本地双 outbox 演练。它们都属于
DevelopmentOnly 的 operator coordination material，不由默认 bootstrap 加载，也不进入
Release ZIP。

私有产品 remote 与两个 control repository 已创建，产品旧 `main` 基线已推送，两个
`outbox/` 已初始化。GitHub 当前套餐拒绝 private ruleset；最小角色 credentials、VM
只读身份及负向写验证、真实 guest reset adapter、VM Codex automation 和无人值守闭环
仍未完成。宿主机 heartbeat 已创建但保持暂停。Formal Lane 的 CAS、签名和外部
snapshot supervisor 也未实现。因此当前不能宣称 P10A-0A 完成，更不能开始真实 P10A/P11。

## 不可变原则

- 宿主机 Codex 是唯一代码写入者。源码、测试、文档、runbook、Release manifest
  和构建逻辑只允许在宿主机受控工作树中修改。
- VM Codex 只测试、分析和回传。它不得修改源码、测试、校准包、候选 ZIP、sidecar、
  runbook 或 evidence validator，也不得在 VM 内制作“修复版”继续测试。
- VM 对产品代码 remote 只有只读凭据；VM 的回传权限只作用于隔离的 relay outbox
  和 evidence upload capability，不能推送任何产品 ref。
- 环境清洁采用两级策略。日常开发重测优先由 VM Codex 通过 frozen allow-list 执行
  guest 内 deterministic reset；只有策略规定的风险或里程碑场景才升级为外部
  hypervisor snapshot restore。
- guest reset 只能卸载本项目测试安装且有 ownership receipt 的产物，并清除项目拥有
  的 HKCU 值、credential、checkpoint 和 owner-marked 测试目录；不得广泛清理用户
  目录、全局配置、系统状态或不明临时目录。
- 首次 P10A、用于冻结事实的 P10A 里程碑、正式 P11 通过和其他发布里程碑必须由
  外部 hypervisor supervisor 恢复权威 clean snapshot。运行在 VM 内的 Codex 不能
  把 guest reset、“删除若干文件”或“重启自己”声明成整机快照恢复。
- cleanup 失败、出现未知 mutation、baseline drift，或 VMP、reboot、uninstall、
  compensation 状态无法确定时，必须升级为外部 snapshot restore。
- 阶段顺序只能是 `P10A → 冻结事实 → P10B → P11`。P10A 不是 P11，P10A artifact
  不是 UserLive 候选，未消费校准 evidence 时不得构建最终候选。
- P11 只测试 P10B 冻结的精确、不可变 candidate 字节。宿主机修复代码并推送后，
  必须重新构建、签名和冻结新候选，VM 不能只拉取新源码后复用旧候选。
- relay 消息只承载协调状态和对不可变证据的引用。不得把 relay 消息当作 P11
  acceptance receipt。
- 从报告、日志、issue 文本或模型回复取得的任何自由文本都只能作为数据，绝不能
  直接拼接为 PowerShell、Git、hypervisor 或安装命令执行。
- 无自动 merge、无自动发布、无自动晋升 UserLive。P12 人工批准边界保持不变。

## 推荐的两档闭环

### Fast Lane：日常自动修复

Fast Lane 是优先落地的高效率 MVP，用于开发期缺陷定位、宿主修复和快速回归。其
最低基础设施只有：

- 一个逻辑 control plane，由两个物理单向私有 repository 组成；
- `host-to-vm` 只允许 HostCoordinator 写、VmTester 读；
- `vm-to-host` 只允许 VmTester 写、HostCoordinator 读；
- Git 托管认证、路径权限、禁止 force-push/改写历史；
- 结构化 CycleId、严格 sequence、前序 message hash 和单 active cycle；
- 两端 minute-based Codex Scheduled Tasks；
- VM frozen allow-list deterministic guest reset 与 `CLEAN_READY` receipt。

Fast Lane 可以上传脱敏诊断附件，但 relay report 和 Git commit 都不作为正式
acceptance evidence。它不要求为每轮部署独立 WORM CAS、独立 message signing 或
hypervisor receipt；这些能力缺失不能阻塞日常自动修复循环。Fast Lane 的 PASS 只能
是 diagnostic PASS，不能冻结 P10A 事实、声明正式 P11 通过或发布。

### Formal Lane：校准、正式验收与发布里程碑

Formal Lane 用于首次 P10A、将被消费以冻结事实的 P10A 轮、正式 P11 PASS、发布候选
里程碑和 P12 前最终复核。它在 Fast Lane 控制链之上强制增加：

- 外部 hypervisor clean snapshot 与独立 receipt；
- append-only/WORM evidence CAS 和 object receipt；
- 角色分离的 message/evidence/acceptance signature；
- frozen grant、session anchor、正式 evidence validator 和 acceptance receipt；
- 更严格的 expiry、重放、时钟、retention 和人工停止门。

日常可先在 Fast Lane 收敛缺陷，再为同一精确 commit/candidate 创建新的 Formal Lane
CycleId，从 clean snapshot 重跑。Fast Lane evidence 只能辅助诊断，不能被“晋升”或
包装成 Formal Lane receipt。

## 四个角色

### HostCoordinator

宿主机 Codex 与宿主机上的确定性 runner 共同承担：

- 校验进入请求、回传 envelope、control identity、hash、序号和 expiry；Formal Lane
  还必须校验签名；
- 生成 P10A 精确 commit/校准包请求，或 P11 精确 candidate 请求；
- 读取脱敏 `TEST_RESULT`，在宿主机修改代码并运行完整本地质量门；
- 将修复提交推送到专用 repair branch；
- 对 P11 修复重新执行 P10B 构建、签名和冻结，再发出 `FIX_READY`；
- 保持每次修复、候选、测试结果和证据 receipt 的可追溯绑定。

HostCoordinator 不得因收到消息而绕过本地门禁、直接合并默认分支或发布制品。

### VmTester

VM Codex 与 VM 内固定 runner 共同承担：

- 只读取得精确请求、源码 commit 或不可变 candidate；
- 按请求的清洁等级执行 frozen deterministic reset，或核验 VM image、snapshot
  receipt；随后核验 operation grant、artifact、sidecar 和 runbook；
- 依冻结 runbook 执行 P10A 或 P11，不扩大操作范围；
- 收集、脱敏、验证并上传 evidence；
- 发出结构化状态和 `TEST_RESULT`；
- 测试完成后清理本轮 owner-marked 资源，并记录清理结果。

VmTester 不参与修复、commit、push、candidate 构建、sidecar 生成或 release 决策。

### RelaySupervisor

RelaySupervisor 是非产品、非模型驱动的确定性协调器。它只执行固定 schema
validation、hash 校验、compare-and-swap、过期拒绝、去重、状态推进和通知；Formal
Lane 还执行签名验证。它不得解释报告来生成命令，也不得为产品操作签发 Live grant。

### Human/HypervisorSupervisor

用户或独立 hypervisor 自动化负责：

- 创建并冻结指定 VM image 和 snapshot；
- 在首次 P10A、事实冻结、正式 P11 通过、其他里程碑和所有升级条件下，从 VM 外部
  恢复快照；
- 为恢复动作生成可验真的 snapshot receipt；
- 管理 VM 启停、网络隔离和紧急停止；
- 在 P12 决定是否合并、发布或停止。

该角色不能由正在被恢复的 VM 内进程替代。

## 四个平面与凭据隔离

~~~text
Product code plane
  Host: repair branch write
  VM: exact commit/candidate read only

Operator coordination plane
  Host: host-to-vm write, vm-to-host read
  VM: vm-to-host write, host-to-vm read
  RelaySupervisor: schema/CAS/state validation only

Evidence plane
  Fast Lane: diagnostic attachments, not acceptance truth
  Formal Lane: append-only/WORM CAS + signed receipts

Hypervisor plane
  Policy-required snapshot restore + signed snapshot receipt
  No product or evidence signing key
~~~

不得复用一个全能 token。至少分开：

- 宿主机代码 remote repair-branch write credential；
- VM 代码 remote read-only credential；
- 宿主机只持有 `host-to-vm` 写凭据和 `vm-to-host` 读凭据；VM 只持有
  `vm-to-host` 写凭据和 `host-to-vm` 读凭据；
- evidence store 的一次性、路径受限 upload capability；
- Formal Lane 每个角色独立的消息/证据签名密钥；
- Formal Lane 外部 snapshot receipt 签名密钥；Fast Lane 使用独立的 guest reset
  receipt 身份。

所有凭据只在对应机器的安全凭据存储中提供，不进入仓库、relay payload、Codex
对话、命令行参数、报告或 evidence archive。VM 只读产品凭据不得具备创建 branch、
tag、release、issue、PR 或 workflow dispatch 的权限。

## 传输拓扑

### 产品代码 remote

产品代码使用私有 Git remote `LXZ56156/claude-desktop-deepseek-installer`，本轮 repair
ref 是 `codex/repair/p10a-0a-fast-lane`。宿主机最终只能向受保护的 repair branch 推送，
VM 使用独立只读 deploy key 或等效细粒度凭据。当前 GitHub 套餐拒绝 private ruleset，
所以这项服务端强制与角色凭据仍未满足；交互式 bootstrap admin 不得交给 automation。

P10A 需要源码时，VM runner 只允许类似以下的确定性操作：

~~~text
git fetch <read-only-remote> <exact-repair-ref>
git checkout --detach <RepositoryCommitSha>
git rev-parse HEAD
~~~

runner 必须验证 `HEAD` 等于请求中的完整 commit SHA，禁止跟随浮动 branch head，
禁止 merge、rebase、commit、push、submodule URL 重写和 hook 执行。工作树必须是本轮
新建的 owner-marked clone；验证 tracked 文件后发现本地变化即停止。

P11 默认不以源码 checkout 作为被测输入。VM 取得的是 P10B 冻结 candidate、detached
signed sidecar 和 runbook，并逐项匹配请求中的 SHA-256、profile、candidate ID、
source commit 和签名策略。

### control repository 与双 outbox

Fast Lane 冻结为“一个逻辑双 outbox、两个物理单向私有 repository”：
`LXZ56156/cddsi-host-to-vm` 与 `LXZ56156/cddsi-vm-to-host` 已创建并初始化。两个 repository
都与产品代码 remote 分离；该拆分是实际权限边界，不是部署细节。两端 Codex automation
最终通过出站轮询消费各自 inbox，正常路径无需用户逐轮搬运文件：

- `host-to-vm` repository 只允许 HostCoordinator 追加，VmTester 只读；
- `vm-to-host` repository 只允许 VmTester 追加，HostCoordinator 只读；
- 已发布消息不可改写、删除、force-push 或复用 `MessageId`；
- 每个方向的提交绑定 repository identity；RelaySupervisor 以原子 CAS 维护唯一 active
  cycle 和下一合法 sequence；
- 消费者只出站轮询，不开放从外部直接进入宿主机或 VM 的控制端口。

低延迟需要可由只读、确定性 watcher 监视 control ref 的变化，在完整验证新消息后
触发受限的 `codex exec resume`。watcher 不能解释 payload、执行其中命令或持有产品
write credential。不得把两个方向合并为使用共享可写 token 的单一 repository；未来
只有在两个独立认证主体或窄 relay API 能精确强制方向写边界时，才可重新评审物理拓扑。

relay outbox 不是大日志仓库。消息只携带小型 canonical JSON 和内容摘要。Fast Lane
的脱敏诊断附件可以进入受限附件存储，但不产生正式 evidence；Formal Lane 完整
evidence 必须进入独立 append-only/WORM content-addressed store。

### Formal Lane evidence CAS

Formal Lane evidence store 必须满足：

- 对象地址由完整 SHA-256 决定；上传后不可覆盖或删除；
- 每个对象产生独立 receipt，绑定 uploader、CycleId、对象 hash、长度和时间；
- 宿主机消费前重新下载、重新计算 hash，并验证 receipt 和 evidence validator；
- 日志、截图、结构化结果与正式 acceptance receipt 分开对象化；
- retention、读取授权和删除审批不由 Codex 自行改变。

relay 只传 `EvidenceUri`、`EvidenceSha256` 和 receipt 引用。URI 必须是受限对象标识，
不能是任意协议或会在验证阶段触发 credential 转发的 URL。

## 单一 active cycle 状态机

同一 repository、profile、candidate 和 VM matrix cell 在任一时刻只能有一个 active
cycle。基本状态机为：

~~~text
IDLE
  -> TEST_REQUESTED
     -> VM_ACKED
        -> ENVIRONMENT_PREPARING
           -> CLEAN_READY
              -> TEST_RUNNING
                 -> TEST_PASSED | TEST_FAILED | TEST_BLOCKED
                    -> HOST_ACKED
~~~

失败后的修复闭环为：

~~~text
TEST_FAILED | TEST_BLOCKED
  -> HOST_ACKED
     -> HOST_FIXING
        -> FIX_PUSHED
           -> CANDIDATE_REBUILT       # P11 必需；P10A 为校准包重建
              -> RETEST_REQUESTED
                 -> VM_ACKED -> ENVIRONMENT_PREPARING -> CLEAN_READY -> TEST_RUNNING
~~~

消息类型与主要状态对应：

| MessageType | 发送者 | 作用 |
|---|---|---|
| `TEST_REQUEST` | HostCoordinator | 冻结本轮精确输入、范围、runbook 和 expiry |
| `VM_ACK` | VmTester | 声明确认请求，但尚未测试 |
| `SNAPSHOT_READY` | HypervisorSupervisor | 仅在策略要求外部恢复时提供 snapshot receipt |
| `CLEAN_READY` | VmTester | 提供 guest reset receipt，或核验并绑定 snapshot receipt |
| `TEST_STARTED` | VmTester | 声明全部前置核验通过并开始固定 runbook |
| `TEST_RESULT` | VmTester | 回传 PASS/FAIL/BLOCKED 与 evidence 引用 |
| `HOST_ACK` | HostCoordinator | 声明结果已验真、已接收或已拒绝 |
| `FIX_READY` | HostCoordinator | 冻结新 commit 和新校准包/新 P10B candidate |
| `STOP` | Human/HypervisorSupervisor | 停止当前 cycle，不授权隐式恢复或继续 |

非法跳转、重复终态、分叉 sequence、过期消息、未知 sender、前序 hash 不匹配或同一
输入的并行 active cycle 都必须 fail closed。`STOP` 后必须创建新 CycleId，不能在旧
cycle 上续写为通过。

## canonical message envelope

所有消息使用 UTF-8、无 BOM 的 canonical JSON；字段排序、数字格式和 null 规则在
实现前冻结为 versioned schema。Formal Lane 另外冻结签名算法。最小 envelope 为：

~~~json
{
  "SchemaVersion": "1",
  "ProtocolVersion": "cddsi-vm-test-relay-v1",
  "Lane": "Formal",
  "MessageId": "<uuid>",
  "CycleId": "<uuid>",
  "Sequence": 1,
  "MessageType": "TEST_REQUEST",
  "SenderRole": "HostCoordinator",
  "CreatedAtUtc": "<RFC3339 UTC>",
  "ExpiresAtUtc": "<RFC3339 UTC>",
  "PreviousMessageSha256": null,
  "RepositoryCommitSha": "<40-or-64-hex-by-policy>",
  "ArtifactProfile": "VmCalibration",
  "CandidateId": "<stable-id-or-null>",
  "ArtifactSha256": "<64-hex>",
  "SidecarSha256": "<64-hex>",
  "RunbookSha256": "<64-hex>",
  "VmImageSha256": "<64-hex>",
  "EnvironmentResetMode": "SnapshotRestore",
  "CleanReceiptSha256": null,
  "SnapshotReceiptSha256": null,
  "PayloadSha256": "<64-hex>",
  "EvidenceUri": null,
  "EvidenceSha256": null,
  "Status": "TEST_REQUESTED",
  "Signature": "<required-in-Formal-null-in-Fast>"
}
~~~

实现时还必须精确绑定：repository identity、repair ref、OS matrix cell、runId、
environment reset policy/allow-list digest、operation grant/session anchor、nonce、
expected previous state、message body length，以及 Formal Lane 的 signing key ID 和
签名算法。未使用字段必须按 message schema 为显式 `null`，不得省略后产生歧义。

`PayloadSha256` 覆盖 envelope 外的类型化 payload。Fast Lane 由受认证的 Git commit、
禁止历史改写和 message hash chain 提供协调完整性，`Signature` 固定为 `null`。
Formal Lane 的 `Signature` 覆盖 canonical envelope（将 Signature 置为协议定义的
空值）和 payload hash。每条消息的 `PreviousMessageSha256` 覆盖上一条完整 canonical
message，形成不可分叉链。

### 防重放与 CAS 规则

- `MessageId` 全局唯一，重复提交同一 ID 即使正文相同也只允许幂等读取，不得二次
  推进状态。
- `CycleId + Sequence` 唯一且严格递增；RelaySupervisor 只接受等于当前序号加一的
  消息。
- 每次写入携带 expected previous message hash，使用原子 compare-and-swap；失败后
  重新读取，不得强行覆盖。
- `CreatedAtUtc`、`ExpiresAtUtc`、最大时钟偏差和最大消息年龄均被验证；过期授权不能
  通过重发新 envelope 延长。
- authenticated Git identity/path、message type 和允许状态迁移使用精确 allow-list；
  Formal Lane 还验证 signer role。
- commit、artifact、candidate、runbook、VM image、clean/snapshot receipt 和 evidence
  的 hash 全部进入 message hash；Formal Lane 还进入签名绑定。任何漂移都创建新
  cycle。

## P10A 请求与结果

P10A `TEST_REQUEST` 必须绑定：

- 完整 `RepositoryCommitSha` 和只读 repair ref；
- 精确 `VmCalibration` artifact、sidecar、content digest 和 runbook；
- stage-policy v2 grant、预持有 session anchor、固定八项 operation-use；
- 固定 VM image/snapshot、environment reset policy、测试用户和唯一允许的校准范围；
- 本轮完成、清理、evidence 终态与最大年龄要求。

首次 P10A 必须从外部恢复的 clean snapshot 对精确 commit 和精确校准包执行。日常
诊断重跑在 guest reset 完整通过且未命中升级条件时可以使用 `GuestReset`，但任何
将被宿主消费并用于冻结 P10B 事实的 P10A 结果都属于里程碑，必须由
`SnapshotRestore` 支撑。P10A `TEST_RESULT=PASS` 只表示校准 evidence 已产生并可进入
宿主消费；它不能声明 P11 或发布通过。

宿主机必须独立验证、CAS 消费 evidence 并冻结事实。只有消费和事实冻结 receipt
完成，才允许 P10B 构建。若 P10A 暴露代码缺陷，宿主机修复并推送后必须生成新
commit、新校准包、新 grant 和新 CycleId。诊断轮按清洁策略准备环境；用于事实冻结
的最终轮仍必须由外部 supervisor 恢复 clean snapshot。

## P11 请求与结果

P11 `TEST_REQUEST` 必须绑定：

- P10B 冻结的 `VmAcceptance` candidate ID 和完整 ZIP SHA-256；
- 对应 source commit、content digest、detached signed sidecar 和签名策略；
- 已填充、无占位符的 frozen runbook 及其 SHA-256；
- 固定 VM image、snapshot、environment reset policy、OS matrix cell、operation grant
  和补偿矩阵；
- 本轮允许的真实资源、停止线、有效期和证据清单。

VM 只执行 candidate 字节，不以 branch head 替代。若 `TEST_RESULT` 暴露产品缺陷：

1. HostCoordinator 验证并 ACK 失败证据；
2. 宿主机修改代码、运行完整本地质量门并推送 repair commit；
3. 重新执行 P10B，生成具有新 ID、hash、sidecar 和 runbook 绑定的新 candidate；
4. 通过 `FIX_READY` 引用新 candidate；
5. 创建新 CycleId，按本协议清洁策略准备环境并测试新 candidate；
6. 若该结果要成为正式 P11 PASS，再从外部 clean snapshot 执行一次正式里程碑轮。

仅有 `FIX_PUSHED` 不足以触发 P11 重测。旧 candidate 的结果永远只属于旧字节，不能
因新源码存在而改写。

日常 P11 缺陷定位和修复回归可以在确定性 guest reset 后运行，以缩短循环；其 PASS
只能标为 diagnostic。正式 P11 通过证据必须绑定外部 clean snapshot receipt。涉及
VMP、reboot、uninstall，或 compensation 状态不确定的场景不能使用 guest reset
降级。

## 分层清洁与 CLEAN_READY

`TEST_REQUEST` 必须精确指定 `EnvironmentResetMode=GuestReset|SnapshotRestore`，以及
对应 reset policy 和 allow-list digest。VmTester 只能按请求执行更强或相同等级；若
guest reset 期间命中升级条件，可以停止并要求 snapshot restore，不能自行降低等级。

### Level 1：日常 deterministic guest reset

日常缺陷定位、修复回归和非里程碑重测优先使用 guest reset。VM Codex 调用固定
runner，按 frozen allow-list 依序：

1. 验证上一轮终态、resource ownership ledger 和 cleanup receipts 均完整；
2. 只卸载本项目测试安装且由精确 identity/instance receipt 证明拥有的产物；
3. 只清除 allow-list 中项目拥有的精确 HKCU key/value，不枚举或改写相邻配置；
4. 只删除本项目固定 target name、由本轮/前序 receipt 证明拥有的 credential；
5. 只删除项目拥有的 checkpoint、state 和补偿记录；
6. 只删除 marker、runId、预持有路径三者完全匹配的 owner-marked
   `cddsi-vm-test-<GUID>`；
7. 核验 OS、AppX、Git、VMP、registry、credential、checkpoint 和文件系统的冻结
   baseline；
8. 生成经 control identity 认证的 `CLEAN_READY` receipt 后才允许测试；Formal Lane
   还必须对 receipt 签名。

receipt 至少绑定 CycleId、VM identity、image SHA-256、reset policy/allow-list hash、
前后 baseline digest、每项动作和资源 receipt、开始/结束时间、cleanup failure count、
unknown mutation count、secret scan count 和认证身份；Formal Lane 另含签名。所有
count 必须为零且 baseline 精确匹配，状态才可为 CLEAN_READY。

不得用 `git clean`、用户 profile 清空、全局 Git/PowerShell 配置重写、计划任务枚举
删除或广泛临时目录清理来伪造“干净”。也不得因“这是 disposable VM”而删除未在
ownership ledger 中的资源。

### Level 2：外部 clean snapshot restore

以下任一条件强制升级到外部恢复：

- 首次 P10A；
- 用于冻结事实的 P10A 里程碑轮；
- 正式 P11 PASS、发布候选里程碑或 P12 前最终复核；
- guest cleanup 失败、receipt 缺失或 validator 不可用；
- 发现 unknown mutation、unexpected ledger entry 或 baseline drift；
- VMP、reboot、uninstall 或 compensation 的最终状态无法确定；
- frozen runbook 或 Human/HypervisorSupervisor 显式要求更强清洁等级。

Human/HypervisorSupervisor 必须从 VM 外部停止或回滚目标 VM、恢复请求绑定的
immutable snapshot、启动指定 VM 与独立测试用户，并生成签名 snapshot receipt。
receipt 至少绑定 hypervisor identity、VM identity、image SHA-256、snapshot ID、
snapshot generation、restore operation ID、CycleId、完成时间和启动 nonce。

HypervisorSupervisor 通过 `SNAPSHOT_READY` 提交 receipt；VmTester 核验其与
`TEST_REQUEST` 一致，再生成引用该 receipt 的 `CLEAN_READY`。无法验证时返回
BLOCKED。snapshot restore 后仍可清理本轮新建的 owner-marked 目录，但不得把该
guest 清理当成 snapshot receipt 的替代。

## TEST_RESULT 与 evidence bundle

`TEST_RESULT` payload 只包含结构化、小型、已脱敏的结果摘要和附件/evidence 引用。
Fast Lane 引用的是诊断附件，Formal Lane 引用的是不可变 evidence。最小字段包括：

- CycleId、Sequence、runId、phase、matrix cell；
- source commit、artifact/candidate ID、所有输入 hash；
- VM image、reset mode、clean receipt hash，以及适用时的 snapshot receipt hash；
- overall status：`PASS`、`FAIL` 或 `BLOCKED`；
- 每个 runbook step 的稳定 ID、结果码、开始/结束时间和 receipt hash；
- failure class、稳定 error code、最小脱敏 excerpt；
- rollback/compensation/cleanup 结果；
- secret scan count、forbidden mutation count、unexpected ledger count；
- bundle URI、SHA-256 和长度；Formal Lane 还必须有 append-only receipt；
- Formal Lane acceptance receipt 的 URI/hash，或未产生原因；Fast Lane 固定为 `null`。

evidence bundle 至少分开保存 canonical `report.json`、供人阅读的 `summary.md`、必要的
脱敏日志/截图、provider/operation receipts 和 validator 输出。自由文本不能改变稳定
状态码，截图不能替代结构化 evidence。

以下内容禁止进入消息或 evidence：

- DeepSeek/API key、Authorization、cookie、session token、deploy key 和签名私钥；
- 可逆 credential blob、credential helper 原始输出和 DPAPI material；
- 原始 managed policy/config 正文、用户 settings 正文和不必要的 registry dump；
- 宿主机或 VM 用户名、真实用户路径、共享目录、剪贴板内容；
- 未截断且未脱敏的通用进程、环境变量、网络或系统日志。

脱敏后仍无法安全分享的对象只记录稳定错误码、独立 validator 结果与 object hash，
不得用“测试需要”作为泄露密钥的理由。

### acceptance 与 relay 的关系

`TEST_RESULT=PASS` 是协调状态，不是产品验收事实。P11 的正式判断仍必须消费 frozen
runbook 要求的逐操作 receipt、签名 evidence、候选字节绑定、补偿结果和 secret
scan，并由独立 validator 输出 acceptance receipt。

因此，不得把 relay 消息当作 P11 acceptance receipt。relay repository 的 commit、
issue、comment、workflow success 或消息签名也都不能替代 evidence CAS 中的正式
receipt。

## 自动化实现状态

正常通信路径是两个单向私有 control repository 组成的逻辑双 outbox 与两端自动监控，
不需要用户逐轮复制请求、结果或 `FIX_READY`。两端只对已验证的新 message commit 作出
反应。当前 canonical/schema/state validator、reset 合同、两端 prompt 模板、纯
synthetic dry rehearsal 与真实 private repository pair 已实现；protected history、
最小凭据、VM runner adapter、VM task、安全启用 host heartbeat 和无人值守验收仍是
外部部署工作，不能直接在现有宿主机进入产品 Live。

### Codex automation

这里的分钟级 Codex automation 是产品之外的 operator coordination 机制，不是安装器
创建、枚举或管理的 Windows Scheduled Task，也不得进入产品 provider 或 Release。它
不会授予 operation grant，不会扩大宿主机权限；宿主机 automation 永远不得执行产品
Live。`operator/fast-lane/prompts/host-poll.md` 和 `vm-poll.md` 是固定模板；宿主机
heartbeat `cddsi-fast-lane-hostcoordinator-minute-poll` 已按分钟创建，但在 protected
history 与窄凭据就绪前保持暂停。本机 Codex 没有 VM project，VM task 必须从 VM
设备创建。当前未完成两端无人值守证明。

- 宿主机 minute-based scheduled task 在现有开发任务中轮询 `vm-to-host/`；收到合法
  `TEST_RESULT` 后验证诊断附件/evidence，自动恢复 HostCoordinator 任务进入分析、
  修复和本地质量门；验证通过后只推送 repair branch，P11 再重建候选并发出
  `FIX_READY`/新 `TEST_REQUEST`。
- VM minute-based scheduled task 只读轮询 `host-to-vm/` 中合法的
  `TEST_REQUEST`/`FIX_READY`。监视任务本身不拥有 Live grant；真正执行由固定 runner
  在本轮 operation grant 与请求指定的 guest reset 或 snapshot 前置都有效后自动
  启动，并在结束后写入 `vm-to-host/`。
- 两台机器必须保持 Codex app 和计算机可运行。轮询失败只告警，不改变 cycle 状态。
- “代码已 push”本身不假设能够唤醒另一台 Codex；只有已验证 relay 消息和轮询器
  才是通知路径。

~~~text
VM TEST_RESULT
  -> host automation resumes HostCoordinator
     -> fix -> local gates -> repair push
        -> P11 candidate rebuild (when applicable)
           -> host-to-vm FIX_READY / TEST_REQUEST
              -> VM automation -> clean -> exact-input test -> TEST_RESULT
~~~

### 非交互 codex exec runner

若 minute-based polling 的延迟过高，可选的确定性 watcher 只检查 control ref 和
message hash；发现新消息后触发 `codex exec resume` 恢复对应任务。runner 也可以用
`codex exec --json` 和固定 output schema 启动分析任务，将模型输出约束为建议或
结构化摘要。执行系统操作的仍是经过 allow-list 的 runner，而不是把模型文本直接
当脚本。

两种方案都必须提供：单实例锁、最大运行时、重试上限、输出大小上限、消息去重、
审计日志脱敏、STOP 处理和人工接管。protected history、凭据发放、VM task、host
heartbeat 启用和 unattended acceptance 属于外部 operator 工作，不改变产品 Live
授权边界。

## 手工降级流程

手工搬运不是正常工作流。只有 control repository、认证或两端 automation 故障且无法
及时恢复时，才允许以下人工降级；它不降低证据要求：

1. 宿主机生成符合当前 Lane 认证/签名要求的 `TEST_REQUEST` bundle 和 hash 清单；
2. 用户通过只读介质或受控传输将 bundle 送入 VM；
3. 按请求清洁等级执行 guest reset；若命中升级条件，则由用户从 VM 外部恢复快照并
   把 snapshot receipt 送入 VM；
4. VM Codex 核验后只执行测试，导出符合当前 Lane 认证/签名要求且已脱敏的
   `TEST_RESULT` bundle；
5. 用户把 bundle 送回宿主机并显式唤醒宿主任务；
6. 宿主机验证 evidence 后修复、过门、推送；P11 再重建候选；
7. 用户将新的 `FIX_READY`/`TEST_REQUEST` bundle 送入 VM，并按新请求重复清洁流程。

人工复制不能改写 envelope、跳过 expiry/CAS/hash/signature，也不能把聊天中粘贴的
错误文本当作正式 evidence。若链条无法验证，状态只能是 BLOCKED。

## 威胁与 fail-closed 行为

| 威胁 | 必须行为 |
|---|---|
| VM 凭据泄露 | 只能污染 `vm-to-host/`；不能写产品 refs、`host-to-vm/` 或旧 evidence |
| relay 消息重放 | 由 CycleId、Sequence、expiry、nonce、previous hash 和 CAS 拒绝 |
| moving branch 替换输入 | 只接受完整 commit 或 candidate hash；本地重新计算 |
| 报告提示词/命令注入 | 全部按不受信数据处理，不生成或自动执行命令 |
| 伪造干净环境 | Fast Lane 缺有效 clean receipt 即 BLOCKED；Formal Lane 缺外部 snapshot receipt 即 BLOCKED |
| Formal evidence 被覆盖 | Formal Lane 使用 append-only/WORM CAS，消费前重新下载并验 hash/receipt |
| secret 出现在报告 | 上传前 secret scan；非零即拒绝并停在 VM 内隔离处置 |
| 两轮并发或结果串线 | 单 active cycle、原子 sequence CAS、精确 candidate/matrix 绑定 |
| 修复后复用旧候选 | P11 强制 `CANDIDATE_REBUILT` 和新 candidate ID/hash |
| 自动化越权 | 无 auto merge/release；STOP 与 P12 人工 gate 优先 |

任何当前 Lane 必需的 verifier、签名或 receipt 不可用，或 hash 漂移、状态不合法、
路径不受控、报告超限、secret scan 非零，都必须停止；不得为了“继续自动循环”降级
为信任模型回答、relay commit 或用户口头确认。

## 实施前置与完成判据

### P10A-0A Fast Lane MVP

先用最小基础设施打通高效率日常闭环：

- 配置私有产品 remote、repair branch protection 与 VM 只读身份；
- 创建两个单向私有 control repository：`host-to-vm` 仅 HostCoordinator 写、VM 读，
  `vm-to-host` 仅 VM 写、HostCoordinator 读，并禁止 force-push 和历史改写；
- 实现 canonical schema、CycleId、sequence、previous hash、单 active cycle 和 STOP；
- 配置宿主机与 VM 的 minute-based Codex Scheduled Tasks；
- 实现 frozen allow-list guest reset runner、baseline validator 和 `CLEAN_READY` receipt；
- 用纯 synthetic payload 演练 PASS、FAIL、BLOCKED、修复、P11 候选重建和重测；
- 证明 VM 无产品 write、宿主 control credential 无 merge/release、secret scan 为零。

完成这组 dry rehearsal 不以 WORM CAS、独立 message signing 或 hypervisor receipt
已经部署为前置；Fast Lane report 明确为 diagnostic。可选 watcher/`codex exec resume`
也不是 MVP 阻塞项。

当前完成了本地合同、prompt 模板、纯 synthetic rehearsal，以及三个 private
repositories 与两个 `outbox/` 的 bootstrap。宿主机 task 仅为暂停模板；GitHub private
ruleset、remote credential 权限测试、真实 VM reset adapter、VM 分钟级 task 和无人值守
闭环均未满足。因此 P10A-0A 仍处于进行中。

### P10A-0B Formal Lane gate

在首次真实 P10A 或任何正式里程碑前，再完成：

- 配置 append-only/WORM evidence CAS 与 receipt validator；
- 配置每角色消息/证据签名和 key rotation/revocation；
- 实现外部 snapshot supervisor 和 snapshot receipt validator；
- 实现 Formal Lane expiry、重放、时钟、retention 与 acceptance validator；
- 演练手工降级，证明 control repository 故障不迫使降低证据等级；
- 从外部 clean snapshot 对 synthetic Formal Lane bundle 完成端到端演练。

### 可进入 P10A

P10A-0A 完成后可以运行 Fast Lane 日常诊断闭环；它不授权真实 P10A。只有 P10A-0B
的权限/攻击测试、Formal message 测试、CAS 并发测试、证据上传测试和 snapshot
receipt 演练全部通过，用户才可在 disposable VM 开始首次窄校准。

### 可进入 P11

进入 P11 仍须依次满足：P10A 完成、宿主消费 evidence、事实冻结、P10B 两类候选
构建与签名、runbook 无占位符，以及本文 relay/手工通道对精确 candidate 的端到端
演练通过。协调通道就绪不能替代任何 P10/P11 gate。

## 外部参考

- Codex scheduled tasks：<https://learn.chatgpt.com/docs/automations.md>
- Codex non-interactive mode：
  <https://learn.chatgpt.com/docs/non-interactive-mode.md>
- Codex notifications：<https://learn.chatgpt.com/docs/notifications.md>
- GitHub repository rulesets：
  <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets>
- GitHub deploy keys：
  <https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys>

这些文档只支持“计划任务轮询、结构化非交互输出和最小 Git 权限”等能力选择；
本协议中的双机状态机、签名链、evidence CAS 和角色分离是本项目的安全设计，不是
第三方平台替本项目提供的验收保证。
