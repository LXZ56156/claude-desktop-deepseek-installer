# 宿主机与 VM Codex 测试中继协议

更新日期：2026-07-22

## 定位与权威范围

本文是开发期“双机测试、宿主修复、重新制品化、VM 重测”协调协议的唯一权威
文档。它定义角色、信任边界、消息状态机、证据引用、干净环境恢复和失败闭环，
供 P10A 校准与 P11 全面验收共同使用。

本文不授予任何 Live 权限，不改变 `TEST_ISOLATION.md`，也不把中继组件加入产品、
Release ZIP、默认 bootstrap 或 trusted test harness。relay 是独立的 operator
coordination plane；产品平面、测试执行平面、证据平面和协调平面必须分离记账。

## 2026-07-21 controlled pause 与 relay-only 放行

当前不得继续 onboarding ZIP、旧 VM bootstrap、产品 integration、旧产品测试循环或 Formal
Lane。D-022 作出了精确例外：可进入已准备的 VM 执行人工 relay-only 通信
smoke；D-024 又允许 canary 通过后，由用户启动的两个新前台对话串行执行固定 profile 的
只读离线诊断测试。两者都不读取/运行旧 ZIP、不执行产品 Live、不触发 automation。
暂停前最后一个 retained ZIP/prompt 以及所有更早版本均标记为
`SUPERSEDED_DO_NOT_USE_REALTIME_RELAY_REPLAN`，只保留审计字节，不再交付或执行。任何本次
tracked 文档修改也使暂停前 finalization、CI、automation prompt 和 readiness receipt 失去
对新 HEAD 的绑定。因此当前：

- `CanStartVmBootstrap=false`；
- `CanStartVmIntegration=false`；
- `P10A0AComplete=false`；
- `CanStartFormalP10A=false`。

现有 HostCoordinator automation 必须继续 `PAUSED`；VM automation 若存在也必须继续
`PAUSED`。本轮用户已授权 Cloudflare
外部门 1–7 项并限定 Free-only；精确 infra toolchain/keyring helper、139/139 离线测试、69-file
secret scan、typecheck、实际本地 workerd/SQLite/Hibernation forced-eviction test 与 Wrangler
dry-run 已通过；既有 encrypted keyring `default` credential 已完成 generation-1 adoption 与固定
四 GET preflight；初始 preflight 确认单账号、既有 workers.dev subdomain、目标 Worker当时
不存在，并报告
`STANDARD / BillingPlanVerified=false / BILLING_VERIFICATION_REQUIRED`。随后经用户授权，只读复用
其个人 Edge 既有登录态查看 Billing → Subscriptions：未列出 Workers/Workers Paid，active 的
Teams Free Base 与无关 R2 Paid 不改变 Workers 的独立订阅边界，也不授权 relay 使用 R2。SQLite
DO 支持 Workers Free，Free 超限后操作失败而非计费；该观察不把整个账号称为 Free。
D-022 已将 machine receipt/ticket、coordinated DPAPI/staging receipt 降为 optional hardening，
不再阻断 Free-only provision 和一次性 smoke。用户回传的 `VM_RELAY_READINESS_V1`
为 `Ready=true`：VM 上 PowerShell 7、Git、`ClientWebSocket`、时钟、GitHub/`workers.dev`
443 出站与 `%LOCALAPPDATA%\CDDsiRelayVm\state` 目录均就绪，无 blocker。首次 smoke
的 VM secret 可由人工拖入一份 repo 外 owner-only fixed-schema handoff JSON；固定
`invoke-vm-smoke.ps1 -PackagePath` 有界读取后必须在首次网络前删除该文件。
缺少显式 `-AcknowledgeRelayOnlyLive` 时脚本只做 Plan，不读取/删除 package 或访网。
该交接不进入 Git/prompt/日志/evidence；DPAPI 只在持久 watcher 前必须。Free-only provision
与跨设备 HTTP relay smoke 已完成；生产 WebSocket reconnect/Hibernation 仍待真实 E2E。该结果
不改变产品 Live 和 automation 暂停。
暂停后的精确事实和恢复条件只看 `HANDOFF.md` 顶部与实际 Git/remote/PR/CI/automation/evidence。

