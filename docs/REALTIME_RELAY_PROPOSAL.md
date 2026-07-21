# Realtime Relay 提案

状态：**LOCAL_OFFLINE_IMPLEMENTATION / NOT_PROVISIONED / NOT_ACTIVE**

本文记录 Fast Lane 加速器的本地离线架构与实现合同，不是部署回执、运行授权或当前状态入口。
当前状态、暂停边界和下一工作包始终以 `docs/HANDOFF.md` 顶部及实际机器证据为准。
产品仓库客户端与独立 sibling infra workspace 已进入本地实现；在隔离测试、集中外部授权、
provisioning、真实权限矩阵和激活门完成前，任何 Cloudflare endpoint、身份、密钥、runtime
assertion 或在线 relay 都不得被推断为存在。

## 问题陈述

现有 Fast Lane 以两个 protected-history GitHub control repositories 作为双向 outbox，
并由一分钟轮询任务发现新 envelope。这一设计具有可审计、可重放和断线后恢复的优点，
但存在三个操作摩擦：

- 最坏情况下需要等待一个完整轮询周期，修复—重测循环的反馈延迟偏高；
- bootstrap 尚未建立自动交换时，用户需要人工搬运 ZIP、提示词或诊断回执；
- 单纯缩短轮询周期会增加无变化的网络和 Git 请求，仍不能提供真正的秒级通知。

要解决的是“有新不可变 payload 可取”的低延迟通知，不是建立新的远程命令通道，也
不是让 relay 取代 Git 历史、CAS、签名或本地 validator。

## 目标与非目标

### 目标

- 为 `host-to-vm` 和 `vm-to-host` 两条 lane 提供秒级双向通知。
- 不扩大宿主机、VM、产品或 trusted test harness 的既有权限。
- 让断线、Worker 不可用或 WebSocket 重连时仍能由一分钟 Git 轮询恢复。
- 只传固定 schema 的通知和 immutable payload pointer，保持消息小、可验证、可去重。
- 用独立身份、加密认证、顺序链、ACK 和重放防护形成 fail-closed transport。
- 保持 Fast Lane 与 Formal Lane、产品 Live、发布确认之间的现有隔离边界。

### 非目标

- 不通过 WebSocket 传任意 prompt、脚本、命令、日志正文、截图或大型报告。
- 不把 Cloudflare 公网 URL、TLS 连接成功或匿名读取当作 sender authority。
- 不让 VM 编辑、提交或推送产品代码，不让宿主机执行产品 Live。
- 不替代 protected-history control repos、Formal Lane CAS/签名或外部 snapshot receipt。
- 不自动 merge、release、promotion，也不越过 P12 的一次人工发布确认。
- 不在 VM 安装 Node.js、npm、Wrangler 或其他 infra 工具。

## 推荐架构

推荐采用 **Cloudflare Worker + SQLite-backed Durable Object + WebSocket Hibernation**。
这是 operator coordination plane 的独立基础设施，不属于产品运行时或 Release package。

### 组件

1. **Cloudflare Worker 边缘入口**
   - 只接受固定 HTTP/WebSocket 路由和固定版本 schema。
   - 在进入 Durable Object 前验证 method、path、body size、content type、时间窗和 HMAC。
   - 不提供任意 URL fetch、任意 repository 代理、shell、prompt 或 free-text 转发能力。
2. **SQLite-backed Durable Object**
   - 按环境和 lane 选择确定的 object key，串行化 sequence、previous hash、nonce、ACK
     和短期连接元数据更新。
   - SQLite 只保存受限通知元数据、全生命周期 MessageId/body-hash 去重 tombstone 和逐消息
     ACK 状态；通知正文只保留在有界窗口内，不保存大 payload 或 secret。
   - 使用 WebSocket Hibernation 接受客户端连接，使空闲连接可休眠并在消息到达时恢复。
     代码不得依赖休眠前的内存状态；恢复所需状态来自 SQLite 或受限 socket attachment。
