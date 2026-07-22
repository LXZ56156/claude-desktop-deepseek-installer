# 决策记录

更新日期：2026-07-22

本文件记录跨工作包的重要决定。状态为“暂定”的决定需要 artifact 或 VM 证据后
才能转为“冻结”；撤销决定必须保留历史理由并同步相关文档和测试。

## 状态

- **冻结**：后续实现必须遵守；变更需单独评审。
- **暂定**：当前方向，仍有明确验证门。
- **待决策**：未选择，不得偷偷在实现中固定。
- **撤销**：不再采用，但保留记录。

## 决策总览

| ID | 决策 | 状态 |
|---|---|---|
| D-001 | 首版只写官方 HKCU managed configuration | 冻结 |
| D-002 | 产品承诺是“一次双击发起”，不是绝对零点击 | 冻结 |
| D-003 | API Key 使用 DPAPI-backed credential helper | 暂定 |
| D-004 | Git 是 Code 条件依赖，不是全局硬依赖 | 撤销 |
| D-005 | 开发机和 CI 永不执行 Live provider | 冻结 |
| D-006 | 对 Claude Code settings 采取零读取政策 | 冻结 |
| D-007 | 不集成非官方 Claude UI 汉化 | 冻结 |
| D-008 | 配置源不混写，已有配置默认冲突停止 | 冻结 |
| D-009 | Standard 与 Offline MSIX 选择 | 待决策 |
| D-010 | Credential helper 采用签名、固定工具链的 .NET EXE | 冻结 |
| D-011 | 首版配置层级使用 HKCU，HKLM 只检测 | 冻结 |
| D-012 | 自动重启、RunOnce 和计划任务不进入默认首版 | 冻结 |
| D-013 | Stage manifest 与 Live grant 生命周期 | 暂定 |
| D-014 | Surface 按用户选择和 readiness 启用 | 撤销 |
| D-015 | 产品不内置 Desktop UI 自动化 | 冻结 |
| D-016 | 不提供 surface 选择，固定启用 Chat、Code、Cowork | 冻结 |
| D-017 | Git 是产品必备前置，合格复用、否则安装/升级 | 冻结 |
| D-018 | 每个 Release 冻结单一 MSIX 部署范围 | 冻结 |
| D-019 | 运行、能力、UI 证据使用分层状态 | 冻结 |
| D-020 | 双机 Codex 使用分权 relay 与分层 clean-start | 冻结 |
| D-021 | GitHub Free public visibility 迁移 | 冻结 |
| D-022 | Realtime relay 通信优先与风险成比例 | 冻结 |
| D-023 | 一次性 Fast Lane 自动诊断恢复 | 冻结 |

## D-001：首选 managed configuration

**状态：冻结**

官方 Windows policy 可以在首次启动前激活 3P 模式，避免用户进入 Developer
Mode。credential helper 和 `disableDeploymentModeChooser` 是 MDM-only，因此
configLibrary 仅作为冲突检测、导出研究和兼容验证面，不进入首版 writer。

首版写 HKCU managed policy。VM 仍需验证 chooser、写后重启和更新行为；验证失败
则阻断发布，而不是回退到明文 local credential。

## D-002：一键的含义

**状态：冻结**

一键表示用户双击一次即可启动完整编排。UAC、Key 输入、必要重启、BIOS 虚拟化
和高风险工具授权不被视为应该绕过的“多余点击”。所有产品文案必须遵守这一表述。

## D-003：凭据方案

**状态：暂定**

Key 使用安全输入，经 DPAPI CurrentUser 保护，由 Claude credential helper 在
需要时输出。Key 不写 policy/configLibrary、命令行、环境变量、状态、日志或
报告。

helper 的具体技术形态已由 D-010 冻结；本决定仍需实际 DPAPI/helper/VM 行为证据后
才能从“暂定”升级为“冻结”。

## D-004：Git 条件依赖

**状态：撤销（2026-07-14）**

Chat 不需要 Git。只有用户选择本地 Code 且系统缺少合格 Git 时，才进入 Git
安装分支。项目不安装 Node.js、npm、WSL 或独立 Claude Code CLI。

项目不直接或静默修改 PATH。如果官方 Git 安装器会产生精确 PATH 变化，必须在
实现前建立披露、独立授权、检测和补偿合同。

该决定只描述外部技术依赖，但其“产品可选”结论已被 D-016/D-017 撤销。保留本节
用于说明变更历史。

