# 外部合同与调研基线

最后核验：2026-07-22

项目影响更新：2026-07-25（D-027 正式只支持 Windows 11 x64 +
Windows PowerShell 5.1；D-026 与历史 relay/Automation 不再产生操作权）

本文件是 Anthropic、DeepSeek、Windows、Git、Cloudflare 和 OpenAI Codex 外部事实的
唯一项目内来源。上游可能随版本变化；实现不得只依赖这里的文字，必须把适用版本和
实物证据写入合同。

本文中的部署选择和代码差异只是外部事实对项目的影响摘要；产品/技术选择以
`docs/DECISIONS.md` 为准，易变实现状态以 `docs/HANDOFF.md` 和实际 Git 状态为准。
上游支持范围不自动成为本产品支持范围；D-027 明确不发布或验收 Windows 10/Arm64。

## 状态定义

- **官方确认**：官方文档明确说明。
- **实物待验**：方向已确认，但每个发布包或 Desktop 版本仍需验证。
- **待决策**：需要产品或安全选择。
- **历史旁证**：过去本机曾成功，不作为当前 Release 证明。

## OpenAI Codex operator coordination

截至本次核验，Codex 官方文档确认：

- Codex app automation 可以按计划在本地项目后台运行，也可以从现有 task 创建并
  返回同一 task；本地 automation 依赖 Codex app/电脑保持可运行状态。
- 非交互 `codex exec` 可用于脚本化运行，支持 JSONL `--json`、
  `--output-schema`、输出文件和 resume；默认安全边界仍应保持只读/最小权限。
- Codex notification 可以在需要关注或工作结束时通知操作者，但 notification 本身
  不是跨代理的受信消息、授权或验收证据。

官方来源：

