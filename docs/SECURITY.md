# 安全设计

更新日期：2026-07-25

## 安全目标

- 默认拒绝真实系统修改。
- 宿主机开发测试不接触真实用户配置或系统资源。
- 安装只消费完整、当前、路径绑定的官方 artifact 验证证据。
- API Key 不进入不允许的持久面或可分享证据。
- 项目拥有的 policy、credential、state 和备份在任何写入失败点可精确恢复；
  共享系统资源使用显式补偿矩阵，不承诺整机事务式回滚。
- 未测试能力不能被报告为成功。

## 当前 D-026 安全边界

D-026 只改变开发阶段的 writer 和执行地点，不降低产品安全门：

- 宿主机提交 clean handoff 后冻结产品写入；disposable VM 的 `VmDevelopment` stage
  成为现有分支和 PR #1 的唯一 writer。不得双写、force push、改写历史或创建重复 PR。
- 宿主机、CI、TestSafe、DryRun 和默认 bootstrap 继续零 Live。真实系统探测、安装、
  HKCU policy、DPAPI credential、AppX/进程、VMP/UAC/重启和最小 DeepSeek 请求只允许
  在明确 disposable VM 内由 package-bound Live context/provider 执行。
- VM 开发可以反复修改和重测；最终候选必须重新冻结 clean commit/ZIP，之后只读验收。
  失败返回开发 stage 并构建新候选，不能热补丁被测字节。
- 实际 Release ZIP 的安装、配置、API、恢复和 Computer Use Chat/Code/Cowork 是发布
  关键门。retired relay/outbox/Automation 传输与旧 evidence-plumbing 回归可保留为
  非阻塞历史诊断，但不得伪造 PASS，也不得掩盖产品、安全或供应链失败；正式候选的
  P10A/P11 evidence 仍是 P12 前置。
- 任何 API Key 即使低余额也不得进入 Codex 对话、prompt、argv、环境变量、Git、测试
  fixture、日志、状态、报告、截图、evidence 或 Release。已经贴入对话的 Key 视为暴露，
  应撤销/轮换；新 Key 只由用户在 VM 本地遮罩输入，Codex 不读取、不转述、不截图。
- `RELEASE_READY` 不等于发布授权。merge、GitHub Release、promotion 和 P12 仍由用户
  人工决定。

## 风险成比例原则（D-022；历史已撤销）

Realtime relay 是独立 operator notification plane，不是产品安装器 Live。对它的
控制必须围绕可能导致实际损害的路径，不得将所有理论 hardening 都变成
当前交付门。Free-only 部署和一次性 relay-only VM smoke 不要求 machine
Billing receipt、two-phase ticket、coordinated provisioner/DPAPI receipts、bulk semantics 或
two-secret staging receipt。现有相关代码可保留作 optional defense-in-depth。

以下是历史 relay 决策当时不可放宽的直接风险：Cloudflare 出现付费/升级提示；secret
泄漏到日志、Git、prompt、报告或 evidence；payload/free text 被执行；VM 获得
产品写权；或 relay 越权发起 merge/release/promotion/P12 动作。Formal Lane 的
snapshot/CAS/签名仍是正式证据门，不因 lean relay 改变。

## 执行许可

执行模式为 `TestSafe`、`DryRun`、`Live`：

- 默认 `TestSafe`。
- TestSafe/DryRun 的潜在修改操作必须 `Changed=false`。
- 环境变量不能单独授权真实操作。
- Live 需要独立确认、适用 stage、ExecutionContext 和 operation-specific grant。
- 默认 `Scaffold` stage 继续无条件拒绝 Live。独立 `VmDevelopment` 授权骨架只允许
  精确 stage/tier/profile、`Unloaded` provider 和已确认、已 CAS 提交的
  `LoadLiveProviders` operation；环境变量或 `-Live` 开关不能单独授权。
