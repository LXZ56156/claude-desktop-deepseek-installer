# 新任务交接

更新日期：2026-07-24

## 当前动态状态（唯一入口）

**MANUAL_HOST_VM_REPORT_TRANSFER_ONLY / RELAY_RETIRED /
AUTOMATION_PAUSED_OR_ABSENT / VM_BATCH_RETEST_PARTIALLY_VALIDATED_FAILED /
VM_EVIDENCE_MANIFEST_PARTIAL / PRODUCT_DEFECT_ZERO /
HOST_TEST_DEFECT_REPAIRS_VALIDATED / VM_RETEST_REQUIRED /
VM_STANDARD_TEMP_ROOT_CORRECTION_REQUIRED / NO_PRODUCT_LIVE_AUTHORITY。**

2026-07-24 已接收用户人工拖回的第三份 minimal H02/full-quality
`VM_BATCH_TEST_REPORT_V1` 详细报告。附件为 18867 bytes，SHA-256
`7493505c3ed0cbf2547b1f7af9811bfe5230eafec51cc5cd2816285a331fc1f8`；
其 commit `f1f5525b142e3ec8c0c195b163c6d8f76dd378a3`、tree
`e8b87a3d0b063d7120f6b0b79c900cc993ceaf71` 与接收时本地、upstream、
remote 和 PR #1 head 精确一致。冻结 H02 源文件 hash 也一致，报告中的 25 项
repo-relative path/source line/静态 `It` 名称全部重新绑定 AST，未截断。

这份附件没有原始 `quality-failure-v3.json`、validation 文件、canonical manifest
envelope/整体 hash，也没有完整 aggregate/PS5.1/timeout injection/Release DryRun；
用户先前搬回的 18 项 TSV 只能逐项交叉绑定 length/hash/path。因此 external evidence
consistency 只能记为 `PARTIAL`，aggregate 零指标仍是 null，不能声称完整 VM gate 或
完整 evidence manifest 已通过。

第三份报告和宿主机独立复现的分类结论：

- `PRODUCT_DEFECT=0`。25 项 H02 不是 25 个产品缺陷，而是同一个 `BeforeAll` fixture
  Git push 在 VM 批处理器深层 `TEMP` 中触发 `Filename too long`；产品断言未到达，
  此前 keygen mock/ACL 的静态猜测已被排除。
- Git fixture 漏掉接收端 bare repository 的长路径配置属于 `TEST_DEFECT`。宿主机在
  141 字符 owner-scoped synthetic `TEMP` 精确复现后，为每个 Git 命令固定
  `-c core.longpaths=true`，并只在 owner-marked bare fixture 的 local config 写入
  `core.longpaths=true`；不读取或修改 system/global Git config。
- safe failure 脱敏只识别反斜杠、却放过 Git 输出的正斜杠 VM 私有路径，属于第二个
  `TEST_DEFECT`。路径 token 现对正斜杠、反斜杠和混合分隔符做
  culture-invariant/ignore-case 等价匹配；`tr-TR`、PS7 和 WinPS 5.1 回归均覆盖。
- 在同一人为深层 `TEMP` 跑完整 H02，会在固定
  `CDDsi\FastLane\packages|credentials` 产品合同路径继续触发 MAX_PATH；缩短这些
  安全绑定名称会正确 fail closed，不能作为修复。该项保持 `ENVIRONMENT_BLOCKER`：
  下一轮 VM controller 必须让标准 `scripts/check.ps1` 使用正常 OS temporary root，
  不得把 `TEMP/TMP` 再嵌进 evidence run-root；标准门自身会创建、记账并清理
  owner-marked HostSandbox。
- cleanup 后未另存完整 H02 role evidence 仍是 `NOT_IMPLEMENTED` 诊断增强；outer v3
  已携带 source-bound 失败摘要，不把未实现项冒充本轮缺陷。

本轮不恢复或调用任何 relay/Cloudflare/Automation 路径，不改产品公开函数、release
文件集合或安全断言。宿主机 focused PS7/WinPS 5.1 脱敏/证据合同为 39/39，额外的
双引擎 `tr-TR` source-bound 窄回归为 3/3。一次标准门尝试在 WinPS 5.1/H02 的
`rejects duplicate IDs and tampered payload text without executing it` 第二次
`git commit` 打开 fixture `.git/index` 时遇到一次 `Permission denied`；同一 index
此前的 commit、pull 和 add 均成功，前序 ACL 测试尚未执行，且 bare longpaths local
config 不引用 writer index。该目标测试随后在三个独立 WinPS 5.1 进程中 3/3，完整
WinPS 5.1 H02 为 25/25，因此现有证据只支持一次性环境占用候选；没有据此猜改 ACL、
加入 retry、放宽 timeout 或降低断言。

最终标准双引擎 gate RunId
`c94f68bf-8b55-49e9-9d7f-8f9cfde5edef` 在 PS7/WinPS 5.1 各通过 617/617，
31/31 trusted processes 与 68 条 harness ledger 精确，cleanup 成功、仓库快照未变，
所有真实访问、越界写入、secret、意外 ledger 和 mutation 指标为 0。30 秒 timeout
injection RunId `00937ad2-26e5-4511-9dc8-d5b1d820e134` 在 PS7 static worker
以 `QUALITY_WORKER_TIMEOUT` fail closed；没有断言失败，cleanup 成功、
`RepositoryContentChanged=false` 且 safe disclosure 通过。Release Simulation
DryRun 通过 39 个 package files，四层 secret findings 为 0，inventory/hash/
deterministic ZIP 精确且 `Changed=false`。提交门只接受在本段事实写入后的最终
tracked bytes 上再次通过标准 gate、timeout injection 和 Release DryRun，不得用较早
运行替代。

2026-07-23 已接收第二份用户人工搬运的 `VM_BATCH_TEST_REPORT_V1`。报告精确绑定
commit `d808a18db63361fd76f61efd63379eeef1475fee` 和 tree
`fb19143c0e3fe6e133733bd55b274f20138b3ced`，与宿主机接收时 HEAD/tree 一致。
18 个场景满足
`8 passed + 1 failed + 3 blocked + 2 expected fail-closed + 4 not implemented`，
11 个 executed 满足 `8 + 1 + 2`。附带 canonical manifest 正文实际为 4911 UTF-8
bytes，重新计算 SHA-256 为
`9763c6a68ecee87059c7ba49fd98db5c7030a7f7c6a0448d9397ad4206c6fbdb`，
与报告一致；其 RunId/commit/tree、30 个 entry 和 Issues 引用内部一致。宿主机未取得
VM-local 30 个文件字节，因此只证明搬回 manifest 正文绑定，不声称逐项重新哈希。

第二份报告分类结论：

- `PRODUCT_DEFECT=0`。六个 wrapper 均以 exit 4 返回完整四字段；两个 Live negative
  均为 `EXPECTED_FAIL_CLOSED`。
- `TD-002` 为 `TEST_DEFECT`：PS7/H02 报告 aggregate `Failed=3`，但旧 worker evidence
  未保留失败测试名；报告列出的 keygen mock 与 ACL readback triplet 都只是静态假设。
  宿主机同文件 focused 为 25/25、完整门双引擎也通过，不能据此猜改 mock 或削弱 ACL。
- `TD-001` 为 VM 批处理器自身的 `TEST_DEFECT`：一项辅助 Git status 未显式抑制
  system/global config；它不命中产品仓库文件，由下一轮 VM harness 修正。
- lifecycle、完整 HTTP fault、GUI/UAC、真实多进程仍是 `NOT_IMPLEMENTED`；真实
  GUI/system baseline 是 `REQUIRES_EXTERNAL_SNAPSHOT`。

本轮只修已证实的诊断合同缺口：Pester shard evidence 升为 schema v2，measurement
rules 升为 v4；非超时失败最多保留 32 项 repo-relative path、source line 和静态
`It` 名称，worker 与父进程各自重新绑定 tracked AST。外层
`CDDSI_SAFE_FAILURE_EVIDENCE_V3` / progress schema v2 在报告中携带当前失败项，
禁止任意 runtime/error 文本进入结构化清单。相关 focused tests 为 58/58。

最终标准门发现并在 PS7 与 Windows PowerShell 5.1 各通过 617/617，精确为 31 个
trusted process、68 条 harness ledger，cleanup 成功、仓库快照未变、所有真实访问/
secret/意外 ledger 指标为 0。30 秒 fault injection 在 `PowerShell7/C02` exit 1，
保留 2 个已完成 worker、5 个 test files、51 个通过断言，failed-test count 为 0，
cleanup 成功、`RepositoryContentChanged=false` 且无 U+FFFD。Release Simulation
DryRun 通过 39 个 package files，四层 secret findings 为 0，inventory/hash/
deterministic ZIP 精确且 `Changed=false`。PR #1 head/CI 在最终 commit push 后核验，
不在 tracked 文档中自引用尚未生成的 commit/tree。

realtime relay、Cloudflare、WebSocket watcher、control-repo 实时消息、Codex
Automation、scheduler、`codex exec resume`、旧 onboarding ZIP、foreground canary、
VM bootstrap、automation binding 和 relay finalization 已全部废弃。不得调试、恢复、
部署、调用或依赖，不得再要求用户搬运通信凭据。Automation 永远保持
`PAUSED`/`ABSENT`，也不再做 readback。当前唯一闭环是用户人工搬运完整 VM 报告和
宿主机生成的一段完整重测提示词；宿主机仍是唯一产品代码写入者，VM 只读。

## 2026-07-22 relay 动态状态（历史；已退役，无操作权）

**LOCAL_GATES_PASSED / EXTERNAL_AUTHORIZED_FREE_ONLY /
AUTHENTICATED_READ_ONLY / BILLING_DASHBOARD_REVIEWED /
WORKERS_PAID_NOT_LISTED / VM_RELAY_READY / PROVISIONED /
CROSS_DEVICE_SMOKE_PASSED / FOREGROUND_RUNNER_LOCAL_TESTED /
HOST_FOREGROUND_CREDENTIAL_READY / VM_FOREGROUND_CREDENTIAL_READY /
VM_DEPLOY_KEY_REGISTERED / CLEAN_ROOM_EPOCH_DEPLOYED /
FOREGROUND_CANARY_PENDING / NOT_PRIMARY / AUTOMATION_PAUSED。**

2026-07-22 用户已冻结 D-024：当前旧 Host/VM 对话只做公网 canary；通过后由宿主机与
VM 两个新 Codex 对话接管有界前台 relay cycle，不使用 Codex Automation、scheduler 或
`codex exec resume`。
DevelopmentOnly `invoke-foreground-cycle.ps1` 已实现 `Status`、`WaitPointer` 和
`PublishPointer`；本地 fake transport/方向/重连/ACK-loss replay/CLI fail-closed/
non-execution 测试在 PowerShell 7 与 Windows PowerShell 5.1 均为 12/12。纯
`CDDsi_FOREGROUND_CONTROL_V1` validator 测试在两引擎均为 60/60；PowerShell 7 连同
operator boundary 的 focused tests 为 85/85。
本轮最终字节的完整 HostSandbox gate 在 PowerShell 7 与 Windows PowerShell 5.1 均发现并
通过 605/605；Release Simulation DryRun 通过 39 个 package files，四层 secret findings
均为 0、inventory/hash 精确且 `Changed=false`。
Wait 可在不知道下一条 MessageId 时返回角色固定 read lane 的下一条合法 pointer，
不会调用 wake 或执行 payload。Host/VM 当前用户的 foreground DPAPI credentials 均已
准备；VM deploy key `158030457` 只注册到 `cddsi-vm-to-host`，产品仓库和
`cddsi-host-to-vm` 均无匹配。旧 Durable Object lane 已在手工 smoke 推进到 4/2；
`RELAY_ROOM_EPOCH=2` 的干净逻辑 room 现已部署，且未改变 auth environment/runtime
secrets。Cloudflare active-version 精确回读通过，新 room 两条 lane 均从 sequence 0
基线开始。下一步由两个前台对话完成
WebSocket 正负向测试。现有 automation 继续 `PAUSED`，VM automation 可保持 `ABSENT`，
task readback 不是门。这不是 P10A/P11，也不授权产品 Live、自动 merge、release 或 promotion。

