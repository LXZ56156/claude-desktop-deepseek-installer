# Realtime Relay 提案

状态：**PROPOSED / NOT_PROVISIONED / NOT_ACTIVE**

本文只定义一个待评审的 Fast Lane 加速器，不是部署回执、运行授权或当前状态入口。
当前状态、暂停边界和下一工作包始终以 `docs/HANDOFF.md` 顶部及实际机器证据为准。
在新的独立工作包完成实现、隔离测试、外部授权、provisioning 和激活门之前，任何
Cloudflare endpoint、身份、密钥、runtime assertion 或在线 relay 都不得被推断为存在。

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
   - SQLite 只保存受限通知元数据、去重窗口和 ACK 状态；不保存大 payload 或 secret。
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

Worker 只接受版本化、无额外字段的 notification/ACK schema。建议 notification 至少包含：

- `SchemaVersion`、`Lane`、`MessageId`；
- `SenderId`、`KeyId`、`IssuedAtUtc`、`ExpiresAtUtc`；
- 随机 `Nonce`、单调 `Sequence`、`PreviousMessageHash`；
- allow-list 内的 `PayloadKind`；
- `PayloadRepository`、精确 `PayloadCommitSha`、规范化 `PayloadPath`；
- `PayloadSha256`、`PayloadLength` 和 envelope/pointer 的 canonical hash；
- `AckRequired`，以及 ACK 中唯一允许出现的 `AckOfMessageId` 与消费结果代码。

字段名、大小写、排序、编码、长度上限、时间格式和 canonical JSON 算法必须由独立 schema
冻结。未知字段、重复 JSON key、非 UTF-8、非规范时间、越界长度、路径穿越、浮点 sequence、
任意正文和不在 allow-list 的 payload kind 一律拒绝。relay/free text 永远是不可信数据，
不能成为 PowerShell、shell 或 Codex prompt。

## 认证、顺序与重放防护

- Host 和 VM 使用两个独立、方向相反、最小权限身份；发布密钥不能订阅另一受限 lane，
  control repo deploy key 也不能被 Worker 凭据替代。
- 每个请求使用 HMAC 请求认证。canonical input 至少绑定 schema、HTTP method、规范 path、
  sender/lane、timestamp、nonce、body SHA-256 和 key id；服务端以常量时间比较 MAC。
- 密钥只由独立 provisioner 注入 Cloudflare secret 和对应客户端受保护存储，不进入仓库、
  prompt、automation TOML、日志、回执或命令行。轮换采用短暂双 key-id 验证窗口，旧 key
  到期后立即拒绝。
- 时间戳必须位于窄时钟偏差窗口，`ExpiresAtUtc`/TTL 到期即拒绝；nonce 在 TTL 窗口内唯一。
- 每条 lane 的 `Sequence` 必须严格递增，并绑定 `PreviousMessageHash`。缺口、倒退、分叉、
  跨 lane/跨环境重放均 fail closed，并触发 control repo 重新同步而不是猜测继续。
- `MessageId` 全局去重；相同 MessageId 只有字节完全一致时可幂等返回既有结果，内容漂移
  直接拒绝并记录 public-safe 原因码。
- ACK 绑定原 MessageId、lane、payload hash 和已验证消费状态。发送成功不等于 ACK，ACK
  也不替代 control repo commit、测试 receipt 或 Formal evidence。
- 对 sender、lane、IP/连接和全局 body bytes 设独立速率限制、并发上限和突发桶。限流时
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

客户端日志只记录 public-safe MessageId、lane、sequence、hash 和原因码。HMAC、Authorization、
完整 payload、用户路径和凭据不得落盘。任何本地 spool 必须是 owner-marked、protected ACL、
有界、原子写入且可按精确归属清理。

## 工具与仓库隔离

VM 运行时只使用已固定并验证的 PowerShell 7 和 .NET `ClientWebSocket`；不得为了 relay 安装
Node/npm。宿主机产品仓库同样不得加入 Wrangler、Node dependency、Cloudflare token、部署
脚本或生成物。

Worker TypeScript、Wrangler 配置、schema、部署测试和 infra runbook 必须位于独立的
**sibling infra repo**。该仓库使用独立 CI、权限、secret 和 release cadence；它只产出可审计
的 Worker version、deployment id、route、schema hash 和 runtime assertion receipt，产品
仓库只消费经过评审的不可变公共事实。创建仓库、Cloudflare project、route、secret 或身份
都属于后续外部 provisioning，不由本文授权。

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

