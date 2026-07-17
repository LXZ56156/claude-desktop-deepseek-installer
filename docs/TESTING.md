# 测试与质量门

更新日期：2026-07-18

## 核心原则

本地测试不能靠“运行后看起来没出事”证明安全。必须通过 fake provider、独立
sandbox、静态门和 access ledger，证明受控产品代码没有发起真实 Claude、Git、
registry、AppX、VMP、进程或网络访问。HostSandbox 不是 OS 权限隔离；不受信任
代码和 live adapter 只在 disposable VM。

完整保护合同见 `TEST_ISOLATION.md`。P1 质量入口已固定为 owner-marked
HostSandbox、双 PowerShell 引擎、精确工具授权和机器可读证据；该整套质量门已于
2026-07-14 实际通过，后续工作包必须持续保持全绿。

## 测试层级

### L0：Static

- PowerShell AST 和 JSON 语法。
- 模块依赖与无副作用加载。
- 公开函数、Mandatory 参数、Mode 和确认开关。
- 直接系统 API/live adapter 精确 allow-list。
- 编码、换行、secret 和私钥扫描。
- Release manifest 全文件精确分类。
- 文档体系完整性与交接可发现性。

### L1：Unit / Contract

- 仓库本地 Pester 5。
- 纯函数、schema、serializer、provider contract。
- 只写 `TestDrive:`。
- Registry、network、process、AppX、feature、credential 全部 fake。
- 每个公开函数变更同步 `config/public-functions.psd1`。

### L2：HostSandbox

- 独立 `-NoProfile -NonInteractive` 子进程。
- synthetic HOME、AppData、Temp、Git 和 Claude 路径。
- 唯一 owner-marked `cddsi-test-<GUID>`。
- AccessLedger、mutation spy、canary 和 forbidden-access 证据。
- 本机不加载 live provider。
- trusted harness 可以启动声明过的 pwsh/Pester/Git，但与产品 ledger 分开，
  未授权 harness 调用必须为零。

### L3：Release Simulation

- 从白名单 ZIP 解压。
- 路径包含中文、空格、`&`、`!` 和括号。
- 只运行 TestSafe/HostSandbox。
- ZIP 条目、secret、运行产物和仓库变化精确比较。

### L4：CI

- Windows 临时 runner。
- PowerShell 7 与 Windows PowerShell 5.1。
- 运行 L0-L3。
- checkout action 使用完整 commit SHA 固定，且 `persist-credentials=false`。
- 受信 harness 前置只解析 runner 已知的 pwsh、Windows PowerShell 和 Git
  可执行文件，计算 SHA-256 后把精确授权传给 HostSandbox。
- 不单独绕过 HostSandbox 运行 Pester、Git 或第二套测试命令。
- DPAPI 仍使用 fake；真实 DPAPI 首次执行留到 disposable VM。
- 绝不运行 Live。

### L5：Disposable VM 校准与 Live 验收

VM 工作分两道门。先按 `VM_CALIBRATION_PLAN.md` 在 P10A 专用 disposable VM 中执行
首次限域真实校准，只采集 Standard/Offline、MSIX scope、Git、helper/chooser、HKCU
与 cleanup 事实；evidence 返回后必须经受信外部 CAS 原子提交并冻结事实。随后才可
构建 P10B `VmAcceptance` 与 `UserLive` 双候选。只有两个候选精确字节均已冻结，才按
`VM_ACCEPTANCE_PLAN.md` 进入 P11，执行首次全面产品 Live、故障、补偿、重启、API
以及 Chat/Code/Cowork 验收。两道 VM 门均不授权宿主机真实操作。

### 双机 operator coordination

`VM_TEST_RELAY.md` 是双机角色、消息状态机、清洁启动和回传合同的权威。operator
coordination runtime 与产品平面分离，全部文件归类为 DevelopmentOnly，不由默认
bootstrap 加载，也不进入 Release。trusted harness 只按精确 allow-list 运行 synthetic、
owner-marked local Git/onboarding 和 fake/reset contract 测试；不得借测试连接 remote、
加载真实 credential 或进入 VM/system Live。这不把 operator modules 变成产品依赖：

