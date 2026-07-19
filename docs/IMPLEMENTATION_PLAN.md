# 实现计划

更新日期：2026-07-19

## 总目标

在当前 Windows 宿主机完成纯合同、fake 测试、故障注入和 deterministic Release
Candidate 组装能力，但不执行任何 Live 安装、配置、API、进程或系统动作。真实
工作分两道 VM 门：先在 disposable Windows VM 执行 P10A 窄范围校准并冻结事实，
再构建 P10B 双候选，最后由另一轮 disposable VM 与 VM 内 Codex 执行 P11 全面验收。
两道 VM 门之前先完成 P10A-0A 双机 Fast Lane MVP 前置门；该外部控制面只
协调宿主机 Codex 与只读 VM Codex，不属于产品或 trusted test harness。

产品流程和完成定义见 `PRODUCT_SPEC.md`；宿主机安全门见
`TEST_ISOLATION.md`；双机职责与消息协议见 `VM_TEST_RELAY.md`。

## 阶段总览

| 阶段 | 名称 | 当前状态 | 关键退出门 |
|---|---|---|---|
| P0 | 规划与外部合同基线 | 已完成（2026-07-13） | 文档体系、来源、决策、交接一致 |
| P1 | Sandbox Foundation | 已完成（2026-07-14） | 本机零接触证据全部通过 |
| P2 | 正式 3P 配置合同 | 已完成（2026-07-14） | 官方字段和 fixture 精确匹配 |
| P3 | 只读环境探测域模型 | 已完成（fake/synthetic） | 全部通过 fake/provider 测试 |
| P4 | 供应链获取与验签合同 | 已完成（纯合同） | 换包/签名/TOCTOU 全部 fail closed |
| P5 | Credential 生命周期 | 已完成（纯合同） | Key 不进入不允许的持久明文面 |
| P6 | 配置所有权、备份与恢复 | 已完成（纯合同） | receipt、备份与补偿独立绑定 |
| P7 | Cowork 与重启续跑 | 已完成（纯合同） | checkpoint/CAS 幂等、无 secret |
| P8 | Live Adapter 与编排器 | fake 编排器已完成；Live 未实现 | 本机始终无法执行 Live |
| P9 | Chat/Code/Cowork 验收 | synthetic 已完成 | fake/simulated 验收分别通过 |
| P10A-0A | 双机 Fast Lane MVP 前置门 | 唯一 phase2 与 loader 安全实现已通过 dirty WIP 双引擎统一门；clean-commit finalization 未完成、不得进入 VM | 从 clean exact commit 重跑双引擎门并完成 host finalization；再完成角色权限、真实双向交换、VM reset 与无人值守闭环 |
| P10A | 窄 VM 校准与事实冻结 | evidence/consumption 合同已完成；VM 未执行 | 真实 VM evidence 提交并冻结 |
| P10B | 双 Release Candidate | 宿主机支撑合同已通过门；真实双候选受外部输入阻断 | L0-L4、签名、SBOM 和双候选冻结 |
| P11 | VM Codex 全面 Live 验收 | 后置 | 两个候选的必需 VM 矩阵通过 |
| P12 | 不可变晋升与正式发布 | 后置 | 发布 P11 已测试的精确字节 |

依赖硬约束：

- P1 基线必须持续全绿；不得增加产品 live adapter 或 sandbox 外 I/O。P1 trusted
  harness 仅可管理自有 sandbox 和精确 allow-list 的测试工具。
- 没有验签证据，不得进入安装步骤。
- 没有 credential helper，不得持久化 3P 配置。
- 没有可恢复备份，不得写 policy；configLibrary 首版没有 writer。
- 没有 checkpoint，不得启用 VMP。
- P10A 只允许在专用 disposable VM、专用 runbook 和窄 operation allow-list 下执行；
  其授权不扩展到宿主机，也不等于 P11 全面 Live 授权。
- P10A-0A Fast Lane 必须先证明宿主机为唯一代码写入方、VM 代码 remote 为只读、
  relay 消息可去重且不会被当作命令或正式 evidence。Formal Lane 另行证明独立 evidence
  存储和外部 supervisor 可以恢复权威干净快照。
- VM Codex 不得修改源码、候选、runbook 或测试期望；P11 失败后必须由宿主机修复
  并回到 P10B 重建/签名新候选，不能让 VM 拉源码后继续使用旧候选结论。
- 没有已提交并消费的 P10A evidence，不得冻结 release facts 或开始 P10B 双候选。
- P10B 未完成，不得开始 P11 全面 VM Live。
- P11 未通过，不得宣称产品完成或进入 P12。

## 2026-07-19 当前工作包与端到端目标

用户可见的正常路径已经冻结为：用户启动 disposable VM、安装并登录 Codex、把宿主机
交付的唯一 onboarding ZIP 放进一个新建空目录并打开、粘贴一次最终提示。之后不再让
用户手工运行 hash、解压、PowerShell、Git、密钥或 automation 命令。VM Codex 完成本地
bootstrap；两端窄身份和 runtime protection 就绪后，HostCoordinator 唯一修改产品代码，
VmTester 只 reset、测试、分析和回传，自动循环到场景矩阵与 Formal 验收满足。P12 发布
仍保留一次人工确认，不自动 merge、promotion 或 release。

这是一项目标合同，不是当前完成状态。当前工作树基于 commit
`809942943bfeb0547fa36f57aedb8e75e1d45e29`、tree
`423e740e9fc191a23959e8c37a9a16eb81776ef3`，有 20 个 tracked 文件未提交；旧 bundle、
CI、automation prompt 和 430/430、39/39 结果均不绑定当前字节。

当前 dirty WIP 已通过标准 HostSandbox 双引擎全树门：两引擎各 448/448，全部 failure/
skip/not-run/inconclusive 与安全、ledger、mutation 指标为 0，repository unchanged、cleanup
succeeded。该结果早于本文最终同步与 commit，不能替代第 5 步要求的 clean exact HEAD 门。

宿主机进入 VM 前必须按以下顺序收口，任何 tracked 修改都从第 5 步重新开始：

