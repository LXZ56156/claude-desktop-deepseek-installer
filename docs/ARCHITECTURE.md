# 架构

更新日期：2026-07-16

## 定位

本项目独立安装和配置 Claude Desktop，不依赖独立 Claude Code CLI。目标是通过
Anthropic 官方 Third-Party managed configuration 连接 DeepSeek，固定以 Chat、
内置 Code 和 Cowork 三项全部可用为产品目标。

产品工作流仍为 `Scaffold`，领域模块的 Live 动作无条件失败。P1 已实现
ExecutionContext、十类 provider contract、default-deny fake provider、
AccessLedger、state-store provider 边界和 trusted HostSandbox；没有 live adapter
进入默认 bootstrap 或本地执行图。

## 分层

~~~text
Entrypoints
  -> Orchestrator
     -> ExecutionContext + Policy + AccessLedger
        -> Domain services
           -> Provider interfaces
              -> Fake/Sandbox providers (local and CI)
              -> Live adapters (VM/UserLive only)

OperatorCoordination (separate development plane)
  -> Fast Lane policy + pure relay state machine + readiness
     -> deterministic onboarding + bounded directional Git transport
        -> pure/fake reset + VM-only provider boundary + synthetic rehearsal
           -> external protected history, credentials, paused tasks and VM evidence
~~~

### Entrypoints

`.cmd` 和 `Start-Here.ps1` 只负责参数、模式、交互边界和退出码，不直接执行
领域动作。

### Orchestrator

编排顺序、补偿和阶段门只放在顶层：

~~~text
preflight
  -> fixed all-surfaces target
  -> acquire and verify artifacts
  -> ensure Git availability
  -> Cowork preparation
  -> acquire protected credential
  -> detect config sources and backup
  -> deploy one config source
  -> lifecycle
  -> Chat / Code / Cowork acceptance
  -> report / repair / restore
~~~

### ExecutionContext

所有非纯操作显式接收上下文：

- RunId、Mode、EnvironmentTier。
- synthetic/live 路径。
- provider 集合。
- real-resource policy。
- access ledger。

TestSafe/DryRun 测试缺 fake provider 时失败，不能回退到真实环境。详细合同见
`TEST_ISOLATION.md`。

### Domain services

现有模块按领域保留：

- `desktop-env-check.ps1`
- `desktop-msix.ps1`
- `git-for-windows.ps1`
- `cowork-readiness.ps1`
- `deepseek-api.ps1`
- `desktop-config.ps1`
- `desktop-lifecycle.ps1`
- `desktop-acceptance.ps1`

领域模块之间不形成循环依赖，也不能直接调用系统 cmdlet/.NET I/O。跨域协调只在
orchestrator。acceptance 消费结果，不成为安装实现的依赖。

### Providers 与 Live adapters

Provider 覆盖 FileSystem、Environment、Registry、Network、Process、Package、
Feature、Service、Credential、Clock。

- fake/sandbox provider 是本地和 CI 唯一可加载实现。
- live adapter 使用精确文件 allow-list，不能由默认 bootstrap 加载。
- live adapter 首次真实执行只在后续 disposable VM。
- trusted test harness 使用另一份精确 allow-list，只能创建自有 sandbox、启动
  pwsh/Pester/Git 质量门并单独记账，不属于产品 provider。

### Operator coordination plane

双机测试闭环属于独立 OperatorCoordination development plane，权威合同见
`VM_TEST_RELAY.md`。它不进入产品 bootstrap、ProductCore、Release 或 trusted
harness runtime；trusted harness 仅可从自己的 allow-listed 测试入口调用其
synthetic/local/fake contract。它不充当正式证据验证器。截至 2026-07-16，宿主机侧
transport/runtime、onboarding 和 readiness 合同已实现，但外部保护/凭据、VM 设备
provisioning 和无人值守双机验证尚未完成：

~~~text
Fast Lane logical control plane:
  HostCoordinator -> private host-to-VM repository -> VmTester (read only)
  HostCoordinator <- private VM-to-host repository <- VmTester (write only)
Formal Lane: external clean snapshot + exact artifact
             -> independent CAS/signature/receipt validators
~~~