- Fast Lane（日常自动修复）MVP 使用一个逻辑双 outbox、两个物理单向 public protected control
  repository：`host-to-vm` 仅 HostCoordinator 写/VM 读，`vm-to-host` 仅 VM 写/
  HostCoordinator 读。envelope 绑定 repository identity、CycleId、单调 sequence、
  previous hash 和内容 hash。
- 分钟级 Codex automation 是外部 operator coordination，不是产品创建或管理的
  Windows Scheduled Task，也不授予产品 Live。public protected repository pair 已创建，宿主机
  heartbeat 已按分钟创建但保持暂停；VM task 必须由 VM Codex 设备创建并同样先暂停。
  protected history 已通过真实 ruleset/effective-rules receipt；最小 credentials、runtime
  assertion、VM 负向权限验证、安全启用与 unattended
  acceptance 尚未完成。
- Formal Lane 的 append-only/WORM CAS、独立签名、外部 snapshot supervisor 和正式
  acceptance validator 尚未实现；Fast Lane synthetic PASS 不能替代这些门。
- 宿主机 Codex 是唯一产品代码写入者，负责修复、L0-L4、本地提交/推送和候选重建；
  VM Codex 只有产品仓库只读访问，只测试、分析和回传，但可向 control repo 自己的
  VM outbox 写入结构化结果。
- P10A 每轮绑定精确 commit 和校准 artifact；P11 每轮绑定 P10B candidate ID、
  exact bytes/hash 和 signed sidecar，不跟随移动分支头。
- Fast Lane 使用 deterministic guest reset：只卸载本项目产物、清除项目拥有的
  HKCU policy/credential/checkpoint/owner-marked 目录并核验 baseline；它不以 WORM、
  message signing 或每轮整机快照为前置，也不能产生 P10A/P11 正式通过证据。
- Formal Lane 用于 P10A/P11 正式证据：由外部 hypervisor supervisor 恢复快照，
  并使用独立 CAS/receipts/signatures。VMP/重启/卸载、补偿未知、baseline drift 或
  reset 失败必须从 Fast Lane 升级到 Formal Lane；VM Codex 不能恢复自身快照。
- relay 消息、ACK 和通知不等于受信 CAS、签名、snapshot receipt 或 acceptance
  receipt；free text/log 只能作为数据，不能直接转成命令执行。
- P11 失败后宿主机必须修复并回到 P10B 重建、签名新候选，不能让 VM 拉源码直接
  重测；任何 PASS 都不触发自动 merge 或 P12。

当前本地实现与测试映射：

- `lib/vm-test-relay.ps1` 是纯函数合同；`tests/Unit/VmTestRelay.Tests.ps1` 覆盖
  canonical/hash、方向与身份、expiry、重复/乱序/篡改、状态转换和 STOP。
- `lib/vm-reset.ps1` 只实现 fake/TestSafe/DryRun 合同；
  `tests/Contract/VmReset.Tests.ps1` 覆盖 ownership、baseline、plan/receipt、
  `CLEAN_READY` 与需外部快照的 fail-closed 分支。
- `operator/fast-lane/invoke-git-outbox.ps1` 固定 Git/SSH/tool hash、最小进程环境、
  pinned-genesis/linear-history 校验、canonical message path、原子本地 state/lock 和
  fast-forward-only append；HostSandbox 测试只能使用 owner-marked local transport。
- `lib/vm-fast-lane-readiness.ps1` 分开计算宿主实现、VM bootstrap、VM integration、
  P10A-0A 和 Formal P10A；protected history 或窄凭据缺失不能被 bootstrap 状态吞掉。
- `operator/fast-lane/build-vm-onboarding.ps1` 从 clean exact commit 生成确定性 Store ZIP，
  绑定 commit/tree、committed blob、working bytes、工具 hash、repository identity 和
  genesis。输出是 diagnostic onboarding，不是 evidence CAS 对象或产品候选。
- `operator/fast-lane/invoke-vm-reset-live.ps1` 与
  `operator/fast-lane/providers/windows-vm-reset.ps1` 冻结 VM-only dispatcher/provider
  边界。宿主机/CI/伪造上下文必须在任何真实 provider dispatch 前失败；设备 trust、
  real system evidence 与 development-retest Live smoke 仍由 disposable VM 验证。