3. **两个 PowerShell 7 客户端**
   - 宿主机 HostCoordinator 和 VM VmTester 均使用 .NET `ClientWebSocket` 建立 `wss://`
     连接、重连、发送 ACK 和接收通知。
   - 客户端只把验证通过的固定事件交给既有固定 validator/runner 入口。
4. **两个现有 GitHub control repositories**
   - `host-to-vm` 与 `vm-to-host` protected-history outbox 继续保存 durable audit record 和
     immutable payload pointer，并作为断线兜底的事实来源。
   - 一分钟轮询继续保留为 fallback；未来 realtime 启用不删除、不弱化该路径。

Worker 只暴露以下固定路由；任何其他 method/path/query 均在进入 Durable Object 前拒绝：

| 路由 | 用途 | 固定边界 |
|---|---|---|
| `GET /v1/watch?lane=<lane>&after=<sequence>` | WebSocket watch/resume | 只允许该 identity 的读取 lane；`after` 必须为非负 safe integer |
| `POST /v1/publish/<lane>` | 发布规范 notification | 只允许该 identity 的写入 lane；正文必须是唯一规范 JSON |
| `POST /v1/ack` | 逐消息 ACK | 只接受固定 ACK schema 和原消息绑定 |
| `GET /v1/messages/<lane>?after=<sequence>` | 有界断线重放 | 只允许该 identity 的读取 lane；不得越过 retention gap |
| `GET /v1/health` | 匿名存活检查 | 只返回固定 OK/protocol 元数据，不返回 identity、secret、消息正文、sequence、repository 或 storage 状态 |

### 数据流

`host-to-vm` lane：

1. HostCoordinator 用其 lane 专用发布身份将 envelope/payload pointer 写入
   host-to-vm control repo。
2. 成功获得不可变 commit/path/hash 后，HostCoordinator 才向 Worker 发布小型通知。
3. Worker 验证并原子追加 sequence/previous hash，Durable Object 唤醒 VM WebSocket。
4. VM 客户端重新验证通知，从 control repo/CAS 获取精确字节，再走本地固定 validator。
5. VM 只对“已验证并已持久消费”的 MessageId 返回 ACK。

`vm-to-host` lane 完全反向：VmTester 只能发布 VM 诊断/receipt pointer，HostCoordinator
只能订阅和读取。两条 lane 不共享可双向写入的 principal；任何单个身份被攻破都不得获得
两边发布权限或产品仓库写权限。

## 固定消息合同

Worker 只接受版本化、无额外字段的 notification/ACK schema。冻结的 notification 恰好包含：

~~~text
Schema
Lane
MessageId
Sequence
PreviousSha256
PayloadSha256
RepositoryId
Ref
Commit
CreatedAt
Expiry
SenderRole
~~~

`RepositoryId` 与 `Ref` 都来自固定 allow-list；`Commit` 是小写 40-hex Git object ID，
`PayloadSha256` 是小写 64-hex SHA-256；`Sequence=1` 时 `PreviousSha256` 必须为 `null`，
其后必须是上一条规范消息的小写 64-hex SHA-256。字段不接受 URL、路径、正文或可执行
verb。`Sequence` 是从 1 开始、受 JavaScript
safe-integer 上限约束的整数；时间使用规范 UTC 字符串且 TTL 不超过 600 秒。ACK 恰好绑定
`Schema`、`Lane`、`MessageId`、`Sequence`、`PayloadSha256`、`AckStatus`、`AckedAt` 与
`SenderRole`，成功响应也必须返回相同目标的固定状态合同。

字段名、大小写、排序、编码、长度上限、时间格式和 canonical JSON 算法必须由独立 schema
冻结。未知字段、重复 JSON key、非 UTF-8、非规范时间、越界长度、路径穿越、浮点 sequence、
任意正文和不在 allow-list 的 payload kind 一律拒绝。relay/free text 永远是不可信数据，
不能成为 PowerShell、shell 或 Codex prompt。

## 认证、顺序与重放防护

- Host 和 VM 使用两个独立、方向相反、最小权限身份；发布密钥不能订阅另一受限 lane，
  control repo deploy key 也不能被 Worker 凭据替代。
