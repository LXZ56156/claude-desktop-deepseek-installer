# 文档索引

更新日期：2026-07-17

本目录是项目设计、实施和交接的长期事实入口。文档按“稳定规则”和“易变状态”
分工，避免下一任务依赖聊天记录，也避免同一事实散落在多个文件后发生漂移。

## 阅读顺序

新开发任务按以下顺序阅读：

1. `AGENTS.md`：仓库内不可突破的开发、安全、测试和 Release 规则。
2. `docs/HANDOFF.md`：当前代码状态、已完成事项和下一工作包。
3. `docs/PRODUCT_SPEC.md`：产品承诺、最终用户流程和非目标。
4. `docs/EXTERNAL_CONTRACTS.md`：Anthropic、DeepSeek、Windows 和 Git 的外部事实。
5. `docs/DECISIONS.md`：已经冻结或仍待决策的产品与技术选择。
6. `docs/LEGACY_REUSE.md`：旧 Claude Code 安装项目中可复用与禁止迁移的内容。
7. `docs/ARCHITECTURE.md`、`docs/CONFIGURATION_DESIGN.md`：代码边界和配置方案。
8. `docs/TEST_ISOLATION.md`、`docs/SECURITY.md`、`docs/TESTING.md`：宿主机零接触、
   安全威胁和质量门。
9. `docs/IMPLEMENTATION_PLAN.md`：从已完成 P1 的当前基线到 VM-ready 的阶段门。
10. `docs/VM_TEST_RELAY.md`：宿主机修复端、VM 只读测试端，以及 Fast Lane 日常
    自动修复与 Formal Lane 正式证据回传的 operator coordination 权威协议。
11. `docs/RELEASE_PLAN.md`、`docs/VM_CALIBRATION_PLAN.md`、
    `docs/VM_ACCEPTANCE_PLAN.md`：发布候选、窄范围虚拟机校准与后续全面验收。

`docs/BOOTSTRAP_REPORT.md` 是 2026-07-12 初始脚手架的历史快照，不是当前状态
来源。

未来正式包还携带根目录的 `USER_GUIDE.md`、`TROUBLESHOOTING.md` 与
`PRIVACY.md`。三者是最终用户合同，不替代本目录的开发事实，也不表示当前
Scaffold 已可执行 Live。

## 文档职责

| 文件 | 唯一职责 | 何时更新 |
|---|---|---|
| `docs/README.md` | 文档地图、职责和维护规则 | 文件增删或职责变化时 |
| `docs/HANDOFF.md` | 当前状态、下一工作包、停止线 | 每个工作包完成后 |
| `docs/PRODUCT_SPEC.md` | 用户价值、流程、范围、完成定义 | 产品边界变化时 |
| `docs/EXTERNAL_CONTRACTS.md` | 外部官方事实和核验日期 | 上游版本或合同变化时 |
| `docs/DECISIONS.md` | 决策及其理由、状态、替代项 | 作出或撤销决策时 |
| `docs/LEGACY_REUSE.md` | 旧项目复用清单和禁止项 | 迁移旧项目思路时 |
| `docs/ARCHITECTURE.md` | 模块、依赖、执行上下文、数据流 | 模块边界变化时 |
| `docs/CONFIGURATION_DESIGN.md` | Claude 3P、模型、凭据和回滚 | 配置合同变化时 |
| `docs/TEST_ISOLATION.md` | 宿主机零接触权威合同 | 测试能力或保护区变化时 |
| `docs/SECURITY.md` | 威胁、许可门、供应链、凭据 | 安全边界变化时 |
| `docs/TESTING.md` | 测试层级、命令、证据和质量门 | 测试流程变化时 |
| `docs/IMPLEMENTATION_PLAN.md` | 阶段、依赖、交付物和退出条件 | 阶段状态变化时 |
| `docs/RELEASE_PLAN.md` | 构建、签名、分发和发布门 | 发布流程变化时 |
| `docs/VM_TEST_RELAY.md` | 双机角色、消息状态机、证据回传和重测协调 | 协调协议或自动化边界变化时 |
| `docs/VM_CALIBRATION_PLAN.md` | P10A 窄范围 VM 校准、证据和回传门 | 校准事实或 schema 变化时 |
| `docs/VM_ACCEPTANCE_PLAN.md` | 后续真实 Live 验收 | VM 矩阵或 runbook 变化时 |
| `docs/BOOTSTRAP_REPORT.md` | 初始脚手架历史证据 | 原则上不改历史数据 |