独立 infra 精确本地提交为 `42424472a5b7d685486db0ae3cab0b6817333dcb`、tree
`b0df22cf01fd09a27a32a876cfb740a63662395e`。固定版本 Wrangler 复用 encrypted-keyring
`default` profile；因旧 OAuth token 无法 refresh，用户在个人 Edge 完成一次明确授权，随后
generation-3 adoption renewal、epoch update 和 postdeploy readback 均成功。endpoint 仍为
`https://cddsi-realtime-relay.lizixuan6383828.workers.dev`，两项 runtime secret binding 未变。

control repos 继续保存正文、不可变 envelope 和审计历史；relay 只传 pointer。宿主机
仍是产品代码唯一写入者，VM 只读产品仓库并负责测试、分析和回传不可信建议。

2026-07-21 用户已冻结 D-022：realtime relay 以尽快打通 Host/VM 通信为
首要目标，控制与现实风险成比例。machine Billing receipt/ticket、coordinated
DPAPI provisioner/receipts、bulk semantics 与 two-secret staging receipt 不再阻断
Free-only Worker/DO 部署或一次性手工 relay-only VM smoke。一次性 smoke 可使用
当前 Host/VM 进程/安全输入 secret；VM 侧交接可使用 repo 外、owner-only、
一次性固定-schema JSON，人工拖入后由固定 `invoke-vm-smoke.ps1 -PackagePath`
读入并在首次网络前删除。它不进入 Git/prompt/日志/evidence，不是长期明文
存储。DPAPI CurrentUser 只在后续启用持久 unattended watcher 前要求。
现有复杂 receipt/ticket 代码可保留
作为 optional hardening，但不再产生当前 policy gate。

用户已回传经 VM 实际检查的 `VM_RELAY_READINESS_V1`，`Ready=true`：
Windows 11 x64、PowerShell 7、Git、`ClientWebSocket`、系统时钟、GitHub/`workers.dev`
443 出站连通、VMware Tools 和 `%LOCALAPPDATA%\CDDsiRelayVm\state` 本地工作目录均
已就绪，无回传 blocker。该回执只授权后续 relay-only smoke，不是旧 bootstrap、
产品 integration、产品 Live 或 Formal Lane readiness。

2026-07-22 已完成 Free-only 实际 provisioning 与跨机 relay-only smoke：精确 endpoint 为
`https://cddsi-realtime-relay.lizixuan6383828.workers.dev`；Worker、SQLite-backed
`RelayRoom` Durable Object 与两项独立 runtime secret binding 已创建，postdeploy 精确配置
回读通过。Host dual-role HTTP smoke 通过；随后 VM 消费 `host-to-vm` sequence 4、
MessageId `50f12439-4e4b-4d52-8468-b329be714cbf`，发布 `vm-to-host` sequence 2、
MessageId `2df56de0-ba05-439b-9325-75966a996db5`，Host 复核得到前一 ACK
`ACK_IDEMPOTENT` 并成功 ACK VM reply。该证据不包含 secret。生产 WebSocket 断线重连和
Hibernation 尚未完成真实公网 E2E，因此 relay 仍是 `NOT_PRIMARY`，两端 automation 继续
`PAUSED`，Git control repos 继续作为持久审计与 fallback。

一次性 VM handoff package、Host prepared envelope 与 VM report 的本地副本均已删除。宿主机
64-byte 明文 runtime frame 已完成 DPAPI CurrentUser round-trip 后删除；仓库外只保留 owner-only
DPAPI blob，不记录其路径或内容。在该次 manual smoke 完成时，VM 尚未安装持久 secret 或
watcher；此后 VM 已另行完成 D-024 的 owner-only DPAPI foreground credential provisioning，但仍未
启用 unattended watcher/primary path。两项事实分别证明 manual smoke 与前台凭据 readiness，
automation 继续 `PAUSED`。

2026-07-21 本轮继续前从实际磁盘复核：分支仍为
`codex/repair/p10a-0a-fast-lane`；上一轮已推送 HEAD 为
`45943fa1207e8f1b61ac71cc3319dfb5381c6561`，PR #1 仍是现有唯一 PR，其 Release dry-run
run `29831979425` 与双引擎 CI run `29831979357` 均已成功。本轮 tracked 修改继续按同一 PR
追加。本段不嵌入会自引用的最终 commit；实际 HEAD/upstream、PR head 和 CI 必须从
Git/GitHub 回读，且只有绑定同一最终 commit 的新 CI 可证明远端字节。旧 CI、tree 和任何旧
finalization 不能证明本轮字节。

当前已在产品仓库的 DevelopmentOnly `OperatorCoordination` plane 增加纯 PowerShell relay
客户端及 fake/contract tests；本地 sibling workspace
`D:\projects(WIN)\cddsi-relay-infra` 已创建 Worker、SQLite-backed Durable Object、WebSocket
Hibernation、协议 kernel 与离线测试的源码实现，并已部署上述同名 Free-only 云资源。两个 workspace
保持分离：产品/Release 不含
Node、npm、Wrangler、Worker 源码或 Cloudflare 配置；infra workspace 目前没有 remote，亦未
发布。实现只接受两条窄 lane 的固定 immutable-pointer schema，不携带或执行 prompt、脚本、
命令、日志正文或自由文本。Git protected-history control repos 仍是持久审计与断线 fallback，
一分钟轮询合同未删除或放宽。

产品侧 reader watcher 与 writer publisher 使用分离的 context/runtime assertion 和相反 lane ACL。
publisher 的五字段 pointer 包含从已创建 immutable control envelope 复制的 `MessageId`，在首次
网络前原子保存规范 pending body；响应丢失、重启或 TTL 已过时都只重发相同 bytes/MessageId，
只有精确 `PUBLISHED`/`PUBLISHED_IDEMPOTENT` 回执才能推进 sequence/hash。
watcher 经 relay 验证后仍必须让固定 Git outbox `Poll` 二次绑定 repository/ref/commit/MessageId/
payload hash，再按 `PENDING` proof、hash-bound absolute `codex.exe` 固定 `exec resume --json`、
exit 0、assertion 复验、`SUCCEEDED` proof、state commit、ACK 的顺序执行。relay/Git/model/free text
均不进入 executable、argv、prompt 或 environment。owner-marked cleanup 需要独立 action-bound
assertion 与 Live 确认，并在任何 publisher chain/pending state 存在时拒绝清理；它不能静默退役
出站链。

独立 infra workspace 已初始化**仅本地** Git `main`，无 remote；基线提交为
`a74ef5986b801bf5c9c500e473590d5167a062a8`，当前离线提交为
`42424472a5b7d685486db0ae3cab0b6817333dcb`、tree
`b0df22cf01fd09a27a32a876cfb740a63662395e`；该最终本地提交包含 room epoch 与
existing-Worker update/readback 收口，worktree clean 且无 remote。用户已授权外部门 1–7 项并限定
Free-only。授权后使用 Node `24.16.0` 的 bundled npm `11.13.0` 生成精确
`package-lock.json`，安装 workspace-local `wrangler@4.112.0`、`typescript@6.0.3`，并在
Wrangler global native helper 精确前缀安装/回读 `@napi-rs/keyring@1.3.0`；未使用 global
Wrangler 或 PATH npm。当前 infra 离线测试 139/139、69 files/0 secret findings、固定
`wrangler types`/TypeScript 均通过；真实 Wrangler dry-run 共 4 artifacts/151250 bytes，
扫描为 secret=0、console=0。GET-only Cloudflare readback
固定了单账号、usage-model 枚举、既有 workers.dev subdomain、目标 Worker无碰撞，以及部署后
active 100% version/SQLite export/精确 binding/route 回读；usage model 明确不作为 Billing
subscription 证据。固定 Wrangler
`createTestHarness` 的实际本地 workerd 测试还通过了 SQLite publish/read/ACK、错身份与伪造 HMAC、
close eviction 恢复，以及 Hibernation eviction 后原 WebSocket 继续投递；runtime log、Node-side
harness fetch-spy call 和临时残留均为 0。本地证据不是部署回执，也不表示生产 Cloudflare 的 idle
调度、平台日志或公网 Hibernation 已验证。
本地 `default` profile 采用实现还包含严格 owner-only 崩溃恢复、过期 receipt 的
`auth:renew-default` generation/previous-hash 原子续期、malformed/reparse directory-binding
fail-close，以及 account-bound 私有 credential snapshot。snapshot 只由
`auth token --profile default` 取得，并用唯一 account GET 对照 adoption receipt 的 account hash；
后续 deploy/secret/list 只使用该内存 token 与固定 account target，不再解析磁盘 profile，且不会
把 token、账号 ID 或原始 CLI/API 输出写入 evidence。
早期 code-pinned Cloudflare write policy 把 coordinated provisioner、Host/VM DPAPI receipts、
bulk semantics 与 two-secret staging receipt 固定为 false，所以当时 `deploy`、
`stage-initial`、`stage-rotation` 会返回 `CLOUDFLARE_WRITE_PREREQUISITES_NOT_MET`。D-022
已取消这些条件对 Free-only deploy/手工 smoke 的阻断权；infra 实现应走最短
lean path，不必删除已有 validator/recorder/ticket，但也不得等待签发 machine
receipt。OAuth 与 GET-only preflight 保持可用。

产品本地完成门已通过：realtime relay client focused tests 在 PowerShell 7 与 Windows
PowerShell 5.1 各 67/67，新增 VM smoke focused tests 各 8/8，并通过两套引擎各 25/25 的
operator coordination boundary tests；完整
`scripts/check.ps1` 双引擎 HostSandbox gate 通过，所有产品真实 network/process/registry、
outside-sandbox、forbidden access、unexpected ledger、secret finding 和 mutation spy 指标均为 0；
Release Simulation DryRun 通过 39 个 package files，source/staging/ZIP/extract secret findings 均为 0，
精确 inventory/hash 与 deterministic ZIP 校验通过。上述证据只证明本地离线实现，不得把
`LOCAL_GATES_PASSED` 解释为可激活 automation。当前已有上述 Worker URL、Durable Object、两项
runtime secret binding、postdeploy readback、Host HTTP smoke 与跨设备 relay-only evidence；secret
本身未进入仓库或 evidence。生产 WebSocket reconnect/Hibernation E2E 与持久 watcher 激活证据仍不存在。
本轮已按授权执行 npm 网络访问、精确 infra toolchain 安装、keyring helper 安装、typecheck 与
Wrangler dry-run，并已采用既有 Cloudflare OAuth credential、执行固定四 GET preflight；
随后已按 D-022 执行 secret binding、Worker/DO 部署和上述 live smoke。只读审计曾发现一个此前已存在的
keyring 加密 `default.enc`：单账号、29 项权限，包含本任务四项必需 scope，另有 25 项。用户在
知悉该差异后已明确授权直接复用，不要求 exact-scope equality，也不因额外 scope fail closed；
真实精确 infra root 的 binding-absence proof 已通过，generation-1 owner-marked adoption receipt
已绑定 `default.enc`、account 和 permission hashes。随后 preflight 确认单账号、既有 account
workers.dev subdomain、目标 `cddsi-realtime-relay` 不存在，并报告
`WorkersUsageModel=STANDARD / BillingPlanVerified=false /
BILLING_VERIFICATION_REQUIRED`。Cloudflare 官方合同表明 usage model 不是订阅 receipt。随后经用户
授权，只读复用其个人 Edge 既有登录态查看 Billing → Subscriptions：列表未出现 Workers 或
Workers Paid；显示 active 的 Teams Free Base 与另一个无关的 R2 Paid。该结果已经脱敏，仓库与测试
evidence 不记录 account id、邮箱、地址、付款方式、cookie、截图或其他身份明文，也不得把整个
Cloudflare 账号称为 Free。Cloudflare 官方合同表明 Workers Paid 与其他 Cloudflare 产品计划分离；R2 Paid 不隐式升级
Workers，也不授权 relay 使用 R2。SQLite-backed Durable Objects 支持 Workers Free，Free 限额超出
后操作失败而不是产生按量账单。没有 DNS/域名变更、系统服务/计划任务注册或 infra 远端。