## 2026-07-22 D-024 前台双对话诊断

当前测试路径是宿主机与 VM 两个新 Codex 对话分别前台运行
`invoke-foreground-cycle.ps1`，不创建或启动 Codex Automation，不使用 scheduler 或
`codex exec resume`。Automation 保持 `PAUSED`/`ABSENT`，task readback 不再是门。

当前旧 Host/VM 对话只负责公网 canary。canary 通过后才由两个新对话接管；新会话一次
只处理一个 active CycleId，但可在前一轮终态后用新 CycleId 串行处理下一轮，直到经验证的
`STOP`、用户停止或真正 blocker。允许的测试只限固定的 offline focused regression、
`scripts/check.ps1` 和 Release Simulation DryRun；产品 Live、旧 bootstrap/integration、
Formal Lane 与发布门仍保持暂停。

`Status` 回报固定方向；`WaitPointer` 可不预知 MessageId，从 `AfterSequence` 等待、
验证、保存、ACK 并返回下一条合法 pointer；`PublishPointer` 只写角色固定 lane。
前台 Wait 不调用 Git wake，也不执行 payload。control repos 保存正文/envelope/审计，
relay 只传 pointer。宿主机唯一写产品代码；VM 只读产品仓库、执行测试和回传不可信
建议。Host/VM foreground DPAPI credentials 已准备，VM deploy key `158030457` 仅注册到
VM-to-host control repo。旧 room lane 为 4/2；不改变 auth environment/secret 的干净
`RELAY_ROOM_EPOCH=2` 已部署并精确回读，新 room 从 sequence 0 开始。下一步由两对话完成公网双向、错方向、
断线 resume、payload 不执行和 secret scan canary。本轮结果不是 P10A/P10B/P11 或发布依据。
前台 control repo body 使用固定 `CDDsi_FOREGROUND_CONTROL_V1`；它只含枚举状态、精确
product commit 和可选 evidence path/hash，不含自由文本、命令、脚本或 prompt。

## 暂停前实现快照（历史；不可执行）

截至 2026-07-19，本仓库已经实现 Fast Lane 的宿主机侧基础合同与大部分 runtime：
`lib/vm-test-relay.ps1` 提供 canonical JSON、hash、envelope/state/transition 的纯函数
合同；`lib/vm-reset.ps1` 提供 fake/TestSafe/DryRun 的 ownership、baseline、plan、
receipt 与 fail-closed reset 合同；`lib/vm-fast-lane-readiness.ps1` 分开计算 VM
bootstrap、integration、P10A-0A 和 Formal readiness；`operator/fast-lane/` 提供固定 Git
outbox runner、deterministic onboarding builder、VM-only reset dispatcher/provider
boundary、两端轮询模板、runbook 与本地双 outbox synthetic rehearsal。它们都属于
DevelopmentOnly 的 operator coordination material，不由默认 bootstrap 加载，也不进入
Release ZIP。当时一文件/一提示 bootstrap 仍是未提交的收口工作：phase2 行为测试、
phase2-only builder/loader、execution boundary、HostSandbox path binding、semantic ACL、
captured-byte loading、atomic/idempotent state 和 explicit-stack cleanup 均已落盘，并已通过
dirty WIP 的标准 HostSandbox 双引擎全树门，各 448/448 且全部顶层零指标为 0。该结果不是
clean exact commit、bundle、automation 或 CI finalization，不能把 bootstrap、Fast Lane 或
无人值守通信写成已通过。

public 产品 remote 与两个 public control repository 已部署，产品旧 `main` 基线已推送，
两个 `outbox/` 已初始化。三个无 bypass protected-history ruleset 已对目标 refs 实际施加
禁止删除、禁止非快进和线性历史。暂停前计划要求宿主最终实现从 clean exact commit 生成
immutable diagnostic onboarding ZIP；当时工作树 dirty、没有新 final anchor，四个
readiness/complete 标志均为 false。暂停前规则曾要求最终 clean HEAD 通过双引擎全树门、
Release DryRun、immutable onboarding bundle 自校验、暂停 heartbeat binding 与
remote/PR/CI 核验后，才由四方事实考虑 bootstrap-only readiness。该派生规则现已由顶部
controlled pause 覆盖：即使未来四方事实再次一致，也必须先有新的显式恢复决定、完整
finalization 和新 readiness receipt，不能自动变为 true。