- [Codex automations](https://learn.chatgpt.com/docs/automations.md)
- [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode.md)
- [Codex notifications](https://learn.chatgpt.com/docs/notifications.md)

“一次 Git push 会直接唤醒另一台机器上的既有 Codex 对话”不是上述官方合同；这是
项目根据当前能力边界作出的设计推论。Fast Lane 因此使用独立于产品 remote 的逻辑
control plane，envelope 绑定 CycleId、单调 sequence、前序消息 hash 和双向身份。

截至 2026-07-15，本地 operator 合同已经实现于
`config/fast-lane-policy.psd1`、`lib/vm-test-relay.ps1`、
`lib/vm-reset.ps1` 和 `operator/fast-lane/*`。GitHub deploy key 的权限作用于整个
repository，而不是 repository 内的单一路径；同一 repository 的两个目录不能靠两把
writable deploy key 精确隔离写权限。因此一个逻辑 control plane 由两个物理单向
repository 承载：宿主机只写 host-to-VM repository，VM 只写 VM-to-host
repository，并分别只读另一方向。不能用共享可写 token 把它降级为一个双方可写仓库。

Fast Lane 只用于日常诊断，不以 WORM、message signing 或每轮整机快照为前置，也不
产生 P10A/P11 正式证据。Formal Lane 才对 P10A/P11 使用外部 clean snapshot 与独立
CAS/receipts/signatures。

若 control plane 由 GitHub 承载，可利用 ruleset/protected-ref 和 repository-scoped
deploy key 收窄每个物理 repository 的权限；deploy key 不是 path-scoped capability，
所以方向隔离来自两个 repository 与两套最小角色凭据，而不是目录约定。
2026-07-15 当时实测个人账号对 private repository 创建 ruleset 返回 HTTP 403；
2026-07-16 用户选择
GitHub Free public 方案，并接受现有 history/metadata 与未来 public outbox 可见性且不
重写历史。版本化 public 合同通过后，三仓已于 2026-07-17 切换为 public，并分别启用
ruleset `19068339`、`19068292`、`19068313`。服务端已验证无 bypass actor，且对目标 refs
实际施加 deletion、non-fast-forward 与 linear-history 约束；private 套餐的 HTTP 403
不再是当前阻塞。GitHub 只提供一种可选实现，项目不能把它限定为唯一 transport，也不能把 Git
remote 当作 WORM/CAS 或签名/receipt 服务。

public control repository 的所有历史 envelope、ACK 与脱敏诊断对互联网可读。合同必须
把 public-safe 字段白名单、禁止的个人/本机/credential/自由文本内容、retention 和删除不
等于撤回的事实冻结进 schema/tests；不能用 repository 名称不可猜测或之后删除 commit
作为隐私控制。

- [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [GitHub deploy keys](https://docs.github.com/en/rest/deploy-keys/deploy-keys)
- [GitHub repository visibility](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility)

## Cloudflare realtime relay

截至本次核验，Cloudflare 官方文档确认：

- Durable Objects 同时可用于 Workers Free 与 Workers Paid；Workers Free 只能创建和
  访问 SQLite-backed Durable Objects，且 Cloudflare 推荐新 namespace 使用 SQLite。
- 当前 Workers Free 额度为 Worker 请求 100,000 次/日；Durable Objects 请求
  100,000 次/日、duration 13,000 GB-s/日；SQLite storage 为读取 5,000,000 rows/日、
  写入 100,000 rows/日、SQL stored data 合计 5 GB。额度是上限合同，不是本项目的
  容量目标；超过 Free 边界必须失败并暂停，不能自动切换付费方案。
- WebSocket Hibernation API 是 Durable Objects WebSocket server 的推荐接口；休眠时
  客户端连接仍保持，duration 不累计，事件到达后 object 重新初始化。内存状态会重置，
  因此可恢复协议状态必须落在 SQLite storage 或受限 WebSocket attachment 中。
- Wrangler 的声明式 `exports` 是当前 Durable Object class lifecycle 入口，并取代新实现
  的命令式 `migrations` 流程；代码 export、配置声明与已 provision namespace 会在部署时
  对账。新建 live class 的 `storage` 必须为 `sqlite`。
- `GET /accounts/{account_id}/workers/subdomain` 返回账号的 Workers subdomain；
  script subdomain GET 返回 Worker 是否在 `workers.dev` 启用。初始 relay endpoint 因此只用
  `workers.dev`，不要求或授权自有域名、route 或 DNS 修改。
- versions API 明确把列表第一项定义为最新 version；deployments API 明确把第一项定义为
  当前主动承载流量的最新 deployment。部署后回读必须同时核对最新 version、主动 deployment、
  binding、SQLite `RelayRoom` export 和 script 的 `workers.dev` 状态，不能只信 CLI 成功文本。
- Worker account settings GET 的返回模型只有 `default_usage_model` 与 `green_compute`；
  该字段是 usage-model 配置，不是 Billing subscription receipt。`standard` 与当前 Workers Paid
  相关，`bundled`/`unbound` 是 legacy usage models，三者都不能证明 Workers Free。订阅列表是
  独立 API，并要求 Billing Read 或 Billing Write；本任务的四项必需 OAuth scope 本身不包含该
  权限，既有 profile 的额外 scope 也不能把 account settings 推断成“已证明 Free 套餐”。

官方来源：

- [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [Durable Objects WebSocket Hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)
- [Durable Object declarative class exports](https://developers.cloudflare.com/durable-objects/reference/durable-objects-migrations/)
- [Worker account settings API](https://developers.cloudflare.com/api/resources/workers/subresources/account_settings/)
- [Account workers.dev subdomain API](https://developers.cloudflare.com/api/resources/workers/subresources/subdomains/methods/get/)
- [Worker workers.dev state API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/subdomain/methods/get/)
- [Worker versions API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/versions/methods/list/)
- [Worker deployments API](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/deployments/methods/list/)
- [Account subscriptions API](https://developers.cloudflare.com/api/resources/accounts/subresources/subscriptions/methods/get/)

项目影响是把秒级通知实现限制在独立 sibling `cddsi-relay-infra` workspace：Worker、
SQLite-backed `RelayRoom`、Wrangler/Node/TypeScript 和所有 Cloudflare 配置均不得进入产品
安装器或 Release。当前精确本地 toolchain、139/139 离线测试、69-file secret scan、guarded
typecheck、实际 workerd/SQLite/Hibernation forced-eviction integration 与 Wrangler dry-run 已
通过；本地 forced eviction 不替代生产 idle scheduling 或公网平台证据。用户已授权 Free-only
认证、创建、secret、部署与真实正负测试，并在知悉既有 encrypted keyring `default` profile 的
29 项 scope 包含四项必需项及 25 项额外项后，明确授权直接复用且不要求 exact-scope equality。
本地采用路径已实现可续期 owner-marked receipt 和 account-bound 私有 credential snapshot；截至
2026-07-21，真实精确 infra root 的 exact/inherited binding absence 已证明，初始 generation-1 receipt
已绑定 `default.enc`、account 与 permission hashes。2026-07-22 epoch update 时旧 token 无法
refresh，用户在个人 Edge 明确确认一次 OAuth，generation-3 renewal 随后通过。固定四 GET preflight 已确认单一账号、必需
scope、既有 account subdomain 与目标 script 不存在，并报告
`WorkersUsageModel=STANDARD / BillingPlanVerified=false /
BILLING_VERIFICATION_REQUIRED`；该段是写入前事实。随后已创建 Free-only Worker/SQLite Durable
Object 与两项 runtime secret binding，endpoint 为
`https://cddsi-realtime-relay.lizixuan6383828.workers.dev`，postdeploy 精确回读、Host HTTP smoke
和跨设备 relay-only smoke 均通过。生产 WebSocket reconnect/Hibernation 尚无公网 E2E 证据。
经用户授权复用个人 Edge 既有登录态的只读 Billing → Subscriptions 核对未列出 Workers/Workers
Paid；active Teams Free Base 与无关 R2 Paid 不把整个账号分类为 Free，不升级 Workers，也不授权
relay 使用 R2。Workers-only machine receipt validator/recorder 已在 infra 本地实现并通过测试，
但没有签发真实 receipt；这只说明人工观察不是 Cloudflare 官方机器回执。项目的
D-022 已决定接受该观察作为本次 Free-only 部署依据，machine receipt/ticket
仅作 optional hardening，不再是写门。如真实 Cloudflare 界面/API/CLI 显示付费或升级
要求，仍必须停止。SQLite-backed Durable Objects 支持 Workers Free，Free 超限后操作
失败而非计费。

## Anthropic Third-Party Desktop

### 已确认能力

Anthropic 已正式提供 Claude Desktop Third-Party（3P）模式：

- 可以连接 Anthropic-compatible gateway。
- 不需要 Anthropic 账号登录或席位。
- Chat、内置 Code 和 Cowork 使用同一受管 provider 与凭据。
- Windows 支持在应用启动前部署 managed configuration。
- 配置在启动时读取，因此写入后需要重新启动 Desktop。

官方来源：

- [Third-party overview](https://claude.com/docs/third-party/claude-desktop/overview)
- [Installation](https://claude.com/docs/third-party/claude-desktop/installation)
- [Configuration reference](https://claude.com/docs/third-party/claude-desktop/configuration)
- [Configuration changelog](https://claude.com/docs/third-party/claude-desktop/configuration-changelog)
- [Gateway configuration](https://claude.com/docs/third-party/claude-desktop/gateway)
- [MDM deployment](https://claude.com/docs/third-party/claude-desktop/mdm)
- [Code tab](https://claude.com/docs/third-party/claude-desktop/code)
- [Feature matrix](https://claude.com/docs/third-party/claude-desktop/feature-matrix)

### Windows 配置来源

官方文档列出的配置面包括：

- `HKLM\SOFTWARE\Policies\Claude`
- `HKCU\SOFTWARE\Policies\Claude`
- `%LOCALAPPDATA%\Claude-3p\configLibrary\`

当前文档说明配置源存在优先级且不做字段级合并。实现必须先检测 HKLM、HKCU 和
local source 的占用情况，把一个完整配置写在一个拥有明确所有权的层级；发现
更高优先级配置时 fail closed，不得以“写成功”误判为“生效”。

首版无 Developer Mode 的首选方案是 Windows managed configuration。
由于 credential helper 和隐藏模式选择器都是 MDM-only，首版 configLibrary 只
用于冲突检测、导出研究和兼容性验证，不作为实际写入目标。

### 目标配置键

以下是下一阶段要固化为版本化 fixture 的官方方向，不表示当前代码已实现：

| 目的 | 目标键/值 | 状态 |
|---|---|---|
| 第三方 gateway | `inferenceProvider=gateway` | 官方确认 |
| 凭据来源 | `inferenceCredentialKind=helper-script` | 官方确认 |
| DeepSeek base URL | `inferenceGatewayBaseUrl` | 官方确认 |
| 认证方案 | `inferenceGatewayAuthScheme=x-api-key` | 官方确认 |
| 模型发现 | `modelDiscoveryEnabled=false` | 官方确认 |
| 固定模型 | `inferenceModels` | P2 fixture 已按 `name/labelOverride/supports1m` 固定 |
| Chat | `chatTabEnabled=true` | 官方确认 |
| Code | `isClaudeCodeForDesktopEnabled=true` | 官方确认 |
| Cowork | `coworkTabEnabled=true` | 官方确认 |
| 自动模式 | `autoModeEnabled=false` | 暂定安全默认 |
| 隐藏模式选择 | `disableDeploymentModeChooser` | MDM-only，启动行为实物待验 |
| 凭据 helper | `inferenceCredentialHelper` | MDM-only，打包方案待决策 |
| Helper TTL | `inferenceCredentialHelperTtlSec` | MDM-only，默认 3600 |
| Helper timeout | `inferenceCredentialHelperTimeoutSec=60` | MDM-only，官方默认 60、范围 1–600 |
| Helper 静默刷新 | `inferenceCredentialHelperSilentRefreshEnabled=true` | MDM-only，官方默认开启 |

Windows registry 官方合同已经明确：

- 值直接写在 policy key 下，不使用子键。
- canonical 表示使用 `REG_SZ`；布尔/整数也可用 `REG_DWORD`。
- 数组/对象必须写成 JSON 字符串。
- 不使用 `REG_EXPAND_SZ`、`REG_QWORD`、`REG_MULTI_SZ` 或 `REG_BINARY`。
- HKLM policy 存在时完全覆盖 HKCU；managed source 覆盖 local。
- 仅设置自动更新相关键的 managed source 是 precedence 例外。

项目统一使用 `REG_SZ`，减少类型分支。P2 fixture 已固定 15 个值、完整 JSON
字符串和 Desktop `1.20186.0` 最低版本；当前 HKLM/HKCU 整体不合并语义的版本门槛
另记为 `1.19367.0`。

### 凭据

Anthropic 提供 credential helper 机制。helper 输出的 token 在内存中按 TTL
缓存；静态 API Key 若直接放在 registry/config 中则仍是明文持久化。Desktop 还会
通过 `CLAUDE_HELPER_CONTEXT` 区分 `interactive`、`mid-session-refresh`、
`scheduled-task`、`setup-test` 和 `background`；`mid-session-refresh` 的调用超时会
额外限制到 20 秒，其余已知 context 按项目配置使用 60 秒。

项目因此选择“安全输入 + DPAPI CurrentUser + helper”的方向，详细设计见
`CONFIGURATION_DESIGN.md`。

官方来源：

- [Credential helper](https://claude.com/docs/third-party/claude-desktop/credential-helper/)
- [Data storage](https://claude.com/docs/third-party/claude-desktop/data-storage)

## Windows 与 Claude Desktop 安装

上游官方安装条件（不等于 D-027 产品支持矩阵）：

- 上游文档列出的最低 Windows 版本包括 Windows 10 build 19041；D-027 产品明确只
  支持和验收 Windows 11 x64，不从该上游最低条件外推 Windows 10 支持。
- x64 或 Arm64。
- Cowork 需要 MSIX 和硬件虚拟化。
- Windows 支持按用户 `Add-AppxPackage` 和整机
  `Add-AppxProvisionedPackage` 部署。
- Cowork 完整能力可能要求管理员权限、整机预配和
  VirtualMachinePlatform。

官方来源：

- [Claude Desktop Windows deployment](https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows)
- [Third-party installation](https://claude.com/docs/third-party/claude-desktop/installation)

2026-07-26 的只读来源核验确认：官方 Windows deployment 页的 x64 MSIX 链接精确为
`https://claude.ai/api/desktop/win32/x64/msix/latest/redirect`。该入口当前必须用不自动
跟随的 GET 观察，返回 307 和空 body；HEAD 返回 405。当前 Location 是
`downloads.claude.ai/releases/win32/x64/.../*.msix`，终点返回 200、
`application/octet-stream`、无下一跳并声明 Content-Length。这些是时点性的 transport
形状，不是 frozen artifact metadata；实现仍须逐次手动验证 redirect、终点 header、
实际接收长度和内容。

该 `latest` endpoint 的 unresolved source descriptor binding 只标识官方请求策略和
transport 入口，不是 immutable artifact/cache identity。D-027 的首次 acquisition
snapshot workload 可以把精确候选、这个 source binding 和产品 temp 目标绑定到一次
外部 clean-snapshot authorization，但不能预先声称最终 SHA-256、signer、Publisher、
package identity 或安装权限；这些必须在实际 body 完成后由同句柄证据产生，并由独立的
完整 provisioning workload 再授权。

代码中的纯 transport header contract 目前精确固定官方核验到的单次 GET 307 →
GET 200、唯一 Location、终点无下一跳、`application/octet-stream`、无 content/
transfer encoding 和唯一有界 Content-Length。它允许 raw transport URI 在调用期间
携带不透明易变 query，但 query 前的 raw URI 必须逐字节等于 canonical
`https://downloads.claude.ai/releases/win32/x64/<numeric.version>/Claude-<40-lower-hex>.msix`
projection，不允许 dot/percent canonicalization、显式端口、Unicode control/separator
或平台/架构歧义。文件名 hex 只是 routing grammar，不作为 hash evidence。只保留这个
scheme/host/path projection；raw URI/query 不被哈希、绑定或持久化。该 policy
observation 不下载 body，也不是最终 URL、SHA-256、signer、Publisher、package identity
或 cache identity；上游形状改变时必须 fail closed 后重新核验。

每个实际 MSIX 的 URL、架构、SHA-256、Authenticode signer、证书链、Publisher、
package identity 和最低 Desktop 版本仍属于**实物待验**，不能只靠固定字符串。

标准 MSIX 会在首次功能使用时取得部分运行资源；离线 MSIX 体积更大。首版采用
哪种包仍是待决策项。

## DeepSeek Anthropic-compatible API

DeepSeek 官方 endpoint：

`https://api.deepseek.com/anthropic`

认证方案为 `x-api-key`。当前官方服务端模型映射方向：

- `claude-opus-*` 请求映射到 `deepseek-v4-pro`。
- `claude-sonnet-*`、`claude-haiku-*` 请求映射到
  `deepseek-v4-flash`。

`deepseek-chat` 和 `deepseek-reasoner` 是旧兼容名，不能进入正式配置。P2 只把
`deepseek-v4-pro` 与 `deepseek-v4-flash` 的精确 API ID 写入 `inferenceModels`，
并将 Pro 作为第一项默认；两个条目均按 DeepSeek 官方 1M 上下文能力写入
`supports1m=true`。

`anthropicFamilyTier` 是单值 enum，而官方没有说明同一 `name` 能否重复绑定 Sonnet
和 Haiku。P2 因此不猜测重复条目：服务端 alias 映射作为独立内部事实保留，外部
serializer 暂不写 `anthropicFamilyTier/isFamilyDefault`。P10/P11 必须分别验证 UI
选择、实际请求模型和 DeepSeek 的静默 fallback，不能仅凭请求成功判定模型正确。

官方来源：

- [DeepSeek API 首页](https://api-docs.deepseek.com/)
- [Anthropic API compatibility](https://api-docs.deepseek.com/guides/anthropic_api/)
- [API updates](https://api-docs.deepseek.com/updates/)

DeepSeek 兼容层对基础文本、streaming、thinking 和 tool use 支持较好，但图片、
document、container、部分 MCP/code-execution 结果等内容块存在缺口。Chat 文本
通过不等于 Code/Cowork 全功能通过，验收必须拆分。

DeepSeek 官方没有承诺稳定的 API Key 前缀或长度。产品只可拒绝空值、多行、控制
字符和不合理长度；`sk-` 等前缀校验在没有版本化官方证据前不得作为硬合同。

## Claude Code 与 Git

Claude Desktop 自带 Code 功能，不需要本项目安装独立 Claude Code CLI、Node.js
或 npm。外部技术事实是 Windows 本地 Code 工作流需要 Git，而 Chat 本身不要求
Git。项目产品决策固定包含 Code，因此本安装器必须确保 Git 可用；这是产品范围
推导，不是对上游技术依赖的错误改写。

官方来源：

- [Claude Code desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart)
- [Git for Windows downloads](https://git-scm.com/install/windows)

Git 下载元数据、静默参数、签名身份、安装范围和 PATH 行为仍需固定版本实物
验证。即使 Git 官方安装器默认会修改 PATH，本项目也不能在未形成授权和回滚
合同前静默接受。

## 中文界面

Anthropic 当前公布的 Desktop UI 语言列表不含简体中文或繁体中文：

- [Use Claude in your preferred language](https://support.claude.com/en/articles/10769299-how-to-use-claude-in-your-preferred-language)

项目只提供中文安装器、说明和报告，不修改签名应用资源，不集成非官方汉化。

## 分发与法律边界

Claude 3P 使用仍受 Anthropic 条款约束，DeepSeek 使用受其服务条款约束。发布前
需要完成许可证和再分发评审。暂定 Release ZIP 只包含本项目脚本；Claude MSIX
和 Git 安装器在运行时从官方来源获取，不重新打包分发。

- [Claude third-party legal](https://claude.com/docs/third-party/claude-desktop/legal)

## 当前代码与官方合同的边界

本节是便于评审的非权威摘要；精确当前状态以 `docs/HANDOFF.md` 为准。

P2 已在 `config/deepseek-desktop.defaults.json`、
`New-CddsiClaudeDesktopDesiredConfig` 和版本化 fixture 中完成正式纯数据迁移：

- provider、endpoint、auth、helper、模型、三项 surface 和安全默认均精确固定；
- Windows serializer 输出 15 个直接位于 policy key 下的 `REG_SZ`；
- HKLM、HKCU、configLibrary 的 8 组 synthetic presence 组合按当前优先级解析；
- 任一既有来源均默认冲突停止，不携带原始值；
- configLibrary writer 已关闭，所有 mutation-shaped 配置函数仍 plan-only。

这只证明纯合同，不证明真实 registry、helper、Desktop UI 或 DeepSeek 请求。当前
Key 格式函数已经移除固定前缀假设，只拒绝空值、空白/控制字符、非可打印内容和不
合理长度。handoff 时 HKCU writer 仍未实现：D-026 要求先在 `VmDevelopment`
disposable VM 实现，并用不可 promotion 的 development ZIP 真实测试配置、DPAPI、
API 和完整功能流程；收敛后再由 P10A 冻结 helper/chooser/HKCU 事实、P10B 构建
候选，最终由 P11 对精确候选字节重复全面验收。

以下本地 operator coordination 合同与 Free-only relay 部署只保留历史背景，不等于
产品激活，也不再是当前开发依赖：

- `config/fast-lane-policy.psd1` 冻结产品 remote、两个物理单向 control repository、
  两端角色、分钟级轮询、guest reset 和禁止 promotion 的策略；
- `lib/vm-test-relay.ps1` 实现 Fast Lane canonical envelope、双 repository/outbox
  身份、CycleId、sequence、previous hash、CAS、单 active cycle、STOP 和 fail-closed
  transition；
- `lib/vm-reset.ps1` 实现 owner receipt、冻结 allow-list、baseline、升级判定和
  `CLEAN_READY` 的纯合同，TestSafe/DryRun 只消费 fake provider，Scaffold Live 在
  provider dispatch 前失败；
- `lib/vm-fast-lane-readiness.ps1` 分开派生 VM bootstrap、integration、P10A-0A 与
  Formal readiness；
- `operator/fast-lane/*` 保存固定 Git outbox runtime、deterministic onboarding builder、
  VM-only guest-reset dispatcher/provider boundary、两端 prompt/runbook 和 synthetic 演练。

独立 `cddsi-relay-infra` workspace 已实现 Cloudflare Worker/SQLite Durable Object、
WebSocket Hibernation 与本地 readback/dry-run gates；产品仓库的
`operator/realtime-relay/realtime-relay-client.ps1` 只消费固定通知 schema 并调用固定 wake
adapter。两者都仍是未激活的 coordination plane：既有 encrypted keyring `default` OAuth
profile 已完成 generation-1 adoption、GET-only preflight 与 Edge Billing dashboard 人工核对；
Workers Paid 未列出，D-022 已授权在没有 machine Billing receipt/Host/VM DPAPI receipt
的情况下走 lean provisioning 和一次性临时-secret smoke。Host 可用进程内存/
安全输入；VM 可人工拖入 repo 外 owner-only fixed-schema JSON，并由固定 smoke 脚本在
首次网络前删除。该文件不进入 Git/prompt/日志/evidence，不是长期明文存储。用户回传的
`VM_RELAY_READINESS_V1` 为 `Ready=true`。Free-only Worker/SQLite Durable Object、两项 secret
binding、endpoint、postdeploy 精确回读、Host HTTP 与跨设备 relay-only smoke 已完成；生产
WebSocket reconnect/Hibernation 尚未公网 E2E。现有 control repositories 继续作为持久审计与
断线 fallback，automation 继续保持暂停；
DPAPI 在启用持久 watcher 前才是必选。

这些文件属于 OperatorCoordination development plane，不进入默认 bootstrap、
ProductCore 或 Release 包。三个 public protected repositories 已部署，产品旧 `main` 已推送，
两个 control `outbox/` 已初始化；这只完成 transport bootstrap，不等于角色授权。
Windows reset adapter boundary 已实现精确 resource/provider allow-list、device/command
trust、preflight/postcondition、action receipt 与 fail-closed escalation，但尚无 disposable
VM 的 device provisioning、Live mutation、idempotence 或 clean-receipt evidence；它不能
在宿主机/CI 执行，也不进入产品包。自由文本只是不受信数据，固定 prompt 不包含 deploy
key、token 或其他凭据。

历史设计中 protected history 已部署并验证；两个方向的最小角色凭据、runtime protection assertion、
VM 产品 remote 只读负向验证、real guest reset、VM automation、安全启用当前暂停的 host
heartbeat 与两端无人值守闭环仍是外部阻断项。宿主机不得执行 product Live，VM 不得
编辑、提交或推送产品代码。在这些证据完成前不得宣称 P10A-0A 完成。relay 仍只传输
状态与诊断引用；正式判断消费独立 CAS、签名和 receipt。

D-026 当前开发协调不使用上述 relay 或 Automation。宿主机 clean handoff 后冻结写入，
disposable VM 通过官方交互认证取得现有开发分支/PR 的阶段性唯一写入租约，并在 VM 内
实现和验证 Live。最终候选重新冻结后仍按 Formal P10A/P11 的独立 snapshot、CAS、签名
和只读验收合同处理。

## 历史实测的正确使用

2026-07-12 的本机历史测试曾验证 Chat、Code、Cowork 可以连接 DeepSeek。该结果
只能证明方向可行，不证明当前 Desktop、DeepSeek 模型或配置 schema 仍完全相同。
正式发布必须在后续干净 VM 中重新验证。

## 更新程序

任何上游事实更新必须：

1. 记录核验日期、官方 URL 和适用版本。
2. 区分“官方文档事实”和“当前 artifact 实测”。
3. 更新 fixture、Pester、`DECISIONS.md`、`HANDOFF.md` 和变更日志。
4. 对模型、schema、签名或最低版本变化运行完整回归。
5. 未确认值保持 `null` 或 fail closed，禁止凭经验猜测。