1. 已落盘并通过 dirty WIP 统一门：`Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding` 的 canonical
   automation identity、目标 exact schema、唯一任务、prompt/current-task readback、伪造输入、
   phase1 后零/一状态重扫与漂移补偿、HostSandbox 路径绑定和权限正负测试；旧 direct 实现已
   收缩为 facade。readback 只作为绑定持有 TOML 字节的时点 observation，每次 Handoff 都重验。
2. 已落盘并通过 dirty WIP 统一门：`config/execution-boundaries.psd1` 只暴露 phase2 operator surface；
   direct core、direct handoff 与 mutation helper 保持 fail closed。
3. 已落盘并通过 dirty WIP 统一门：builder/loader 不再接受 `ObservationJsonBase64`、caller
   result/prompt/observation，只把 `CodexHome`、原始 ZIP、11 个外部锚点、固定 roots、target
   token 和 acknowledgement 交给 phase2。
4. 已落盘并通过 dirty WIP 统一门：loader 对 existing root 执行 current-SID/protected-DACL 精确校验，
   hash/parser/load 消费同一 captured bytes，状态 create-only/atomic/idempotent，cleanup 使用显式
   栈、逐层 no-reparse、deepest-first 非递归删除；测试不再启动未记账嵌套 PowerShell。
5. 在正常提交并非 force push 到同一 repair branch 后，从新的 clean exact HEAD 运行标准
   HostSandbox 双引擎全树门、Release Simulation DryRun、diff/编码门。
6. 从同一最终 commit 生成并自校验 18-entry/16-inventory/1980-timestamp onboarding bundle，
   原位更新既有 `cddsi-fast-lane-hostcoordinator-minute-poll` 的完整 binding，仍保持 `PAUSED`。
7. 核验 remote ref、PR #1 OPEN/DRAFT、最终 HEAD CI 与 clean worktree 全部一致；只有此时
   才可派生 `CanStartVmBootstrap=true` 并交付 ZIP、prompt 与 loader/prompt hashes。

bootstrap-ready 也不等于通信已经建立。prepared VM baseline 必须已有 manifest 固定的
Git、OpenSSH、`ssh-keygen`、PowerShell 7 和 Windows PowerShell；当前 bootstrap 只验证，
不下载或安装。要让普通全新 Windows VM 也只需安装 Codex，后续必须在用户明确授权后，
增加受固定来源/hash/签名约束的工具安装阶段，或交付预构建 baseline。

三组 VM keypair 初始仅为 `KEYPAIR_STAGED`。GitHub deploy-key 注册、窄 HostCoordinator/
VmTester 权限、正负向 remote 测试和 runtime assertion/hash/token 需要一次受授权的外部
provisioner；交互式 GitHub/bootstrap-admin 只能完成这次注册，不能保存或复用为 automation
credential。其后才允许安全激活两端 task、完成真实 publish/poll、deterministic reset、
unattended 修复循环。Formal Lane 的 external snapshot receipt、CAS、签名及 P10A/P10B/P11
仍是后续阶段，当前四个 readiness/complete 标志全部为 false。

## P0：规划与外部合同基线

### 目标

把调研结论、用户流程、安全边界、开发阶段和下一任务入口写入仓库，结束
“依赖聊天记录”的状态。

### 交付物

- 文档索引、产品规格、外部合同、配置设计、决策记录。
- 旧 Claude Code 安装项目的复用与禁止迁移清单。
- 宿主机零接触测试合同。
- Release 与 VM Codex 验收计划。
- 更新架构、安全、测试、README、AGENTS 和 HANDOFF。
- 文档完整性静态门和 Release manifest 分类。

### 退出条件

- 所有新增文档可从 `docs/README.md` 发现。
- 当前 Scaffold 与目标合同的差异明确，不把旧配置写成可部署状态。
- `scripts/check.ps1`、`build-release.ps1 -DryRun` 和 `git diff --check` 通过。
- 未执行安装、API、配置、进程、VMP 或重启。

## P1：Sandbox Foundation（已完成）

### 目标

在任何功能开发前，让受控产品代码只经过 fake provider，并把测试外壳的有限真实
进程/文件操作放入独立 trusted-harness allow-list。HostSandbox 不是 OS 权限
边界；不受信任代码和 live adapter 只能进入 disposable VM。

### 主要实现

- `ExecutionContext`：RunId、Mode、EnvironmentTier、Paths、Policy、Providers、
  AccessLedger。
- FileSystem、Environment、Registry、Process、Network、Package、Feature、
  Service、Credential、Clock provider 接口。
- fake provider、精确调用账本、mutation spy 和 synthetic canary。
- HostSandbox runner：唯一 owner-marked 临时根、最小子进程环境、清理边界。
- Git 配置隔离和 Pester 模块加载隔离。
- 两套 static AST allow-list：live adapter 与 trusted test harness 分开。
- TestSafe/DryRun 缺 fake/context 时 fail closed，不回退到真实系统。
- trusted harness 进程/网络 ledger 与产品 AccessLedger 分开。

### 测试

- PowerShell 7 与 5.1。
- synthetic HOME/AppData/Temp/Git/Claude 路径。
- registry、网络、进程、AppX、VMP、service 全部 fake。
- owner marker 错误、reparse point、路径逃逸和清理失败。
- canary 访问次数和内容泄露。

### 退出条件

`TEST_ISOLATION.md` 的 P1 退出条件全部通过，至少得到：

~~~text
LIVE_PROVIDER_LOADED = false
FORBIDDEN_RESOURCE_ACCESS_COUNT = 0
OUTSIDE_SANDBOX_WRITE_COUNT = 0
PRODUCT_LIVE_PROCESS_SPAWN_COUNT = 0
PRODUCT_NETWORK_REQUEST_COUNT = 0
REAL_REGISTRY_ACCESS_COUNT = 0
UNAPPROVED_HARNESS_PROCESS_COUNT = 0
UNAPPROVED_HARNESS_NETWORK_COUNT = 0
SECRET_FINDINGS = 0
~~~

受信任 pwsh/Pester/Git 进程计数可以大于零，但必须与场景声明精确相等。

### 完成证据（2026-07-14）