在未来获准恢复的合同中，四方核验仍是宿主机 finalization 的职责，不是 VM bootstrap 步骤。
VM 不读取也不核验
宿主机 retained path、automation、PR/CI、worktree 或 remote；它只消费宿主机最终提示词
带外给出的 ZIP SHA-256/length、product commit/tree、manifest/inventory binding token 和
content digest，再校验本地唯一 ZIP 的外层与内部绑定。
窄 HostCoordinator/VmTester credentials、runtime protection assertion、VM 只读身份及
负向写验证、VM reset 设备信任/实测、VM task、安全启用和无人值守闭环仍未完成，所以
`CanStartVmIntegration=false` 且 `P10A0AComplete=false`。暂停前宿主机 heartbeat 已创建并保持
暂停；后续 tracked edits 会使旧 prompt/bundle binding 失效。若未来显式恢复，必须在新的
最终 clean commit 后原位更新；VM task 也只能从 VM 设备创建且初始暂停。Formal Lane 的 CAS、签名
和外部 snapshot supervisor 也未实现，所以 `CanStartFormalP10A=false`，不能开始真实
P10A/P11。暂停前合同曾把普通 VM 启动与 Formal clean-snapshot receipt 分开；当前 controlled
pause 下用户不得启动 guest、运行 ZIP 或继续 bootstrap，不能把该历史区别读成执行许可。

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

- 一个逻辑 control plane，由两个物理单向 public protected repository 组成；
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

### 本地实现中的 realtime accelerator（Fast Lane only）

为减少 minute polling 和人工搬运带来的反馈延迟，当前独立工作流已在本地实现 Fast Lane
Cloudflare realtime notification accelerator 的离线源码：独立 sibling workspace 中的
Cloudflare Worker、SQLite-backed Durable Object 与 WebSocket Hibernation，以及产品仓库
DevelopmentOnly operator plane 中的纯 PowerShell 客户端。完整协议、威胁模型、授权点和回滚见
`REALTIME_RELAY_PROPOSAL.md`。当前状态严格为 `LOCAL_GATES_PASSED /
EXTERNAL_AUTHORIZED_FREE_ONLY / AUTHENTICATED_READ_ONLY /
BILLING_DASHBOARD_REVIEWED / WORKERS_PAID_NOT_LISTED /
VM_RELAY_READY / PROVISIONED / CROSS_DEVICE_SMOKE_PASSED /
FOREGROUND_RUNNER_LOCAL_TESTED / HOST_FOREGROUND_CREDENTIAL_READY /
VM_FOREGROUND_CREDENTIAL_READY / VM_DEPLOY_KEY_REGISTERED /
CLEAN_ROOM_EPOCH_DEPLOYED / FOREGROUND_CANARY_PENDING / NOT_PRIMARY /
AUTOMATION_PAUSED`；用户已授权
Free-only 外部门 1–7 项，并在知悉 scope 超集后明确允许直接复用既有 encrypted keyring
`default` OAuth profile；真实精确 infra root 的 binding-absence proof、owner-marked adoption receipt
与 GET-only preflight 已完成，脱敏 Dashboard 人工核对也已完成。Free-only endpoint
`https://cddsi-realtime-relay.lizixuan6383828.workers.dev`、Worker、SQLite-backed Durable Object、
两项 secret binding 与 postdeploy 精确回读已经存在；Host HTTP 与跨设备双向 relay-only smoke
均通过且未记录 secret。生产 WebSocket reconnect/Hibernation 仍缺真实公网 E2E，所以 relay
不是主路径，也不允许自行激活持久 watcher/automation。