永久强制值继续为：

- `CanStartVmBootstrap=false`；
- `CanStartVmIntegration=false`；
- `P10A0AComplete=false`；
- `CanStartFormalP10A=false`；
- HostCoordinator automation `cddsi-fast-lane-hostcoordinator-minute-poll` 必须继续
  `PAUSED`；本轮已从 automation 配置与应用内 view 回读为 `PAUSED`，未触发或更新；不推断 VM
  automation 存在，也不创建、触发、更新或启用任何 automation；
- 允许人工进入已就绪 VM 执行 relay-only smoke；不执行旧 bootstrap、产品
  integration 或产品 Live，不自动 merge/release/promotion，不越过 P12；
- 所有旧 onboarding ZIP、prompt、finalization、bundle 与 automation binding 继续为
  `SUPERSEDED_DO_NOT_USE_REALTIME_RELAY_REPLAN`。

集中外部授权门已由用户一次性通过，限定 Free-only；用户随后在知悉既有 encrypted keyring
`default` profile 有 29 项 scope、其中 25 项超出四项必需集合后，明确授权直接复用。Wrangler
`4.112.0` 的 `default` 是 reserved profile，不能用 `auth activate default`。受控
`auth:adopt-default` 已证明精确 infra root 没有 exact/inherited profile binding；无 binding 时
`auth keyring`/`whoami` 才从该 root fallback 到 `default`，随后生成 owner-marked 本地 adoption
receipt，绑定 `default.enc` hash、permissions 与脱敏 readback，并验证明文 profile 不存在、
`account:read`、`user:read`、`workers_scripts:write`、`offline_access` 四项均存在且只返回单一
account；不要求 scope 集合精确相等，额外 scope 不再构成失败，也不扩大本任务授权。采用未触发
新 OAuth 登录；随后经用户明确授权，复用其个人 Edge 既有登录态完成只读 Billing Dashboard
核对，没有执行新的登录、订阅、付款或计划变更。
GET 与未来写入先用 `auth token --profile default` 形成内存 snapshot，再以唯一 account GET 核对
receipt account hash；deploy/secret/list 使用 snapshot token 和固定 account target，不传 profile
argv。receipt 到期只允许 `auth:renew-default` 在严格 owner/root、canonical、无 reparse 且确实过期
时原子续期；有效、伪造或未知状态不得覆盖。
OAuth/deploy credential 与 Host/VM runtime credential 必须继续完全分离。
固定 GET-only account/subdomain/collision preflight 已完成；它记录 `STANDARD` 但不能把任何
Workers account usage model 冒充 billing-plan receipt。脱敏 Dashboard 人工观察已确认订阅列表未
列出 Workers/Workers Paid；active 的 Teams Free Base 与无关 R2 Paid 不改变 Workers 的独立订阅
边界，也不授权 relay 使用 R2。D-022 接受这份人工观察作为当前 Free-only
部署依据，不等待 machine receipt。多账号、目标 Worker 碰撞或付费/升级提示
仍必须停止。初始一次性 smoke 允许 Host 使用受控内存/安全输入 secret，
VM 使用上述人工拖入、读后即删的 repo 外 owner-only handoff JSON，不要求事先产生
两份 DPAPI receipt。授权不自动
激活持久 watcher、恢复 VM bootstrap 或启用 automation。

## 2026-07-20 controlled-pause baseline（历史；由上方当前状态覆盖）

**CONTROLLED_PAUSE：不得继续 VM bootstrap。** 2026-07-20T15:19:09Z
（北京时间 2026-07-20 23:19:09），本任务在宿主机审计到
`codex/repair/p10a-0a-fast-lane` 的暂停基线 commit
`5df3744f526619b7e4a1d3ca93e130a4974fc5d5`、tree
`8c361b65bdd51a26fa5c57076bdb96432229236a` 后，按用户指令停止旧 onboarding 路径，转入
realtime relay 重规划。该基线当时与 upstream/remote repair ref 精确一致、worktree/index
clean，PR #1 是唯一 PR 且为 OPEN/DRAFT；CI run `29745570954` / quality job
`88362548125` 与 Release dry-run run `29745571080` / release-contract job
`88362548450` 均 completed/success；两个实际 PR check-run 均 success。Claude GitHub App 另有
一个不含 check-run 的 queued 空 suite `80546088325`，它不出现在 PR checks 中，不能误报为
第三个执行中质量门。上述事实只证明暂停前字节，不授权暂停后的任何 VM 动作。

本次对 tracked 文档和 manifest/tests 的任何修改都改变 commit/tree。因此，暂停前的
HostSandbox finalization、Release Simulation、GitHub CI、HostCoordinator prompt、retained
bundle 以及 `finalization-readiness-receipt.json` 已不再绑定当前工作树或本次最终提交。精确的
暂停后 commit/tree 不能由 tracked 文档自引用；只以本任务提交/push 后的实际 Git、remote、
PR 和 CI 为准。

当前强制状态：

- `CanStartVmBootstrap=false`；
- `CanStartVmIntegration=false`；
- `P10A0AComplete=false`；
- `CanStartFormalP10A=false`；
- 不进入 VM 执行旧流程，不再让用户或 VM 运行、复制、校验或修复任何
  onboarding ZIP/prompt；D-022 只另行允许不接触这些材料的 relay-only smoke；
- 不执行 bootstrap、poll、integration、reset、测试循环、Formal Lane 或产品 Live；
- 不启用、触发、删除或重建任何 automation；HostCoordinator 必须继续 `PAUSED`，VM task
  若存在也必须继续 `PAUSED`，没有来自 VM 的可靠当前 receipt 时不得推断其存在或状态；
- 不 merge、release、promotion、force push，也不创建重复 PR。

### 暂停前 retained 字节与 superseded 标记

暂停前最后一个 owner-marked retained root 保留在：

`C:\Users\LIZIXUAN\AppData\Local\Temp\cddsi-test-a03ca352-f256-414b-8afc-80c8adc8c38b`

其中最后生成但**没有可靠 VM 成功 receipt**的 onboarding ZIP 为
`final-vm-onboarding\cddsi-fast-lane-vm-onboarding.zip`，length `842085`，SHA-256
`ff8f923ba1e7af37b4cac8de2d5b54ec9fbc47a9e6c00cf2231c71f00b2f7208`；其提示词
`vm-bootstrap-prompt.txt` length `81505`，SHA-256
`6470511fd7267bf093ddf624b699a70c42f4d741a69e054339702ac9a463fa35`。manifest、inventory、
loader、launcher 与 content digest 的暂停前只读锚为：

- `final-vm-onboarding\staging\manifest.json`：length `10460`，SHA-256
  `2f38ce77f7fa8b1600775c400b42b20644e9cdafe81d82ad3a961757b801076d`，binding token
  `96318a5753f1cfb087383ee8ebdf336ff7b232c1a5095634624a2f1068acf815`；
- `final-vm-onboarding\staging\inventory.json`：length `4901`，16 entries，SHA-256
  `d238b5b269b1820eb1cfb34c1db4c9a55b9bc9758153c50e0adf440d85d5100a`，binding token
  `a579b591dc39280abaed13d0eabb2d82da01fc200a1c970146fe25ae22b35718`；
- content digest：`09c31785d2d6a380e46de06c2b139342202ea281a994366792acda280ab64172`；
- loader source 只嵌入 retained prompt，没有独立交付文件：length `62501`，SHA-256
  `6414c044b11cdb8009de54303d9730829402f3c7f39769e491ace660323e2d3b`；
- exact launcher 同样嵌入 retained prompt：length `4079`，SHA-256
  `204019b33e36be53d9dd4fc8078e0040924b62640013a993c7c7228f24d9d5aa`；
- `evidence\finalization-readiness-receipt.json`：length `4984`，SHA-256
  `fa6991de25e13d9c7bf21f95ce10e104621d1d57365a6fe62dc790325d9f5a7a`；其旧
  `CanStartVmBootstrap=true` 只绑定暂停前 commit，现已失效，不能读取为当前状态。

以上全部状态统一改为：

`SUPERSEDED_DO_NOT_USE_REALTIME_RELAY_REPLAN`

该标记也覆盖此前所有 onboarding ZIP 及其 prompt，包括但不限于：

- `d4dc6df133cd331ac8411212c105b205a9491942247f83f1256aaee4b62c065c`；
- `311f8fe7cfac6eefb51b6c9f588ae7a396ed82505d10a6837d208181b0ee9ed8`；
- `6127b0a0d4e555db9b0ef6174c4c37ea17876bdd151ed5e60606783da92144e1`；
- `416805e8781957dc8c7b1bb7fea31710447624cb5b3e35a19957b1a5b7d2246a`；
- `58bf3d26930b1c2eda78c29b4d53a89a28794fc7d74ef6ecdb90b6858cb88832`；
- `ff8f923ba1e7af37b4cac8de2d5b54ec9fbc47a9e6c00cf2231c71f00b2f7208`。

这些历史字节、owner marker、evidence 和 sandbox 均不得删除或重写；保留只为审计。聊天中的
早期 VM diagnostics 分别绑定旧 ZIP，并不是 `ff8f923b...` 的执行 receipt。未发现能够证明
最新 ZIP 已执行、完成 bootstrap 或生成有效 public handoff 的可靠 receipt，因此真实状态是
`LATEST_ZIP_EXECUTION=NOT_PROVEN`，不能由“已交付路径”推断成功。

### Automation 与外部授权状态

宿主机唯一 HostCoordinator automation 仍为
`cddsi-fast-lane-hostcoordinator-minute-poll`、kind `heartbeat`、名称
`CDDsi Fast Lane HostCoordinator minute poll`、目标 task
`019f667f-e2ed-7c40-91fb-9bfc8367f9cf`、一分钟 cadence、`PAUSED`。暂停前 TOML SHA-256
为 `769a2e61b488efe329ff49330ed2e6cd304f5ddda882a5091f8505e746fe3a2e`，length
`17303`；prompt SHA-256 为
`4ba8df222451e5c3593a452f37f208a510b747cd38f1be23364ade0baf43ada9`，length `16754`。
本任务只读复核，不更新该 automation；新的 tracked commit 会使其旧 prompt binding 失效，
但它必须继续保持暂停。