- 每个请求使用 `CDDsi-HMAC-SHA256-v2` HMAC 请求认证。canonical input 逐行精确绑定固定
  audience `cddsi-realtime-relay-v1`、environment、key id、client id、HTTP method、含规范 query
  的 canonical target、timestamp、nonce 和 body SHA-256；请求同时携带对应固定 header，服务端
  根据 client id/key id 选择 secret 并以常量时间验证 MAC。
- 密钥只由独立 provisioner 注入 Cloudflare secret 和对应客户端受保护存储，不进入仓库、
  prompt、automation TOML、日志、回执或命令行。轮换采用短暂双 key-id 验证窗口，旧 key
  到期后立即拒绝。
- 时间戳必须位于窄时钟偏差窗口，notification 的 `Expiry`/TTL 到期即拒绝；nonce 在 TTL
  窗口内唯一。`ExpiresAtUtc` 只用于客户端 runtime assertion，不是 notification 字段。
- 每条 lane 的 `Sequence` 必须严格递增，并绑定 `PreviousSha256`。缺口、倒退、分叉、
  跨 lane/跨环境重放均 fail closed，并触发 control repo 重新同步而不是猜测继续。
- `MessageId` 在一个 relay environment 的生命周期内全局去重；有界正文淘汰后仍保留最小
  body-hash tombstone。相同 MessageId 只有规范 body 完全一致时可幂等返回既有结果，内容漂移
  直接拒绝并记录 public-safe 原因码。
- ACK 逐消息绑定原 MessageId、lane、sequence 和已验证持久消费状态，并允许幂等重复。服务端
  不用一个连续 ACK watermark 阻塞后续消息；断线恢复由客户端持久 `LastAckedSequence` 与严格
  sequence/previous-hash 链共同保护。发送成功不等于 ACK，ACK 也不替代 control repo commit、
  测试 receipt 或 Formal evidence。
- ACK response 丢失时，服务端在有界正文窗口内仍可重放已 ACK/已过期的精确 notification；
  客户端只有在本地 state 已记录相同 sequence、MessageId、message hash 与 payload hash 时，才可
  跳过 CreatedAt/Expiry freshness 并补发 ACK，且绝不再次 wake。未见过的陈旧/过期通知仍 fail
  closed 并转 control-repository fallback；late ACK 不授予任何执行 authority。
- 对 identity-total、identity/lane/operation、连接和全局 body bytes 设独立速率限制、并发上限
  和突发桶。限流时
  fail closed，客户端退回带抖动的指数重连及一分钟轮询，不丢弃 durable pointer。

## 本地消费边界

Cloudflare 的公网 URL 不是 sender authority。TLS、HMAC 和 Worker 接受只说明请求来自某个
relay identity；消费端仍必须执行既有固定 validator：schema、control-repo 身份、protected
history、commit/path、hash、长度、sequence、previous hash、TTL 和 public-safe 字段检查。

watcher 只能把验证通过的固定事件映射到预先登记的 runner verb，并唤醒固定入口。它不得：

- 执行 relay 字段、payload 正文或自由文本；
- 拼接 shell/PowerShell/Codex 命令；
- 写产品仓库、变更 automation 状态或扩大 Live/network/credential grant；
- 因 WebSocket 消息而跳过 Git/CAS 拉取、hash 验证或本地状态 CAS；
- 把连接、通知或 Fast Lane PASS 提升为 Formal evidence。

出站 publisher 使用与 watcher 分离的 writer context、provider 和最长 600 秒的 runtime
assertion。调用方只能提交恰好包含 `SchemaVersion`、`Lane`、`MessageId`、`PayloadSha256`、
`Commit` 的固定 pointer；其中小写 UUIDv4 `MessageId` 必须复制自已创建且不可变的 control-repo
envelope，随后仍由消费端 Git `Poll` 二次验证。RepositoryId、ref、sender role、sequence、
previous hash、创建时间和五分钟 expiry 均由本地固定策略或持久状态派生。客户端必须在首次
HTTP 之前原子保存规范 body 与其
SHA-256。响应丢失、进程重启或 TTL 已过时仍只能重发相同 bytes/MessageId；只有精确绑定该消息的
`201/PUBLISHED` 或 `200/PUBLISHED_IDEMPOTENT` 才能推进 publisher sequence/hash 并清除 pending。
若消息从未被 relay 接受，过期重发由服务端正常拒绝；客户端不得在同一 environment epoch
静默生成替代 MessageId 或跨过 pending chain。