- `LoadLiveProviders` 成功只会把同一 context 转换为身份和 capability-set digest 精确绑定
  的 `LiveReadOnly` provider set；它只包含冻结的 11 个 `Inspect` tuple，不包含 mutation
  或任意扩展能力。每个 provider contract 显式为 `Access=ReadOnly`，capability 绑定
  精确 `ResultSchemaId`。所有 tuple 当前均为零 OS I/O：provider set 尚未绑定 adapter
  规范化绝对路径、函数定义 SHA-256 和组合 load receipt，通用 dispatcher 会在解析或
  调用任何 ambient 同名函数、写 ledger 或改变 context 前返回稳定
  `LIVE_READ_ONLY_ADAPTER_SOURCE_UNBOUND`。adapter 内的
  `ProviderFailure/LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED` 只是不可达的静态合同。
  静态门除精确 command/type allow-list 和 pipeline 调用多重集外，还锁定两个函数完整、
  规范化的 `FunctionDefinitionAst` source SHA-256；把既有检查包进不可达分支等控制流改写
  也会造成摘要漂移并 fail closed。
- `Test-CddsiRealMutationAllowed` 仍为 false；provider 装载成功不等于真实系统读取或
  写入获准。Host、CI、TestSafe、DryRun 和默认 bootstrap 始终不能装载该 set。
- 开发机和 CI 即使代码未来实现 Live，也不得加载或执行 live provider。
- D-026 后首次实现与真实系统操作允许在 `VmDevelopment` disposable VM 执行；它必须
  使用 owner-scoped 资源、独立交互确认、失败补偿和可恢复 snapshot，不得加载到宿主机。
- 开发循环结束后必须重新冻结候选。需要 P10A 外部事实时仍由限域 calibration
  runner/provider 和受信 CAS 产生；P11 仍只测试精确 candidate bytes。
- stage/profile 来自完整性保护的 embedded manifest 与 detached sidecar，不由
  环境变量或普通命令行开关单独授权。VM grant 绑定候选 hash、runId、operation、
  expiry 和交互确认，但不冒充 OS 级 VM 身份证明。
- `VM_TEST_RELAY.md` 定义当前人工交接和 VM 单写者租约；历史 monitor/control repo
  不扩展产品 Live 权限，也不能用消息、通知或 automation 绕过 grant。
- 截至 2026-07-16，`config/fast-lane-policy.psd1`、`lib/vm-test-relay.ps1`、
  `lib/vm-fast-lane-readiness.ps1`、`lib/vm-reset.ps1` 和 `operator/fast-lane/*` 已实现
  DevelopmentOnly 的固定 Git transport、确定性 onboarding、VM-only reset 边界与
  synthetic 演练。它们不进入 bootstrap、ProductCore 或 Release；也不因代码存在而
  获得宿主机 Live、VM product-write、remote credential 或无人值守执行授权。

## 宿主机保护

`TEST_ISOLATION.md` 是完整零接触合同。保护区包括真实 Claude/Claude Code/Git
配置、managed policy、Credential Manager、AppX、VMP、服务、任务计划、PATH、
进程和网络服务。

本地自动化不读取、Test-Path、枚举、哈希、备份、监视或修改这些资源。系统能力
必须经过不可缺省的 ExecutionContext/provider；缺 fake 时 fail closed。

P1 Sandbox Foundation 已完成；后续阶段必须持续保持该门全绿，不得增加宿主机
可加载的产品 live adapter 或 sandbox 外 I/O。P1 trusted harness 只可创建/清理
自有 sandbox，并启动精确 allow-list 的测试工具；其调用与产品 ledger 分开记录。

## 供应链

### 来源

- Claude Desktop MSIX 只接受 Anthropic 官方来源。
- Git for Windows 只接受 Git for Windows 官方来源。
- Release 默认不捆绑或重新分发上游安装包。
- URL、版本、架构和身份事实以 `EXTERNAL_CONTRACTS.md` 为入口。

### Git readiness 边界

Git 是产品必备前置，但“确保可用”不授权盲目重装：

- 只通过 provider 检查版本、Git for Windows 身份和唯一 canonical executable。
- 不读取或修改用户/系统全局 Git 配置。
- 合格且路径唯一时复用，`Changed=false`。
- 缺失、过旧或损坏时才进入已验签官方安装/升级合同。
- 多版本或 PATH 归属歧义时 fail closed，不猜测、不覆盖。
- 用户拒绝安装、UAC 或必要 PATH 影响时返回 `CANCELLED/ACTION_REQUIRED`，不得
  静默退化为 Chat-only 成功。

### 验签证据

下载、验证和安装是三个阶段。安装函数只接受包含以下字段的结构化证据：