HostCoordinator/VmTester 的窄 credentials、GitHub deploy-key 注册、runtime protection
assertion/hash/token 与外部 provisioner receipt 均没有可靠的 provisioned 证据；状态继续为
`NOT_PROVISIONED` / `UNPROVISIONED`。不得读取 credential store 来猜测，也不得复用交互式
bootstrap-admin 身份。服务端 PUBLIC + protected-history 是保留的外部历史事实，但不构成
sender authority 或 runtime readiness。

仓库、operator state 与 retained evidence 中没有 task-owned foreground watcher/relay 的 PID、
owner receipt 或启动记录。为避免把不明进程误认成本任务进程，本次没有枚举或终止未知进程；
`OwnedWatcherStatus=NOT_PROVEN_PRESENT`、`WatcherStopCount=0`。

### 暂停原因与下一任务

暂停不是继续修复旧 loader，也不是进入 VM。原因是现有 minute polling、用户人工搬运和反馈
延迟不满足下一轮高频双机协作，需要先独立设计并实现秒级通知 accelerator，同时保持 Git
control repositories 的 durable audit/fallback 与全部原有权限边界。

当时冻结的下一独立任务名称为 **Cloudflare realtime relay 设计与实现**；它现在就是本文顶部
记录的当前工作包，入口为 `docs/REALTIME_RELAY_PROPOSAL.md`。本历史段的
`PROPOSED / NOT_PROVISIONED / NOT_ACTIVE` 已由顶部的本地实现状态覆盖，但“不得在未授权时创建
Cloudflare Worker、Durable Object、域名、secret、token、远端或激活 watcher”仍持续有效。
一分钟 fallback 不变；任何后续 provisioning、网络、Cloudflare/GitHub 管理动作仍必须取得明确
外部授权。

恢复旧 VM bootstrap 前必须从未来新的最终 clean exact commit 重新执行完整双引擎
HostSandbox、Release Simulation DryRun、diff/编码门、远端/PR/CI 核验，重新生成并自校验
onboarding bundle，重新原位绑定且保持暂停的 automation，再生成新的 readiness receipt。
任何暂停前 ZIP、prompt、CI 或 receipt 均不得复用。

### 新对话读取顺序

1. `AGENTS.md`
2. `docs/HANDOFF.md` 顶部当前动态状态
3. `docs/README.md`
4. `docs/REALTIME_RELAY_PROPOSAL.md`
5. `docs/VM_TEST_RELAY.md`
6. `docs/IMPLEMENTATION_PLAN.md`
7. `docs/TEST_ISOLATION.md`
8. `operator/fast-lane/README.md`
9. `operator/fast-lane/runbooks/vm-bootstrap.md`
10. 仅在方案评审需要时再读其他 Fast Lane runbook；不得从旧聊天恢复执行许可。

## 旧 bootstrap 收口状态（历史，已由上方 controlled pause 覆盖）

**当前不能重试 VM。** 2026-07-20，VM 用精确 ZIP（length `842085`，SHA-256
`6127b0a0d4e555db9b0ef6174c4c37ea17876bdd151ed5e60606783da92144e1`）完成外层 ZIP、manifest、
inventory、固定工具与依赖字节验证后，在进入 phase2 wrapper 的第一条赋值处以
`Cannot overwrite variable ExecutionContext because it is read-only or constant.` fail closed。
PowerShell 变量名不区分大小写；生成 loader 内的局部 `$executionContext` 与内建
`$ExecutionContext` 相同，而后者在 PowerShell 7 与 Windows PowerShell 中均为
`Constant, AllScope`。回执中的 `PackageValidated=true`、`PackageRevalidated=false`、
network/Git/credential/automation/product-Live 全为 0，以及 deepest-first cleanup 成功，均与该
精确调用点一致。该 ZIP 及绑定它的 prompt 现在是
`SUPERSEDED_DO_NOT_USE_LOADER_EXECUTION_CONTEXT_COLLISION`；禁止在 VM 手工改 loader 或重试。
此前 `311f8fe7...` 的 BOM loader 缺陷包也继续保持 `SUPERSEDED_DO_NOT_USE`。

宿主已在 commit `a20326b6661e1e29e1be454f6957662069ae2838`（tree
`63bfa01fa7efd506254237188f994c0a9cdb5ce6`）把生成 loader 的局部变量改为唯一的
`$phase2BootstrapContext`，并加入生成后 AST Constant/ReadOnly 冲突扫描及 exact phase2 binder
双引擎执行测试。clean HostSandbox RunId `39725c39-d002-4eee-9133-52b02b90b9bc` 当时为双引擎
449/449、全部非 PASS/隔离/mutation 指标为 0；Release Simulation DryRun 为 39/39、
`Changed=false`、四层 inventory exact、全部 forbidden/secret/mutation 指标为 0。为该 commit
生成的 retained ZIP `416805e8781957dc8c7b1bb7fea31710447624cb5b3e35a19957b1a5b7d2246a`
也已由两套引擎独立验证为 18-entry、16-entry inventory、Store、timestamp 1980，loader
`6414c044...` 无 `$ExecutionContext` 冲突。

但该 commit 的 GitHub `CI / quality` 成功后，独立 `Release dry run / release-contract`
run `29740013822` 在 source quality gate 暴露了既有测试时序缺陷：测试把
`REMOTE_CAS_MISMATCH` 语义断言耦合到最多 8 个、每个 2 秒预算的真实 Git 子进程；runner 负载
波动使其中一条命令合法 fail closed 为 `GIT_COMMAND_TIMEOUT`，结果为 448/449，release exact
DryRun 因前置失败未运行。同一 SHA 的另一工作流全绿，且该失败发生在未被 `a20326b...` 修改的
Git outbox 测试，证明不是 loader 修复回归。当前 WIP 在**不扩大任何 timeout**、也不接受 timeout
作为通过的前提下，把 stale CAS 与 held lock 拆成两个确定性负向测试；真实 Git/history/publish
仍由其余集成测试覆盖。修改后的整份 Fast Lane Git outbox 测试已在 PowerShell 7 与 Windows
PowerShell 各通过 21/21，失败/跳过/未运行/不确定均为 0。

因此 `416805e8...` ZIP 及其 prompt 也已因新的 tracked 测试与本文修改而成为
`SUPERSEDED_DO_NOT_USE_CI_TEST_TIMING_REBIND_REQUIRED`，不得交付或运行。现有宿主机 automation
仍是同一 ID 且 `PAUSED`，但只绑定旧 commit/bundle；VM 回执为
`AutomationReconciliationReached=false`、`AutomationMutationCount=0`，未产生有效 VM automation
binding。必须先提交当前 WIP，再从新的 clean exact commit 重跑双引擎全树门、Release DryRun、
GitHub 两个 workflow、18-entry bundle 自校验与同一 automation 原位重绑。当前精确状态仍是：

- `CanStartVmBootstrap=false`；
- `CanStartVmIntegration=false`；
- `P10A0AComplete=false`；
- `CanStartFormalP10A=false`。

上一轮 BOM 修复仍保持原始依赖字节、SHA、只读句柄和最终重读不变，只在同一 captured byte
array 上严格消费唯一开头 UTF-8 preamble；重复/嵌入 BOM、无效 UTF-8、UTF-16 与 NUL 均
fail closed。本轮必须重新完成包含当前测试与本文的 clean-commit 双引擎全树门、Release DryRun、
CI、新 bundle/prompt 与同一 automation 原位重绑。
只有一个 `ProductCommitSha`/tree 与当前 clean HEAD 精确相等、且所有失败/隔离指标为 0 的
新 owner-marked finalization receipt 才能重新派生 `CanStartVmBootstrap=true`；tracked 文档本身
不能替代该外部机器证据。

新的唯一 phase2 入口
`Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding`、builder/loader、execution boundary 和正负
测试已经按目标合同落盘：不再接受 caller result/prompt/observation 或 derived roots；direct
phase1/core/handoff/mutation surface 均为纯 fail-closed facade；真实目标 automation TOML 采用
canonical identity scan、目标专用 exact schema、唯一 ID/name、prompt readback 和进程内
`CODEX_THREAD_ID` 绑定。非 Live context 还必须把所有输入路径绑定到 owner-marked HostSandbox。
loader 已采用 current-SID/protected-DACL 精确校验、同一已哈希字节解析/加载、create-only 与
原子状态写、显式栈 deepest-first 非递归清理及幂等状态比较。

此前 `7f3f7260...` 的标准 HostSandbox、Release DryRun、39-entry release、18-entry onboarding
与 CI success 只绑定含变量碰撞的 loader 字节；VM 的真实 phase2 失败已证明它们不能授权重试。
`a20326b...` 的 449/449、39/39 与 ZIP `416805e8...` 又只绑定 CI 测试修复前的 tracked 字节。
新的最终测试计数与所有 hash/length/token 必须以当前 WIP 后的 clean exact commit 机器结果为准，
不得沿用 448/448、loader `b1eb4981...`、prompt `a0242117...`、ZIP `6127b0a0...`，也不得把
`416805e8...` 当成 active handoff。

已完成且仍有效的外部历史事实只有：三个 public repositories 与无 bypass 的
protected-history ruleset 已部署，产品旧 `main` 与两个 control outbox 已初始化；既有宿主机
heartbeat 仍必须保持 `PAUSED`。2026-07-16/17 的 427/427、430/430、39/39、18-entry bundle
和 CI 记录只说明当时精确字节通过，不能授权当前未提交工作树。详细历史锚保留在后文。

项目较早阶段的 P3-P9 纯合同/fake/synthetic、P10A evidence/consumption 合同和 P10B 宿主机
支撑合同已经实现；这不等于真实 VM evidence、helper PE/签名、frozen facts、P10B 双候选或
P11 全面验收已经产生。产品运行阶段仍为 `Scaffold`，宿主机不得执行产品 Live。

用户的端到端目标已经冻结：正常路径中，用户只启动 VM、安装并登录 Codex、放入一个宿主机
交付文件、粘贴一段最终 prompt。之后由两端 Codex 与固定 runner 自动完成 VM 本地配置、
窄凭据和双向通道 provisioning、宿主修复/VM 重测循环、场景矩阵、Formal evidence、候选
构建与验收；最终发布仍默认需要用户人工确认。网络、官方工具安装和 GitHub 管理授权不是
静默权限：若确有需要，只允许各请求一次明确确认，Codex 代为执行具体步骤，且交互式
bootstrap-admin 会话不得保存或复用为 automation credential。

## 暂停前仓库与工作树（历史）

- 项目目录：`D:\projects(WIN)\claude-desktop-deepseek-installer`
- 只读参考：`D:\projects(WIN)\claude-deepseek-installer`
- 分支：`codex/repair/p10a-0a-fast-lane`
- 产品 Remote：`origin` → `git@github.com:LXZ56156/claude-desktop-deepseek-installer.git`
  （PUBLIC，protected-history ruleset `19068339`）
- Control repos：`LXZ56156/cddsi-host-to-vm`、`LXZ56156/cddsi-vm-to-host`
  （均为 PUBLIC；ruleset `19068292`、`19068313`）
- 当前版本：`0.1.0-dev`
- 产品运行阶段：`Scaffold`
- 本次 WIP 基线 commit：`a20326b6661e1e29e1be454f6957662069ae2838`；tree：
  `63bfa01fa7efd506254237188f994c0a9cdb5ce6`。当前修复快照修改
  `tests/HostSandbox/FastLaneGitOutbox.Tests.ps1` 与本文；remote repair ref 仍指向该基线 HEAD。
  这些数量只是 2026-07-20 的工作快照，不是最终 bundle/CI/VM 授权锚。
- 历史宿主机锚：`3e843912...`、`a09130f2...`、`615bbf368...`；包含本文的最终
  clean HEAD 与其 bundle/task/CI 绑定必须从外部机器事实重新发现，任何历史锚都不能
  当成当前授权
