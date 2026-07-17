# 新任务交接

更新日期：2026-07-18

## 一句话状态

本项目已经越过旧交接所写的 P2/P3：P3 环境域模型、P4 供应链合同、P5-P7
安全纯合同、P8 fake 编排器、P9 synthetic 验收以及 P10A evidence/consumption 合同均已
实现。P10B 的宿主机支撑合同也已完成并通过统一门，包括 `release-facts`、
`release-artifact`、`credential-helper-release` 和 fail-closed candidate assembler。

`RunId=62ed01b0-7c51-411d-9931-206fbc28602f` 与每引擎 338 项 Pester 只是
P10A-0A runtime 变更前的历史基线。2026-07-16 对 commit
`3e843912df2543c1da05b09061970faff511d016` 完成过一次宿主机 finalization：
HostSandbox 双引擎均为 427/427，Release Simulation DryRun、18-entry onboarding
bundle、暂停 heartbeat 的最终 hash binding 和当时 PR CI 均通过，现只作历史锚。

2026-07-17 的 public-contract/cutover 质量锚为
`a09130f2afadb6dcf4cfc60a61a72095dc41faa6`：标准 HostSandbox
`RunId=8e6efa51-9980-4bb5-b60e-8512c08d0205` 在 PowerShell 7 与 Windows PowerShell
均为 430/430，全部 zero metrics 为 0、repository unchanged、cleanup succeeded；
Release Simulation 为 39 package files/39 ZIP entries、四层 inventory exact、
`Changed=false`，diff/编码门和 PR CI 均通过。它证明 PUBLIC 合同可部署，但不是
包含本交接更新的最终 onboarding bundle/task authorization。

随后在 2026-07-17 对 commit
`615bbf3687caa862bd6077b2fc620e00bf0e7568` 完成过一次宿主机 finalization：
HostSandbox `RunId=9c2fd721-56c7-41c3-adc0-870c644a5b3b` 双引擎均为
430/430，Release Simulation 为 39/39，18-entry onboarding bundle、同一暂停
heartbeat 的精确绑定、remote/PR 与最终 CI 均通过。该结果证明当时字节可进入
bootstrap-only；由于 2026-07-18 文档闭环会改变 tracked tree，`615bbf3...` 与其
bundle/task binding 现在也只作历史证据，不能授权包含本文的新 HEAD。

这些结果只证明纯合同、fake/synthetic、deterministic Release Simulation 和
fail-closed assembler。P10A 真实 VM evidence、实际 helper PE/签名、frozen facts、
P10B 双候选和 P11 全面 VM 验收均未产生，不能写成已完成。

双机 Codex 测试闭环的职责、消息、证据、清洁和重测合同已经写入
`docs/VM_TEST_RELAY.md`。P10A-0A 宿主机侧现已实现：`DirectionalRepositoryPair`、
relay/state/hash、固定 Git outbox runtime、readiness resolver、deterministic VM
onboarding builder、fake reset 与 VM-only reset dispatcher/provider boundary、两端
分钟级 prompt/runbook 和 synthetic rehearsal；整个 operator coordination plane 只归入
`DevelopmentOnlyFiles`。

public 产品 remote 与两个物理单向 public control repos 已创建，产品 `main` 基线已推送，
两个 `outbox/` 已初始化；三仓均已启用无 bypass 的 protected-history ruleset，目标 refs
实际受禁止删除、禁止非快进和线性历史约束。宿主机分钟级 heartbeat 已创建并保持暂停。
旧 `3e843912...`、`a09130f2...` 与 `615bbf3...` 均为历史锚，不能授权包含本交接更新的
新 HEAD。文档提交后，必须对包含本文的 clean HEAD 重新完成完整质量门、Release
Simulation、bundle 自校验、同一暂停 task 重绑以及 remote/PR/CI 核验。在这些闭环条件
全部由外部机器事实确认前，`CanStartVmBootstrap=false`，不得携带旧 bundle 进入 VM；
全部成立后才派生 `CanStartVmBootstrap=true`，且授权范围仅为 bootstrap-only。

为避免 tracked 文档对自身 commit/tree/hash 产生不可能稳定的自引用，最终 exact
commit/tree、bundle/manifest/inventory/content digest、task prompt hash 与 CI run 不嵌入
本文。它们必须由 retained owner-marked bundle output 的 manifest/inventory/marker、同一
`PAUSED` automation 的绑定、PR #1/最终 CI 和公开 Git/remote 状态四方相互核验；任一来源
缺失或不一致即 fail closed。这样下一任务可从持久事实重建，不依赖本次聊天正文。

