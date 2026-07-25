# P10A disposable VM 窄校准计划

更新日期：2026-07-25

> **D-027 历史声明：** P10A calibration 不再是当前发布要求。本文件只保留 D-026
> 事实与旧 schema，不能阻塞或授权 D-027。当前候选路线见 `RELEASE_PLAN.md` 和
> `VM_ACCEPTANCE_PLAN.md`。

## 定位

P10A 只解决无法在开发宿主机 synthetic 证明、但冻结 P10B 最终候选前必须取得的
少量实物事实。它不是 P11 全面验收，不产生发布通过结论，也不能替代
`VM_ACCEPTANCE_PLAN.md`。

D-026 在 P10A 之前新增可写的 `VmDevelopment` 通道：宿主机交接后冻结写入，VM
可以在 disposable 环境内实现 Live、提交和重建 development ZIP。进入本文件的
Formal P10A 时，
开发租约暂停，commit/artifact/runbook 全部重新冻结为只读；任何失败返回
`VmDevelopment` 并生成新的源提交/development ZIP/P10A 输入，不在校准轮现场修改。本文件后文的“宿主机唯一写入、
VM 只读”只描述旧流程或 Formal 轮内的不可变性，不撤销 D-026 的前置开发租约。

证据 readiness 只有 `COMPLETE`、`INCOMPLETE` 和 `FAILED`。三种状态的
`ComprehensiveAcceptance` 均固定为 `false`。`COMPLETE` 也不直接包含
`CanFreezeP10B`；冻结判断只能由宿主机使用外部终态会话调用
`Resolve-CddsiVmCalibrationConsumption` 后取得。

双机角色、消息状态机、清洁启动和证据转交以 `VM_TEST_RELAY.md` 为 operator
coordination 权威。Formal P10A 开始后没有活动代码 writer：VM 只测试冻结对象，
不得修改源码、ZIP、runbook 或 fixture。旧 Fast Lane 的 public protected control repo、
双 outbox、Scheduled Tasks 和 deterministic guest reset 已退役，只保留历史诊断背景。
本文件产生可消费 P10A evidence 的运行属于 Formal Lane，必须使用独立 CAS/receipt/
signature 和外部 clean snapshot。

## 固定顺序

~~~text
宿主机完成 P5-P9 synthetic 与绑定精确 commit 的 P10A 校准包
  -> 外部 hypervisor supervisor 恢复 fixed snapshot 并签发 receipt
     -> 宿主机预持有不可由 evidence 自证的 session anchor
     -> 外部 stage-policy v2 grant、workflow 与八项 operation-use 被原子 claim
        -> disposable VM 按顺序完成八项操作及逐操作 provider evidence
           -> cleanup 完成，八项 operation-use 与 workflow 进入 COMPLETED
              -> 导出无 secret、无路径、无用户名的结构化 evidence
                 -> 宿主机以 anchor、ExpectedSession 和八项终态回执验真
                    -> consumption CAS 先提议、再验证已提交的 CONSUMED 状态
                       -> 冻结 P10B 并构建 VmAcceptance + UserLive 最终字节
                          -> P11 对 P10B 精确 hash 执行全面矩阵
~~~

不得在校准 VM 内修改 ZIP 后直接进入 P11，也不得把 P10A artifact 晋升为
UserLive。发现代码缺陷时必须结束 Formal 轮，返回可写 `VmDevelopment` 修复、通过
产品门、提交和推送，再生成绑定新 commit 的校准包并重新授权。重新进入 Formal P10A
时仍须由外部
hypervisor supervisor 恢复干净快照。

## 进入条件

- P5-P9 synthetic 合同、故障 reducer 和 secret scan 已完成。
- calibration artifact、signed sidecar、content digest、`VmCalibration` profile 和
  runId 已冻结。
- stage manifest 通过 `Test-CddsiStageManifest`，operation grant 通过
  `Test-CddsiOperationGrant`，原子 claim 产生的 authorization session 通过
  `Test-CddsiAuthorizationSession`。