- 实施位置：P10B 宿主机支撑合同已通过门；P10A-0A 宿主实现与 public protected
  repository pair 已实现。旧 finalization anchor 已保留为历史证据；包含本文的文档
  roll-forward 必须由新 clean HEAD 重新 finalization，并用外部绑定证明。服务端 protected
  history 已完成；最小权限凭据、runtime
  assertion、VM provider/device/reset evidence、VM task 与 unattended 负向权限验证仍阻断 integration，随后还须完成 Formal
  Lane，才可执行首次 P10A 窄范围 disposable VM 校准。
- 交互式 `gh` bootstrap-admin 会话属于易变外部事实，使用前必须重新核验；即使可用也
  绝不能作为 HostCoordinator/VmTester 自动化凭据

保留当前工作树继续开发。不得 reset、checkout、清理或覆盖用户与前任务的改动。
实际 commit/clean 状态只能通过项目规定的隔离 Git 入口核验，不能把本交接中的描述
当作 clean-commit 证据。

后续代理不需要重新从零调研，应从本文件记录的当前工作包和真实工作树继续。所有
宿主机开发与统一门禁都不在开发机执行 Live；首次限域真实校准只能进入 P10A 专用
disposable VM，首次全面产品 Live 只能进入 P11 disposable VM。

## 旧任务必读顺序（历史；新对话使用顶部顺序）

1. `AGENTS.md`
2. 当前 `docs/HANDOFF.md`
3. `docs/README.md`
4. `docs/PRODUCT_SPEC.md`
5. `docs/EXTERNAL_CONTRACTS.md`
6. `docs/DECISIONS.md`
7. `docs/TEST_ISOLATION.md`
8. `docs/IMPLEMENTATION_PLAN.md`
9. `docs/RELEASE_PLAN.md`
10. `docs/VM_TEST_RELAY.md`
11. `docs/VM_CALIBRATION_PLAN.md`
12. `docs/VM_ACCEPTANCE_PLAN.md`

## 已实现的阶段能力

### P0-P2：规划、P1 Sandbox Foundation 与正式 3P 配置合同

- 建立 ExecutionContext、default-deny fake providers、AccessLedger、mutation spy、
  owner-marked HostSandbox、工具路径/hash 授权及双 PowerShell worker。
- 冻结 `claude-desktop-3p-managed-policy-v1` desired state、15-value HKCU serializer、
  exact fixture、来源优先级和 fixed Chat/Code/Cowork 三项产品目标。
- 所有配置、备份、写入和恢复在宿主机保持纯数据、plan-only 或 fake。

### P3-P4：环境域模型和供应链合同

- Windows、Desktop、Git、Cowork readiness 的 synthetic/fake 探测矩阵已经实现。
- Desktop 安装冲突、Git 缺失/过旧/损坏/歧义、VMP/service blocker 均稳定
  fail closed，不会把依赖失败改写成 Chat-only 成功。
- artifact metadata、下载计划、签名证据、路径 token、SHA-256、artifact type、
  identity/signer/publisher 绑定和安装前重新验 hash 的纯合同已经实现。

### P5-P7：安全纯合同

- credential 生命周期、独立授权/使用 receipt、补偿授权、轮换与删除的 fake 合同
  已实现；日志、状态、报告和 fixture 不允许保存 Key。
- 配置 ownership、可恢复备份、独立写入 receipt、失败补偿与脱敏快照合同已实现。
- state schema v3、CAS revision、checkpoint claim/complete/abort、过期和 v2→v3 严格
  迁移以及 Cowork prepare/resume 独立 receipt 已实现。

这些是领域和 fake 合同，不是 DPAPI Live adapter、真实 registry writer 或真实 VMP
实现。

### P8-P9：编排与 synthetic 验收

- InstallPlan/trace、stage/grant/auth/workflow 绑定、正向与逆序补偿、故障注入和
  fake orchestrator 已实现。
- Chat、Code、Cowork 的 readiness、分层状态、脱敏报告和外部 E2E evidence 接口已
  通过 synthetic 场景验证。
- `lib/live-adapters.ps1` 目前只是精确 allow-list 下的 fail-closed 隔离入口；它不含
  可工作的真实 provider，并且不能在宿主机加载或执行 Live。

### P10A：校准 evidence 与消费合同

- calibration canonical JSON、外部 session anchor、8 项 operation receipt、provider
  evidence digest、cleanup、时序/新鲜度、evidence schema v2 以及
  `READY_TO_COMMIT → READY_TO_FREEZE` CAS 消费合同已经实现。
- 这些能力只验证 evidence 的结构、绑定与状态迁移。实际 P10A runner/provider、
  VM evidence 导出、签名 helper/chooser 行为与真实 Standard/Offline/MSIX/Git 事实
  尚未在 disposable VM 产生。

### P10B：宿主机支撑合同

- `release-facts` 只接受受信外部 CAS authority 签发、已提交且未篡改的 P10A
  evidence，并把事实编译为版本化、可重算的冻结输入。
- `release-artifact` 强制由调用者提供外部 signature trust policy；manifest、sidecar
  或攻击者自洽替换的证书/策略不能自举成为信任锚。
- `credential-helper-release` 绑定源码、依赖锁、固定工具链、实际 PE、SBOM、
  Authenticode 与真实 provider receipt，缺一项即 fail closed。
- candidate assembler 已实现外部 frozen facts/trust anchor、双 profile、两阶段构建和
  deterministic identity 合同；没有真实外部输入时不会生成可发布候选。

## 2026-07-16 已消费的对话切换暂停点（历史）

本节保留当时的输入状态与执行清单，用于解释后续 finalization 的来源；7 个步骤现已
全部完成。它不再是当前工作入口，其中“当前”“尚未”和旧占位符都只描述当时快照。
当前状态只看本文开头、2026-07-17 cutover 证据与“当前停点”；本节 private/403/
“当前”等字样均是当时快照，已被后文取代。

### 当时 Git 与工作树

- 分支与 remote ref 均停在
  `c93b15fe8850fcf42188492bf2449258e9f63615`，对应 tree
  `fe932672f31776bbf7a5f8f35929ae096822b652`；该 commit 已推送。
- 前一实现 commit 为 `3fba4b3948a2c59d66402d9dd6aed6fdc78caec3`。
- 工作树故意保留 8 个未提交文件：
  `operator/fast-lane/build-vm-onboarding.ps1`、
  `tests/HostSandbox/FastLaneOnboardingBundle.Tests.ps1`、
  `docs/HANDOFF.md`、`docs/README.md`、`docs/IMPLEMENTATION_PLAN.md`、
  `docs/TEST_ISOLATION.md`、`docs/VM_TEST_RELAY.md`、
  `operator/fast-lane/README.md`。不要 reset、checkout 或丢弃它们。
- 最新 builder 工作字节 SHA-256 为
  `7f7fb843aa87100a294ff0529a2ce7864115d416487fb58f0c84232be0f32684`；
  最新 onboarding test 工作字节 SHA-256 为
  `161ea8933b6bf0c8f74cc76c0b0d8bb9324af063f35f9b4c8dd51eba0730bd89`。
- 没有新增、删除或重命名文件，因此本工作包不需要改变
  `scripts/release-manifest.psd1`。

### 本次已收口的安全修复

- builder 在任何可能触发 clean filter 的 `git status` 或
  `hash-object --path` 前，使用 `git check-attr -z --all --stdin` 按属性名拒绝
  `filter`、`working-tree-encoding` 和 `ident`；字面值 `filter=unspecified` 不能再伪装
  成未设置，也不能执行配置的 filter sentinel。
- 固定 Git 的 `--stdin` NUL 输出在不同调用/引擎中可采用 `None` 或
  `PerRecordBom`。builder 只在单次响应内冻结并验证一致模式：首 record 不得含 marker，
  expected path 不得以 FEFF 开头，后续只允许一致的零枚或一枚 transport marker，剥离
  后仍有 FEFF 即拒绝，最后用 ordinal membership 绑定。显式 `-- <path>` 的 SafeGit
  使用单次 `check-attr -z --all -- <path>` 同时按属性名拒绝三类危险属性并校验
  `text/eol`；它不复用 stdin mode，所有 path token 必须 ordinal exact。这样仍在每次
  `hash-object --path` 前完成 TOCTOU 邻近复验，同时避免为每个文件重复启动第二个 Git
  进程。
- final clean-commit bundle 首次实建安全暴露了 synthetic fixture 与真实 runner 的
  purpose-marker 漂移：builder 仍要求真实文件中不存在的旧泛化字符串
  `cddsi-fast-lane-git-outbox-v1`。失败路径未交付 ZIP，并由 caller owner cleanup 成功
  收口。builder 与 fixture 现共同冻结真实 runner 的 `owner-v1`、`state-v1`、`result-v1`
  三个版本化合同及入口函数，禁止通过删掉 purpose 检查绕过。
- no-user-path scanner 现在以 strict UTF-8 读取；只允许无 traversal/ADS/非法 segment 的
  固定 VM 根 `C:\ProgramData\cddsi-vm-operator\`。普通、重复、escaped、device、WSL
  UNC，Windows root-relative user path，Unicode/特殊首字符 POSIX user roots，file URI、
  MSYS/Cygwin roots 和超过 512 字符的 traversal 均 fail closed；普通
  `https://example.com/home/index` 不再被误报。
- 独立只读安全复审已放行，未发现新的明确可复现高风险项；复审未编辑文件、未运行
  Live、未提交。

### 当时有效测试证据

- 上述单调用性能修复前的 `FastLaneOnboardingBundle.Tests.ps1` 回归基线：PowerShell 7 为 16/16，
  duration `00:04:20.3556251`；Windows PowerShell 5.1 为 16/16，duration
  `00:03:41.3006499`。两端 Failed/Skipped/NotRun 均为 0；它不能替代修复后的最终全树门。
- 2026-07-16 第一次标准 900 秒全树门在 PowerShell 7 worker 完成后，Windows
  PowerShell worker 被 `Trusted process timed out` 安全终止；总耗时 29:31，该轮不构成
  PASS。根因是每个 allow-listed 文件重复执行两次 `check-attr`，在多次完整/近完整 bundle
  build 中放大为每引擎约两百个额外 Git 进程；现已合并为上述单调用实现，最终 900 秒门
  仍必须重新运行，不能通过增大 timeout 绕过。
- 两个 PowerShell 文件均为 UTF-8 BOM、精确 CRLF、末尾换行；双引擎 parser error 为 0；
  当前 `git diff --check` 通过。
- 这只是定向证据。最新 8 文件工作树尚未运行标准 HostSandbox 全树双引擎统一门，
  也尚未运行最终 Release Simulation DryRun。此前 426/426 与 Release DryRun PASS 都在
  本次安全/文档修改之前，只能作旁证，不能作为 final evidence。

### 当时要求的 7 个步骤（已全部完成）

1. 先重新读取 `AGENTS.md` 和本节，确认 HEAD/remote 与上述 commit 相同、工作树只含
   上述 8 文件；不要先编辑或清理。
2. 使用固定工具运行标准 `scripts/check.ps1 -PassThru` 全树门。当前预期每引擎发现
   427 项；实际计数不精确一致或任何 top-level zero metric 非零都必须停机诊断。
3. 统一门通过后运行 `scripts/build-release.ps1 -DryRun`，要求 39 个 allow-listed files、
   四层 inventory exact、`Changed=false`，所有 forbidden/mutation/secret 指标为 0；再运行
   `git diff --check` 和编码检查。