**VM integration 仍被外部门阻断**：private ruleset HTTP 403 已由 PUBLIC cutover 与
真实 protected-history receipts 解除，但窄 HostCoordinator/VmTester credentials、runtime
protection assertion 尚未发放；VM 负向权限、provider/device trust、reset smoke、两端任务
安全启用和 unattended loop 均尚未产生真实证据。Formal
Lane 的外部 clean-snapshot receipt、CAS/WORM store、签名 authority 与 receipt validator
也未就绪。因此无论 bootstrap-only 是否已经就绪，`CanStartVmIntegration=false`、
`P10A0AComplete=false`、`CanStartFormalP10A=false`；不能宣称 P10A、P10B 真实候选
或 P11 已完成。

产品运行阶段仍是 `Scaffold`。产品 Release/default bootstrap 内没有可工作的真实 Live
adapter、已构建的 credential helper PE、代码签名或冻结的 VM 事实；新增的 Windows
guest-reset provider 仅属于 DevelopmentOnly 的 VM operator plane，不能进入产品包或在
宿主机执行。宿主机也从未执行真实安装、配置、API、系统探测或进程控制。

## 仓库与工作树

- 项目目录：`D:\projects(WIN)\claude-desktop-deepseek-installer`
- 只读参考：`D:\projects(WIN)\claude-deepseek-installer`
- 分支：`codex/repair/p10a-0a-fast-lane`
- 产品 Remote：`origin` → `git@github.com:LXZ56156/claude-desktop-deepseek-installer.git`
  （PUBLIC，protected-history ruleset `19068339`）
- Control repos：`LXZ56156/cddsi-host-to-vm`、`LXZ56156/cddsi-vm-to-host`
  （均为 PUBLIC；ruleset `19068292`、`19068313`）
- 当前版本：`0.1.0-dev`
- 产品运行阶段：`Scaffold`
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

## 2026-07-18 文档闭环、当前停点与 VM bootstrap-only 入口

本文提交本身会改变 commit/tree，所以不能在本文内写一个“最终 SHA”再声称它包含本文。
宿主机必须在文档提交后对包含本文的 clean HEAD 完成以下 finalization；最终精确值只由
retained owner-marked bundle output、同一暂停 automation、PR/CI 与公开 Git/remote 四方
持久事实核验：

1. 把本轮文档更新只作为正常 fast-forward commit 推到既有
   `codex/repair/p10a-0a-fast-lane` 与 PR #1；不得 force push、创建重复 PR、merge、
   发布或 promotion。
2. 从该最终 clean exact commit 运行标准 HostSandbox 双引擎全树门；当前预期每引擎
   430 项，全部 zero metrics、repository unchanged 与 cleanup 必须成立。
3. 运行 Release Simulation DryRun，要求 39 package files/39 ZIP entries、四层 inventory
   exact、`Changed=false`、全部 forbidden/secret/mutation 指标为 0；再过 diff/编码门。
4. 从最终 clean exact commit 生成并自校验 Store onboarding bundle：18 ZIP entries、
   inventory entries 16、timestamp 1980；记录 ZIP/manifest/inventory/content hashes、
   长度与 retained owner-marked path。
5. 用 `codex_app__automation_update` 更新既有宿主机 heartbeat，保持同一 id、minute
   cadence、target task 与 `PAUSED`，prompt 精确绑定最终 commit/tree/bundle、repository/
   protection/tool facts。凭据或 runtime assertion 仍为 `UNPROVISIONED` 时，误触发必须在
   任何网络、Git 或代码修改前返回 `BLOCKED`。
6. 核对 remote ref、clean tree、PR #1 仍 OPEN/DRAFT 且最终 HEAD CI 全部成功。以上完成后
   才可令 `CanStartVmBootstrap=true` 并交付 VM bootstrap-only handoff；此前不得进入 VM。
7. `CanStartVmIntegration=false`、`P10A0AComplete=false`、Formal readiness=false。
   服务端 protected history 已完成；窄角色凭据、runtime assertion、VM negative-permission/
   reset/task/unattended evidence 仍缺失。

状态判定不依赖本文编辑时的快照：上述 1–6 任一项未由外部事实证明时，
`CanStartVmBootstrap=false`；全部成立时，`CanStartVmBootstrap=true`，但仅允许执行下面的
bootstrap-only 工作。后一种状态也不改变
`CanStartVmIntegration=false`、`P10A0AComplete=false`、`CanStartFormalP10A=false`。

### VM bootstrap-only 步骤

1. 只在预定 disposable VM 基线启动后，取得 retained owner-marked output 中、并由同一
   暂停 automation 精确绑定的 onboarding ZIP；先离线
   校验 ZIP、manifest、inventory、content digest、长度、18 个 Store entries、16 个
   inventory entries、1980 timestamp、product commit/tree、三个 repository identity/
   genesis 与固定工具路径/hash。不得用本文中的历史锚替代外部精确绑定。