- schema/contract version；
- artifact type 和架构；
- official source policy；
- canonical absolute path 与路径绑定 token；
- 当前文件 SHA-256；
- Authenticode status；
- 可信证书链；
- expected Publisher/signing identity；
- MSIX package identity 或 Git artifact identity；
- 生成时间和适用版本。

安装前必须对同一文件重新计算 SHA-256 并重验签名/身份。路径改变、文件替换、
时间过期、未知 signer 或 identity 全部 fail closed。不存在 bypass/skip 参数。

项目自身 Release sidecar 采用另一条精确合同：embedded manifest v2 从 sidecar
外部固定证书/public-key 指纹、Subject、KeyId、request ID、nonce 与最大签名年龄；
sidecar v2 携带实际 X509 DER 和 RSA-PSS-SHA256 签名字节。验证器只在 canonical
claims bytes 公钥验签成功后接受，不能把调用者可重算的 SHA、`Valid=true` 或自报
证书身份当作授权。helper Authenticode、DPAPI、ACL 和 P10A 系统事实仍必须由后续
disposable VM 的受信 provider 产生实物 receipt；宿主机 synthetic evidence 不能
晋升为发布证据。

### 下载

- 唯一 owner-marked 临时目录。
- TLS、重定向域、大小、超时和内容类型限制。
- 部分下载不进入验证。
- cache 命中也重新验证。
- 错误响应正文不直接进入日志。

## API Key

- 不接受明文命令行参数、环境变量或配置文件导入。
- 不接受通过 Codex 对话、prompt、GitHub issue/PR、测试代码或 clipboard 交付；已经
  出现在这些持久面中的 Key 必须视为泄漏并轮换。
- 不静默 Trim；拒绝空白、多行、控制字符和非法格式。
- 使用 SecureString 或不可序列化 credential handle。
- 用户只在 disposable VM 的遮罩输入框或安全终端本地输入；Computer Use 不查看或
  截图该界面。明文只在安全输入、DPAPI adapter 和 helper stdout 的最短边界出现。
- 使用 DPAPI CurrentUser 与受限 ACL。
- Claude 配置只引用 credential helper，不包含 Key。
- helper 采用签名、固定工具链的最小 .NET EXE，不接受明文参数，不经 shell、不读
  stdin、不提示，stdout 不得被记录。
- helper 精确消费 `CLAUDE_HELPER_CONTEXT`；`mid-session-refresh` 最多 20 秒，其余
  已知 context 最多 60 秒，所有 context 的 stderr 必须为空。
- 日志、异常、ledger、状态、报告、截图和 Release 全量完整脱敏，不保留前后缀。
- 测试 Key 运行时分片构造，fixture 不包含看似真实的 token。

Credential helper 技术形态已由 `DECISIONS.md` D-010 冻结；实际源码、固定工具链、
SBOM、PE、签名身份和 VM provider receipt 仍是发布阻断项。

## 配置所有权

- 首版唯一写入面是当前用户 HKCU managed policy。
- HKLM 和 configLibrary 只检测；HKLM 存在时停止，因为它覆盖 HKCU。
- credential helper、TTL/timeout 和隐藏 chooser 使用 MDM-only 键，不得回退到
  configLibrary 明文 credential。
- 非本项目配置默认不覆盖。
- 写入前必须有可恢复备份和独立确认。
- HKCU registry 备份保留 value 类型和值；首版没有 configLibrary writer。
- 恢复后必须重读验证。
- 恢复失败不得继续启动或验收。

## 备份与快照

- 可恢复备份可能含敏感材料，必须 DPAPI/ACL 保护。
- 脱敏快照可分享，但永远不能作为恢复源。
- 状态只记录 backup ID/hash/target metadata。
- DPAPI blob 不跨用户、机器或 VM 声称可恢复。
- owner、expiry 和清理失败必须有稳定错误。
- D-026 `VmDevelopment` 首次 Live 前必须确认可由 VM 外部恢复的 snapshot；每个实际
  支持环境使用独立 clean snapshot/镜像，不用一个已污染 VM 外推多环境结论。日常重测
  只清理项目拥有、owner/token 精确匹配的资源，未知所有权一律停止。