该 accelerator 只传两条方向隔离 lane 的 12-field 固定 schema 通知及 immutable payload
pointer：`host-to-vm` 与 `vm-to-host` 使用两个独立身份和相反读写权限。请求用
`CDDsi-HMAC-SHA256-v2` 绑定 audience、environment、key id、client id、method、canonical target、
timestamp、nonce 与 body SHA-256；sequence、previous hash、TTL、全局 MessageId 去重、逐消息
ACK、重放防护与速率限制必须在本地固定 validator 之前全部通过。Cloudflare 公网 URL、
WebSocket 连接或 Worker 自报角色都不是 sender authority。reader watcher 与 writer publisher
使用分离的 context、runtime assertion 和相反 lane ACL；publisher 在网络前原子保存规范 pending
body，响应丢失、重启或 TTL 已过时只重发相同 bytes/MessageId，只有精确
`PUBLISHED`/`PUBLISHED_IDEMPOTENT` 回执才能推进本地 sequence/hash。watcher 只能唤醒固定入口，
绝不能解释或执行 relay/free text。

两个 public protected Git control repositories 继续是 durable source、持久审计链和断线
fallback。大日志、截图、报告与 Formal evidence 不通过 WebSocket 携带；只在 CAS/control
repository 中保存不可变对象或引用。现有一分钟 polling 保留为断线兜底，不能因 realtime
通道可用而删除、放宽或共享 credential。VM 客户端只使用 PowerShell 7
`ClientWebSocket`；可共享的 parser/schema/security helper 已由 PowerShell 7 与 Windows
PowerShell 5.1 的同一 focused suite 验证。Wrangler/Node 只允许存在于独立 sibling infra
repository，不能进入产品仓库或 VM runtime。TestSafe/DryRun 使用 fake
transport/credential/state/wake provider，真实 network、
registry、credential、process、outside-sandbox 与 unexpected-ledger 指标必须全部为 0。

固定 wake 先让 Git outbox `Poll` 验证精确 repository/ref/commit/MessageId/payload hash，再原子
记录 `PENDING` proof；随后只允许绝对路径且 hash-bound 的 `codex.exe` 执行固定
`exec resume --json <fixed-session-uuid> <fixed-prompt>`。relay/model/report 正文不得进入 prompt、
argv、environment、executable 或 working root。进程使用 job object、空 stdin、固定 timeout、
无继承 PATH/proxy/token 的最小环境及有界输出 drain；exit code 0 和 runtime assertion 复验后才
把 proof 提升为 `SUCCEEDED`，然后持久化 watcher state 并 ACK。匹配的已成功 proof 不重复
spawn；exit 后、proof commit 前崩溃允许同一固定任务 at-least-once 重试，因此固定 inbox handler
必须幂等。该未来 Live operator Codex spawn 只记作 operator-plane 指标；产品 process 指标仍为
0，全部离线 TestSafe/DryRun focused tests 的真实 process 指标也必须为 0。

该提案不改变 Formal Lane：P10A/P11 仍要求外部 snapshot receipt、独立 CAS、签名和正式
validator；P12 仍需人工确认，禁止自动 merge、release 或 promotion。

### 已暂停的一次提示 bootstrap 入口

以下只保留历史目标接口，不是当前操作步骤，也不是 realtime relay 的 provisioning 路径。
普通用户原目标只做四件事：用普通 VM 软件启动 disposable VM，在 VM 中安装并登录 Codex，
把宿主机交付的唯一 onboarding ZIP 放进新建空文件夹并让 Codex 打开，最后只粘贴一次
宿主机最终提示词。用户不手动解压、算 hash、生成密钥、运行 PowerShell/Git 或配置 task。

该用户流程是目标接口，不表示当前可以执行。prepared VM baseline 必须已有 manifest v3
精确固定的 Git、OpenSSH、`ssh-keygen`、PowerShell 7 和 Windows PowerShell；历史
bootstrap 合同只验证，不下载或安装。普通全新 Windows VM 若缺工具必须在持久写入前返回
稳定 blocker。若要把工具安装也自治化，必须另行取得用户对 bootstrap-time network/
install 的明确授权，并固定来源、hash、签名、路径和清理合同。