Live 客户端不接受调用方提供的 wake scriptblock/closure。它只接受无可执行成员的固定 Git
outbox binding，逐次复验客户端源码、`Invoke-CddsiFastLaneGitOutbox` runner、binding SHA-256、
lane/client/repository/ref 与 runtime assertion，再以固定 `Poll` 操作消费精确 pointer。Poll 回执
必须逐字段绑定 MessageId/sequence/commit/payload hash，并只允许 `CONSUMED_NOW` 或
`ALREADY_CONSUMED`。Git outbox 的 AcceptedRemoteHead、SeenMessageIds 与原子 state CAS 覆盖
“Git 状态已提交但 watcher state 尚未提交”的崩溃窗口；watcher state 已提交后的 ACK 丢失只
重复 ACK，不重复 wake effect。

`CONSUMED_NOW` 后客户端先原子记录 lane-specific `PENDING` wake proof，再以 hash 绑定的绝对
`codex.exe` 直接执行固定 `exec resume --json <fixed-session-uuid> <fixed-prompt>`。relay、Git
payload、报告和模型文字都不得进入 executable、argv、prompt、environment 或 working root。
进程必须使用 Windows job object、空 stdin、固定 timeout、无继承 PATH/proxy/token 的最小环境，
并有界 drain 后丢弃 stdout/stderr。只有 job assignment 成功、未 timeout/未终止 process tree、
exit code 0 且 runtime assertion 再验证通过，proof 才能原子推进为 `SUCCEEDED`；ACK 必须在其后。
匹配的 `ALREADY_CONSUMED` + `SUCCEEDED` 不重复 spawn，匹配的 `PENDING` 可按 at-least-once 语义
重试同一固定 resume。下游固定 inbox handler 因而必须幂等，且任何 proof 漂移都 fail closed。

Live `ExecutionContext` 及 state/transport/wake/clock/credential provider 必须是精确属性集的
纯数据 descriptor；只有模块内部固定 dispatch 可以触发实现，fake scriptblock 只允许非 Live。
runtime assertion 精确绑定 endpoint、environment/key id、client adapter hash 与这些 provider，
有效期不得超过 600 秒，并在 receive、wake、state commit、ACK 签名和发送前重新验证。真实 relay
网络尝试单独累计 `OperatorRelayNetworkRequestCount`，即使 descriptor/源码随后漂移也不得把已经
发生的请求错误报告为 0；产品 Live、产品 network/process/registry/credential 和 mutation 指标
继续固定为 0。清理只使用进入网络前已验证并内部捕获的 trusted session id；即使 provider/source
随后漂移或 socket close/dispose 失败，也必须从内部 session table 移除，不能接受调用方伪造 id。

上述 source/hash 检查绑定的是当前磁盘字节与数据 descriptor，不是对已加载 PowerShell function
或动态 .NET type 的内存证明。Live 必须从核验精确字节后的全新、可信 PowerShell 7 runspace
启动；任意同 CurrentUser 代码执行或已被篡改的 runspace 能同时绕过 DPAPI/ACL 与进程内类型边界，
属于本版本可信计算基之外。怀疑该类 compromise 时必须停止 watcher/publisher、丢弃该 runspace，
轮换两个 runtime credential 并重新签发 runtime assertion，不能把磁盘 hash 当成内存 attestation。

客户端 credential 创建/轮换只接受内存中的精确 32-byte `byte[]`。`TestSafe`/`DryRun` 只返回
脱敏计划并且不得接触文件系统或 DPAPI；`Live` 还要求独立确认、PowerShell 7、owner-marked
CurrentUser ACL/no-reparse state root 与单实例锁。创建使用 `CreateNew`，轮换必须提供旧 blob
SHA-256 CAS；候选写入同目录 `.next`、flush-to-disk、DPAPI CurrentUser round-trip 校验后再原子
Move/Replace，且不得创建旧 credential backup。任何残留 `.next` 或历史 `.backup` 都会在解密、
签名或网络前阻断 watcher；任何失败保留旧 credential，只返回固定错误码，绝不输出 secret、
DPAPI blob、用户路径或底层异常文本。真实 DPAPI 调用仍只允许在后续获批的专用设备
provisioning 门执行。