以下数字是 P1 首次退出门的历史快照，不是当前全树结果；当前易变证据以
`HANDOFF.md` 为准。

- PowerShell 7 与 Windows PowerShell 5.1 worker 各运行 124 项 Pester，全部通过，
  无 skipped、not-run 或 inconclusive。
- isolation evidence schema v2 绑定两个 engine grant、固定 Pester tree、仓库
  inventory/manifest、执行边界、依赖 manifest 和 16/10/6 suite 摘要。
- trusted process 5/5、最终 harness ledger 16 项精确匹配；产品 live/process/
  network/registry、outside write、未授权 harness、secret、unexpected ledger 和
  mutation spy 均为 0。
- 仓库 97 文件/26 目录前后 hash 相同，HostSandbox cleanup 成功。
- Release DryRun 对 29 个 PackageFiles 完成 source/staging/ZIP/extracted 四层扫描，
  清单与内容 hash 精确一致，16 项文件 ledger 精确匹配且 cleanup 成功。

该完成门只证明项目控制的本机自动化满足 P1 合同，不是 OS sandbox 或 Live/VM
验收。

## P2：正式 3P 配置合同（已完成）

### 目标

把当前 configLibrary-only、旧模型占位迁移到版本化 Anthropic 3P 合同，仍不写
任何真实配置。

### 主要实现

- 内部 desired state 与外部 serializer 分离。
- `gateway`、`helper-script`、`/anthropic`、`x-api-key`、
  `inferenceModels` 和 surface 字段。
- `RequestedSurfaces` 固定为 Chat/Code/Cowork，不存在用户输入；三个外部 surface
  字段固定为 `true`。
- Windows managed policy value set fixture。
- 基于官方 schema/changelog 的版本化规范 fixture；不要求宿主机导出。
- local source 只做 synthetic 检测 fixture；真实校准只允许在 P10A disposable VM，
  全面产品行为留到 P11。
- HKLM/HKCU/local source precedence 和冲突结果。
- Claude tier → DeepSeek V4 映射、label 和默认项。
- Desktop 最低版本与 contract version。

### 测试

- exact property/value/type 集合。
- 拒绝任何 capability selector、surface=false 或 readiness 改写 serializer 的
  输入。
- 未知字段、未知版本、旧模型和 discovery 失败。
- source conflict、低优先级不生效和静默模型降级。
- credential payload 中不出现 Key。

### 退出条件

- 当前 defaults、公开函数和 Contract 测试同步。
- 未确认字段保持 null/fail closed。
- fixture 有来源、核验日期和适用版本。
- 配置写入仍关闭。

### 完成证据（2026-07-14）

以下数字是 P2 首次退出门的历史快照，不是当前全树结果；当前易变证据以
`HANDOFF.md` 为准。

- 冻结 `claude-desktop-3p-managed-policy-v1`：最低 Desktop 版本 `1.20186.0`，
  Windows policy 不合并门槛 `1.19367.0`，首版唯一目标为
  `HKCU\SOFTWARE\Policies\Claude`。
- 内部 desired state 与 `ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet` serializer
  已分离；外部 value set 精确包含 15 个直接 `REG_SZ`，不包含 credential material。
- 固定 `gateway`、DeepSeek `/anthropic` endpoint、`x-api-key`、`helper-script`、
  V4 Pro/Flash 模型、关闭 discovery、三项 surface 为 true 和 Auto mode 为 false。
- `tests/Fixtures/claude-desktop-3p-contract-v1.json` 记录来源、核验日期、适用版本、
  exact value set 和 8 组 HKLM/HKCU/configLibrary synthetic source-resolution cases；
  产品运行时不读取 fixture。
- 旧 provider、endpoint、model、capability selector、surface=false、未知字段/版本、
  credential material 和 configLibrary writer 均 fail closed；backup/snapshot/write/restore
  继续 plan-only、`Changed=false`。
- PowerShell 7 与 Windows PowerShell 5.1 worker 各运行 131 项 Pester，全部通过，
  0 failed、0 skipped、0 not-run、0 inconclusive。
- live provider、产品真实进程/网络/registry、forbidden access、outside-sandbox write、
  unexpected ledger 和全部 mutation spy 均为 0；仓库前后均为 98 个文件、26 个目录，
  inventory/hash 不变且 HostSandbox cleanup 成功。
- Release DryRun 对 29 个 PackageFiles 完成 source/staging/ZIP/extracted 四层扫描，
  secret findings 为 0，清单与内容 hash 精确一致且 cleanup 成功。

该完成门只证明纯合同和项目控制的 fake/sandbox 自动化满足 P2，不代表读取过真实
Windows、Claude、Git、AppX、VMP、service、process 或 network 状态。

## P3：只读环境探测（fake/synthetic 已完成）

### 目标

实现 Windows、Desktop、Git、Cowork 的领域探测与 fake provider 逻辑，不编写或
加载真实探测 adapter，不读取宿主机。

### 主要实现

- Windows build、架构、管理员能力。
- Desktop 安装类型、版本和 package identity。
- Git 版本、来源、路径唯一性和能力；不读取/修改全局配置。
- VMP、硬件虚拟化、Cowork readiness 和服务合同。
- Standard/Offline 的部署决策输入，以及 P10A VM evidence 冻结的唯一
  per-user/machine-wide scope 合同。
- 从固定 `RequestedSurfaces` 派生 `EffectiveSurfaces` 和能力状态。

### 测试

- 支持/不支持的 Windows 与架构。
- legacy EXE、旧 MSIX、当前 MSIX、冲突安装。
- Git 合格复用、缺失、过旧、损坏、多路径歧义和异常输出。
- 相反 MSIX scope、双装风险和静默 fallback 被拒绝。
- 虚拟化/VMP/service 的全部组合。
- provider 超时、拒绝访问和不完整数据。

### 退出条件

- 所有结果结构稳定且无主机路径、用户名或敏感内容。
- 探测失败不触发安装或修复。
- AccessLedger 无真实调用。

## P4：供应链获取与验签（纯合同已完成）

### 目标

实现官方元数据 parser、fake 下载缓存和完整验签领域合同；不实现真实网络
adapter，安装仍然关闭。