- `tests/Contract/FastLanePolicy.Tests.ps1` 冻结两 repository 拓扑、角色权限和
  diagnostic-only 边界；`tests/Contract/OperatorCoordinationBoundary.Tests.ps1` 证明
  operator modules 是 DevelopmentOnly、非默认 bootstrap、非 Release 且不能加载 Live。
- `tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1` 通过
  `operator/fast-lane/invoke-synthetic-rehearsal.ps1` 演练本地双 outbox。该演练必须为
  零产品 Live、零网络、零真实 Git、零 registry/AppX/VMP/credential/process 探测和
  零 secret；结果只作诊断，不能证明 P10A-0A 已完成。

上述映射已证明 clean exact commit 可制作 VM onboarding，双引擎各 430 项和全部 zero
metrics 可验证 PUBLIC 合同。tracked 文档不嵌入会自引用的最终 commit/tree/hash；只有同一
暂停 automation、PR CI、实际 Git/remote 与 immutable bundle 的外部机器事实全部匹配，
才派生 bootstrap-only 的 `CanStartVmBootstrap=true`。真实 ruleset/effective-rules receipt
已证明 protected history 生效；本地测试覆盖 public-protected 正向、visibility
mismatch、缺保护、public-outbox secret 与错误角色写入负向合同，但仍不证明窄角色
credential、VM reset 或 unattended loop 已通过。两端 minute tasks
在这些 integration gates 完成前都必须保持暂停。首次 P10A 另需外部 snapshot receipt、
独立 CAS 与签名，Fast Lane 测试绝不能替代。

Release secret scanner 只证明当前 PackageFiles 的 source/staging/ZIP/extracted bytes；它不
覆盖 Git history/metadata、DevelopmentOnly 文档、PR、Actions logs/artifacts 或 control-repo
history。用户已接受未审计的存量范围且 cutover 已完成；public outbox 对
credential/Authorization/secret 和未脱敏自由文本的禁令及负向测试仍必须通过。

## 本地依赖

Pester 固定为 5.6.1。精确的 `.dev/modules/Pester/5.6.1` runtime tree 随仓库
提交；`.dev/modules` 的其他内容仍被忽略，也不得用作一般测试输出目录。
`config/dev-dependencies.psd1` 固定版本、文件数、总字节数、manifest SHA-256 和
整树 SHA-256。

`scripts/bootstrap-dev.ps1` 是只读校验器：只核对上述 lock 和 runtime tree，
不下载、不修复、不安装、不导入 Pester，也不修改 PowerShellGet、`PSModulePath`
或用户级模块配置。任何文件缺失、额外文件、reparse point 或 hash 漂移都必须
fail closed，并从可信仓库 checkout 恢复；普通本地与 CI 质量门保持零网络。

## P1 标准检查

调用者必须先显式选定三个受信工具的绝对路径。项目代码不得搜索 PATH 或自行
选择替代工具；下面的占位路径必须替换为本机已明确选定的路径：

~~~powershell
$pwsh7 = 'C:\absolute\path\to\pwsh.exe'
$windowsPowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$git = 'C:\absolute\path\to\git.exe'

$pwsh7Sha256 = (Get-FileHash -LiteralPath $pwsh7 -Algorithm SHA256).Hash
$windowsPowerShellSha256 = (Get-FileHash -LiteralPath $windowsPowerShell -Algorithm SHA256).Hash
$gitSha256 = (Get-FileHash -LiteralPath $git -Algorithm SHA256).Hash