## D-005：Live 只在后续 VM 执行

**状态：冻结**

本地开发和 CI 只运行 static、Unit、Contract、HostSandbox 和 Release
Simulation。即使 live adapter 已写完，也不得由被测产品在宿主机加载或执行。

真实 MSIX、Git、registry、VMP、重启、Desktop 进程和 API 的首次执行在用户后续
准备的 disposable VM 内由 Codex 按专用 runbook 完成。同一 Windows 用户下无法
靠代码可靠证明“这是 VM”；stage/grant 只防误触，真正隔离来自操作流程和 VM。

## D-006：Claude Code settings 零读取

**状态：冻结**

项目和宿主机自动化不定位、不 Test-Path、不读取、不哈希、不备份、不监视
`%USERPROFILE%\.claude\settings.json`。

因此撤销“由本进程证明前后 SHA-256 不变”的要求，改用：

- provider/adapter 无访问证据；
- static guard；
- sandbox ledger；
- 后续 VM 内允许范围基线。

## D-007：不修改 Claude UI 资源

**状态：冻结**

官方当前无中文 Desktop UI。项目提供中文安装、诊断、报告和文档，但不修改
MSIX/Electron 资源，不集成社区汉化补丁。

## D-008：配置所有权

**状态：冻结**

首版一次运行只管理 HKCU policy。发现现有 HKLM、HKCU 或 configLibrary 内容时
默认停止；HKLM 会覆盖 HKCU，因此不能继续。configLibrary 不进入首版 writer。

## D-009：MSIX 类型

**状态：待决策**

Standard 体积较小但可能在首次使用时下载运行资源；Offline 体积大但更利于稳定
验收。需要比较：

- 下载体积和失败恢复；
- 自动更新行为；
- Code/Cowork 首次启动依赖；
- 离线包来源、签名和许可；
- 用户网络环境。

## D-010：Helper 技术形态

**状态：冻结（2026-07-14）**

首版采用最小、签名的 .NET EXE，不采用 PowerShell helper。Release 合同固定为：

- `net8.0-windows`、按 x64/Arm64 分别构建；self-contained、single-file、
  deterministic。
- 固定 SDK、编译器、runtime pack 和依赖锁；源码树、PE、工具链与 CycloneDX
  SBOM 全部进入可重算证据。
- PE 必须 Authenticode 签名并匹配 Release 外部信任策略；缺少实际签名验证
  receipt 时 fail closed，不能用调用者自报的 `Valid` 字段代替。
- Claude 只直接执行绝对路径、零参数 helper；不经 shell、不读 stdin、不提示，
  stdout 只允许单行 token 或 exact JSON，stderr 必须为空。
- helper 消费 `CLAUDE_HELPER_CONTEXT`；`mid-session-refresh` 的有效超时为 20 秒，
  其余已知 context 为 60 秒，TTL 为 3600 秒。
- Key 仅以 DPAPI CurrentUser 保护的 opaque blob 保存；helper、配置、日志、状态和
  报告均不得保存明文或明文摘要。

该冻结只确定产品和构建合同，不表示 helper 源码、固定工具链、SBOM、PE、证书或
签名服务已经存在。任一外部材料缺失时不得组装真实候选，也不得以明文静态 Key、
PowerShell 脚本或环境变量作为临时捷径。

## D-011：首版 HKCU

**状态：冻结**

首版只写 HKCU managed policy，并把 helper 与 DPAPI blob 安装在当前用户项目
专属 LocalAppData。即使 Cowork MSIX 采用整机预配，其他 Windows 用户也不会继承
当前用户凭据。

HKLM 只检测并作为阻断冲突。未来组织/多用户版本必须另行设计机器级 helper、
每用户凭据、无凭据用户行为、ACL、更新和卸载。

## D-012：重启策略

**状态：冻结**

首版 VMP 变更使用 `-NoRestart`、安全 checkpoint 和人工重启后重新双击续跑。
不默认使用自动重启、RunOnce 或计划任务。未来若引入，必须另行授权并增加任务
所有权、过期和清理合同。

用户拒绝 VMP/UAC 时不绕过：能力状态为 `BLOCKED`，运行状态为
`PARTIAL/ACTION_REQUIRED` 或 `CANCELLED`；同一 checkpoint 的续跑次数必须有上限。

## D-013：Stage 与 Live grant

**状态：暂定**

运行阶段不由环境变量或普通 `-Mode Live` 单独决定。目标生命周期：