- `config/fast-lane-policy.psd1` 冻结两个物理单向 private repository、产品 remote、
  角色、分钟级轮询、reset allow-list 和禁止 promotion 的策略。之所以不用同一仓库
  两个目录，是因为 GitHub deploy key 是 repository-scoped，不提供 path-scoped 写
  capability。
- `lib/vm-test-relay.ps1` 是 pure Fast Lane canonical validator/state machine，负责
  双 repository/outbox identity、CycleId/sequence/previous hash、CAS、单 active
  cycle、STOP 和 fail-closed transition；它没有 Git/network transport。
- `operator/fast-lane/invoke-git-outbox.ps1` 是 DevelopmentOnly 的固定 transport
  runner：清空继承环境、绑定 Git/SSH/key/known-hosts hash、验证 repository 数字/node
  identity、protected-history evidence、pinned genesis 和线性 commit chain，只允许
  bounded fast-forward poll/append，不执行 payload。protection observation 还必须与
  operator-plane `control-protection-trust` owner marker、receipt-specific authority
  assertion、独立预置的 assertion SHA-256/authority token 及单调 previous-receipt
  chain 交叉绑定，不能用 receipt 或 relay 自举信任。
- `lib/vm-fast-lane-readiness.ps1` 明确区分 `CanStartVmBootstrap` 与
  `CanStartVmIntegration`。前者只授权离线 bundle/key/task staging；后者还要求 protected
  history、窄 HostCoordinator credential 和保持暂停的 host task。policy 与 onboarding
  manifest 同时冻结 host/VM 两端的初始状态为 `PAUSED`。
- `operator/fast-lane/build-vm-onboarding.ps1` 从 clean exact commit 构造 deterministic
  Store ZIP，并绑定 tree/blob/working bytes、工具 hash、repository identity、genesis、
  prompt 和 runbook。ZIP 为 diagnostic-only，不是产品候选或 Formal evidence。
- `lib/vm-reset.ps1` 是 pure/fake deterministic-reset 合同：冻结 owner receipt、
  精确 allow-list、baseline、升级原因和 `CLEAN_READY`。TestSafe/DryRun 只消费声明的
  fake provider，Scaffold Live 在 provider dispatch 前失败。
- `operator/fast-lane/invoke-vm-reset-live.ps1` 与 `providers/windows-vm-reset.ps1`
  冻结 VM-only dispatcher/provider 和 device-trust boundary；只有 disposable VM、精确
  trust/evidence、DevelopmentRetest 及单独 real-change acknowledgement 才可进入真实
  dispatch，且必须在 runtime 注册前独占复验并原子消费由外部 supervisor 签发、
  SYSTEM-owned、共同绑定本轮全部事实的 one-shot anchor/grant pair；每次 Live 都必须
  使用全新 pair。宿主机/CI/里程碑场景均 fail closed。
- `operator/fast-lane/*` 还保存固定的 host/VM prompt 与纯 synthetic 双 outbox 演练；
  prompt 不携带凭据，relay 自由文本只作为数据，不能成为 shell、PowerShell 或 Codex
  操作指令。
- 宿主机完成修复、本地门、提交/推送和候选重建；VM 没有产品仓库写权限，只能向
  VM-to-host repository 写结构化结果。宿主机不得执行 product Live，VM 不得编辑、
  提交或推送产品代码。
- P10A 消费精确 commit/calibration artifact；P11 消费精确 candidate bytes/hash，
  不跟随移动分支头。
- Fast Lane 由 VM 按精确 allow-list 做 deterministic reset：只卸载本项目产物、
  清除项目拥有的 HKCU policy/credential/checkpoint/owner-marked 目录并核验 baseline；
  不以 WORM、message signing 或每轮快照为前置，结果只用于诊断。
- Formal Lane 才为 P10A/P11 使用外部 clean snapshot 与独立 CAS/receipts/signatures。
  VMP/重启/卸载、未知补偿、baseline drift 或 reset 失败升级到 Formal Lane；VM
  不能恢复自身快照。
- relay 只传输状态、脱敏结果和证据引用，不替代 WORM/CAS、签名、snapshot receipt
  或 acceptance receipt；消息正文和日志永不作为 shell/PowerShell 指令执行。