### 主要实现

- Anthropic x64/Arm64 MSIX 官方元数据解析器。
- Git for Windows 官方元数据解析器。
- 受限重定向、大小、超时、取消和唯一缓存的 fake/provider contract。
- artifact type、路径 token、SHA-256、Authenticode、chain、Publisher、
  identity、source policy 证据。
- 安装前重新计算 hash 的 TOCTOU 合同。

### 测试

- DNS/TLS/超时/截断/超限/非法重定向。
- hash、signer、Publisher、identity、arch 和 package name 不匹配。
- 验签后同路径换包。
- 不存在任何 skip/bypass 参数。
- 所有下载使用 fake HTTP 和 synthetic artifact。

### 退出条件

- 安装函数只接受完整、匹配当前文件的证据。
- 元数据未知时 fail closed。
- Release 二进制扫描策略同步。

## P5：Credential 生命周期（纯合同已完成；helper binary 未完成）

### 目标

实现安全输入、保护、helper 协议、轮换和删除的领域合同/fake，不让 Key 进入不
允许的持久面。当前完成的是 receipt、授权、使用、补偿和 fake 生命周期合同；实际
DPAPI adapter、helper 源码、固定 .NET 构建链、SBOM、已签名 PE 均仍未完成。

### 主要实现

- SecureString 输入；只拒绝空值、多行、控制字符和不合理长度，不假设 `sk-`
  前缀。
- Credential provider 与 fake DPAPI；Live DPAPI adapter 留到 P8。
- helper 绝对路径、stdout/stderr、TTL、timeout 和 exit code 合同。
- DPAPI blob、ACL、ownership、rotation、revocation 和 cleanup。
- D-010 技术选择及相应构建/签名/SBOM。

### 测试

- 空白、多行、控制字符、错误格式且不静默 Trim。
- protect/unprotect、错误用户、损坏 blob、ACL 失败。
- helper 多行/空/过长/非法输出、超时和 stderr 泄露。
- logs/state/report/temp/release 全量 secret scan。

### 退出条件

- Key 不进入命令行、policy、configLibrary、环境、状态、日志或报告。
- synthetic secret findings 为零。
- helper 技术决策冻结。

## P6：配置所有权、备份与恢复（纯合同已完成）

### 目标

在 fake registry/filesystem 中证明 HKCU policy 的冲突检测、原子更新和失败
恢复；HKLM/configLibrary 只检测，不写入。

### 主要实现

- 配置来源 inventory 与 ownership。
- HKCU registry 精确值类型和值集备份/补偿。
- HKLM/local source 阻断冲突；首版没有 configLibrary writer。
- DPAPI 可恢复备份与不可恢复脱敏快照。
- 备份 ID、ACL、生命周期和清理。

### 测试

- HKLM/HKCU/local 冲突。
- 非项目配置默认拒绝覆盖。
- 备份失败、部分写、重读不一致、恢复失败。
- reparse point、路径逃逸、TOCTOU 和 owner mismatch。
- 脱敏快照不能作为恢复源。

### 退出条件

- 每个项目拥有的配置故障点都有确定原状态或显式 unrecoverable 失败。
- 状态只含 metadata，不含原始配置或 Key。
- 没有备份不得进入写入。

## P7：Cowork 与重启续跑（纯合同已完成）

### 目标

实现 VMP 计划、双重确认、checkpoint 和重新双击后的幂等续跑。

### 主要实现

- readiness/blocker 结果。
- `Enable-WindowsOptionalFeature -NoRestart` 的 provider/fake 合同，真实 adapter
  留到 P8。
- system change 前写 checkpoint。
- run ownership、过期、schema migration、resume phase 和 cleanup。
- 用户拒绝、重启未完成、状态损坏和重复运行。
- `PENDING_RESTART/BLOCKED/ACTION_REQUIRED/CANCELLED` 的稳定状态映射。

### 测试

- VMP 所有状态组合。
- checkpoint 写入失败时不修改 feature。
- 损坏/过期/他人 runId 状态拒绝续跑。
- checkpoint 无 credential、原始配置和真实路径。
- 自动重启、RunOnce、任务计划保持不存在。

### 退出条件

- fake restart 流程幂等。
- 任何异常都不会误认为 Cowork ready。
- D-012 保持成立。

## P8：Live Adapter 与编排器（fake 编排器已完成；Live 未实现）

### 目标

以完整用户流程、stage/grant/auth/workflow 绑定、receipt trace 与补偿编排为核心。
fake executor/orchestrator 已实现；真实 adapter 源码仍是未完成交付物。本地只做
静态/contract/fake executor 测试；“不在宿主机执行”是强制开发政策，stage/grant
负责防误触但不声称能在同一 Windows 用户权限下证明 VM 身份。

### 主要实现

- 真实网络、MSIX/Git 获取与安装 adapter。
- HKCU managed policy、DPAPI、credential helper adapter；HKLM/local 只读检测。
- VMP、service、Desktop lifecycle adapter。
- 顶层 orchestrator：preflight → fixed all-surfaces target → acquire → verify →
  ensure Git → Cowork preparation → credential → backup → config → lifecycle →
  acceptance → report；没有 capability selector。
- P10A VM evidence 冻结的单一 MSIX scope；运行时不 fallback、不双装、不静默
  迁移。
- 独立许可、确认、回滚和取消。
- `Scaffold → Development → VmAcceptance → UserLive` stage manifest 和
  operation grant 验证。

### 测试

- live adapter 只做静态/contract/fake executor 测试。
- 每个操作的 TestSafe、DryRun、Live gate、失败注入和补偿。
- 参数边界、特殊路径、超时和进程树。
- Git 合格复用时 `Changed=false`；缺失/过旧时才进入安装，歧义或用户取消时不能
  报告完成。
- Cowork 阻断可以保留已安全完成的 Chat/Code，但顶层只能为
  `PARTIAL/ACTION_REQUIRED`，未知部分修改必须 `FAILED`。
- 本机测试证明 live adapter 未加载/未执行。

### 退出条件