- Fast Lane 历史日常开发重测只允许按冻结 allow-list 做 deterministic guest reset：
  卸载本项目产物，清除项目拥有的 HKCU policy、credential、checkpoint 和
  owner-marked 目录，再核验 baseline。该 lane 不以 WORM、message signing 或每轮
  snapshot 为前置，结果只用于诊断。
- Formal Lane 的 P10A/P11 正式证据必须由外部 hypervisor supervisor 恢复固定快照
  并出 receipt，再由独立 CAS/receipts/signatures 验真。VMP/重启/卸载、补偿状态
  未知、baseline drift 或 reset 失败必须升级到 Formal Lane。VM Codex 不能恢复
  自身正在运行的整机快照；正式 P11 PASS 必须绑定 clean-snapshot receipt。

## 资源级补偿

- HKCU policy、项目 credential、state、helper 和本项目创建的临时资源要求精确
  恢复/删除。
- 新装 MSIX/Git 是否卸载、Desktop 升级是否可降级，必须服从上游支持和所有权，
  不能默认执行。
- VMP、PATH、服务和 machine-wide package 可能被其他软件使用，默认不自动反向
  修改；报告 `FULL`、`PARTIAL` 或 `UNSUPPORTED` 补偿状态并给出人工步骤。
- “修复/恢复”不能表述为整个 Windows 回到安装前。

## 重启和持久化

- checkpoint 在 VMP 修改前写入，不含凭据。
- 首版使用 `-NoRestart` 和用户重启后重新双击续跑。
- 不默认创建计划任务、RunOnce 或自动重启。
- 陈旧、损坏或 ownership 不匹配的 checkpoint 拒绝续跑。
- 清理只删除本项目拥有且 token 匹配的状态/临时资源。

## 进程和命令

- FilePath 与参数数组分离，不通过 shell 字符串拼接。
- Key 不进入 argv。
- 超时后处理进程树，stdout/stderr 先脱敏再进入结果。
- 不使用 `Invoke-Expression`、动态脚本下载执行或 `ExecutionPolicy Bypass`
  作为信任替代。
- Claude 关闭/启动需要独立许可，不能在诊断或配置读取中隐式发生。

## 日志、报告和隐私

- 默认中文脱敏报告。
- 不记录真实用户名、完整用户路径、代理口令、Key、Authorization、helper stdout、
  原始配置或 API 响应敏感正文。
- Finding 只记录 logical source、相对路径、行号/类型和固定脱敏占位。
- TestSafe/DryRun 文件日志只进入 owner-marked sandbox。
- 失败证据也必须通过 secret scan。

## Claude Code 配置

项目在任何 stage、mode 或 provider 中都不定位、不 Test-Path、不枚举、不读取、不
哈希、不监视、不备份、不写入或删除
`%USERPROFILE%\.claude\settings.json`。这是冻结决策，不再保留“由本进程计算前后
hash”的矛盾要求。
disposable VM、真实用户验收和 known-folder 探测都不构成例外；只能对不指向该真实
文件的 synthetic 项目资源建立测试基线。

## 汉化

不修改 Claude MSIX/Electron 资源，不跳过应用完整性，不集成社区汉化补丁。
中文体验仅由安装器、提示、报告和文档提供。

## 双机 relay 威胁与防护（历史；无当前操作权）

以下内容只保留 D-020 至 D-024 的威胁模型和回归背景。D-026 不部署、不调用也不依赖
这些 transport、credential、watcher 或 Automation。

Fast Lane 的逻辑 control plane 与产品仓库分离。GitHub deploy key 是
repository-scoped、不是 path-scoped；因此 GitHub transport 不能用同一 repository
内的两个目录和两把 writable deploy key 声称精确方向隔离。当前冻结拓扑使用两个
物理单向 public protected repository：HostCoordinator 只写 host-to-VM repository，
VmTester 只写 VM-to-host repository，并分别只读另一方向。三个 repositories 与两个
control `outbox/` 已 bootstrap；三个无 bypass ruleset 已实际施加删除、非快进和线性历史
约束，但方向隔离 writer 凭据尚未发放。两端分钟级 Codex Scheduled Tasks 最终轮询 inbox；可增加低延迟
  watcher 触发受限 `codex exec`/resume，但 transport 和自动化均不进入产品信任根。

本地实现边界如下：