- grant 精确包含以下八项操作，顺序和 operation-set digest 均不得变化：
  `InspectEnvironment`、`AcquireCalibrationArtifacts`、
  `VerifyCalibrationArtifacts`、`CalibrateMsixScope`、
  `CalibrateCredentialHelper`、`CalibrateGit`、
  `WriteCalibrationEvidence`、`CleanupCalibrationResources`。
- VM 使用固定镜像和独立测试用户；不复用宿主凭据，不共享可写用户目录。
- Formal request 已绑定精确 repository commit、校准 artifact/sidecar/hash 和 runbook；
  VM 不跟随移动分支头，且本轮不使用开发写权限。
- 外部 hypervisor supervisor 已为本次 Formal P10A 恢复固定快照并出 receipt。VM
  Codex 不能恢复自身正在运行的整机快照；Fast Lane 的 in-guest reset receipt 不
  满足该进入条件。
- 校准不需要真实 DeepSeek Key；禁止把 Key 放入对话、fixture、日志或 evidence。

## ExpectedSession 与外部 anchor 合同

`ExpectedSession` 是校准器外部提供的终态对象，不由 evidence 自行声明。其 v2
exact schema 精确包含：

- `StageManifest`、`OperationGrant` 和原子 claim 产生的
  `AuthorizationSession`；
- stage-policy v2 的 `WorkflowSessionState`；
- 按 grant 固定顺序排列的八个 `OperationUseStates`；
- `SessionAnchorToken` 与 `SessionBindingToken`。

宿主机必须在 VM 执行前独立保存 `ExpectedSessionAnchorToken`。anchor 绑定 manifest、
grant、authorization session、workflow 稳定 state key，以及八个 operation-use
稳定 state key；它不绑定执行后才产生的 revision、终态或 provider evidence。这样
VM 可以提交合法终态，但不能事后替换整套 session 后再让 evidence 自证。

八个 operation-use 必须全部为 `COMPLETED`，其终态 receipt、provider evidence
digest、发生时间和顺序均有效；workflow 也必须为 `COMPLETED`，并以
`TerminalOperationSetDigestSha256` 精确聚合八个终态。manifest、grant、authorization
session、workflow 和 operation-use 必须共同绑定同一 artifact SHA-256、sidecar
SHA-256、content digest、profile、runId、grantId、nonce、claimId 与 expiry。

时间顺序必须满足 manifest 创建、grant 签发、claim、八项操作、cleanup、workflow
完成的单调顺序，且全部早于 authorization expiry。宿主机验证时还必须传入精确
`ValidationTimeUtc` 和有限 `MaximumAgeSeconds`，过期终态不得补写或消费。

Evidence 不定义私有 grant/session schema。任何未通过 stage-policy v2 validator 的
对象、非终态 operation/workflow、anchor 漂移、重复 operation-use、终态集合漂移或
陈旧 session 都使 evidence 无效。

## 唯一允许的校准范围

### 固定 OS image facts

只记录镜像 SHA-256、SKU、架构、build、UBR、语言、补丁日期和 nested
virtualization 是否支持。不得记录 VM 路径、用户名、机器名、账户或磁盘内容。

### Claude Desktop MSIX 双候选

顶层 `MsixCandidates` 必须精确包含两个元素，并固定排序：

1. `Standard`；
2. `Offline`。

每个候选都记录：

- 官方 source URI、最终 redirect URI 和 redirect 次数；
- artifact 版本、字节数和 SHA-256；
- Authenticode 状态、可信链、signer subject/thumbprint、时间戳状态；
- certificate SHA-256、序列号和有效期；
- manifest Identity 的 Name、Publisher、Version、ProcessorArchitecture、
  ResourceId、PackageFamilyName 和 PackageFullName；
- per-user 与 machine-wide 部署结果，以及各自 Cowork service 是否存在；
- 精确 `ObservedAtUtc`。

缺少一个候选、顺序颠倒，或任一候选为 `NOT_OBSERVED`，都不得冻结 P10B。

`Selection` 必须由两个候选共同派生，并绑定整个 candidate-set digest。Standard 有
完整可行 scope 时固定优先 Standard；只有 Standard 的两个 scope 均有明确失败事实
且 `RecommendedScope=NONE`、Offline 有完整可行 scope 时，才能选择 Offline。未知
事实不能被解释成失败事实，也不能触发 fallback。