- 所有用户路径均有安全停止点和回滚。
- Development stage 的默认执行仍阻止 Live。
- VmAcceptance grant 绑定候选 ZIP hash、content digest、runId、允许操作、
  过期、nonce 和用户确认；环境变量或 `-Mode Live` 不能单独授权。

## P9：Chat、Code、Cowork 验收（synthetic 已完成）

### 目标

建立固定完整功能目标下的分能力 readiness、修复和中文脱敏报告，并定义 VM
外部 E2E 证据接口。

### 主要实现

- Chat 配置/API validation/readiness。
- Code 配置、Git 必备前置和 readiness。
- Cowork 配置与 readiness。
- VM Codex 注入的 Chat/Code/Cowork E2E 证据 schema。
- 运行状态、能力状态和 UI 证据三层 schema；`NOT_TESTED` 只属于 UI 证据。
- Repair/Restore 计划和报告。

### 测试

- 每个子项独立成功/失败/超时。
- 不存在 capability selector；三个 surface 固定为 true。
- `SUCCEEDED/PARTIAL/RESTART_REQUIRED/ACTION_REQUIRED/CANCELLED/FAILED` 与
  `READY/BLOCKED/PENDING_RESTART/UNSUPPORTED/UNKNOWN` 的全部映射。
- DeepSeek 不支持的 content block。
- 一个子项 PASS 不提升其他子项。
- 任何依赖失败都不能通过关闭 Code/Cowork 提升总结果。
- API Key、用户名、真实路径和响应敏感内容脱敏。

### 退出条件

- fake/simulated acceptance 全部通过。
- `Success=true` 只可能对应全部三项 readiness 为 `READY` 的 `SUCCEEDED`。
- 产品自身不内置 Desktop UI 自动化；真实 UI E2E 只在 P11。

## P10A-0A：双机 Fast Lane MVP 前置门（bootstrap implementation landed；bootstrap/integration blocked）

### 目标

按 `VM_TEST_RELAY.md` 建立与产品、trusted harness 分离的操作员协调平面，使宿主机
Codex 能接收脱敏测试结果、修复并推送，使 VM Codex 能获知精确的新测试对象并重新
执行，同时不给 VM 代码写权限，也不把 relay 当作正式发布证据。

### 主要实现

- 已实现 `DirectionalRepositoryPair` 本地策略合同：一个逻辑双 outbox 映射为两个
  物理单向 public protected control repos。`LXZ56156/cddsi-host-to-vm` 与
  `LXZ56156/cddsi-vm-to-host` 已创建并初始化 `outbox/`；两仓 `main` 的 protected
  history 已由 ruleset `19068292`、`19068313` 实际施加，方向隔离 writer credential
  尚未部署。
- 已实现 relay/state/hash 纯合同：结构化 envelope、canonical payload/message hash、
  前序 hash、单调 sequence、过期、去重、一个 active cycle、STOP 与 acknowledgement。
  日常结果只作 Fast Lane 开发诊断，不能成为正式验收事实。
- 已实现固定 Git outbox runtime：绑定 Git/SSH/key/known-hosts hash，使用最小进程环境、
  owner-marked state/lock、repository numeric/node identity、当前 protection observation、
  pinned genesis、线性 history、bounded poll 与 fast-forward-only append；payload 不执行。
  state direct-child leaf 固定为 `fl-<32 lowercase hex>`，每条 Git 命令只使用
  command-local `core.longpaths=true`，不继承 `PATH` 或读写 global Git config；Git 失败
  只披露 invocation ordinal 与数值 exit code。
- 已实现 readiness resolver，分别输出宿主实现、`CanStartVmBootstrap`、
  `CanStartVmIntegration`、VM credential/task/reset/unattended、`P10A0AComplete` 和 Formal
  readiness；bootstrap 不能掩盖 protection/credential 的 integration 失败。
- 已实现 deterministic VM onboarding builder：只从 clean exact commit 生成 Store ZIP，
  绑定 commit/tree、committed blob/working bytes、工具 hash、三个 repository identity、
  两个 genesis、prompt/runbook，且不包含 credential、用户路径或正式 evidence。
- dirty worktree 已实现并通过标准双引擎全树门的一次提示自治 VM bootstrap；clean-commit
  finalization 仍待完成：普通用户只启动
  VM、安装登录 Codex、把唯一 ZIP
  放进新建空文件夹并打开、粘贴一次最终提示。单一受审 onboarding 入口负责外层 hash/
  length 零写入门、owner-marked 安全解压、manifest v3/inventory/五工具校验、三组
  `KEYPAIR_STAGED`、唯一 `PAUSED` minute task 的创建或原位更新与 readback，以及 public
  redacted handoff；不允许临时拼替代命令。
- 已实现 fake deterministic reset、ownership/baseline/plan/action receipts、baseline
  drift 阻断和诊断性 `CLEAN_READY`，并增加 VM-only dispatcher/provider、device/command
  trust、preflight/postcondition 与 fail-closed escalation。实际 provider/device evidence
  和 development-retest Live smoke 仍必须在 disposable VM 完成。
- 已增加宿主机/VM 轮询 prompts、runbooks 与 synthetic rehearsal，并把 operator
  coordination plane 精确隔离为 `DevelopmentOnlyFiles`，不进入默认 bootstrap 或 Release。
- public protected 产品 remote `LXZ56156/claude-desktop-deepseek-installer` 已创建并接收
  旧 `main` 基线；ruleset `19068339` 覆盖 `main` 与 `codex/repair/*`。本轮修复位于
  `codex/repair/p10a-0a-fast-lane`。宿主机仍需限修复分支写凭据，
  VM 仍需独立 read-only credential；VM 对产品 remote 的负向写验证不能由本地 fake
  合同代替。
- 宿主机分钟级 heartbeat 已创建为
  `cddsi-fast-lane-hostcoordinator-minute-poll`。宿主机 finalization 必须把同一任务原位更新为
  当次精确 commit/tree、bundle 和 runtime material 绑定，并继续保持 `PAUSED`；精确值只从实际 Git、
  既有 PR/CI 和该暂停 automation 的当前配置交叉核验，不写回 tracked 文档。窄凭据与
  runtime assertion 仍为 `UNPROVISIONED`，任务因此在网络、Git 或代码修改前 fail closed。
  本机没有 VM Codex project，VM task 必须在 VM 设备上创建并先保持暂停。
