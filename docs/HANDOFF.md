# 新任务交接

更新日期：2026-07-15

## 一句话状态

本项目已经越过旧交接所写的 P2/P3：P3 环境域模型、P4 供应链合同、P5-P7
安全纯合同、P8 fake 编排器、P9 synthetic 验收以及 P10A evidence/consumption 合同均已
实现。P10B 的宿主机支撑合同也已完成并通过统一门，包括 `release-facts`、
`release-artifact`、`credential-helper-release` 和 fail-closed candidate assembler。

最新记录质量门 `RunId=62ed01b0-7c51-411d-9931-206fbc28602f` 中，PowerShell 7
与 Windows PowerShell 5.1 各 338 项 Pester 全部通过；扫描 139 个仓库文件，
`PackageFiles` 仍为 39。live provider、产品真实 process/network/registry、越界
写入、forbidden access、unexpected ledger、secret findings 和全部 mutation spy
均为 0，cleanup 成功。随后 Release Simulation DryRun 以 `Changed=false` 验证 39 个
PackageFiles、39 个 ZIP/extract 条目、精确 inventory/content hash、deterministic Store
ZIP 和四层零 secret；本节证据写回后还会由下一次统一门覆盖。

这些结果只证明纯合同、fake/synthetic、deterministic Release Simulation 和
fail-closed assembler。P10A 真实 VM evidence、实际 helper PE/签名、frozen facts、
P10B 双候选和 P11 全面 VM 验收均未产生，不能写成已完成。

双机 Codex 测试闭环的职责、消息、证据、清洁和重测合同已经写入
`docs/VM_TEST_RELAY.md`。P10A-0A 的本地 TestSafe/DryRun 合同切片已经实现：
`DirectionalRepositoryPair`、relay/state/hash、fake reset 与 `CLEAN_READY`、两端
轮询 prompt、synthetic rehearsal，以及独立且只归入 `DevelopmentOnlyFiles` 的
operator coordination plane。私有产品 remote 与两个物理 control repos 已创建，
产品 `main` 基线已推送，两个 `outbox/` 已初始化；宿主机分钟级 heartbeat 也已创建但
保持暂停。GitHub 当前套餐拒绝私有仓库 ruleset，角色最小权限凭据、VM 对产品 remote
的负向写验证、真实 VM reset adapter、VM Scheduled Task 和无人值守闭环仍未完成；
外部 CAS/WORM evidence store、签名 authority 与外部快照 supervisor 也未就绪。
因此不能宣称 P10A-0A、P10A、P10B 或 P11 已完成。

产品运行阶段仍是 `Scaffold`。仓库内没有可执行的真实 Live adapter、已构建的
credential helper PE、代码签名或冻结的 VM 事实；宿主机也从未执行真实安装、配置、
API、系统探测或进程控制。

## 仓库与工作树

- 项目目录：`D:\projects(WIN)\claude-desktop-deepseek-installer`
- 只读参考：`D:\projects(WIN)\claude-deepseek-installer`
- 分支：`codex/repair/p10a-0a-fast-lane`
- 产品 Remote：`origin` → `git@github.com:LXZ56156/claude-desktop-deepseek-installer.git`
- Control repos：`LXZ56156/cddsi-host-to-vm`、`LXZ56156/cddsi-vm-to-host`（均为 private）
- 当前版本：`0.1.0-dev`
- 产品运行阶段：`Scaffold`
- 实施位置：P10B 宿主机支撑合同已通过门；P10A-0A 本地合同及私有 repository pair
  已落地，当前停在 protected history、最小权限凭据、真实 VM reset、VM task 与
  无人值守负向权限验证门；完成并验证后才执行 P10A 窄范围 disposable VM 校准

保留当前工作树继续开发。不得 reset、checkout、清理或覆盖用户与前任务的改动。
实际 commit/clean 状态只能通过项目规定的隔离 Git 入口核验，不能把本交接中的描述
当作 clean-commit 证据。

后续代理不需要重新从零调研，应从本文件记录的当前工作包和真实工作树继续。所有
宿主机开发与统一门禁都不在开发机执行 Live；首次限域真实校准只能进入 P10A 专用
disposable VM，首次全面产品 Live 只能进入 P11 disposable VM。

## 必读顺序

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

## 最新统一验证基线