本阶段只冻结部署事实，不执行 Chat/Code/Cowork UI happy path。

### Git for Windows

记录固定 release tag、官方 asset 文件名和 source URI、版本、字节数、SHA-256、
Authenticode signer/certificate、PE OriginalFilename、ProductName、CompanyName、
FileVersion、Machine 和精确 `ObservedAtUtc`。不得记录安装路径、PATH 内容、用户名
或全局 Git 配置。

### Desktop 3P 行为

只验证以下合同事实：

- Claude 是否实际调用 credential helper；stdout 是否只有一个 token、stderr 是否
  为空，`CLAUDE_HELPER_CONTEXT` 五种值、`mid-session-refresh=20s`、其他 context
  `=60s`、TTL/silent refresh 与“不得提示”是否符合合同；测试使用非真实
  synthetic token；
- deployment chooser 是否隐藏，是否跳过 Developer Mode 和 Anthropic 登录；
- HKCU managed policy 是否生效、是否为 15 个 `REG_SZ`、是否使用 helper 引用、
  configLibrary writer 是否保持关闭。

证据只保存布尔结果、计数、稳定错误码和精确 `ObservedAtUtc`；禁止保存 helper
stdout、token、原始 registry 值、配置正文或 Desktop/network response。

## Evidence exact schema 与绑定

顶层必须精确包含：

- `SchemaVersion=2`；
- `Purpose=P10A_VM_CALIBRATION_ONLY`；
- `SessionBinding`；
- `ObservationStartedAtUtc`；
- `CompletedAtUtc`；
- `OsImage`；
- `MsixCandidates`；
- `Selection`；
- `Git`；
- `DesktopBehavior`；
- `Cleanup`；
- `OperationReceipts`；
- `Readiness`；
- `EvidenceBindingToken`。

`SessionBinding` 只引用外部 session，并绑定 artifact、sidecar、content、profile、
runId、grantId、claimId、operation-set digest、session anchor、整个 session 的
canonical binding token 和 workflow 终态集合 digest。

`OperationReceipts` 精确包含八项记录。每项把 operation 名称、该项最小 provider
evidence digest 和对应 stage-policy terminal receipt 绑定在一起；顺序、重复、替换、
跨 session 复用或只重算 evidence 内部 token 均不得通过。`Cleanup` 必须显式为
`COMPLETE`，并绑定校准资源清理的稳定证据和时间。顶层 `EvidenceBindingToken` 覆盖
完整 evidence（不含 token 自身）。因此攻击者即使修改观察值并同步重算 Selection、
Readiness 和 evidence token，也无法伪造 anchor、八个外部 operation receipt 或
workflow 终态。

所有 `ObservedAtUtc` 必须满足：

~~~text
ClaimedAtUtc <= ObservationStartedAtUtc <= ObservedAtUtc
ObservedAtUtc <= matching operation receipt time <= Cleanup.CompletedAtUtc
Cleanup.CompletedAtUtc <= WorkflowSessionState.OccurredAtUtc < ExpiresAtUtc
~~~

时间必须是带 `Z` 的精确 UTC 文本。无法观察的事实使用精确字符串
`NOT_OBSERVED`，不得猜测、留空或从文档推断。

## URI 与数据最小化

MSIX source 必须通过 `Test-CddsiOfficialArtifactUri(..., Anthropic)`；Git source 必须
通过 `Test-CddsiOfficialArtifactUri(..., GitForWindows)`。所有 URI 最长 2048 字符，
只允许 HTTPS，禁止 userinfo、query 和 fragment。redirect 允许 HTTPS CDN 地址或
精确 `NO_REDIRECT`，但同样受长度和敏感信息限制。

Evidence exact schema 拒绝以下内容及同类扩展：

- filesystem path、安装路径、用户目录；
- username、账户、机器名；
- API Key、Authorization、helper stdout；
- raw registry values、配置正文；
- raw HTTP/Desktop response、完整日志、截图；
- evidence 内部的 `CanFreezeP10B`。