- `Scaffold`：当前阶段，无 live adapter。
- `Development`：可以存在 live adapter 源码，但默认 bootstrap 不加载。
- `VmAcceptance`：只用于未发布候选，要求 package-bound stage manifest 和
  一次性 operation grant。
- `UserLive`：P10 生成并冻结但保持未发布；P11 验证精确字节，只有 P12 才允许
  原字节晋升和发布。

embedded stage manifest 绑定版本、commit、profile 和“排除 manifest/signature
自身”的 content-manifest digest。detached signed sidecar 再绑定最终 ZIP
SHA-256、content digest 和 profile，避免 manifest 引用包含自身的 ZIP hash。

manifest v2 还必须从 sidecar 外部固定 RSA-PSS-SHA256 signer 的证书/public-key
SHA-256、Subject、KeyId、signing request ID、nonce 和最大签名年龄。sidecar 必须
携带实际签名字节和 X509 DER，并由验证器对 domain-separated canonical claims
bytes 做真实公钥验签；自报 `VALID`、签名 hash 或证书指纹不能充当验签。当前
`SignedAtUtc` 仅是 signer assertion，不冒充 RFC3161 可信时间戳。

VM grant 绑定 sidecar/候选 hash、content digest、VM runId、允许操作、过期时间、
nonce 和用户确认。它用于防止误触，不声称能在同一用户权限下密码学证明 VM
身份。

P10 应同时构建并冻结 VmAcceptance artifact 与待发布 UserLive artifact。P11
必须测试两者的精确字节/hash；P12 只发布已经测过的 UserLive 字节，不重建。
在 P11 exact acceptance receipt 和 promotion CAS 合同完成前，任何纯函数都不得
构造 `PROMOTED` receipt；当前 promotion 必须以
`P11_ACCEPTANCE_RECEIPT_REQUIRED` fail closed。

## D-014：Surface 选择

**状态：撤销（2026-07-14）**

Chat 默认启用。Code/Cowork 只有用户选择且 readiness 满足后才在 policy 中启用。
未选择或未就绪的 surface 关闭并报告 `NOT TESTED`，不显示成已就绪。

该交互方案被 D-016 撤销，不得实现。

## D-015：验收边界

**状态：冻结**

产品自身只报告配置、API validation、Git/VMP/readiness、process launch 和恢复
证据，不内置没有官方稳定接口的 Desktop UI 自动化。

Chat/Code/Cowork 的真实 UI E2E 由后续 VM Codex 外部执行。若未来 Anthropic
提供稳定机器接口，再通过新决策评审。

## D-016：固定完整功能目标

**状态：冻结**

首版不向用户展示 Chat/Code/Cowork 选择页。`RequestedSurfaces` 固定为三项，
managed policy 中三个 surface 固定为 `true`；`EffectiveSurfaces` 由 readiness
派生，只控制前置处理和验收结果，不修改产品目标。

任何依赖失败、用户取消必要系统修改或环境不支持，都必须安全停止并分别报告；
禁止关闭 Code/Cowork 后把结果包装成 Chat-only 成功。

## D-017：Git 是产品必备前置

**状态：冻结**

由于 D-016 固定包含 Code，Git 从技术上的条件依赖转为产品流程的必备前置：

- 已有合格 Git for Windows 时直接复用，不重复安装。
- 缺失、过旧或不合格时，只使用已验签的官方 Git 安装器安装/升级。
- 不读取或修改全局 Git 配置。
- 任何 PATH 变化仍须满足披露、独立确认、检测和补偿合同。
- 用户取消必要确认时阻断完成，不静默退化。

## D-018：每个 Release 冻结单一 MSIX 部署范围

**状态：冻结**

用户不选择 per-user/machine-wide。P10 根据固定 Desktop 版本的 VM 证据冻结该
Release 唯一部署范围；优先 per-user，只有 Cowork 实证要求时才采用 machine-wide。

运行时不得静默 fallback、双装或卸载相反范围的既有安装。发生范围冲突时进入显式
迁移合同或 `ACTION_REQUIRED`，不能临场猜测。

## D-019：分层状态模型

**状态：冻结**

报告分别记录：

- 运行：`SUCCEEDED/PARTIAL/RESTART_REQUIRED/ACTION_REQUIRED/CANCELLED/FAILED`。
- 能力：`READY/BLOCKED/PENDING_RESTART/UNSUPPORTED/UNKNOWN`。
- UI 证据：`PASS/FAIL/NOT_TESTED`。