2026-07-15 的最新记录全树基线（Quality RunId
`62ed01b0-7c51-411d-9931-206fbc28602f`）：

- PowerShell 7 worker：338 项 Pester，0 failed、0 skipped、0 not-run、
  0 inconclusive。
- Windows PowerShell 5.1 worker：338 项 Pester，0 failed、0 skipped、0 not-run、
  0 inconclusive。
- live provider loaded、产品真实 process/network/registry、forbidden access、
  outside-sandbox write、unexpected ledger、secret findings 与所有 mutation count
  均为 0。
- 统一门扫描 139 个仓库文件，`PackageFiles` 保持 39；仓库不变性与 HostSandbox
  cleanup 成功。
- 双引擎 AST/contract/fake/synthetic、deterministic ZIP32 和 trusted-harness 边界通过。
- Release Simulation DryRun：`Status=SUCCEEDED`、`Changed=false`、39 个 PackageFiles、
  39 个 ZIP/extract 条目、inventory/content hash 精确、deterministic Store ZIP、四层
  secret findings 为 0，cleanup 成功。
- 未执行真实下载、MSIX/Git 安装、registry/AppX/VMP/service、重启、DeepSeek API、
  Claude 配置、凭据或 Claude/Git 进程探测。

这是本轮证据写回前的最新记录基线；证据写回后的完整树必须再通过统一门、
`scripts/build-release.ps1 -DryRun` 和 `git diff --check`。最终交接以后一轮结构化结果为准，
无需为了把最终 RunId 再写回本文而制造无限重跑循环。

## 当前停点与下一外部工作包

1. P10B 宿主机支撑合同、故障注入、双引擎统一门和 Release DryRun 已完成。
2. P10A-0A 本地 TestSafe/DryRun 合同、私有产品 remote、两个 control repos 与暂停的
   宿主机 heartbeat 已实现；下一工作包是解决 protected history、部署并验证最小角色
   凭据、真实 VM reset adapter、VM 分钟级任务与无人值守闭环。operator coordination
   plane 是 P10A 的外部前置门，不是产品功能或 P11 验收。
3. P10A-0A 全部退出门通过后，下一合法产品阶段才是执行 P10A 窄范围 disposable VM 校准，
   不是直接进入 P11。
4. P10A runner/provider、evidence exporter、受控 submission、CAS authority/commit
   service、helper 与 release 签名能力等外部输入未齐备前继续阻断。
5. P10A evidence 经外部 CAS 提交、消费并生成 frozen facts 后，才返回 P10B 构建和
   签名真实 `VmAcceptance`/`UserLive` 双候选。
6. 两个候选的精确字节冻结后，才能进入 P11 全面 disposable VM 验收。

### P10A-0A 当前工作包的精确范围

1. 私有产品 remote `LXZ56156/claude-desktop-deepseek-installer` 已创建，旧 `main`
   基线已推送，本轮改动位于 `codex/repair/p10a-0a-fast-lane`。当前交互式 `gh` 身份只作
   bootstrap admin，不能交给 automation；宿主机限 repair-ref 写凭据、VM 独立
   read-only credential 及 VM 负向写验证仍未完成。
2. Fast Lane 本地合同采用一个逻辑双 outbox、两个物理单向私有 control repos：
   `host-to-vm` 只承载宿主机发往 VM 的消息，`vm-to-host` 只承载 VM 发往宿主机的
   消息。`DirectionalRepositoryPair`、结构化 `CycleId`/sequence/previous hash、
   去重与状态转换已经实现；`LXZ56156/cddsi-host-to-vm` 与
   `LXZ56156/cddsi-vm-to-host` 已创建为 private，且各自 `outbox/` 已初始化。GitHub
   当前套餐以 HTTP 403 拒绝 private-repository ruleset，因此 protected history 与
   方向隔离 writer credential 仍保持阻断。消息与脱敏报告只作开发诊断，不是正式
   evidence；独立 CAS/WORM、签名 authority 和正式 receipt 留给 P10A/P11 Formal Lane。
3. fake deterministic reset、ownership receipt、baseline drift 阻断和诊断性
   `CLEAN_READY` 合同已经实现；真实 VM reset adapter 仍保持 fail closed。部署后，
   日常开发重测只允许按冻结 allow-list 卸载本项目产物、清除项目拥有的
   HKCU/credential/checkpoint 和 owner-marked 测试目录。首次 P10A、正式 P11/里程碑，
   以及 cleanup 失败、baseline drift、VMP/重启/卸载/补偿状态未知时，仍须由 guest
   外 supervisor 恢复权威快照并签发 receipt。