最终 prompt 先做唯一 ZIP 的零写入 outer length/hash preflight，再以 Codex 自身受控文件
编辑能力写入并校验固定 loader。loader 只加载 manifest/inventory 绑定的 runtime。operator
的唯一带副作用目标入口是 `Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding`：调用者只提供
原始 ZIP、11 个宿主机外部锚、固定 roots、`CodexHome` 和 acknowledgement；入口内部重跑
package/onboarding 校验、读取真实本机 Codex automation TOML 并构造 public handoff。
调用者不得提供 result、automation prompt、observation、`ObservationJsonBase64` 或派生目录。
direct core、direct handoff、mutation helper 与 failure helper 都不是 operator API，必须
fail closed。相同 binding 可幂等复验；冲突、重复 task、路径或 hash 漂移一律
`VM_BOOTSTRAP_BLOCKED`，不得临时拼替代命令。

bootstrap runner 与 minute poll task 权限不同。前者由用户显式发起，outer hash/length
匹配后只可创建 owner-marked VM-local state、用五个固定工具校验并生成三组
`KEYPAIR_STAGED`，以及通过 Codex automation 能力创建或更新唯一的一分钟 `PAUSED` VM task。
phase2 只信任写入固定 `CodexHome` 后的真实 automation TOML readback，不接受对话或调用者
拼出的 14 字段 observation。minute poll task 在 runtime protection assertion/hash/token 仍
`UNPROVISIONED` 时必须零 network、零 Git、零 credential probe、零 runtime-state write。
phase2 在本地 staging 后无论初扫为零还是一都重扫；初扫为零但重扫出现任务、重扫重复或
无效时必须补偿本轮自有 roots 并阻断。成功 readback 只证明由持有句柄绑定的该时点 TOML
字节，不声称阻止外部行为在返回后修改 automation；每次 Handoff 都必须在 task 保持
`PAUSED` 时重新扫描和 readback。
本地 runner 先返回 `VM_BOOTSTRAP_LOCAL_STAGED`；task readback 后才输出 public redacted
`VM_BOOTSTRAP_STAGED` 并停止。密钥注册、真实正/负向权限、poll/reset/test 都属于后续
integration，不得在本次继续。

这段目标入口已经被 controlled pause 明确冻结。即使 phase2 正负测试、旧 surface 收缩、
execution boundary、phase2-only builder/loader、existing-root ACL、captured-byte load、
atomic/idempotent state 和 no-reparse 非递归 cleanup 曾在其绑定提交通过，也不得继续执行。
未来若恢复，必须从新的最终 clean commit 重跑完整 finalization、重新生成 bundle、重新原位
绑定仍暂停的 automation，并生成新的 readiness receipt。

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
Human 与 HypervisorSupervisor 是 relay 外部的决策或 receipt 权威，不是 Git
transport sender。dual outbox 只认证 HostCoordinator 与 VmTester；relay 中出现的
`SenderRole` 不能证明人工决定或 snapshot receipt 的权威性。

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

产品代码使用 public protected Git remote `LXZ56156/claude-desktop-deepseek-installer`，本轮 repair
ref 是 `codex/repair/p10a-0a-fast-lane`。宿主机最终只能向受保护的 repair branch 推送，
VM 使用独立只读 deploy key 或等效细粒度凭据。产品 ruleset `19068339` 已对 `main` 与
`codex/repair/*` 实际施加历史保护；角色凭据与 runtime assertion 仍未满足，交互式
bootstrap admin 不得交给 automation。
onboarding manifest 另绑定产品 repository numeric ID/node ID、精确 commit/tree 与固定
Git 工具 hash；显示名或 remote URL 不能单独替代身份验证。

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

Fast Lane 冻结为“一个逻辑双 outbox、两个物理单向 public protected repository”：
`LXZ56156/cddsi-host-to-vm` 与 `LXZ56156/cddsi-vm-to-host` 已创建并初始化。两个 repository
都与产品代码 remote 分离；该拆分是实际权限边界，不是部署细节。两端 Codex automation
最终通过出站轮询消费各自 inbox，正常路径无需用户逐轮搬运文件：