`Success=true` 只对应 `SUCCEEDED`。`NOT_TESTED` 只表示尚无 UI 验证证据，不再
表示用户没有选择某项。资源仍独立记录 pre/post state、ownership、mutation 和
compensation；分层状态不能掩盖部分系统修改。

## D-020：双机 Codex 测试闭环

**状态：冻结（2026-07-15）**

双机闭环的角色、消息状态机、clean-start 和证据转交以
`VM_TEST_RELAY.md` 为 operator coordination 权威，并遵守以下不可变边界：

- 宿主机 Codex 是唯一产品代码写入者，负责修复、本地门、提交/推送，以及 P10A
  校准包或 P10B 双候选的重建和签名。
- VM Codex 对产品仓库只读，只测试、分析和回传；它可以向独立 control repo 的 VM
  outbox 写结构化结果，但不得修改源码、ZIP、runbook 或 fixture。
- Fast Lane（日常自动修复）MVP 使用两个物理 control repositories 的双向隔离
  outbox；2026-07-15 最初冻结的部署实例为 private，现已由 D-021 的 public protected
  transport 实例替代。envelope 绑定 CycleId、单调 sequence 和内容 hash，
  由两端分钟级 Codex Scheduled Tasks 自动轮询。可用低延迟 watcher 触发受限
  `codex exec`/resume，不要求用户人工搬文件；transport 可替换，不限定 GitHub。
- P10A 固定精确 commit/calibration artifact；P11 固定 P10B candidate exact
  bytes/hash。P11 失败后，宿主机修复并过门、提交/推送，再回到 P10B 重建/签名新
  候选；VM 不拉取修复源码直接重测。
- Fast Lane 按冻结 allow-list 卸载本项目产物，清除项目拥有的 HKCU policy、
  credential、checkpoint 和 owner-marked 目录，再核验 baseline；它不以 WORM、
  message signing 或每轮 snapshot 为前置，结果只用于诊断。
- Formal Lane 用于 P10A/P11 正式证据：必须由外部 hypervisor supervisor 恢复快照
  并出 receipt，再由独立 CAS/receipts/signatures 验真。VMP/重启/卸载、未知补偿、
  baseline drift 或 reset 失败必须从 Fast Lane 升级。VM 不能恢复自身正在运行的
  整机快照，正式 P11 PASS 必须绑定 clean-snapshot receipt。
- relay message/ACK/notification 不是 CAS、签名、snapshot receipt 或 acceptance
  receipt；free text/log 只作为数据，不能自动执行。不得自动 merge，也不得自动
  进入 P12。

## D-021：GitHub Free public visibility 迁移

**状态：冻结并已部署（2026-07-17）**

用户选择不升级 GitHub Pro，并把产品与两个 control repositories 改为 public；切换前
已明确确认不可逆公开风险，并作出以下选择：

- `PrivacyDecision=ACCEPTED`：接受 commit metadata、历史运营信息和未来 public outbox
  对互联网可见。
- `HistoryRewrite=NO`：不重写现有历史。
- `ResidualPrivacyAudit=NOT_PERFORMED_ACCEPTED_RISK`：Actions logs/artifacts、远端未枚举
  refs/tags 和 control author metadata 不再作为 visibility cutover 前置门。

版本化 visibility/protection receipt、policy/readiness/outbox/onboarding、prompts/runbook
与测试已在 `a09130f2afadb6dcf4cfc60a61a72095dc41faa6` 明确冻结 `PUBLIC` 和
public-safe envelope。2026-07-17 三仓均已切换为 public 并启用
`cddsi-public-protected-history-v1`：产品 ruleset `19068339`，host-to-VM
`19068292`，VM-to-host `19068313`。三个 ruleset 均无 bypass actor，规则精确为
禁止删除、禁止非快进和要求线性历史；effective-rules 已覆盖三仓 `main` 与产品
`codex/repair/*`。D-021 因而替代 D-020 的 private transport 实例。

当前仍须从包含最新交接文档的 clean exact commit 重新运行统一门、重建 onboarding
bundle、重绑仍暂停的 heartbeat 并等待最终 CI。角色限制继续由尚未发放的窄凭据和
真实负向权限测试完成；宿主机 Live、VM 只读产品代码和 Formal Lane 边界不变。

## D-022：Realtime relay 通信优先与风险成比例

**状态：冻结（2026-07-21）**