- `config/fast-lane-policy.psd1` 冻结产品 remote、两个 control repository、角色、
  reset 与禁止 promotion 的安全策略；
- `lib/vm-test-relay.ps1` 只做 canonical validation、双向身份、hash chain、CAS、
  单 active cycle、STOP 和状态迁移，没有 Git/network transport；
- `operator/fast-lane/invoke-git-outbox.ps1` 绑定固定 Git/SSH/key/known-hosts hash，
  清空继承环境并限制进程树、runtime、output 和 message 数量；它验证 repository
  数字/node identity、当前 protection evidence、pinned genesis、linear history 与
  fast-forward-only CAS，不解释 payload；protection evidence 还必须匹配隔离的
  operator trust root、owner marker、receipt-specific authority assertion、独立预置的
  assertion SHA-256/authority token 和 previous-receipt chain，不能由 relay、receipt
  或 state root 自举；state root 使用固定短叶名 `fl-<32 lowercase hex>`，Git
  long-path 支持只作为 command-local config 注入，失败信息不包含 stderr 或本地路径；
- `operator/fast-lane/build-vm-onboarding.ps1` 只在 owner-marked HostSandbox 从 clean
  exact commit 生成确定性 diagnostic ZIP，绑定 tree/blob/working bytes、工具 hash 和
  runbook。bundle 不包含 credential、用户路径或 Formal evidence；
- `lib/vm-reset.ps1` 只做 owner receipt、allow-list、baseline、升级判定和
  `CLEAN_READY` 的 pure/fake 合同；TestSafe/DryRun 使用 fake provider，Scaffold
  Live 在 provider dispatch 前 fail closed；
- VM-only reset dispatcher/provider 还要求精确 VM/device/command trust、preflight、
  postcondition 与 receipt 绑定；宿主机/CI、伪造上下文、未知 mutation 或里程碑场景
  在 mutation 前 fail closed 或升级外部 snapshot；
- 每次 VM reset Live authorization 还必须消费 supervisor 签发的 SYSTEM-owned one-shot
  anchor/grant pair。anchor 绑定 VM/image、consumer SID、grant id/path/hash、execution
  nonce 与本轮全部 trust/input；grant JSON 绑定 nonce、cycle/policy/plan/ownership/
  resource/control-auth/time。consumer 对 grant 只有 Read+Delete，且 supervisor ACL
  receipt 必须证明其不能在父目录 create/replace；provider 还会验证父目录 SYSTEM owner
  与无非受信 mutation ACE，并在注册 runtime 前独占复验、原子删除 grant。进程内标志、
  可写 grant 或仅自洽 hash 都不是防重放证据；
- `operator/fast-lane/*` 还包含固定 prompt 和 pure synthetic rehearsal。prompt 中不
  放 deploy key、token 或其他凭据；relay message、日志、Markdown 和模型自由文本
  全部是不受信数据，不能直接执行。

### Cloudflare realtime accelerator

Realtime relay 只是 Fast Lane 的低延迟通知层，不是 authority、审计仓库或证据根。
Worker、SQLite-backed Durable Object、WebSocket、ACK、日志和 health response 均按公开
敌对输入/输出处理；持久审计、断线兜底与低频轮询仍由两个 protected-history control
repositories 承担。Cloudflare/Node/Wrangler/TypeScript 只存在于独立 sibling infra，
产品仓库仅保留 `operator/realtime-relay/realtime-relay-client.ps1` 的纯 PowerShell 7
watcher/publisher/provider，而且它不进入 bootstrap、ProductCore、Release 或 trusted
harness runtime。

- Relay payload 只允许固定小型 pointer schema，绑定 repository id、ref、commit、
  PayloadSha256、sequence、previous hash、TTL 和 MessageId；shell/PowerShell、Codex
  prompt、代码、日志正文和自由文本不得作为消息正文进入 wake 或执行路径。
- HostCoordinator 与 VmTester 分别持有独立 256-bit capability/HMAC secret。Host 只可
  写 `host-to-vm`、读 `vm-to-host`，VM 权限相反；server 以 client identity 选择 secret，
  将 method、canonical path/lane、timestamp、nonce 与 body SHA-256 纳入 HMAC-SHA256。
  forged signature、过期/未来时间、nonce 重放、错 lane、sequence gap、错误 previous
  hash、重复 MessageId、payload hash 不符、超限或 schema 错误均 fail closed。