## 机器可读事实来源

- 公开函数和参数合同：`config/public-functions.psd1`。
- 执行文件归属、产品/测试平面和 AST allow-list：
  `config/execution-boundaries.psd1`。
- 固定 Pester 来源、整树 hash 和 isolation suite 计数：
  `config/dev-dependencies.psd1`。
- Fast Lane 的预期 PUBLIC 双仓身份、角色、服务端保护要求和初始 `PAUSED` 状态：
  `config/fast-lane-policy.psd1`；真实远端部署 receipt 只记录在当前 `docs/HANDOFF.md`。
- Release 文件分类：`scripts/release-manifest.psd1`。
- 当前安全默认值：`config/deepseek-desktop.defaults.json`。
- 实际 Git 状态：只通过标准 HostSandbox 质量门中的隔离 Git inventory 核验，
  不得只相信交接中的旧哈希，也不得在外部直跑继承用户配置的 Git。

P2-P10A 已把配置、环境、供应链、credential、恢复、重启、fake 编排、synthetic
验收与 VM calibration evidence 建成纯/fake 合同；P10B 宿主机支撑合同也已通过
统一门。P10A-0A 的宿主机侧 Fast Lane 实现现已包括 public protected 产品 remote、
两个物理单向 public protected control repositories、固定 Git outbox runtime、readiness resolver、确定性 VM
onboarding builder、VM-only reset 边界以及两端分钟级 prompt/runbook。宿主机 task 已
创建且暂停；VM task 必须从 VM 设备创建并同样先保持暂停。当前精确收尾状态只以
`docs/HANDOFF.md` 为准。

2026-07-16 曾对 commit `3e843912df2543c1da05b09061970faff511d016` 完成宿主机
finalization：双引擎全树门各 427/427、Release DryRun、18-entry immutable onboarding
bundle、暂停 heartbeat 的最终 hash binding 和 PR CI 均通过。随后发现易变状态文档仍停在
finalization 前；本次文档一致性修复使最终 HEAD/tree 与旧锚点不同，因此上述 bundle 只保留为
历史锚点，不能作为新 HEAD 的 VM 输入。新 HEAD 重新通过统一门、提交/推送、bundle
校验、暂停任务重绑和 CI 前，`CanStartVmBootstrap=false`。

三个 GitHub repositories 已全部切换为 public；版本化合同明确要求 `PUBLIC`，三个
protected-history ruleset 已无 bypass 地对目标 refs 实际施加禁止删除、禁止非快进和
线性历史。窄权限角色凭据、runtime protection assertion 与 VM 负向权限证据尚未发放，
因此 **VM integration 仍阻断**。首次 P10A 还必须经过外部 clean snapshot receipt、独立 CAS
与签名的 Formal Lane。整个过程不增加宿主机产品 Live，VM 也不得修改产品代码。

2026-07-16 公开前预检对产品仓库当时已获取 repair ref（含已获取 main 历史）可达对象的常见凭据
模式扫描为零。用户已明确接受提交元数据、历史运营信息和未来 public outbox 全网可读，
不重写历史；剩余存量审计标记为 accepted risk，不再阻断 cutover。credential、Authorization
数据和未脱敏 secret 仍绝对禁止进入 public repositories。

`docs/HANDOFF.md` 是易变状态的唯一权威来源。其他文档可以保留便于理解的状态
摘要，但必须链接到交接，且摘要与交接冲突时以交接和实际 Git 状态为准。

## 事实状态标记

文档使用以下状态，禁止把“计划”写成“已经实现”：

- **官方确认**：当前官方文档直接支持。
- **实物待验**：官方方向明确，但具体包、版本、签名或运行行为仍需固定版本验证。
- **本机历史实测**：以前的单机结果，只能作旁证，不能替代当前版本回归。
- **已实现**：代码和自动化测试已经存在并通过。
- **计划**：尚未实现。
- **阻断**：未满足前不得进入下一阶段。

## 维护规则

- 易变的 URL、模型、版本和签名身份只在 `EXTERNAL_CONTRACTS.md` 维护，其他文档
  只引用，不复制完整表格。
- 当前状态只在 `HANDOFF.md` 维护；历史报告不反复改写。
- 宿主机测试保护规则只在 `TEST_ISOLATION.md` 定义，其他文档只引用并增加更严
  的局部约束。
- 新增、删除或重命名文档时，必须同步 `scripts/release-manifest.psd1` 和文档
  完整性静态检查。