1. **RT0 — 设计冻结**：评审威胁模型、schema、canonicalization、lane ACL、TTL、rate limit、
   fallback 和成本上限；状态保持 NOT_PROVISIONED。
2. **RT1 — sibling infra repo**：创建独立仓库，完成 Worker/SQLite Durable Object/WebSocket
   Hibernation 实现、迁移、单元/集成测试和无 secret 构建；不连接生产身份。
3. **RT2 — 本地客户端合同**：在 fake/sandbox provider 中实现 PowerShell 7
   `ClientWebSocket` adapter、固定 validator、ACK 状态机、重连和 Git fallback；宿主机网络
   及产品 Live 继续为 0。
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
| Pointer | 精确 repo/commit/path/hash/length 消费 | mutable ref、错误 repo/hash/length、路径穿越、缺失 commit、public URL 伪权威 |
| 权限 | Host 只发布 host-to-vm，VM 只发布 vm-to-host | 反向写、产品 repo 写、跨环境访问、匿名 sender authority |
| Watcher | 验证后唤醒固定 verb | free text/command injection、未知 verb、验证前执行、产品 Live |
| Fallback | relay 不可用时一分钟轮询发现相同 pointer | Worker 5xx/429、DNS/TLS 失败、ACK 丢失；不得丢消息或重复执行 |
| 隔离/secret | fake 网络账本、脱敏日志、owner-marked spool | secret/log 泄漏、宿主保护区访问、outside-sandbox 写、未知进程/网络 |
| Formal/P12 | 保持原有证据和人工确认门 | Fast Lane PASS 提权、自动 merge/release/promotion |

测试必须覆盖 PowerShell 7 的确定性 fake transport 和 disposable 环境真实网络；不得在开发
宿主机通过产品代码探测公网、Credential Manager、真实 automation 或保护资源。负向测试不能
通过放宽 timeout、接受不同错误或跳过断言来“稳定”。

## 外部授权点

以下动作均不由提案授权，实施时必须在精确计划和固定事实就绪后向用户请求明确授权：

1. 创建/选择 Cloudflare account、Worker、Durable Object namespace、route/custom domain。
2. 创建 sibling infra repo 及其 protected branch/history、CI identity 和部署权限。
3. 生成并注册 Host/VM 两组独立 HMAC/relay identity，写入 Cloudflare secret 与客户端受保护
   存储，并验证正反向拒绝矩阵。
4. 允许 disposable VM 与宿主 operator watcher 访问精确 `wss://` endpoint 和两个 control repos。
5. 从 PAUSED 状态激活任一 watcher/automation。

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

回滚不改变 Formal Lane、P12 人工确认或产品权限。若 schema、identity、sequence 链或 runtime
assertion 发生漂移，默认动作是 fail closed 和回退，而不是自动修复服务器权限。

## 激活前退出条件

只有以下条件同时成立，后续任务才可以把状态从 NOT_ACTIVE 改为候选激活：

- sibling infra repo、Worker version、SQLite migration 和 schema hash 已冻结并通过独立 CI；
- 两条 lane 的 HMAC identity、control repo deploy key 和 runtime assertion 已 provision，正反
  权限矩阵全通过；
- PowerShell 7 客户端、validator、watcher fixed-entry、ACK/重连/fallback 的双引擎 host gate
  与 disposable VM evidence 均通过；
- secret、forbidden/outside/network/process/registry/unexpected-ledger 指标满足现有隔离合同；
- kill switch 与 control-repo-only 回退演练通过；
- 旧 bootstrap 暂停之后的全部 tracked 修改已在新的 clean exact commit 上重新 finalization，
  新 bundle、automation binding、remote、PR CI 和 retained receipt 精确一致；
- 用户对外部 provisioning 和最终激活分别作出所需的明确确认。

当前这些条件均未由本文证明。本文状态保持 **PROPOSED / NOT_PROVISIONED / NOT_ACTIVE**。

## 官方技术参考

- [Cloudflare：Durable Objects WebSocket Hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)
- [Cloudflare：WebSocket Hibernation server 示例](https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/)
- [Cloudflare：SQLite-backed Durable Object Storage](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/)
- [Cloudflare：安装与固定 Wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/)
- [Microsoft：System.Net.WebSockets.ClientWebSocket](https://learn.microsoft.com/dotnet/api/system.net.websockets.clientwebsocket)