- Watcher 从最后确认 sequence 恢复并幂等处理重复投递；只有全部验证通过的数据才能
  形成 fixed wake event。wake adapter、Git outbox runner 和 Codex resume binding 必须
  预先固定并校验，payload、错误文本和远端响应均不得拼接到命令、参数、脚本或 prompt。
- 一次性 manual smoke 的本地 runtime credential 可存于当前进程内存/安全输入
  边界。VM 侧可有一份人工拖入的 repo 外 owner-only fixed-schema JSON，但必须由
  固定 smoke 脚本有界读取后在首次网络前删除，不得进入 Git/prompt/日志/evidence
  或作长期明文存储。DPAPI CurrentUser 与本用户 ACL/owner marker/no-reparse
  在启用持久 unattended watcher 前必须完成。原子 state 只保存脱敏状态，不保存
  secret、Authorization、原始响应或可逆密钥材料。日志/异常必须完整脱敏，
  health endpoint 只返回最小可用性信息。
- Wrangler OAuth/API deploy credential 与 Host/VM runtime relay credential 完全分离；OAuth
  凭据只允许进入 Wrangler 的 AES-256-GCM encrypted profile，其加密密钥只允许进入 Windows
  Credential Manager/keyring，明文 profile 必须不存在。用户已在知悉既有 keyring `default`
  profile 有 29 项 scope、包含四项必需项并另有 25 项后，明确授权直接复用：采用门验证必需项和
  单一 account，不再要求 scope 集合精确相等，也不因额外 scope 拒绝。额外 scope 不扩大本任务
  允许的资源、写操作或激活范围。Wrangler `default` 是 reserved profile，不得尝试
  `auth activate default`；采用门必须证明精确 infra root 没有 exact/inherited profile binding，
  并生成 owner-marked 本地 adoption receipt 来绑定 `default.enc` hash、permissions 与脱敏
  readback。本地实现只允许 owner-only crash recovery 和过期 canonical receipt 原子续期；GET 与
  未来写入还必须把私有 token snapshot 的唯一 account hash 与 receipt 绑定，并固定 account target，
  避免 profile 校验/使用竞态。deploy credential 不能复用为 HMAC secret，runtime secret 也不能进入
  Wrangler 配置、Git、prompt、测试 evidence 或 Cloudflare 日志。
- 用户已授权外部步骤 1–7，但限定 Free-only；固定本地工具链、离线测试、dry-run、既有 credential
  的 generation-1 adoption 与固定四 GET preflight 已完成；初始 preflight 确认单账号、既有
  workers.dev subdomain、目标 Worker当时不存在，并报告
  `WorkersUsageModel=STANDARD / BillingPlanVerified=false`。任何 usage model 都不是账单订阅
  receipt；随后经用户授权复用个人 Edge 既有登录态的只读 Billing → Subscriptions 核对未列出
  Workers/Workers Paid。active Teams Free Base 与无关 R2 Paid 不把整个账号称为 Free、不升级
  Workers，也不授权 relay 使用 R2。D-022 已接受该 Dashboard 观察作为本次
  Free-only 部署依据。脱敏 machine receipt validator/recorder 与两阶段账号绑定仅作
  optional hardening；不等待真实 receipt。此后 Free-only Worker/SQLite Durable Object 与两项
  secret binding 已部署，postdeploy 精确 Worker/DO bindings 与唯一 active deployment 回读通过，
  Host HTTP 与跨设备 relay-only smoke 通过。生产 WebSocket reconnect/Hibernation 尚未公网 E2E；
  因而保持 `NOT_PRIMARY / AUTOMATION_PAUSED`。
- 早期 infra write policy 对 Host/VM DPAPI、coordinated parent、bulk semantics 与
  two-secret staging receipt 的硬阻断已由 D-022 取代。direct deploy 与一次性 secret
  staging 应走 lean path；仅在付费/升级、账号歧义、资源碰撞或 secret 泄漏风险时
  fail closed。持久 watcher 仍等待各设备 DPAPI。

必须防御以下威胁：

- VM 获得产品仓库写凭据，或越权写宿主 outbox；
- 旧 cycle 重放、乱序/重复消息、moving-ref 或 candidate hash 替换；
- 把失败日志、markdown、issue 文本或模型输出当作可执行命令造成 prompt/command
  injection；