- Formal Lane 继续使用独立 append-only/WORM evidence store、签名和受信 receipt；
  它属于 P10A/P11 正式门，不阻塞 Fast Lane 自动修复 MVP。
- VM provider/device trust 部署并实测后，日常重测只允许按冻结 allow-list 清除本项目拥有的安装物、
  HKCU/credential/checkpoint 与 owner-marked 测试目录并签发 `CLEAN_READY` receipt；
  不得广泛清理用户 profile 或全局工具配置。
- 外部 hypervisor supervisor 维护权威快照；首次 P10A、正式 P11/里程碑，或 reset
  失败、baseline drift、VMP/重启/卸载/补偿状态未知时才恢复并签发 receipt。白话说，
  supervisor 是普通 VM 软件或其外部自动化，baseline 是 VM 起始状态；Formal
  clean-snapshot receipt 本次 bootstrap 不需要，只属于上述后续正式门。
- 两个物理单向 public protected control repos 共同提供逻辑 `host-to-vm`/`vm-to-host` 双 outbox；
  两端 Codex automation 分别轮询。需要更低延迟时，由 deterministic watcher 验签并调用固定
  `codex exec resume`；普通 Git push 不视为对方已收到。
- 人工搬运已签名 request/report bundle 的降级路径，保持相同 schema 与权限边界。

### 测试

- 本地 synthetic artifact rehearsal 已演练 request、ack、start、result、host ack、fix
  ready 和 retest 的成功路径以及 fail-closed 分支，不执行 Live。
- 本地合同已拒绝篡改、过期、错前序 hash、sequence 回退、重复/并发 cycle、错
  commit/hash、未知 message type 与错误 sender role；Formal Lane 另测无效签名/receipt。
- fake reset 合同已证明只计划项目拥有资源并检测 baseline drift；正式门或任何未知
  状态缺少 snapshot receipt 时阻断，VM 清理不得越出 allow-list/owner-marked 根。
- 真实角色凭据部署后仍须负向证明 VM 不能写产品仓库，也不能写错误方向的 control
  repo；还须证明两端 Scheduled Tasks 可重复完成无人值守闭环。
- 报告自由文本不得被 shell/PowerShell 执行，relay compromise 不得触发 merge、P12
  promotion、发布或宿主机 Live；secret 与真实访问/mutation 指标持续为零。

### 退出条件

- 文档闭环提交后，只有最终 clean exact HEAD 通过双引擎全树门、Release DryRun、
  diff/编码门和 PR CI，immutable onboarding bundle 已重新生成、自校验，host task 已精确
  绑定且保持 `PAUSED`，才由四方持久事实交叉核验派生 `CanStartVmBootstrap=true`。精确 commit/tree、
  bundle/manifest/inventory/hash/token 与 CI run 必须从 retained owner-marked bundle output、
  暂停 automation、既有 PR/CI 和实际 Git/remote 四方交叉核验，不能由 tracked 文档自证。
  任何后续 tracked 修改都会使该状态失效，直到从新的
  clean exact HEAD 重新完成同一 finalization。即使为 true 也只允许 bootstrap-only，始终不
  允许 control polling、产品测试、reset Live 或产品代码修改。
  retained path、host task、PR/CI、worktree 和 remote 的四方核验只由宿主机 finalization
  完成；VM 只消费最终提示词给出的外部 ZIP hash/length、commit/tree 与 binding tokens，
  不重复检查宿主机事实。
- 三个 repositories 的 protected history 已部署并验证。VM integration 另要求窄
  HostCoordinator credential、runtime protection assertion 和随后 VM 侧 credential/
  negative-permission evidence；不得复用 bootstrap administrator credential 作为降级。
- `VM_TEST_RELAY.md` 的 Fast Lane 权限矩阵、状态机、消息 schema 与清洁合同均有
  可重放的 synthetic dry rehearsal 证据；该本地条件已满足，但不能单独完成 P10A-0A。
- 日常 `CLEAN_READY` reset 和自动消息闭环可无人值守重复；用户或外部 supervisor
  仍能在正式门或升级条件触发时从 VM guest 外恢复权威快照。两端最小权限凭据已
  轮换并经负向测试验证。
- 宿主机是唯一代码写入方；VM 只能获取精确测试对象、运行冻结 runbook 和回传
  脱敏结果。
- 不存在自动 merge、自动 P12、自动发布或“拉最新源码即视为候选已重测”的路径。

## P10A：窄 VM 校准与事实冻结（合同已完成；VM 未执行）

### 目标

先在宿主机完成不可伪造、可重算的 calibration evidence/consumption 合同，再在
专用 disposable VM 中执行严格限域的真实校准。P10A 不是完整安装验收，也不授予
宿主机 Live 权限。

### 已实现合同

- canonical JSON 与固定 golden hash。
- 外部 session anchor、terminal session binding、时序和新鲜度约束。
- 精确的 calibration operation set、独立 operation receipt 与 provider evidence
  digest。
- cleanup evidence、schema v2、篡改/重放/跨 session 拒绝。
- `READY_TO_COMMIT → READY_TO_FREEZE` CAS 消费状态机。

### 尚未完成

- P10A-0A 最小角色凭据及负向权限验证、VM provider/device trust 与 deterministic
  reset 实测、从 VM 设备创建并初始暂停的 Codex Scheduled Task、安全
  启用两端任务与无人值守 runner；以及 Formal Lane evidence store、receipt authority
  与外部快照 supervisor。
- 实际 P10A VM runner/provider 与 evidence 导出/提交流程。
- Standard/Offline、唯一 MSIX scope、Git、helper/chooser、HKCU 行为和 cleanup 的
  真实 VM facts。
- credential helper 实际 PE、固定 .NET 工具链、源码/依赖锁、SBOM 和代码签名。

### 退出条件

- 专用 disposable VM 按 `VM_CALIBRATION_PLAN.md` 完成窄矩阵，所有真实 operation
  与一次性 grant 精确匹配。