4. 宿主机 heartbeat `cddsi-fast-lane-hostcoordinator-minute-poll` 已按分钟创建，但在
   protected history 与窄权限 HostCoordinator credential 就绪前保持暂停。VM Codex
   项目不在本机 Codex 项目列表中，VM task 必须从 VM 设备创建，不能由宿主机伪造。
   两端最终都必须配置最小权限的分钟级自动轮询/唤醒：宿主机
   Codex 是唯一代码修改者；VM Codex 只测试、分析和回传。两端都只接受来源已认证、
   未过期、前序 hash/sequence 正确的结构化消息；Formal Lane 还必须验签。报告正文
   永远不得当命令执行。真实角色凭据、VM Scheduled Task 与无人值守闭环尚未部署。
5. 无 Live、无 secret 的本地 synthetic rehearsal 已物化 PASS 链、重复、过期、篡改、
   错向、STOP 与 STOP 后续拒绝；relay unit 合同另覆盖 FAIL、BLOCKED、FIX_READY、
   新 cycle 与 RETEST_REQUESTED。它们不能替代 VM 对真实产品 remote 的负向写验证。
6. P10A 只获取精确 commit 和校准包；P11 只获取 P10B 冻结候选的精确
   candidate ID/hash。P11 失败后，宿主机修复、过门、提交和推送，再回到 P10B
   重建/签名新候选；VM 不得直接拉源码把旧候选标成已重测。

首选实现是两端 Codex automation 持续轮询各自可写的单向 control repository；若计划任务粒度不足，
由低延迟 deterministic watcher 只负责验签、去重并调用固定的 `codex exec resume`
恢复对应任务。正常闭环不需要用户搬运文件；人工签名 bundle 只作断网/故障降级。
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

## 进入下一外部阶段前的阻塞项

以下输入不能由宿主机 fake 测试虚构，未满足前不得宣称 P10A/P10B/P11 完成：

- GitHub private ruleset（或具备等效 append-only/branch-scope 强制力的替代 transport）、
  宿主机限修复分支写/VM read-only 凭据、两个方向的 writer/read-only 凭据负向验证；
- 已暂停的宿主机 heartbeat 的安全启用、必须从 VM 设备创建的 VM Codex Scheduled Task；
- 真实 VM deterministic reset adapter、权威 baseline/snapshot receipt 和可重复的
  无人值守闭环；
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

## 建议给下一对话的开场指令

> 在 `D:\projects(WIN)\claude-desktop-deepseek-installer` 继续当前工作树，不要 reset。
> 先阅读 `AGENTS.md`、`docs/HANDOFF.md`、`docs/VM_TEST_RELAY.md` 和
> `docs/IMPLEMENTATION_PLAN.md`。P3-P4、
> P5-P7 纯合同、P8 fake orchestrator、P9 synthetic、P10A evidence/consumption 和
> P10A-0A 本地 TestSafe/DryRun 合同切片已实现；P10B 宿主机支撑合同也已通过门，但
> 真实候选尚未构建。最新记录质量门 RunId
> `62ed01b0-7c51-411d-9931-206fbc28602f` 双引擎各 338/338；最终交接另记录覆盖本段
> 证据写回后的统一门与 Release DryRun 结果。
> 私有产品 remote 与两个物理单向 control repos 已创建并初始化；GitHub 当前套餐拒绝
> private ruleset，宿主机分钟级 heartbeat 已创建但保持暂停，VM task 尚未创建。下一步
> 解决 protected history，部署最小权限角色凭据、真实 VM reset adapter 与 VM task，
> 再完成负向权限和无人值守闭环验证。
> 宿主机 Codex 唯一改代码，VM Codex 只测试和回传。日常循环由
> VM 做 allow-listed deterministic reset，状态不可信和正式验收才由 guest 外 supervisor
> 恢复快照。不得在宿主机执行 Live，不得让 VM
> 改源码，也不得把 relay 消息当正式 evidence/acceptance receipt。P10A-0A 通过后再
> 执行窄 VM；正确产品顺序是 P10A 窄 VM → 冻结事实 → P10B 双候选 → P11 全面 VM。