Realtime lane `Sequence` 与 control-repository envelope `Sequence` 是两个独立的单调域：前者
只保护 WebSocket/HTTP notification 链，后者只保护 Git control history。固定 wake receipt 会
原样回显并绑定 transport sequence，但 Git consumer 不得要求二者数值相等；它以精确 commit、
MessageId、RepositoryId、ref、payload hash 和 protected history 证明同一 pointer。把两个序号
错误耦合会在合法 Git history 已领先时造成拒绝，因此必须由回归测试禁止。

客户端日志只记录 public-safe MessageId、lane、sequence、hash 和原因码。HMAC、Authorization、
完整 payload、用户路径和凭据不得落盘。任何本地 spool 必须是 owner-marked、protected ACL、
有界、原子写入且可按精确归属清理。

## 工具与仓库隔离

VM 运行时只使用已固定并验证的 PowerShell 7 和 .NET `ClientWebSocket`；不得为了 relay 安装
Node/npm。宿主机产品仓库同样不得加入 Wrangler、Node dependency、Cloudflare token、部署
脚本或生成物。

Worker TypeScript、Wrangler 配置、schema、部署测试和 infra runbook 位于独立本地
**sibling infra repo** `D:\projects(WIN)\cddsi-relay-infra`。它与产品仓库使用独立 Git、权限、
secret 和 release cadence；它只产出可审计
的 Worker version、deployment id、route、schema hash 和 runtime assertion receipt，产品
仓库只消费经过评审的不可变公共事实。当前 sibling 只在本地且没有 remote；创建 Cloudflare
project、route、secret、身份、远端或发布仍属于后续外部 provisioning，不由本地实现授权。

## 与既有两条证据 lane 的关系

- **Fast Lane**：realtime relay 只加速“有新 durable pointer”的发现；GitHub control repo
  仍是 durable source 和断线 fallback，一分钟轮询仍是恢复路径。
- **Formal Lane**：首次 P10A、正式 P11 和里程碑证据仍要求外部 clean snapshot receipt、
  独立 CAS、签名、精确 candidate id/hash 与既有消费门。realtime 通知没有证据权威。
- **P12**：一次人工发布确认保持不变。禁止自动 merge、release、promotion。

这一工作流不重编号、不替代 P10/P11/P12，也不代表旧 VM bootstrap 可以恢复。任何 tracked
修改都会使旧 finalization、bundle、prompt、automation binding 和 readiness receipt 失效；
恢复 bootstrap 必须在新的最终 clean commit 上重新执行完整 finalization。

## 实施阶段

使用独立的 `RT` 前缀，避免改变既有产品阶段编号：

1. **RT0 — 设计冻结（本地完成）**：评审威胁模型、schema、canonicalization、lane ACL、
   TTL、rate limit、fallback 和成本上限；状态保持 NOT_PROVISIONED。
2. **RT1 — sibling infra repo（本地实现）**：独立 workspace 已建立 Worker/SQLite Durable
   Object/WebSocket Hibernation、声明式 `exports` lifecycle 合同、协议 kernel 和零依赖离线测试；没有 remote、生产
   identity、npm 获取、Wrangler 登录或部署。Wrangler/Miniflare runtime integration 和 dry-run
   必须在集中授权后以固定版本补齐。
3. **RT2 — 本地客户端合同（本地实现）**：DevelopmentOnly PowerShell 客户端已实现
   `ClientWebSocket` adapter、独立 writer publisher、fixed Codex resume/wake proof、固定
   validator、ACK 状态机、owner-marked state、重连/resume 与 fake transport，以及受 CAS/原子
   写保护的 DPAPI CurrentUser credential 创建/轮换入口；
   TestSafe/DryRun 的宿主真实网络、registry、credential、process 及产品 Live 必须继续为 0，
   真实 DPAPI/网络不属于离线测试证据。