4. 只 stage 上述 8 文件，检查 cached diff，再提交并非 force push 到现有
   `codex/repair/p10a-0a-fast-lane`；不得 merge PR、发布或 promotion。
5. 从新的 clean exact commit 生成并自校验 final Store onboarding ZIP。预期 14 个提交
   payload + 2 个 generated runbooks + manifest/inventory，共 18 个 ZIP entries，inventory
   entry count 16，timestamp 固定 1980；记录 ZIP/manifest/inventory/content digest 的精确
   hash/token、长度和 retained owner-marked HostSandbox 路径。任何实际源扫描失败都修根因，
   不得放宽或绕过。
6. 通过 `codex_app__automation_update` 更新既有
   `cddsi-fast-lane-hostcoordinator-minute-poll`，保留同一 id、heartbeat kind、名称、
   一分钟 cadence、target thread `019f667f-e2ed-7c40-91fb-9bfc8367f9cf` 和 `PAUSED`；
   prompt 必须绑定最终 commit/tree/bundle/manifest/inventory/content、工具和 repo 身份。
   当前凭据均 `UNPROVISIONED`、protection 因
   `PRIVATE_REPOSITORY_SERVER_PROTECTION_UNAVAILABLE_HTTP_403_CURRENT_PLAN` 为 `BLOCKED`，
   所以误触发必须在网络/Git/代码修改前返回 `BLOCKED`。
7. 验证 remote ref 精确等于新 commit、工作树 clean，并等待现有 draft PR #1 的新 CI；
   不得创建重复 PR 或自动 merge。完成这些步骤后才可把
   `CanStartVmBootstrap` 置为 true；`CanStartVmIntegration`、`P10A0AComplete` 与 Formal
   readiness 仍保持 false。

固定工具与 SHA-256：

- PowerShell 7：`C:\Program Files\PowerShell\7\pwsh.exe`，
  `99ec38d8c4910fd5f2feeeec4dedb5076ff39a08ca21e12642822bc8d989e316`；
- Windows PowerShell：
  `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`，
  `0ff6f2c94bc7e2833a5f7e16de1622e5dba70396f31c7d5f56381870317e8c46`；
- Git：`D:\Soft\Git\cmd\git.exe`，
  `da240fe9bc24895b3e04150a4990b8a6ff329ecabcd8f19684c2cc310da5ef3f`；
- OpenSSH：`D:\Soft\Git\usr\bin\ssh.exe`，
  `118091cb71f2fb42e99000d62a9ffc200a6d97e776346a537e443db985bb3baa`。

当时没有可交付的 final onboarding bundle。现有宿主机 heartbeat 仍为暂停但 prompt 尚未
绑定上述未来 final 值；VM task 仍不存在且只能从 VM 设备创建。不得在完成本节步骤前
上 VM，不得在宿主机执行产品 Live，VM 永远不得修改产品代码。

## 2026-07-16 历史宿主机 finalization 与 VM onboarding 标识

2026-07-16 已产生并复验以下宿主机 finalization anchor：

- final quality：`RunId=dd9af0ff-6230-4b42-9420-4f9f7d3048a4`；PowerShell 7 与
  Windows PowerShell 均为 427/427；Failed/Skipped/NotRun/Inconclusive、全部真实
  Live/forbidden/outside/network/registry/secret/unexpected/mutation 指标均为 0；
- Release Simulation DryRun：39 个 package files，inventory exact，
  `Changed=false`，cleanup succeeded；diff 与编码检查通过；
- product commit：`3e843912df2543c1da05b09061970faff511d016`；
- product tree：`5d2d18317e0dfa9359d8caed6b30c5ddad984985`；
- retained owner RunId：`18abf6b2-252c-469a-a8ac-3d050523c77a`；
- onboarding ZIP：
  `%TEMP%\cddsi-test-3e0136c8-88eb-4fee-9441-53d13612e1f7\final-vm-onboarding\cddsi-fast-lane-vm-onboarding.zip`；
- ZIP SHA-256：`58bf3d26930b1c2eda78c29b4d53a89a28794fc7d74ef6ecdb90b6858cb88832`，
  length 630912，18 Store entries，inventory entries 16；
- manifest binding token：
  `c9309d30b02168a3a33552eb0d1dabd7374492a50d06f64e53d6b8e703ad2a54`；
- inventory token：
  `2b9a772a71bcba8fd7723c699d17673cbc6c29e5a7707ba3fb19ce1e2efc84a8`；
- content digest：
  `0978d0d588564d33a7589fedf3c44289fb004142bad00decd2ab632b986169b3`；
- host heartbeat 保持唯一、分钟级、`PAUSED`，最终 prompt SHA-256 为
  `79c9fc91be08baab8b52c4d8861bec3aeed935ab5adf9c068ddb7cbbeb569d6d`；
- PR #1 保持 open/draft；CI `quality` run `29500914381` 与
  `release-contract` run `29500914443` 均为 SUCCESS。

这些值精确绑定旧 commit `3e843912...`。本次 tracked 文档修复会生成新 commit/tree；
因此旧 bundle/task binding 只能作历史证据，不能为新 HEAD 提供 bootstrap authorization。

最终结构化结果必须继续证明真实 product Live/provider、真实 registry/AppX/VMP/service、
用户配置访问、forbidden/outside-sandbox access、unexpected ledger、secret findings 和
宿主机 mutation 均为 0，且 HostSandbox cleanup 成功。

### 2026-07-16 public visibility 预检（历史）

- 三个 GitHub repositories 仍为 private，远端 visibility 未变更。
- 产品 repository 当前已获取的 repair ref（包含已获取 main 历史）可达对象共 11 commits、
  271 blobs、6,007,742 bytes；针对常见 private key、GitHub/OpenAI/DeepSeek/AWS/Google/
  Slack/Stripe token、Bearer/JWT、Basic-auth URI 与敏感赋值/query 的只读扫描为 0 命中。
- 上述 11 个 commits 的 author/committer metadata 均含同一个人邮箱；历史文档还含本机
  项目/工具路径、Codex task/thread 标识、RunId 与工具 hash。用户已明确接受这些信息
  公开且不重写历史：`PrivacyDecision=ACCEPTED`、`HistoryRewrite=NO`。
- 两个 control repositories 各 2 commits，当前仅含 README/outbox 合同文本，未发现消息、
  credential、路径或敏感 evidence；但改为 public 后，未来 outbox envelope 与脱敏诊断
  会全网可读，必须先把 public-safe 字段、retention 与禁止内容写入合同和负向测试。
- PR #1 的 body/diff/comments/threads 模式扫描未见上述敏感值；Actions job logs/下载制品、
  远端未枚举 refs/tags 和 control-repo 原始 author metadata 尚未审计。用户已将它们标记为
  `ResidualPrivacyAudit=NOT_PERFORMED_ACCEPTED_RISK`，不再作为 cutover 门。Release secret
  scanner 的覆盖边界不变，未来 credential/secret 仍严禁进入 public outbox。
- 当时 `gh` token 已失效，GitHub connector 只有读取能力；仍须先关闭版本化
  public-protected 合同和三仓保护部署门，再通过重新认证的 CLI 或受控 GitHub UI 切换。
  当前 visibility、ruleset 与 CLI 认证事实只看下一节。

## 2026-07-17 PUBLIC + protected-history cutover 证据

只读复核窗口为 2026-07-17 04:07:50–04:08:06（北京时间）：

- 产品 `LXZ56156/claude-desktop-deepseek-installer`、host-to-VM
  `LXZ56156/cddsi-host-to-vm` 与 VM-to-host `LXZ56156/cddsi-vm-to-host` 均为
  `PUBLIC`、`isPrivate=false`，default branch 均为 `main`。
- 三个 active ruleset 均名 `cddsi-public-protected-history-v1`；产品 ID
  `19068339` 覆盖 `refs/heads/main` 与 `refs/heads/codex/repair/*`，host-to-VM ID
  `19068292` 和 VM-to-host ID `19068313` 均覆盖 `refs/heads/main`。
- 该复核窗口内，已认证 bootstrap-admin CLI 的 ruleset-detail receipts 对三个仓库均返回
  `bypass_actors=[]`、`current_user_can_bypass=never`；规则精确为
  `deletion`、`non_fast_forward`、`required_linear_history`；三仓 `main` 及产品
  `codex/repair/p10a-0a-fast-lane` 的 effective-rules API 已返回上述三项。三个 `main`
  均不存在额外 classic branch protection（预期）；历史保护由上述 active rulesets 提供，
  不能把 classic endpoint 的 404 误判为未保护。
- public-contract/cutover 质量锚为 `a09130f2afadb6dcf4cfc60a61a72095dc41faa6`；
  HostSandbox `RunId=8e6efa51-9980-4bb5-b60e-8512c08d0205` 双引擎各 430/430、
  全部 zero metrics 为 0；Release Simulation 为 39/39，diff/编码门通过。
- PR #1 为 OPEN/DRAFT/MERGEABLE，head 为上述 `a09130f2...`；quality run
  `29529510594` 与 release-contract run `29529510801` 均 completed/success。
- 当时只读复核中的 `gh` CLI 认证可用，但该易变事实不延续；即使可用也只属于交互式
  bootstrap admin，不是最小权限 automation credential。

这组 receipt 只证明版本化 PUBLIC 合同和服务端保护已部署。包含本节的 tracked 文档会
产生新 commit/tree，因此它不是最终 VM onboarding authorization。

## 2026-07-20 暂停前宿主机收口与 VM 目标入口（历史）

本文提交本身会改变 commit/tree，所以不能在本文内写一个“最终 SHA”再声称它包含本文。
暂停前可以继续宿主修复与验证，但当时仍不能进入 VM。BOM 修复后的 onboarding 专项 28/28 已通过，
PowerShell 7/Windows PowerShell 定点执行均通过；第一次 dirty WIP 全树尝试中 448 个 Pester
全部通过，但 capability-plane 静态门正确拒绝了测试直接调用 `ScriptBlock::Create`。根因已通过
生产 loader 单一 helper 收口并完成专项复测。第二次 dirty WIP 标准 HostSandbox 已通过：
`RunId=accbc437-df47-41a1-999e-4059dd55bca1`，双引擎各 448/448，全部失败/隔离/mutation 指标
为 0、repository unchanged、cleanup succeeded；Release Simulation DryRun 也以 39/39、
`Changed=false` 通过。本文随后同步了该状态，所以这些仍只是 dirty 行为证据；包含本文的最终
clean exact commit 标准门、提交/push、CI 与 finalization 均仍须重新完成。最终精确值只由
retained owner-marked bundle output、同一暂停 automation、PR/CI 与公开 Git/remote 四方
持久事实核验。以下 1–9 只保留暂停前计划，不是当前待办或执行许可；它们已由本文顶部的
controlled pause、未来显式恢复决定和新 readiness receipt 要求覆盖：

1. phase2 canonical TOML/唯一任务/prompt/current-task/HostSandbox 路径绑定正负测试、
   fail-closed facade、execution boundary 和 phase2-only builder/loader 已与 BOM 修复一起通过
   上述 dirty 标准门；最终 clean exact commit 仍须重新证明。
2. BOM 修复的专项回归已覆盖 BOM/no-BOM 实际执行、同一 captured bytes/hash/held handle、
   UTF-16/非法编码 fail closed、semantic ACL、atomic/idempotent state、早期 failure cleanup 与
   显式栈非递归删除；dirty 全树 PASS 仍不能替代 clean-commit finalization。
3. 把全部 tracked 修改作为正常 commit fast-forward push 到既有
   `codex/repair/p10a-0a-fast-lane` 与 PR #1；不得 force push、创建重复 PR、merge、发布或
   promotion。