用户明确要求结束 realtime relay 的过度工程化，以最短路径实现宿主机与
disposable VM 的双向秒级通知。实现和评审从此以“通信功能优先、控制与
现实风险成比例”为默认；无具体威胁、无明确消费者或只服务未来理论场景的
复杂控制，不得阻断本轮 Free-only 部署和 relay-only VM smoke。

当前最小交付合同是：

- 复用用户已明确授权的 encrypted-keyring Wrangler `default` profile；已知
  scope 超集不构成失败。已有 Billing Dashboard 人工核对未列出
  Workers/Workers Paid，足以作为本次 Free-only 实施依据；若 Cloudflare 真实显示
  付费、升级或购买要求，立即停止。
- machine Billing receipt、two-phase write ticket、coordinated provisioner、Host/VM
  DPAPI receipts、bulk semantics 与 two-secret staging receipt 均降为可选 hardening/
  审计实现，不再是 Worker/DO 创建、secret 写入、`workers.dev` 部署或一次性
  relay-only smoke 的前置条件。
- 一次性手工 smoke 可使用当前进程内存/安全输入中的 relay secret。
  VM 侧允许一份 repo 外、owner-only、一次性固定-schema handoff JSON：人工拖入
  后，只由固定 smoke 脚本读取，在首次网络前删除，并在结束时清零内存 secret。
  该 JSON 不得进入 Git、prompt、日志或 evidence，不得作为长期明文存储。
  DPAPI CurrentUser 仅在后续要启用跨进程/跨重启的持久 unattended watcher 前
  成为必选门。
- 本轮允许人工启动的 relay-only Host/VM publish/watch/ACK/reconnect 正负向 smoke；
  它不启动旧 onboarding/bootstrap、产品 integration、产品 Live 或任何 automation。
- 仍不可突破的边界只保留与实际损害直接相关的项：secret 不进入日志、
  Git、prompt、报告或 evidence；relay payload/free text 不执行；宿主机是产品代码
  唯一写入者，VM 只读产品仓库；无自动 merge/release/promotion，不越过
  P12；Formal Lane 的外部 snapshot receipt、CAS 与签名合同不变。

D-022 只放宽 realtime relay operator coordination 的交付路径，不放宽产品安装器的
Live 边界、P10/P11/P12 发布门或 D-003/D-010 的产品 API Key 合同。早期 relay
文档中与本决定冲突的“未有 machine receipt/DPAPI 所以不得部署”表述，均视为
已被本决定取代的历史硬化方案。

## D-023：一次性 Fast Lane 自动诊断恢复

**状态：冻结（2026-07-22）**

用户已明确授权开始自动化测试。本决定仅恢复一次有界的 Fast Lane 自动诊断循环，
不恢复任何旧 onboarding ZIP/prompt、旧 VM bootstrap、通用产品 integration 或产品
Live。结果只属于 diagnostic evidence，不能作为 P10A 事实、P10B 候选或 P11 PASS。

执行顺序固定为：

1. 在 VM 当前用户下完成一次性 relay secret 导入并写入 DPAPI CurrentUser；明文交接
   文件必须位于仓库外、仅 owner 可读，并在首次网络前删除，secret 不进入 prompt、
   日志、Git、报告或 evidence。
2. 从 VM 设备创建或原位更新唯一 VmTester automation；HostCoordinator 与 VmTester
   均先保持 `PAUSED`。只有持久 credential、固定 endpoint/client binding、单任务
   readback、双向 publish/watch/ACK、断线 resume、权限负测、payload 不执行、secret
   scan 为 0 和 Git fallback canary 全部通过，才可激活。
3. canary 通过后按 HostCoordinator、VmTester 的顺序启动，只处理一个已冻结 CycleId
   的一轮 Fast Lane `TEST_REQUEST`。VM 仍只读产品仓库，不得修改、提交或推送产品
   代码；relay 或自由文本不得成为命令。
4. `HOST_ACK`、`STOP`、失败、阻断或超时任一发生后，两端 automation 都必须自动回到
   `PAUSED`。本次授权随该轮终态消耗，不得自行创建下一轮、自动重试修复或保持常驻。

本决定不要求为该 diagnostic cycle 补建 Formal Lane 的 snapshot receipt、CAS 或签名，
但也不授予 Formal P10A、P10B 构建、P11、自动 merge、release、promotion 或越过 P12
的任何权限。上述正式阶段继续按 D-020 及对应计划 fail closed。