- VM 从已验签 request 获取精确 commit/calibration package，且测试前的固定快照
  receipt 来自 guest 外 supervisor；VM 没有修改产品仓库或 runbook。
- evidence 通过 schema、anchor、receipt、digest、时序、cleanup 和 secret scan。
- evidence 被提交并以 CAS 消费，生成唯一、版本化、可重算的 frozen release facts。
- 任一事实未知、冲突、过期或不可验证时 fail closed，不进入 P10B。

## P10B：双 Release Candidate（宿主机支撑合同已完成；真实候选未构建）

### 目标

只消费 P10A 已提交的 frozen facts，在 clean commit、固定工具链和签名服务下生成可
交给 P11 的两个不可变候选产物。

### 已实现的宿主机支撑范围

- `release-facts`：从已提交 P10A evidence 编译并验证冻结事实。
- `release-artifact` 与 candidate assembler：deterministic manifest、profile、content
  digest、ZIP hash、候选 identity 和 detached sidecar。
- `credential-helper-release`：helper 源码/工具链/构建 receipt/PE identity/
  Authenticode/SBOM 的消费和失败门。
- `RELEASE_PLAN.md` 的 source/staging/ZIP/extracted 精确白名单与 secret scan。
- 中文、空格、`&`、`!`、括号路径仿真，以及 VM runbook/允许变化 manifest。

上述宿主机支撑合同已通过双引擎统一门和 Release DryRun。缺少 P10A frozen facts、
实际 helper PE、签名服务、外部 trust anchor 或 clean commit 时，candidate assembler
仍必须 fail closed，不能生成“模拟可发布”结果。

### 退出条件

- L0-L4、故障注入、Release DryRun 和真实候选构建全部通过。
- ZIP 条目与白名单精确相等，secret findings 为 0。
- 固定 .NET 工具链、helper 源码与依赖锁、实际 PE、SBOM、Authenticode 和 detached
  sidecar 签名 receipt 均可验证。
- copyright holder、许可证和再分发评审完成。
- `VmAcceptance` 与待发布 `UserLive` 的 hash、版本、profile、commit、content digest
  和 sidecar 冻结；任何修改都生成新候选。
- 发布矩阵不存在功能选择或 Chat-only 成功路径，Git ready 且三个 surface 目标均
  可达。

## P11：VM Codex Live 验收

### 目标

在 disposable VM 中对 P10B 两个候选的精确字节执行首次全面产品安装、故障、恢复
与功能验收。P10A 已先做窄范围真实校准，但不替代本阶段。

### 范围

严格按 `VM_ACCEPTANCE_PLAN.md`。用户准备 VM 与 Codex；Key 在 VM 本地输入。
覆盖安装、UAC、Git、VMP、重启、3P 直达、Chat、Code、Cowork、失败、资源级
补偿、重复运行和泄露扫描。最终还必须测试待发布 UserLive artifact 的精确字节。
VM Codex 只执行冻结 runbook、分析和回传，不修改代码、候选或测试期望。失败后由
宿主机修复并通过质量门；随后回到 P10B 构建、签名和冻结新的双候选，再由外部
supervisor 恢复快照后重测。拉取更新源码不能替代候选重建或精确字节验收。

### 退出条件

- 必需矩阵通过。
- 未授权变化和 secret findings 均为零。
- 从干净快照可重复。
- 失败必须回到开发阶段生成新 RC，不在 VM 中热补丁。

## P12：不可变晋升与正式发布

### 目标

只发布 P11 已经测试的 UserLive ZIP 原字节，不重新构建、不修改 VERSION、
CHANGELOG、文件名内容或 ZIP metadata。

### 主要动作

- 核对 P11 evidence 中的 UserLive SHA-256 与待发布文件完全一致。
- 发布 detached sidecar、checksum、Release Notes、支持矩阵和脱敏验收摘要。
- VmAcceptance artifact 不对外分发。
- 上传失败可以重试，但不能重建或替换相同版本字节。

### 退出条件

- 下载后的 ZIP hash 与 P11 测试 hash 一致。
- 正式版本只指向该不可变 artifact。
- 若任何字节改变，返回 P10B/P11 生成新版本并重测。

## 当前停点与下一工作包

P3-P4、P5-P7 纯合同、P8 fake orchestrator、P9 synthetic、P10A
evidence/consumption、P10B 宿主机支撑合同和 P10A-0A 本地 TestSafe/DryRun 合同切片
均已实现。P10A-0A 宿主机侧又完成固定 Git outbox、readiness、deterministic onboarding 和
VM-only reset boundary。包含本节的文档闭环提交必须再从最终 clean HEAD 完成双引擎全树门、
Release DryRun、diff/编码门、immutable onboarding bundle、自校验、暂停 heartbeat binding
及 remote/PR/CI 核验；全部外部事实匹配后才派生 `CanStartVmBootstrap=true`，且仅允许
bootstrap-only。为避免 tracked 自引用，精确 commit/tree、bundle/manifest/inventory/content
digest、token、retained path 和 CI run 不在本文固化；交接时必须从 retained owner-marked
bundle output、暂停 automation、既有 PR/CI 与实际 Git/remote 四方交叉核验。任何后续
tracked 修改都会使该结论失效并要求从新
clean exact HEAD 重新 finalization。

2026-07-16 公开预检确认 repair ref 可达对象的常见凭据模式扫描为零；用户设置
`PrivacyDecision=ACCEPTED`、`HistoryRewrite=NO` 和
`ResidualPrivacyAudit=NOT_PERFORMED_ACCEPTED_RISK`。PUBLIC policy/readiness/outbox
receipt/onboarding/prompts/runbooks/tests 随后升版。2026-07-17 三仓均已 public；产品
ruleset `19068339`、host-to-VM `19068292`、VM-to-host `19068313` 均 active、无 bypass，
并经 effective-rules API 验证目标 refs 的删除、非快进和线性历史约束。

下一工作包严格按以下依赖顺序推进：