- private product/control repositories 已创建并初始化；宿主实现达到 VM bootstrap
  ready，host heartbeat 已创建且暂停，VM task 可在 VM 上创建但必须先暂停。当前 GitHub
  套餐仍以 HTTP 403 拒绝 private ruleset；protected history、两个方向的最小角色凭据、
  VM 产品 remote 只读负向验证、real guest reset 证据、安全启用两端任务和 unattended
  执行仍是 integration 阻断项。VM bootstrap 不等于 P10A-0A 完成。

## 当前加载顺序

现有 bootstrap 顺序保持：

~~~text
bootstrap
  -> logger
  -> common
  -> state
  -> execution-context
  -> fake-providers
  -> state-store
  -> domain modules
  -> acceptance
~~~

bootstrap 顶层仍只定义函数和常量，不得探测系统、访问网络、写文件、提权或控制
进程。HostSandbox runner 属于独立 trusted-harness 执行平面，不进入产品
bootstrap 加载顺序。`config/fast-lane-policy.psd1`、`lib/vm-test-relay.ps1`、
`lib/vm-reset.ps1` 与 `operator/fast-lane/*` 只由 OperatorCoordination 的精确入口或
测试显式加载，也不进入 ProductCore 或 Release。

## 统一结果

领域操作统一返回：

- `Operation`
- `Status`
- `Success`
- `Changed`
- `Mode`
- `ErrorCode`
- `MessageSafe`
- `Data`
- `RestartRequired`
- `PlannedChanges`
- `Warnings`

TestSafe/DryRun 的潜在修改操作必须 `Changed=false`。结果、异常、ledger、状态和
报告不得包含凭据、原始配置、真实用户名或非必要绝对路径。

`Status` 是运行状态，只能取
`SUCCEEDED/PARTIAL/RESTART_REQUIRED/ACTION_REQUIRED/CANCELLED/FAILED`；
`Success=true` 只对应 `SUCCEEDED`。`Data` 分别携带每项能力的
`READY/BLOCKED/PENDING_RESTART/UNSUPPORTED/UNKNOWN` 和 UI 的
`PASS/FAIL/NOT_TESTED`，不得把三个层级压成一个布尔值。

## 固定完整功能流程

~~~text
preflight -> fixed target: Chat + Code + Cowork
  -> Git qualified? reuse : verified official install/upgrade
  -> Cowork-compatible MSIX scope
  -> admin / hardware virtualization / VMP readiness
       -> if needed: independent confirmation + checkpoint + manual restart + resume
  -> deploy -> all three surface flags enabled
  -> separate readiness and acceptance results
~~~

用户不选择 surface。Git 每次都检测并确保合格，但已有合格版本不会重复安装。
VMP 是固定 Cowork 目标的前置，只有 readiness 表明需要修改且用户独立确认后才进入。
任何前置失败都不能通过关闭 Code/Cowork 把总结果提升为 PASS。

## 配置架构

首版唯一 writer 是当前用户 HKCU managed policy。HKLM policy 和 configLibrary
只检测：HKLM 存在时阻断，因为它会覆盖 HKCU；local source 存在时报告冲突。
configLibrary 不支持首版所需的 MDM-only helper/chooser，不能作为安全回退。

编排器先做 source inventory 和 ownership 决策，再写入完整无凭据 HKCU payload。
内部 desired state 与 registry serializer 分离。

P2 已冻结纯合同：Desktop 最低版本 `1.20186.0`、Windows policy 不合并门槛
`1.19367.0`、15 个直接 `REG_SZ` value、V4 Pro/Flash 固定列表和八组 synthetic
source resolution。此阶段没有 registry provider 调用；写入、备份与恢复仍关闭。
DeepSeek 服务端 alias mapping 与 Desktop family-tier serializer 分开建模，未确认的
重复 model ID 语义不进入 payload。

Key 由 DPAPI-backed credential helper 提供，不进入 policy/configLibrary。
完整设计见 `CONFIGURATION_DESIGN.md`。

## 供应链

获取、验证和执行是分层合同。未来真实 adapter 必须在同一受控安装操作内重新
hash、重验并安装，避免“验证后换包”的调用间 TOCTOU；编排器只消费结构化证据：