.\scripts\bootstrap-dev.ps1
$evidence = .\scripts\check.ps1 `
    -PowerShell7Executable $pwsh7 `
    -PowerShell7Sha256 $pwsh7Sha256 `
    -WindowsPowerShellExecutable $windowsPowerShell `
    -WindowsPowerShellSha256 $windowsPowerShellSha256 `
    -GitExecutable $git `
    -GitSha256 $gitSha256 `
    -PassThru

if ($evidence.Scenario -cne 'Quality' -or $evidence.CLEANUP_OUTCOME -cne 'Succeeded') {
    throw 'Isolated quality evidence is not clean.'
}

$releaseEvidence = .\scripts\build-release.ps1 -DryRun
if ($releaseEvidence.Status -cne 'SUCCEEDED' -or $releaseEvidence.Changed -ne $false) {
    throw 'Release Simulation evidence is not clean.'
}
~~~

标准检查覆盖：

- PowerShell AST、双版本模块加载和双版本 Pester。
- 公开函数/参数合同。
- Pester Unit/Contract/HostSandbox/Release Simulation 合同。
- operator coordination plane、DevelopmentOnly、非 bootstrap/非 Release 和 synthetic
  零外部访问合同。
- Scaffold 禁止命令和 Live fail closed。
- JSON、编码、换行、secret scan。
- 隔离 Git inventory、工作区与暂存区 `diff --check`。
- Release manifest 与 DryRun。
- 文档索引、隔离合同、实施计划和 HANDOFF 可发现性。

`check.ps1` 只接受绝对工具路径与对应 SHA-256，并由 HostSandbox runner 间接
运行 Pester 和 Git；不继承真实用户 HOME/AppData/Temp、Git 配置或一般
`PSModulePath`。它已经覆盖 Windows PowerShell 5.1，因此禁止在外部再直接导入
Pester 运行一遍。

HostSandbox 内需要构造本地 bare repository 的测试必须消费父 harness 传入并由
worker 再验 hash 的固定 Git grant，不能依赖 worker `PATH`。该 grant 只允许本地
fixture/CAS 质量验证，不授权网络 remote；缺少固定 binding 时正式 worker 失败。

`build-release.ps1` 必须在同一工作流的 clean quality evidence 之后运行，只接受
`-DryRun`。省略 `-DryRun`、传入 `-SkipQualityGate` 或指定输出目录都必须
fail closed；Release Simulation 只在自有 sandbox 中暂存、打 ZIP、解压、比对并
清理，不发布产物。

## Git 隔离

HostSandbox/CI 中运行 Git 时设置：

~~~text
GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL=<sandbox empty config or Windows null device>
GIT_OPTIONAL_LOCKS=0
HOME=<sandbox>
XDG_CONFIG_HOME=<sandbox>
~~~

这些设置防止读取系统/用户 Git 配置；它们不能替代 provider 隔离。

## 必需断言

每个 TestSafe/DryRun 场景：

- `Changed=false`。
- mutation spy 全部为零。
- live provider 未加载。
- 产品 process/network/registry/package/feature/service 调用为零。
- outside-sandbox write 和 unexpected ledger entry 为零。
- trusted harness 调用与声明精确相等，未授权 harness 调用为零。
- secret findings 为零。

精确证据字段只在 `TEST_ISOLATION.md` 维护。持久/可分享报告只记录 logical
token 和 sandbox 相对路径；本机临时控制台可以显示 sandbox 绝对路径，但不能
持久化或分享。

## 故障注入

### 文件和状态

- 目录创建、磁盘满、flush、重读、replace、rollback 和 cleanup 失败。
- 路径逃逸、reparse point、owner marker 和 TOCTOU。
- checkpoint 损坏、过期、未知 schema 和 runId 冲突。
- P10A consumption 与 release-facts freeze 的 raw proposal 回放、错 store/epoch、
  错 authority key、旧 revision、CAS 竞争、跨 session 与过期 commit receipt。

### 下载和验签

- DNS/TLS/timeout/cancel。
- 截断、超限、非法重定向和缓存污染。
- hash、artifact type、arch、signer、chain、Publisher、identity 失败。
- 验签后同路径换包。
- Release sidecar 的空/伪造 RSA-PSS 签名、换 key/证书、claims 篡改、错 request
  nonce、未来/过期 signer assertion 和 manifest bytes/hash 漂移。
- P11 receipt 缺失时 promotion 构造与验证必须始终失败。

### 进程和系统

- 启动失败、非零退出、超时、大量输出和子进程树。
- AppX/VMP/service/registry fake 的拒绝、部分成功和补偿失败。
- 明确证明没有 bypass 参数。

### 凭据和配置

- Key 格式、SecureString、DPAPI、ACL、helper timeout/非法输出。
- `CLAUDE_HELPER_CONTEXT` 五种精确值；`mid-session-refresh=20s`、其他 context
  `=60s`，非交互调用不得提示或等待输入。
- helper 根目录的 `.`/`..`、尾随点/空格、设备名、superscript COM/LPT alias、
  reparse 和最终解析路径漂移。
- HKLM/HKCU/local precedence、冲突、部分写、重读和恢复失败。
- configLibrary 首版只测检测、precedence 和冲突；sibling temp/flush/replace 仅在
  未来单独批准 local writer 后启用。
- 日志、状态、报告、备份和 Release 的泄露扫描。

### 验收

- 没有 capability selector，三个 surface 的 serializer 值始终为 true。
- Git 合格复用、缺失、过旧、损坏、多路径歧义和用户取消。
- 运行、能力、UI 证据三层状态分别验证；`NOT_TESTED` 只用于 UI 证据。
- Chat、Code、Cowork readiness 分别 READY/BLOCKED/PENDING_RESTART 等状态。
- 不支持 content block。
- Repair/Restore 失败。
- 一个子项不能提升其他子项状态。
- 禁止通过关闭 Code/Cowork 把 PARTIAL/ACTION_REQUIRED 提升成 SUCCEEDED。
- 双机状态机拒绝重复/过期/乱序 cycle、错误 repository 方向、moving-ref 漂移和候选
  hash 漂移。
- VM `TEST_RESULT` 只能携带脱敏结构化结果和证据引用，不能自证 P11 PASS。
- Fast Lane 不依赖正式 evidence infrastructure，结果只作诊断；Formal P10A/P11
  使用独立 CAS/receipts/signatures，正式 P11 PASS 必须绑定外部 clean-snapshot
  receipt。

## 特殊路径

所有入口、process runner、Release Simulation 覆盖：

- 中文。
- 空格。
- `& | < > ^ % !`。
- 括号。
- 空参数与空字符串。
- 长路径和拒绝路径。

`.cmd` 仍必须 ASCII/no-BOM/CRLF，不使用 `chcp`。

## 测试数据

- Key 在运行时分片构造，fixture 中不放看似真实的 token。
- 不使用真实用户名、真实用户路径、真实日志或真实配置。
- MSIX/EXE 使用 synthetic signed/unsigned fixture metadata；本地不下载上游包。
- API 使用 fake handler，不连接 DeepSeek/Anthropic。
- Registry 使用内存 map，不使用“测试子键”触碰真实 HKCU/HKLM。

## 每阶段质量门

每个工作包必须：

1. 先更新测试和故障矩阵。
2. 运行适用的 L0-L3。
3. 取得 clean `check.ps1 -PassThru` 证据，再运行 Release DryRun；隔离
   `git diff --check` 已由 check 质量门执行。
4. 检查 manifest、secret、docs 和 HANDOFF。
5. 记录通过数量、失败/跳过/未运行；任何 skipped/not-run/inconclusive 都不算干净。

不得用 `-SkipPester`、`-SkipQualityGate` 或放宽安全规则交付完成状态。

## P1 交付判定（已满足）

- 不增加或加载真实 provider、live adapter 或系统探测。
- 不直接调用缺少显式 synthetic path/ExecutionContext 的产品函数。
- vendored Pester 校验、双引擎 quality evidence、HostSandbox 清理和 Release
  Simulation 必须全部 clean。
- 任一工具 identity/hash、依赖 lock、sandbox owner、证据 schema、测试计数或
  Release allow-list 漂移都 fail closed，不能用额外直跑命令替代失败证据。
- 以下 2026-07-14 数字是 P1 首次退出门的历史快照；当前全树证据以
  `HANDOFF.md` 为准。双引擎各 124 项全部通过，固定 suite 为 16/10/6；5 个
  trusted process 与 16 项 harness ledger 精确匹配；全部必需零值、mutation spy、
  repository unchanged 和 cleanup 通过。Release DryRun 的 29 个 PackageFiles 在
  四层扫描、清单、内容 hash 和 16 项 filesystem ledger 上全部 clean。
- 该判定只覆盖项目控制的宿主机自动化，不代表 OS 隔离、CI/L4、VM Live 或发布
  候选已完成。完整易变证据见 `HANDOFF.md`。