- API Key、Authorization、helper stdout、原始 policy 或用户路径进入 control repo；
- guest reset 漏项、baseline drift 或 VM 自报快照恢复，形成虚假 clean start；
- 把 relay ACK/`TEST_RESULT` 当作 CAS、签名、snapshot 或 P11 acceptance receipt；
- PASS 自动 merge、自动发布或越过 P12 人工门。

历史对应控制为：产品仓库 VM credential 必须只读，两个物理 control repository 分别
发放最小单向写权限；Fast Lane 消息至少绑定 CycleId、单调 sequence、前序 hash、
物理 repository/outbox identity、精确 commit/candidate 与内容 hash；free text 永远
只作为数据，runner 只执行冻结 allow-list；所有消息与附件先脱敏和 secret scan；
baseline 不一致即升级 Formal Lane。宿主机不得执行 product Live，VM 不得编辑、提交
或推送产品代码。Fast Lane 不把 WORM/message signing/snapshot 当作日常前置，也不
产生正式 evidence；Formal Lane 才由独立 CAS、签名和 receipt validator 判断。始终
禁止自动 merge/P12。Git 只是可替换 transport，不是证据信任根。

## 安全验证

每个真实操作在 VM 实现和正式候选冻结前都必须覆盖：

- TestSafe、DryRun、Live 许可门。
- fake provider 和 access ledger。
- 失败注入、取消、超时、幂等和补偿。
- secret scan。
- 特殊路径和 reparse point。
- Release 白名单。
- disposable VM Live 验收。

## 当前实现与发布阻断风险

- P1 已证明项目控制的本地自动化满足零接触合同，但 HostSandbox 不是 OS 权限边界；
  真实 adapter 和不受信任代码仍只能在 disposable VM 首次执行。
- P10B 新合同必须重新通过统一双引擎质量门；旧 P1/P2 数量不能代表当前全树。
- MSIX/Git 每版本 signer/identity 仍需 P10A VM 实物证据冻结。
- helper 形态已经冻结，但源码、工具链、SBOM、实际 PE、Authenticode/ACL/DPAPI
  provider receipt 和签名服务均未完成。
- P10A consumption、release facts 和候选冻结只能消费 store-issued CAS receipt；
  调用者可重算的 SHA 摘要不能证明提交或授权。
- detached sidecar 必须验证真实签名字节和外部固定信任身份；P11 receipt 不存在时
  P12 promotion 必须保持 fail closed。
- 首次 P10A、P10A 事实冻结轮、正式 P11 PASS 和发布里程碑必须由 VM 外部 supervisor
  恢复 clean snapshot 并签发 receipt，且 Formal Lane 使用独立 CAS 与签名。guest
  reset、Fast Lane PASS 或 control-repo commit 均不能替代。
- `disableDeploymentModeChooser`、Standard/Offline MSIX 的 VM 行为未验证。
- 产品 credential helper、可恢复敏感材料、HKCU policy、lifecycle 和实际补偿的完整
  生命周期及 ACL/DPAPI/provider receipts 仍未完成。
- LICENSE copyright holder 尚未确定。

以上产品、Formal 和法律风险是 D-026 `VmDevelopment` 必须在 disposable VM 内逐项
关闭的工作清单；它们继续阻断 `READY_FOR_FORMAL_P10A`、`RELEASE_READY` 或正式
发布，但不阻断 VM 为关闭这些风险而实现和测试受控 Live。P12 始终保持人工、
fail closed。

### 已退役 operator 缺口（历史；不阻断 D-026）

Fast Lane policy、relay/reset、outbox/onboarding、双向 credential、paused Automation、
watcher、unattended runner、旧 bootstrap readiness 和 protection-receipt 轮换均只保留
历史回归背景。它们不需要补齐，也不得恢复为 `VmDevelopment`、P10A/P11 或发布前置。
三仓既有 public visibility、禁止删除/非快进、线性历史与无 bypass 规则仍保护当前
repair branch；历史 privacy 接受决定不放松 credential、Authorization、API Key 或
未脱敏数据禁令。Realtime relay 的旧 DPAPI/Cloudflare 状态不能替代产品 credential、
Formal evidence 或任何当前验收门。