4. 从该最终 clean exact commit 运行标准 HostSandbox 双引擎全树门；最终测试数以该 clean
   HEAD 的机器结果为准，全部 Failed/Skipped/NotRun/Inconclusive 与 forbidden/live/outside/
   network/registry/secret/unexpected-ledger/mutation 指标为 0，repository unchanged、cleanup
   succeeded。
5. 运行 Release Simulation DryRun，要求 39 package files/39 ZIP entries、四层 inventory
   exact、`Changed=false`、全部 forbidden/secret/mutation 指标为 0；再过 diff/编码门。
6. 从最终 clean exact commit 生成并自校验 Store onboarding bundle：18 ZIP entries、
   inventory entries 16、timestamp 1980；记录 ZIP/manifest/inventory/content hashes、
   长度与 retained owner-marked path。
7. 用 Codex automation 更新既有宿主机 heartbeat，保持同一 id、minute
   cadence、target task 与 `PAUSED`，prompt 精确绑定最终 commit/tree/bundle、repository/
   protection/tool facts。凭据或 runtime assertion 仍为 `UNPROVISIONED` 时，误触发必须在
   任何网络、Git 或代码修改前返回 `BLOCKED`。
8. 核对 remote ref、clean tree、PR #1 仍 OPEN/DRAFT 且最终 HEAD CI 全部成功。暂停前计划曾
   允许以上完成后派生 `CanStartVmBootstrap=true`；该自动派生规则现已失效，不得据此交付或
   进入 VM。
9. `CanStartVmIntegration=false`、`P10A0AComplete=false`、Formal readiness=false。
   服务端 protected history 已完成；窄角色凭据、runtime assertion、VM negative-permission/
   reset/task/unattended evidence 仍缺失。

暂停前状态判定曾规定：上述 1–8 任一项未由外部事实证明时，
`CanStartVmBootstrap=false`；全部成立时才可考虑 bootstrap-only。controlled pause 已撤销这条
自动派生许可：即使未来重新满足同类事实，当前仍固定为 false，必须先有新的显式恢复决定、
新 finalization 和新 readiness receipt；其余三个标志也继续为 false。

暂停前合同曾把普通 disposable VM 启动与 Formal snapshot receipt 分开。当前不得据此启动
guest；正式 P10A/P11 的快照、CAS 与签名要求也没有改变。

宿主机 finalization 负责核验 retained owner-marked path、宿主机 `PAUSED` automation、
PR/CI、clean worktree、remote ref 和服务端保护。VM 看不到这些宿主机事实，也不得重复核验。
宿主机生成器把 11 个最终外部锚点写入提示词：ZIP SHA-256/length，manifest
SHA-256/length/binding token，inventory SHA-256/length/binding token，bundle content digest，
product commit/tree。交付时还必须给出 loader source 与 prompt 各自的 SHA-256/length；tracked
文档不写死这些易变值。VM 提示词不携带 ruleset ID，公开 repository/protection observation
也不构成 sender authority。

### VM bootstrap-only 步骤

以下是 host finalization 通过后交付给用户的目标流程，不是当前执行许可。当前 BOM 修复专项与
dirty WIP 双引擎全树门已通过，但 clean-commit 全树门及 bundle/task/CI finalization 尚未完成，
`CanStartVmBootstrap=false`。

普通用户只做四件事：

1. 用平时的 VM 软件启动 disposable VM；
2. 在 VM 中安装 Codex 并登录；
3. 把宿主机交付的唯一 onboarding ZIP 放进一个新建空文件夹，不解压、不改名，并让
   Codex 打开该文件夹；
4. 只粘贴一次宿主机给出的最终提示词。

其余工作由 VM Codex 自治完成，不再让用户手动执行 hash、解压、PowerShell、Git、密钥或
automation 命令：

1. 准备好的 VM 起始镜像必须已经包含 bundle 精确固定的五个工具：Git、OpenSSH、
   `ssh-keygen`、PowerShell 7、Windows PowerShell。bootstrap 不下载或安装工具；缺失或
   hash/version 不匹配时，在持久状态写入前返回稳定的 `VM_BOOTSTRAP_PINNED_TOOL_*` blocker，
   不让用户在本轮手工排障或补装。
2. 第一段 PowerShell 只做零写入 outer preflight：打开的文件夹不得有 reparse ancestor，且
   必须恰好只有一个普通 ZIP entry；以系统文件长度和 SHA-256 核对原始 ZIP 字节。任何不符
   都在创建/删除文件、启动进程或访问网络前返回 `VM_BOOTSTRAP_BLOCKED`。
3. outer preflight 通过后，Codex 使用自身 `apply_patch` 能力把提示词内的精确 loader source
   写成 ZIP 同目录的固定 ASCII/LF 文件 `cddsi-vm-bootstrap-loader.ps1`；这是第一笔允许的写入，
   不使用 shell 重定向，也不要求用户复制文件。随后运行宿主机生成的短 launcher；launcher
   逐字节核对 loader ASCII、length、SHA-256 和 PowerShell parser 后才执行它。
4. loader 在创建持久 VM-local state 前重新校验原始 ZIP 的 18 个 entry、manifest v3、16 个
   inventory entry、11 个外部锚点和三个固定 runtime dependency；它只提取
   `lib/common.ps1`、`lib/vm-test-relay.ps1` 与
   `operator/fast-lane/invoke-git-outbox.ps1`。唯一带副作用的 operator 目标入口是
   `Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding`；只接受原始 ZIP、11 个外部锚点、
   `BootstrapExecutionContext`、固定 roots、canonical `CodexHome`、target token 和 ack。
   caller result/prompt/observation、`ObservationJsonBase64`、派生目录、direct core/handoff
   或 mutation/failure helper 一律禁止。
5. phase2 Onboarding 只创建本轮 owner-marked VM-local state，
   并生成 product-read、host-to-VM-read、VM-to-host-append 三组互不复用的 device-local
   keypair。成功先返回 `VM_BOOTSTRAP_LOCAL_STAGED`；新 key 仅为 `KEYPAIR_STAGED`，不代表已
   注册或 credential ready，私钥不得进入 prompt、对话、仓库、relay、日志或 public handoff。
6. Codex 用自身 automation 能力查重并创建或原位更新唯一的
   `cddsi-fast-lane-vmtester-minute-poll`，保持精确 id/kind/name、destination、target contract、
   reconcile mode、一分钟 cadence 与 `PAUSED`。phase2 从固定 `CodexHome` 读取真实
   automation TOML，核对 exact schema、唯一性、bindings、完整 prompt 与 prompt SHA-256；
   不接受对话或 caller 构造的 observation，同 ID/name 多份即阻断。本地 staging 后即使
   初扫为零也必须重扫，零到一漂移、重复或无效 readback 都补偿本轮自有 roots 后阻断。
   成功 readback 是绑定持有 TOML 字节的时点 observation，不声称阻止返回后的外部修改；
   每次 Handoff 都在 task 保持 `PAUSED` 时重新扫描和 readback。
7. runtime protection assertion/hash/token 为 `UNPROVISIONED` 时，poll task 即使误触发也必须
   在任何网络、Git、credential probe 或 runtime-state write 前返回 `BLOCKED`。这不影响用户
   显式触发的 bootstrap runner 在 outer binding 匹配后使用上述窄本地写权限。
8. automation readback 通过后，phase2 内部重新校验 package 并构造 handoff。成功只输出
   公开脱敏的 `VM_BOOTSTRAP_STAGED`，删除固定
   loader，保留原始 ZIP 与 owner-marked public receipt 后立即停止。任一步失败也只清理该
   固定 loader。不得 poll/fetch/reset/test、执行产品 Live、修改/提交/推送产品代码、启用
   task、构建候选或把 relay 当正式 evidence。

完成 bootstrap-only 仍不能进入 integration。后续先注册三把公钥并完成真实正/负向权限
测试，`KEYPAIR_STAGED` 才可能变成 credential ready；再由外部 provisioner 发放并绑定
runtime protection receipt，执行 reset smoke、task 安全启用与 unattended loop。这些证据
齐全前不得把 VM task 或宿主机 heartbeat 从 `PAUSED` 改为运行态。

“不让用户手工敲命令”不等于可以静默取得外部权限。为实现用户要求的完整自动闭环，后续
只在确有必要时向用户请求两类一次性授权，具体操作仍由 Codex 完成：

- 若目标是普通全新 Windows VM 而不是 prepared baseline，授权 bootstrap-time network/
  install，以固定官方来源、hash、签名和路径安装五项 prerequisite；未授权时只能选择已
  预装并匹配 manifest 的 baseline。
- 授权一次 GitHub 管理/provisioner 会话注册三把 VM 公钥及宿主机窄身份；该会话只用于
  注册和验证，不能保存为 task credential。之后必须用真正窄身份完成正/负权限测试。

这两项不是要用户逐步操作，也不是现在已经拥有的权限。新任务应先完成宿主机实现与
finalization；需要这些外部权限时再以清晰的一次确认暂停。默认的最后一个人工动作是 P12
发布确认；不得自动 merge、promotion 或 release。

### 暂停前 P10A-0A 稳定能力与 integration 计划（历史；D-024 不执行）

1. public protected 产品 remote `LXZ56156/claude-desktop-deepseek-installer` 已创建，
   旧 `main` 基线已推送，ruleset `19068339` 已覆盖 `main` 与 `codex/repair/*`；本轮改动
   位于 `codex/repair/p10a-0a-fast-lane`。当前交互式 `gh` 身份只作
   bootstrap admin，不能交给 automation；宿主机限 repair-ref 写凭据、VM 独立
   read-only credential 及 VM 负向写验证仍未完成。
2. Fast Lane 本地合同采用一个逻辑双 outbox、两个物理单向 public protected control repos：
   `host-to-vm` 只承载宿主机发往 VM 的消息，`vm-to-host` 只承载 VM 发往宿主机的
   消息。`DirectionalRepositoryPair`、结构化 `CycleId`/sequence/previous hash、
   去重与状态转换已经实现；`LXZ56156/cddsi-host-to-vm` 与
   `LXZ56156/cddsi-vm-to-host` 均已 public，且各自 `outbox/` 已初始化。ruleset
   `19068292`、`19068313` 已验证 protected history；方向隔离 writer credential 与
   runtime protection assertion 仍保持阻断。消息与脱敏报告只作开发诊断，不是正式
   evidence；独立 CAS/WORM、签名 authority 和正式 receipt 留给 P10A/P11 Formal Lane。
3. 固定 Git outbox runtime 已实现：精确绑定 Git/SSH/key/known-hosts hash、repository
   numeric/node identity、protection observation、pinned genesis、线性 history、canonical
   message path 与 owner-marked atomic state/lock，只允许 bounded poll 和 fast-forward
   append，不执行 payload。protection observation 还必须匹配隔离 operator trust root、
   receipt-specific authority assertion、独立预置的 assertion SHA-256/authority token 与
   单调 previous-receipt chain；state leaf 固定为 `fl-<32 lowercase hex>`，Git 只用
   command-local `core.longpaths=true`，不继承 `PATH` 或 global config；服务端 protection
   已就绪，真实 remote 调用仍被 credential/runtime assertion 门阻断。