2. 在 VM 本地生成三把彼此独立、不可复用的 repository-scoped key：product read、
   host-to-VM read、VM-to-host append。只回传公钥与脱敏指纹；不得把私钥、token 或
   broad-admin credential 写入 relay、日志、报告、仓库或宿主机交接正文。
3. 只核对固定 Git、OpenSSH、PowerShell 的路径与 SHA-256；任一不匹配即 `BLOCKED`，
   不得 fallback 到 `PATH`、全局配置或交互式 bootstrap-admin 身份。
4. 只能从 VM 设备创建 `cddsi-fast-lane-vmtester-minute-poll`，保持固定一分钟 cadence、
   初始并持续 `PAUSED`。runtime protection assertion/hash/token 未由外部 provisioner
   提供前，prompt 必须在网络、Git、凭据探测或文件修改前返回 `BLOCKED`。
5. 产出脱敏的 `VM_BOOTSTRAP_STAGED` handoff 后立即停止。bootstrap-only 阶段禁止 poll
   control refs、fetch product、运行 negative-permission/reset/task/unattended 测试、执行
   产品 Live、修改/提交/推送产品代码、构建候选或把 relay 当正式 evidence。

完成 bootstrap-only 仍不能进入 integration。后续必须由外部 provisioner 发放并绑定窄
凭据与 runtime protection receipt，再在独立授权下执行负向权限、reset smoke、task 安全
启用与 unattended loop；这些证据齐全前不得把 VM task 或宿主机 heartbeat 从 `PAUSED`
改为运行态。

### P10A-0A 已实现范围与剩余 integration 工作

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
   onboarding builder 只从 clean exact commit 生成 Store ZIP，绑定 commit/tree、
   committed blob/working bytes、工具 hash、三个 repository identity、两个 genesis、
   prompt/runbook，且不包含凭据、用户路径或正式 evidence。
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

## 进入 VM integration 与 Formal Lane 前的阻塞项

是否可开始 VM bootstrap-only，必须按上一节从 retained owner-marked bundle output、同一
`PAUSED` automation、PR/CI 与公开 Git/remote 四方持久事实实时派生：闭环未完成时为
false，全部精确一致时为 true。
当前 tracked HEAD 的双引擎门、Release DryRun、18-entry bundle、暂停 heartbeat hash
binding 与最终 remote/PR/CI 是持续 bootstrap 核验项；任一漂移就回退为 false，但在全部
匹配时不再是 integration 阻塞。即使 bootstrap-ready，以下输入也不能由宿主机 fake 测试
虚构；未满足前不得激活真实 outbox integration，也不得宣称 P10A-0A/P10A/P10B/P11 完成：

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

## 建议给下一对话的开场指令

> 在 disposable VM 上只执行 P10A-0A bootstrap-only，不进入 integration。先完整阅读
> onboarding ZIP 内的 `vm-bootstrap.md`、manifest、inventory 与固定 policy/prompt；再从
> retained owner-marked bundle output、同一 `PAUSED` HostCoordinator automation、公开
> Git/remote、PR #1 与最终 CI 核验包含 `docs/HANDOFF.md` 的 clean HEAD 是否给出一致 exact
> binding。不得把历史
> `3e843912...`、`a09130f2...` 或 `615bbf3...` commit/bundle 当当前授权；任一事实缺失或
> 不一致即 `BLOCKED`，不要进入 VM 操作。
>
> 核验成立后，仅按“VM bootstrap-only 步骤”离线校验 18-entry Store bundle 与所有
> hashes/tokens/repository/tool bindings，在 VM 本地生成 product read、host-to-VM read、
> VM-to-host append 三把独立窄 key，只回传公钥和脱敏指纹；再从 VM 设备创建
> `cddsi-fast-lane-vmtester-minute-poll` 并保持一分钟 cadence、`PAUSED`。runtime protection
> assertion/hash/token 仍 `UNPROVISIONED` 时必须在网络、Git、凭据探测或文件修改前返回
> `BLOCKED`。产出 `VM_BOOTSTRAP_STAGED` handoff 后停止。
>
> 不得 poll/fetch/reset/test、运行产品 Live、修改/提交/推送产品代码、启用两端任务、
> merge PR、发布或 promotion。`CanStartVmIntegration=false`、`P10A0AComplete=false`、
> `CanStartFormalP10A=false`；后续 integration 需要外部 provisioner 的窄凭据/runtime
> protection receipt、负向权限、reset/task/unattended 证据，Formal P10A 还需要外部
> clean-snapshot receipt、独立 CAS 与签名。