4. **RT3 — 外部 provisioning**：在用户一次明确授权后创建 Cloudflare 资源、两组 relay
   identity/secret、窄 route 和 runtime assertion；bootstrap-admin 凭据不得保存或复用。
5. **RT4 — disposable 环境校准**：仅在重新 finalization 后，以非产品 synthetic payload
   验证正反权限、重放、掉线、顺序、限流和 fallback；两端 automation 先保持 PAUSED。
6. **RT5 — canary 激活门**：独立审阅部署 receipt、客户端 hash、runtime assertion 和负向
   权限证据后，才可另行决定启用 accelerator；启用 realtime 不取消一分钟轮询。
7. **RT6 — 运行与撤回**：监控 public-safe SLO/错误码，定期轮换密钥，演练单开关禁用和
   control-repo-only 回退。

每个阶段都必须有独立退出条件和机器回执。前一阶段通过不自动授权后一阶段。

## 测试矩阵

| 类别 | 必测正向 | 必测负向/故障 |
|---|---|---|
| Schema | 两条 lane 的 canonical notification 与 ACK | 额外/缺失/重复字段、非法 UTF-8、超长 body、错误 lane/kind/path |
| HMAC | 当前 key id、固定 method/path/body hash | 错 key、错 MAC、跨 lane、篡改 body/path、未知/过期 key id |
| 时间与重放 | 窄偏差内 timestamp、唯一 nonce、单调 sequence | 过期 TTL、未来时间、nonce/MessageId 重放、倒退/跳号/分叉 previous hash |
| Durable Object | SQLite 原子提交、幂等重复、ACK 恢复 | 并发发布、休眠重建、事务失败、schema migration 失败、存储不可用 |
| WebSocket | 双客户端接收、休眠唤醒、ACK | 断网、半开连接、乱序/重复帧、重连风暴、连接上限 |
| Publisher | 两端相反 writer ACL、control-envelope MessageId、pending-before-network、201/200 与本地 confirmed-state 幂等推进 | 原子写失败、响应丢失/重启/过 TTL 精确补发、完成后返回丢失、pending/state/pointer 冲突 |
| Pointer | 精确 repo/commit/path/hash/length 消费 | mutable ref、错误 repo/hash/length、路径穿越、缺失 commit、public URL 伪权威 |
| 权限 | Host 只发布 host-to-vm，VM 只发布 vm-to-host | 反向写、产品 repo 写、跨环境访问、匿名 sender authority |
| Watcher | 验证后唤醒固定 verb | free text/command injection、未知 verb、验证前执行、产品 Live |
| Fixed wake | Poll receipt、PENDING→固定 resume→SUCCEEDED→ACK | proof 漂移、argv/prompt/env 注入、job/timeout/exit 失败、输出截断、exit 后 commit 崩溃 |
| 组合链 | publisher bytes→watcher→Git target/receipt，relay/Git sequence 域故意不同 | MessageId/repo/ref/commit/payload 任一漂移、把两个 sequence 域错误耦合 |
| Fallback | relay 不可用时一分钟轮询发现相同 pointer | Worker 5xx/429、DNS/TLS 失败、ACK 丢失；不得丢消息或重复执行 |
| 隔离/secret | fake 网络账本、脱敏日志、owner-marked spool | secret/log 泄漏、宿主保护区访问、outside-sandbox 写、未知进程/网络 |
| Formal/P12 | 保持原有证据和人工确认门 | Fast Lane PASS 提权、自动 merge/release/promotion |

测试必须覆盖 PowerShell 7 的确定性 fake transport 和 disposable 环境真实网络；可共享的
parser/schema/security helper 同时在 Windows PowerShell 5.1 运行。不得在开发
宿主机通过产品代码探测公网、Credential Manager、真实 automation 或保护资源。负向测试不能
通过放宽 timeout、接受不同错误或跳过断言来“稳定”。外部 Cloudflare 测试之前必须先通过
零依赖协议/状态机测试、产品 focused tests、全仓质量门、Release Simulation DryRun、secret
scan 与 Wrangler 可审阅 dry-run；Wrangler/Miniflare 尚未固定安装时不得伪称 runtime integration
已通过。