4. readiness resolver 已把 `CanStartVmBootstrap`、`CanStartVmIntegration`、VM credential/
   automation/reset/unattended、`P10A0AComplete` 和 Formal readiness 分开。deterministic
   onboarding builder 的稳定合同只允许从 clean exact commit 生成 Store ZIP，绑定 commit/tree、
   committed blob/working bytes、工具 hash、三个 repository identity、两个 genesis、
   prompt/runbook，且不包含凭据、用户路径或正式 evidence。当前 v3 one-prompt/phase2
   改造仍在 WIP；BOM 修复专项与 dirty 全树门已通过，但 clean exact commit 的完整门和
   host finalization 尚未完成，不能把这条稳定合同解释为当前 bundle ready。
5. fake deterministic reset、ownership receipt、baseline drift 阻断和诊断性
   `CLEAN_READY` 合同，以及 VM-only dispatcher/provider、device/command trust、
   preflight/postcondition/action receipt 和 fail-closed escalation 已实现。实际
   VM provider/device attestation、owned-resource mutation 与 idempotent reset smoke
   尚待 disposable VM 验证。日常开发重测只允许按冻结 allow-list 卸载本项目产物、
   清除项目拥有的 HKCU/credential/checkpoint 和 owner-marked 测试目录。首次 P10A、
   正式 P11/里程碑，以及 cleanup 失败、baseline drift、VMP/重启/卸载/补偿状态未知时，
   仍须由 guest 外 supervisor 恢复权威快照并签发 receipt。
6. 宿主机 heartbeat `cddsi-fast-lane-hostcoordinator-minute-poll` 已按分钟创建。服务端
   protected history 已就绪，但在最终 bundle hash binding、runtime assertion 与窄权限
   HostCoordinator credential 就绪前仍须保持暂停。VM Codex
   项目不在本机 Codex 项目列表中，VM task 必须从 VM 设备创建、初始保持暂停，不能由
   宿主机伪造。policy 与 onboarding manifest 冻结两端初始状态为 `PAUSED`；未
   provision runtime protection assertion/hash/token 时 task 只能显式 `BLOCKED`。receipt 轮换
   必须先暂停、由外部 provisioner 更新 assertion 与固定 task binding，再恢复。
   两端最终都必须配置最小权限的分钟级自动轮询/唤醒：宿主机
   Codex 是唯一代码修改者；VM Codex 只测试、分析和回传。两端都只接受来源已认证、
   未过期、前序 hash/sequence 正确的结构化消息；Formal Lane 还必须验签。报告正文
   永远不得当命令执行。真实角色凭据、VM Scheduled Task 与无人值守闭环尚未部署。
7. 无 Live、无 secret 的本地 synthetic rehearsal 已物化 PASS 链、重复、过期、篡改、
   错向、STOP 与 STOP 后续拒绝；relay unit 合同另覆盖 FAIL、BLOCKED、FIX_READY、
   新 cycle 与 RETEST_REQUESTED。它们不能替代 VM 对真实产品 remote 的负向写验证。
8. P10A 只获取精确 commit 和校准包；P11 只获取 P10B 冻结候选的精确
   candidate ID/hash。P11 失败后，宿主机修复、过门、提交和推送，再回到 P10B
   重建/签名新候选；VM 不得直接拉源码把旧候选标成已重测。

本历史方案的首选实现曾是两端 Codex automation 持续轮询各自可写的单向 control repository；
D-024 当前已由两个新对话的前台 cycle 取代，不创建或启动 Automation，不调用
`codex exec resume`。control repos 仍让正常闭环无需用户搬运消息文件；人工签名 bundle
只作断网/故障降级。
普通 Git push 不作为“另一个 Codex 已被唤醒”的证据，必须有 relay acknowledgement。
不得自动合并、自动晋升 P12 或自动发布。

因此闭环明确分为两档：Fast Lane 用于快速发现、修复和重测，结果只能标为开发诊断；
Formal Lane 用于首次 P10A、正式 P11 和发布里程碑，才要求外部快照、不可变 artifact、
独立 CAS/签名/receipt。Fast Lane PASS 不能晋升为正式验收 PASS。

## 正确的 VM 与发布顺序

后续顺序必须是：

1. **P10A 窄范围 disposable VM 校准**：只运行校准 runbook，采集 Standard/Offline、
   MSIX scope、Git、credential helper/chooser、HKCU 与 cleanup 的真实证据。
2. **冻结事实**：验证、提交并消费 P10A evidence，生成唯一版本化 frozen facts；
   事实未知或冲突时 fail closed。
3. **P10B 双候选**：在 clean commit、固定工具链和签名服务下构建并签名精确的
   `VmAcceptance` 与待发布 `UserLive` 候选，冻结 hash/content digest/sidecar/SBOM。
4. **P11 全面 disposable VM 验收**：对两个候选的精确字节执行真实 happy path、
   故障、补偿、重启、Chat/Code/Cowork 和泄露扫描。
5. **P12 不可变晋升**：只发布 P11 已测试的 UserLive 原字节，任何变化都返回
   P10B/P11 重新构建和测试。

因此，“真实 provider 首次执行在 P11”是旧说法。P10A 会在专用 disposable VM 内
首次执行严格限域的真实校准；P11 才是对冻结双候选的全面 Live 验收。两者授权都不
扩展到宿主机。

## 进入 VM integration 与 Formal Lane 前的阻塞项（历史清单；当前全部暂停）

暂停前规则曾从 retained owner-marked bundle output、同一 `PAUSED` automation、PR/CI 与公开
Git/remote 四方事实派生 bootstrap-only readiness。该规则现仅作历史证据：四方未来即使再次
精确一致，也不足以自动令任何 readiness 为 true；还必须有新的显式恢复决定、完整
finalization 和新 receipt。当前四个标志全部为 false。以下外部输入继续不能由宿主机 fake
测试虚构；未满足前不得激活真实 outbox integration，也不得宣称
P10A-0A/P10A/P10B/P11 完成：

- 宿主机限 repair-ref/host-to-VM 写、VM product/host-to-VM 只读与 VM-to-host 写的窄
  credentials、runtime protection assertion，以及 product write、错向 write、
  force/delete/rewrite、broad-admin 负测；
- 已暂停的宿主机 heartbeat 的窄 identity/runtime assertion binding 与安全启用、必须从 VM
  设备创建且初始暂停的 VM Codex Scheduled Task；
- VM provider/device trust、真实 deterministic reset smoke、权威 baseline evidence 和
  可重复的 unattended 闭环；
- Formal Lane 使用的独立 evidence store、签名/验签与正式 receipt authority；
- 能在 guest 外恢复固定快照并签发 snapshot receipt 的 hypervisor supervisor；
- P10A 专用 disposable VM、限域 runner/provider、evidence exporter 与受控
  submission 流程，以及真实校准 evidence；
- 受信 CAS store authority/key 管理、原子 commit service，以及 store-issued
  consumption/freeze 签名 receipt；
- 固定的 .NET 构建工具链、helper 源码、依赖锁、SBOM 生成链和实际 PE；
- credential helper 的 Authenticode 身份、证书或签名服务，以及由真实受信
  provider 产生的签名、ACL、DPAPI 与 invocation receipt；宿主机结构性 evidence
  不能作为发布证据；
- 独立的 release-sidecar signing authority、artifact 外部 trust anchor、签名服务
  与可验证 receipt；不能只信任 manifest/sidecar 自带身份；
- copyright holder 与许可证/再分发评审结论；
- P10B 构建时可证明的 clean commit；
- 由已提交 P10A evidence 编译出的冻结 MSIX/Git/helper/HKCU facts。

仓库可以继续把这些外部输入的 schema、验证器、失败注入和 deterministic assembler
做完整，但不得生成假值、测试签名或自签名结果来冒充发布证据。

## 冻结产品流程

- 不提供 Chat/Code/Cowork 选择页；`RequestedSurfaces` 固定三项，managed-policy
  三个 surface 字段固定为 true。
- Git 是产品必备前置；合格且路径唯一时复用，缺失、过旧或损坏时才允许进入经
  验签官方安装/升级流程，不读取或修改全局 Git 配置。
- Readiness 只派生 `EffectiveSurfaces` 和分层状态，不得通过关闭 Code/Cowork 把
  失败静默改写为成功。
- 用户取消 Git/UAC/PATH 必要确认不得报告完成；Cowork 阻断只能返回
  `PARTIAL/ACTION_REQUIRED` 等非成功状态。
- 每个 Release 的 MSIX scope 只能由 P10A 固定版本 VM evidence 冻结；运行时不
  fallback、不双装、不静默迁移。

## 不可突破的停止线

- 不修改只读参考项目。
- 不在宿主机加载或执行 Live adapter，也不访问真实 registry、AppX、VMP、service、
  Credential Manager、网络、进程、任务计划、PATH 或全局 Git/PowerShell 配置。
- 不定位、Test-Path、枚举、哈希、监视、备份、读取或修改
  `%USERPROFILE%\.claude\settings.json`。
- 不引入 Node.js/npm/npmmirror、WSL、VS Code 或独立 Claude Code CLI 安装逻辑。
- 不允许跳过、降级、伪造或绕过签名、SHA-256、path-token 与 artifact identity
  验证。
- 不在日志、fixture、报告、状态、发布包、提交或 CI 中放入真实 API Key。
- 不修改 Claude MSIX 做汉化，不把未执行能力或旧基线写成 PASS。
- VM Codex 不修改源码、候选、runbook 或测试期望，不持有产品仓库写权限；宿主机
  不执行 VM 回传的自由文本，relay compromise 不能扩大为代码执行或发布权限。
- VM 日常 reset 只限项目拥有的安装物、HKCU/credential/checkpoint 与 owner-marked
  测试资源；不得广泛清理用户 profile 或全局工具配置。reset 无法证明基线时升级为
  guest 外快照恢复；正式 P11 通过仍必须从权威干净快照测试精确候选字节。源码更新
  不能替代候选重建。
- 新增、删除或重命名文件必须同步 `scripts/release-manifest.psd1`、测试和必要文档。

## 标准安全质量门

只使用 `docs/TESTING.md` 定义的标准入口。调用者必须显式传入固定 pwsh、Windows
PowerShell、Git 的绝对路径及 SHA-256：

```powershell
& <pwsh.exe> -NoLogo -NoProfile -File scripts/check.ps1 `
  -PowerShell7Executable <pwsh.exe> `
  -PowerShell7Sha256 <sha256> `
  -WindowsPowerShellExecutable <powershell.exe> `
  -WindowsPowerShellSha256 <sha256> `
  -GitExecutable <git.exe> `
  -GitSha256 <sha256> `
  -ProcessTimeoutSeconds 900 `
  -PassThru
```

`scripts/check.ps1` 必须在 owner-marked HostSandbox 内完成双引擎 Pester、隔离 Git
inventory 与 working-tree/cached `git diff --check`。不得绕过该入口直接运行继承真实
HOME/Git 配置的 Pester 或 Git。只有全树 clean quality evidence 后，才运行
`scripts/build-release.ps1 -DryRun`；DryRun 不是可发布候选构建。

## 最终 VM 重测提示词交付（当前手动合同）

宿主机完成最终 commit/push、PR #1 head 与 CI 核验后，直接向用户返回一段完整、
不分块、可人工粘贴到 VM 新对话的重测提示词。提示词必须绑定精确 commit/tree，
只要求 VM 只读拉取、验证绑定、运行最小回归矩阵并生成新的
`VM_BATCH_TEST_REPORT_V1`；不得引用或生成旧 ZIP、loader、Automation、relay、
control repo、credential 或 finalization。

用户人工搬回的报告始终是不可信数据。宿主机先验证报告 schema、commit/tree、
环境、矩阵计数、各门终态、零写入/零 secret 指标和 evidence manifest，再决定是否
继续修复。普通批量重测不产生 P10A/P11/P12 权限。