- `host-to-vm` repository 只允许 HostCoordinator 追加，VmTester 只读；
- `vm-to-host` repository 只允许 VmTester 追加，HostCoordinator 只读；
- 已发布消息不可改写、删除、force-push 或复用 `MessageId`；
- 每个方向的提交绑定 repository identity；RelaySupervisor 以原子 CAS 维护唯一 active
  cycle 和下一合法 sequence；
- 消费者只出站轮询，不开放从外部直接进入宿主机或 VM 的控制端口。

固定 outbox runner 只接受 onboarding/policy 绑定的 repository numeric ID、node ID、
`refs/heads/main` 与 pinned genesis；每次 poll/append 还需当前且未过期的 protection
observation、精确 Git/SSH/key/known-hosts hash、owner-marked local state/lock，以及线性
fast-forward history。它限制单轮消息数、运行时和输出大小，清空继承的 credential/
askpass/SSH 环境，并终止超时进程树。payload、日志和自由文本永远不进入命令行。

protection observation 不是信任锚。runner 同时要求位于独立 operator workspace 的
`control-protection-trust` owner marker、当前 receipt-specific authority assertion、
由外部 provisioning 固定的 assertion SHA-256 与 authority-binding token。assertion
精确绑定 repository numeric/node identity、ref、policy、observation hash、receipt ID、
有效期和 previous-receipt hash；receipt/state/relay 不能提供调用方的 expected 值。轮换
时先暂停两端任务，再 provision 新 assertion 与 task hash/token binding，验证单调链后
才能恢复。
GitHub 三个官方 SSH host key 固定在 DevelopmentOnly 的
`operator/fast-lane/trust/github-known-hosts`；policy、inventory 与 manifest 交叉绑定其
SHA-256，并独立固定 Git、OpenSSH、PowerShell 7 和 Windows PowerShell。设备本地 deploy
key 的 hash 只能来自 provisioning receipt 和暂停任务绑定，不能来自 relay payload。

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
| `SNAPSHOT_READY` | HostCoordinator | 仅在独立外部核验后转发 snapshot receipt 的 hash 与 supervisor authority binding |
| `CLEAN_READY` | VmTester | 提供 guest reset receipt，或核验并绑定 snapshot receipt |
| `TEST_STARTED` | VmTester | 声明全部前置核验通过并开始固定 runbook |
| `TEST_RESULT` | VmTester | 回传 PASS/FAIL/BLOCKED 与 evidence 引用 |
| `HOST_ACK` | HostCoordinator | 声明结果已验真、已接收或已拒绝 |
| `FIX_READY` | HostCoordinator | 冻结新 commit 和新校准包/新 P10B candidate |
| `STOP` | HostCoordinator | 转发已在本地建立的 Human/HypervisorSupervisor 停止决定，不授权隐式恢复或继续 |

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

宿主机已实现该流程的 pure/fake 合同、VM-only dispatcher/provider boundary、精确五类
resource descriptor、device/command trust policy、preflight/postcondition/action receipt
binding 和 fail-closed escalation。onboarding bundle 只交付固定代码与 hash，不携带
device private key，也不证明具体 VM 已 provision。实际 provider/device attestation、
synthetic owned-resource mutation、idempotence 和 clean receipt 必须在 disposable VM
完成 `reset-smoke.md` 后才能记为 `VmResetReady`；宿主机和 CI 不得进入该 Live 路径。
外部 supervisor 还必须为每次执行签发 SYSTEM-owned one-shot anchor/grant pair。anchor
绑定 VM/image、consumer SID、grant id/path/hash、execution nonce 与全部 trust/input；
grant JSON 绑定 nonce、cycle/policy/plan/ownership/resource/control-auth/time。provider
在注册 runtime 前独占验真并原子删除 grant，且 supervisor ACL receipt 必须证明 consumer
不能在父目录 create/replace；provider 同时验证该目录由 SYSTEM 拥有且没有非受信 mutation
ACE。每次 Live（包括幂等复跑）都用全新的 pair；进程内 consumed map 或可重写文件不能
充当跨进程 one-shot 证据。

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