## 外部授权点

以下动作均不由本地实现授权。离线门完成后必须一次性向用户列明资源、URL、权限、套餐/成本、
回滚并请求明确授权：

1. 允许在独立 infra workspace 使用已核验的固定 Node LTS，并仅在该 workspace 安装固定版本
   Wrangler、TypeScript 与测试依赖；安装必须产生并核验 lock/integrity，不得消费 PATH 上的
   全局 Wrangler；
2. 允许该 workspace 访问 npm 与 Cloudflare；第一阶段只安装、typecheck、执行 Wrangler
   dry-run 并扫描生成物，任一版本、schema、bundle 或 secret-scan 漂移都必须停止，不能继续登录；
3. 允许先只读执行固定 Wrangler 的 `login --scopes-list` 并评审最小 OAuth scopes，再执行一次
   命名 OAuth 浏览器登录。Wrangler
   `4.112.0` 不接受 `login --profile`，因此不得修改或复用 default profile；必须在
   `CLOUDFLARE_AUTH_USE_KEYRING=true` 的脱敏子进程中执行当前等价命令
   `wrangler auth create cddsi-relay`，再把该命名 profile 精确绑定到 infra workspace。
   Windows keyring helper 也必须以固定版本、lock/integrity 在授权后单独引导，不能让 Wrangler
   从 PATH 选取任意全局 helper。浏览器交互凭据只进入 Windows Credential Manager/keyring，
   明文 profile 必须不存在，且 deploy OAuth credential 与 runtime relay credential 完全分离；
   待固定 Wrangler 的实时 scope list 复核的最小候选集合恰好是 `account:read`、`user:read` 与
   `workers_scripts:write`。官方 Tail API 接受 `Workers Scripts Write` 作为
   `Workers Tail Read` 的替代，因此不能再冗余请求 `workers_tail:read`。Wrangler 源码还会在
   OAuth URL 中隐式请求
   `offline_access`；它不得作为 `--scopes` argv 项，登录后却必须在脱敏 `whoami` 回读中被验证。
   缺少任一项、出现任何额外项、scope 语义漂移或存在多个 account 都必须停止。该 deploy OAuth
   grant 是 account 级 Worker 管理权限，并不天然缩窄到本 Worker；窄 lane 权限只由两组完全
   分离的 runtime HMAC capability 提供，二者不得复用；
4. 创建一个 Worker 和一个 SQLite-backed Durable Object，初始只使用 `workers.dev`，不购买
   套餐、不绑定自有域名、不修改 DNS；
5. 生成 HostCoordinator/VmTester 两组独立 256-bit runtime secret，经 Wrangler secret 写入
   Cloudflare；同一受保护 provisioner 必须把对应值分别写入实际 HostCoordinator 与 disposable
   VM 的 DPAPI CurrentUser 存储，全程只用内存/stdin 且立即清零。若不能同时进入两个正确的
   CurrentUser 设备上下文，必须停止，不能把两份客户端 credential 暂存在同一宿主账户或磁盘；
6. 部署到精确 `workers.dev` endpoint；
7. 执行正确方向、反向越权、错 token、伪造 HMAC、nonce
   重放、过期、跳号、断线恢复和 fallback 的真实正负 smoke。

上述授权若获批准，预期外部资源集合仍必须精确限制为：Worker service
`cddsi-realtime-relay`；声明式 `exports` 管理的 SQLite Durable Object class/namespace
`RelayRoom` 与 Worker binding `RELAY_ROOM`；首次请求才按固定名称
`relay-room:production-v1` 惰性创建的逻辑 object；两项 secret binding；以及 Cloudflare 分配的
`cddsi-realtime-relay.<account-subdomain>.workers.dev` route。初始 `secret bulk` 可能先为同名
Worker 创建 draft，但不得产生第二个 Worker。精确 account subdomain 和最终 URL 只能由登录后
回读确定，不能预先猜测。授权不包含自有域名、DNS、公开 infra remote、系统服务、计划任务、
付费升级或其他 Cloudflare 产品；出现多 account、付费/升级提示或额外资源计划必须停止并重新
请求决定。