## 执行步骤

1. 宿主机在进入 VM 前保存 session anchor；外部 hypervisor supervisor 为本次
   Formal P10A 恢复固定快照并签发 receipt。随后核对 receipt、精确 commit、artifact、
   manifest/grant/authorization/workflow/operation-use 初态 binding。
2. 原子 claim grant、workflow 和八项 operation-use；确认 session 尚未过期且八项
   操作及逐操作确认均精确匹配。
3. 记录固定 OS image facts。
4. 分别获取并验证 Standard 与 Offline 候选；不把下载响应正文写入 evidence。
5. 分快照执行两个候选的 per-user 与 machine-wide scope 校准。
6. 运行 helper/chooser/HKCU 最小行为检查，不输入真实 Key，不执行完整 UI E2E。
7. 只按 runbook 精确 allow-list 清理本项目产物、项目拥有的 HKCU policy、
   credential、checkpoint 和 ownership marker/token 匹配的
   `cddsi-vm-test-<GUID>` 资源；逐项提交八个 `COMPLETED` operation-use terminal
   receipt，再提交 `COMPLETED` workflow terminal receipt。过期后不得补写、重开
   或替换 session。
8. 生成结构化 evidence 与八项 `OperationReceipts`，校验 canonical binding、secret
   scan、时间单调性和数据最小化。
9. 把 evidence 与外部 ExpectedSession 一起交回宿主机；不得让 evidence 覆盖
   宿主机预持有的 anchor。VM Codex 随后停止 Formal 场景并请求外部 hypervisor
   supervisor 恢复快照，不得自行声称已完成整机恢复。
10. 宿主机先以 anchor 和显式验证时间运行 `Test-CddsiVmCalibrationEvidence`，再以
    `AVAILABLE` consumption state 调用 `Resolve-CddsiVmCalibrationConsumption`。首次
    只可得到带 CAS proposal 的 `READY_TO_COMMIT`，`CanFreezeP10B=false`。
11. 外部原子存储提交 proposal 后，宿主机以同一 consumption ID、revision、session
    和 evidence 再次调用；只有验证已提交 `CONSUMED` receipt 并返回
    `READY_TO_FREEZE`、`CanFreezeP10B=true` 才能冻结。更换 ID、revision、evidence 或
    replay 到其他 session 必须失败。

## 停止线

遇到以下任一情况立即停止当前校准并返回失败或无效证据：

- artifact/sidecar/content/profile/run/grant/claim/session/anchor 不匹配；
- operation-use 或 workflow 非终态、终态集合不一致、已过期或观察时间落在窗口外；
- cleanup 不完整、operation receipt 缺失/重复/乱序或 provider evidence digest 不匹配；
- Standard/Offline 任一候选缺失、未知或顺序错误；
- source、redirect、hash、signer、certificate、manifest/PE identity 无法绑定；
- 需要扩大 grant、修改系统代理/证书/hosts 或临时下载工具；
- 需要真实 API Key、完整 Chat/Code/Cowork UI 测试或用户数据；
- 任何路径、用户名、secret、原始 registry/response 可能进入 evidence。

## 退出与后续

只有 consumption 同时确认外部 anchor、session、八项 operation receipt、cleanup、
evidence 和已提交 CAS receipt 有效，readiness 为 `COMPLETE`、两个候选均完整观察且
Selection 唯一时，才返回 `CanFreezeP10B=true`。宿主机随后冻结 MSIX flavor/scope、
signer/identity、Git identity、helper/chooser/HKCU 行为和固定 VM image facts，并重新
运行完整本地门后构建 P10B 两个最终 artifact。

P11 必须从干净快照测试 P10B 的精确字节和 hash，覆盖安装、失败、恢复、重启、
Chat、Code、Cowork 与 secret smoke。P10A 的 `COMPLETE` 或
`CanFreezeP10B=true` 永远不能写成 P11 通过。relay 只搬运控制消息和证据引用，
不能替代受信 CAS、签名、snapshot receipt 或 P11 acceptance receipt。