- official source policy；
- artifact type 与架构；
- 绝对路径绑定 token；
- SHA-256；
- Authenticode 和可信链；
- Publisher/package identity；
- 适用版本。

安装前对同一文件重新计算 hash 并重验身份。没有 bypass 参数。

## Stage 与授权生命周期

~~~text
Scaffold
  -> Development
     -> P10A test exact commit/calibration artifact in disposable VM
        -> trusted CAS consume evidence and freeze facts
           -> P10B build/sign VmAcceptance + unpublished UserLive candidates
              -> P11 test exact candidate bytes in disposable VM
                 -> P12 publish the exact tested UserLive bytes
~~~

- stage/profile 不由环境变量或 `-Mode Live` 单独决定。
- embedded manifest v2 绑定版本、commit、profile、排除自身的 content digest，
  以及来自 sidecar 外部的 signer 证书/public-key 指纹、request ID、nonce 和最大
  签名年龄。
- detached sidecar v2 绑定最终 ZIP SHA-256、profile 和 content digest，并携带实际
  X509 DER 与 RSA-PSS-SHA256 签名字节；验证器对 canonical claims bytes 做真实
  公钥验签，不信任自报 `VALID` 字段。
- VmAcceptance grant 绑定 sidecar hash、runId、operation allow-list、expiry、nonce
  和交互确认。
- 同用户进程无法可靠证明自己处于 VM；grant 只防误触，真正隔离依赖 VM 操作流程。
- P12 不重建 ZIP，只发布 P11 已测试的 UserLive 原字节。
- P11 exact acceptance receipt 与 promotion CAS 未实现前，P12 promotion 构造始终
  fail closed。
- P11 失败后宿主机修复、过门、提交/推送，再回到 P10B 重建和签名新候选；VM 不
  拉源码直接重测。relay PASS 不自动 merge，也不自动进入 P12。

## 状态与重启

未来状态根位于项目专属 LocalAppData，但本地测试使用 synthetic path。状态包含：

- schema/contract version；
- runId、phase、completed steps；
- pending action；
- restart reason、resume phase、expiry；
- artifact/config backup metadata；
- safe error。

状态不保存 Key、Authorization、原始配置、可逆密钥或 helper stdout。写入采用
owner-checked sibling temp、flush、重读和原子替换。

VMP 首版使用 `-NoRestart` 和人工重启后重新双击续跑，不创建计划任务或 RunOnce。

## 配置备份

- 首版一个运行只拥有 HKCU policy。
- 非本项目配置默认冲突停止。
- 可恢复备份与脱敏快照是两个合同。
- 可恢复敏感材料使用 DPAPI/ACL；脱敏快照不能恢复。
- HKCU registry 采用精确 value/type 补偿；首版没有 configLibrary writer。
- 失败后必须重读证明恢复，而不是只报告“已回滚”。

## Claude Code settings

项目正式选择零读取政策：不定位、不 Test-Path、不哈希、不监视、不备份、不修改
`%USERPROFILE%\.claude\settings.json`。

宿主机完整性证明来自 provider 无访问、AST 门和 sandbox ledger；后续 disposable
VM 可以在 VM 自身范围建立基线，但不授权宿主机读取。

## 架构不变量

- 默认 bootstrap 无副作用。
- 领域模块不直接访问真实系统。
- 缺 Context/provider fail closed。
- 本机/CI 不加载 live adapter。
- trusted test harness 与产品 provider 使用独立 allow-list/ledger。
- 验签先于安装。
- 凭据先保护后持久化配置。
- 备份先于配置写入。
- checkpoint 先于 VMP 变更。
- 子能力分别验收。
- VM Live 先于正式发布。
- 正式发布字节必须与 VM 测试字节相同。
- 宿主机 Codex 是唯一代码写入者；VM Codex 只测试、分析和回传。
- OperatorCoordination 本地合同不得隐式获得 Git transport、真实系统 adapter、
  product Live 或无人值守执行权限；prompt 和自由文本不得携带凭据或被直接执行。
- clean-start tier 必须与风险匹配；正式 P11 PASS 必须由外部 hypervisor 的 clean
  snapshot receipt 证明，日常 guest reset 不可替代。
- relay/control-plane 状态不得替代 CAS、签名或 acceptance receipt。