HypervisorSupervisor 在 relay 外生成 receipt。独立 verifier 必须通过不来自 relay
message 的受保护路径，向 consumer 提供预期 snapshot receipt SHA-256 与 supervisor
authority-binding token。HostCoordinator 只能在这两个外部值已经建立后通过
`SNAPSHOT_READY` 转发 receipt 引用；VmTester 必须同时核验消息与外部预期值、并确认
其与 `TEST_REQUEST` 一致，再生成引用该 receipt 的 `CLEAN_READY`。`SenderRole` 与
payload 内的自我声明都不能替代外部权威核验。无法验证时返回 BLOCKED。snapshot
restore 后仍可清理本轮新建的 owner-marked 目录，但不得把该 guest 清理当成
snapshot receipt 的替代。

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

正常通信路径是两个单向 public protected control repository 组成的逻辑双 outbox 与两端自动监控，
不需要用户逐轮复制请求、结果或 `FIX_READY`。两端只对已验证的新 message commit 作出
反应。当前 canonical/schema/state validator、固定 Git outbox runner、readiness、
deterministic onboarding、VM-only reset boundary、两端 prompt/runbook、synthetic dry
rehearsal 与真实 public protected repository pair 已实现。宿主机 finalization 与文档闭环
是否 bootstrap-only ready，按本文开头所述由 clean HEAD 的外部状态核验，不由本文自证。
服务端 protected history 已完成；最小凭据、runtime assertion、VM device/provider evidence、
VM task 安全绑定、启用 host heartbeat
和无人值守验收仍是外部 integration 工作，不能直接在现有宿主机进入产品 Live。

### Codex automation

这里的分钟级 Codex automation 是产品之外的 operator coordination 机制，不是安装器
创建、枚举或管理的 Windows Scheduled Task，也不得进入产品 provider 或 Release。它
不会授予 operation grant，不会扩大宿主机权限；宿主机 automation 永远不得执行产品
Live。`operator/fast-lane/prompts/host-poll.md` 和 `vm-poll.md` 是固定模板；宿主机
heartbeat `cddsi-fast-lane-hostcoordinator-minute-poll` 已按分钟创建；服务端 protected
history 已就绪，最终 bundle hash binding 必须从四方持久事实外部核验。即使 binding 匹配，
它仍须在 runtime assertion 与窄凭据就绪前保持暂停。本机 Codex 没有 VM project，VM task 必须从 VM
设备创建并先保持暂停；policy/onboarding manifest 冻结两端初始状态为 `PAUSED`。
bootstrap 阶段的 protection assertion/hash/token 明确标为 `UNPROVISIONED`，因此任务
只能 fail closed，不能轮询。bootstrap 只允许 bundle 校验、VM 本地 key provisioning、
工具 hash 回报和 paused task staging；它不允许轮询 control ref 或运行产品测试。
VM 必须生成三把不可跨库复用的 repository-scoped key：product read、host-to-VM read、
VM-to-host append；单一 deploy key 不能覆盖这三个物理仓库。
当前未完成两端无人值守证明。

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

若 minute-based polling 的延迟过高，realtime watcher 只消费已通过 relay schema/chain/TTL
验证并经 control-repository `Poll` 二次绑定的 pointer。它不会从 relay 或模型文字选择命令；
唯一 live effect 是上节所述 hash-bound absolute `codex.exe`、固定 session UUID、固定 prompt 的
`exec resume --json`。不存在 caller-selected `codex exec` 参数、任意 output schema 或泛化分析
runner。模型输出仍只是不可信建议；产品或系统操作继续由各自独立 allow-list/grant 控制。

分钟轮询和 realtime fixed resume 都必须提供：单实例锁、最大运行时、重试上限、输出大小上限、
消息去重、审计日志脱敏、STOP 处理和人工接管。固定 Git runner 与 realtime wake-proof 已实现这些
bounded contract；
服务端 protected history 已部署；凭据发放、runtime assertion、VM device provisioning、
两端 paused task 的安全启用和
unattended acceptance 仍属于外部 operator 工作，不改变产品 Live 授权边界。
任何 protection receipt rotation 都要求先暂停 task、外部更新 authority assertion 与
固定 hash/token，再恢复；不得把观察到的新 receipt 当作新的信任配置。

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