1. VM 只执行 bootstrap：
   用户只完成启动 VM、安装登录 Codex、把唯一 ZIP 放进空文件夹并打开、粘贴一次提示。
   VM Codex 用单一受审入口自治完成离线验 manifest v3/inventory/hash/五工具、owner-marked
   local staging、三组 `KEYPAIR_STAGED`、public fingerprints/tool hash，并从 VM 设备创建或
   原位更新唯一 `PAUSED` minute task 后 readback。先得到 `VM_BOOTSTRAP_LOCAL_STAGED`，
   再输出 `VM_BOOTSTRAP_STAGED` 并停止；不得轮询、测试或运行 reset Live。
2. 发放窄 HostCoordinator/VmTester credentials：宿主机只写 repair ref 与 host-to-VM，
   VM 只读产品和 host-to-VM、只写 VM-to-host；用真实 remote 负向证明错向写、产品写、
   force-push/delete/rewrite 和 broad admin capability 均被拒绝。
3. 在 VM provision 并验证固定 deterministic reset provider/device trust；只处理
   owner-marked allow-list，未知状态升级到 guest 外 snapshot restore。TestSafe、DryRun、
   development-retest Live 与幂等 reset smoke 依序通过前不得记为 ready。
4. 重新确认两端 minute tasks 均为 paused 且绑定精确 runtime/prompt/bundle hash，随后按
   runbook 安全启用并用实际 remotes 证明无人值守失败/修复/重测闭环。普通 push 不能
   替代 acknowledgement，relay 不能替代正式 evidence receipt，VM 不得修改产品代码。
5. 准备 Formal Lane：P10A 专用 disposable VM、限域 runner/provider、evidence
   exporter、外部 snapshot supervisor 与受控 submission，以及外部 CAS
   authority/commit service。
6. 由外部 supervisor 恢复 clean snapshot 并签发 receipt，再按
   `VM_CALIBRATION_PLAN.md` 执行首次窄 VM 校准，获取真实 Standard/Offline、MSIX、
   Git、helper/chooser、HKCU 与 cleanup evidence。
7. 由独立 CAS/签名 authority 原子提交并消费 evidence，生成唯一 frozen facts。
8. 回到 P10B，在 clean commit、固定工具链、实际 helper PE 和独立签名服务下构建
   并冻结 `VmAcceptance`/`UserLive` 双候选。
9. 只有两个候选的精确字节冻结后，才进入 P11 全面 disposable VM；每次失败修复
   都必须生成新 candidate identity/hash 并从外部恢复的干净快照重测。

宿主机不得加载或执行真实下载、registry、MSIX/Git 安装、VMP、API、Claude 配置、
进程控制或重启。`lib/live-adapters.ps1` 继续保持精确 allow-list 下的 fail-closed
隔离入口，不能写成可工作 Live adapter。

## 当前外部阻塞

- 服务端 protected history 已完成。bootstrap-only 的宿主机门不是长期外部阻塞：当 clean
  HEAD、bundle、暂停 task、remote/PR/CI 的外部事实全部匹配时派生
  `CanStartVmBootstrap=true`；任一不匹配则为 false。这不等于 integration 或正式 VM 门已通过。
- VM 不负责重查上述宿主机 retained path/task/PR/CI/remote；它只验证最终提示词的外部
  ZIP hash/length、commit/tree 与 tokens。新 key 只是 `KEYPAIR_STAGED`，必须完成注册及真实
  正/负向权限测试后才可能 credential ready。
- 宿主机限 repair-ref/host-to-VM、VM 产品 read-only/VM-to-host 的窄 credentials，以及
  产品写、错向写、force/delete/rewrite 和 broad-admin 负向证据。
- VM provider/device trust、真实 deterministic reset smoke、从 VM device 创建并保持
  初始 paused 的 task、安全启用当前暂停的宿主机 heartbeat，以及经实际 remotes 验证的
  unattended 闭环。
- Formal Lane 所需的 append-only/WORM evidence store、消息/receipt authority，以及
  能在正式门或升级条件下从 guest 外恢复快照并签发 receipt 的 supervisor。
- P10A 专用 disposable VM、限域 runner/provider、evidence exporter 与受控
  submission 流程，以及真实 Standard/Offline/MSIX/Git/helper/HKCU calibration
  evidence。
- 受信 CAS store authority/key 管理、原子 commit service，以及 store-issued
  consumption/freeze 签名 receipt。
- 固定 .NET 工具链、helper 源码、依赖锁、SBOM 生成链和实际 PE。
- 可发布 credential helper 的 Authenticode 身份、证书或签名服务，以及由真实
  受信 provider 产生的签名、ACL、DPAPI 与 invocation receipt；结构性 evidence
  不能晋升为发布证据。
- 独立的 release-sidecar signing authority、artifact 外部 trust anchor、签名服务
  与可验证 receipt。
- copyright holder 与许可证/再分发评审结论。
- P10B 构建时可证明的 clean commit。

这些输入未满足前，可以完成验证 schema、失败注入和 deterministic assembler，但
不得把 P10A VM facts、P10B 候选、helper binary、签名或 P11 写成已完成。

## P1 完成基线

P1 runner 已存在。`scripts/bootstrap-dev.ps1` 只验证固定 Pester tree；
`scripts/check.ps1` 要求三个工具的绝对路径与 SHA-256，并在 owner-marked sandbox
内运行双引擎 Pester 和隔离 Git。任何依赖、工具 identity、suite count、证据
schema 或 ledger 漂移均 fail closed，不得退回继承真实 HOME 的临时入口。

## P1 之后每个工作包的固定完成门

1. 先写/更新测试与故障矩阵。
2. 实现最小范围。
3. 按 `TESTING.md` 的 P1 标准入口运行双 PowerShell 引擎测试；必须显式绑定三个
   工具的绝对路径与 SHA-256。
4. 取得 clean `scripts/check.ps1 -PassThru` evidence 后运行
   `scripts/build-release.ps1 -DryRun`；working-tree/cached `git diff --check` 已在
   隔离质量门内执行。

5. 复审 secret、真实资源访问、manifest 和文档一致性。
6. 更新 `HANDOFF.md` 的阶段、已完成、下一工作包和验证结果。

任一门失败不得进入下一阶段，也不得用跳过测试或放宽安全规则解决。