成本门默认只允许现有 Workers Free plan：当前官方额度包含 Worker/DO 每日请求限额，SQLite DO
另有每日 row read/write 与总存储限额；超过 Free 限额应失败而不是自动付费。Workers Paid 是独立
的 account 级订阅且当前最低为每月 5 美元，不在本授权内。WebSocket Hibernation 用于降低空闲
duration，但它不是零成本保证；部署前后都必须回读实际 account plan 与用量设置。

创建公开 infra remote、CI identity、系统服务/计划任务或激活任一 watcher/automation 不包含在
上述 provisioning 授权内，仍需另行明确决定。

交互式 GitHub、Cloudflare 或 bootstrap-admin 会话不得变成 automation credential。未获得授权、
未 provision runtime assertion/hash/token、或任何权限验证失败时，客户端与 automation 必须
在网络/Git/credential probe/runtime-state write 前保持 BLOCKED/PAUSED。

## 回滚与禁用

必须设计一个不依赖 Worker 可用性的本地 kill switch。禁用顺序为：

1. 将 realtime watcher/adapter 置为 PAUSED，不再建立新连接；不得触发产品动作。
2. 撤销或轮换两组 relay key，并禁用 Worker route/部署；保留 public-safe 审计元数据。
3. 保持两个 protected-history control repos 和一分钟轮询合同不变，回退到 control-repo-only。
4. 对未 ACK MessageId 从 Git durable source 重新同步并幂等消费，不信任内存队列。
5. 按 owner marker 清理本任务自有临时 spool；不删除 retained evidence、历史 bundle 或未知目录。

删除 Worker、Durable Object namespace/实例或 Cloudflare 版本属于不可恢复的外部破坏动作，只能在
回读精确资源后另行获得 fresh destructive authorization；一般 kill switch 或 rollback 授权不包含删除。

回滚不改变 Formal Lane、P12 人工确认或产品权限。若 schema、identity、sequence 链或 runtime
assertion 发生漂移，默认动作是 fail closed 和回退，而不是自动修复服务器权限。

## 激活前退出条件

只有以下条件同时成立，后续任务才可以把状态从 NOT_ACTIVE 改为候选激活：

- sibling infra repo、Worker version、SQLite `exports` lifecycle 和 schema hash 已冻结并通过独立 CI；
- 两条 lane 的 HMAC identity、control repo deploy key 和 runtime assertion 已 provision，正反
  权限矩阵全通过；
- PowerShell 7 客户端、validator、watcher fixed-entry、ACK/重连/fallback 的双引擎 host gate
  与 disposable VM evidence 均通过；
- secret、forbidden/outside/network/process/registry/unexpected-ledger 指标满足现有隔离合同；
- kill switch 与 control-repo-only 回退演练通过；
- 旧 bootstrap 暂停之后的全部 tracked 修改已在新的 clean exact commit 上重新 finalization，
  新 bundle、automation binding、remote、PR CI 和 retained receipt 精确一致；
- 用户对外部 provisioning 和最终激活分别作出所需的明确确认。

当前只存在本地离线实现，外部与激活条件均未证明。本文状态保持
**LOCAL_OFFLINE_IMPLEMENTATION / NOT_PROVISIONED / NOT_ACTIVE**。

## 官方技术参考

- [Cloudflare：Durable Objects WebSocket Hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)
- [Cloudflare：WebSocket Hibernation server 示例](https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/)
- [Cloudflare：SQLite-backed Durable Object Storage](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/)
- [Cloudflare：Durable Object migrations 与声明式 `exports`](https://developers.cloudflare.com/durable-objects/reference/durable-objects-migrations/)
- [Cloudflare：安装与固定 Wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/)
- [Cloudflare：Wrangler secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Cloudflare：Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)
- [Microsoft：System.Net.WebSockets.ClientWebSocket](https://learn.microsoft.com/dotnet/api/system.net.websockets.clientwebsocket)