## 实施前置与完成判据（历史阶段合同；当前全部暂停）

以下阶段门保留长期安全关系，但不授予当前执行许可。controlled pause 期间不得据此启动
bootstrap、integration、P10A 或 P11；任何恢复都需要新的显式决定、完整 finalization 和 receipt。

### P10A-0A Fast Lane MVP

暂停前计划先用最小基础设施打通高效率日常闭环：

- 配置 public protected 产品 remote、repair branch protection 与 VM 只读身份；
- 创建两个单向 public protected control repository：`host-to-vm` 仅 HostCoordinator 写、VM 读，
  `vm-to-host` 仅 VM 写、HostCoordinator 读，并禁止 force-push 和历史改写；
- 实现 canonical schema、CycleId、sequence、previous hash、单 active cycle 和 STOP；
- 配置宿主机与 VM 的 minute-based Codex Scheduled Tasks；
- 实现 frozen allow-list guest reset runner、baseline validator 和 `CLEAN_READY` receipt；
- 用纯 synthetic payload 演练 PASS、FAIL、BLOCKED、修复、P11 候选重建和重测；
- 证明 VM 无产品 write、宿主 control credential 无 merge/release、secret scan 为零。

完成这组 dry rehearsal 不以 WORM CAS、独立 message signing 或 hypervisor receipt
已经部署为前置；Fast Lane report 明确为 diagnostic。可选 watcher/`codex exec resume`
也不是 MVP 阻塞项。

暂停前曾完成本地合同、固定 outbox/runtime、readiness、deterministic onboarding、
VM-only reset boundary、prompt/runbook、纯 synthetic rehearsal，以及三个 public protected
repositories 与两个 `outbox/` 的 bootstrap。暂停前规则曾在 retained owner-marked bundle
output、暂停 automation、既有 PR/CI 与实际 Git/remote 四方事实全部匹配后考虑
bootstrap-only readiness。该自动派生规则现已失效；未来即使重现同类事实，也仍需新的显式
恢复决定、完整 finalization 和新 readiness receipt。四方事实仍由宿主机完成并压缩为外部
expected binding；VM 无需也不得复查宿主 retained path/automation/PR/CI/remote。只有未来
新 receipt 授权时，才允许 VM 离线校验、
owner-marked local staging、三组 `KEYPAIR_STAGED`、工具 hash 回报和从 VM device 创建或更新
唯一 `PAUSED` minute task。读回通过后输出 `VM_BOOTSTRAP_STAGED` 并停止。

三个 active ruleset 已验证 protected history；narrow credentials 与 runtime assertion
尚未满足，因此 `CanStartVmIntegration` 必须保持 false。remote credential 负向测试、
VM reset 实测、两端任务安全启用和 unattended 闭环也尚未满足；`P10A0AComplete`
仍为 false。Formal Lane 的 snapshot/CAS/signature/receipt evidence 尚未满足，
`CanStartFormalP10A` 仍为 false；暂停前合同不把这些 Formal evidence 作为 bootstrap 前置，
但当前不存在可执行的 bootstrap。

用户选择用 GitHub Free public repositories 代替 Pro，并接受现有 history/metadata 和未来
public outbox 可见性、不重写历史；剩余存量审计为 accepted risk。public-safe schema、
禁止 secret 内容、PUBLIC policy/readiness/outbox receipt/onboarding/prompt/runbook/tests
及正负向合同已在切换前升版。三仓现已 public，ruleset IDs 为产品 `19068339`、
host-to-VM `19068292`、VM-to-host `19068313`。

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

首次 P10A 不是 guest-reset smoke：外部 hypervisor supervisor 必须先恢复请求绑定的
clean snapshot 并签发可验证 receipt，Formal Lane 还必须验证独立 CAS 和角色签名。
任何 Fast Lane PASS、control repository commit 或 onboarding hash 都不能替代这些门。

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
