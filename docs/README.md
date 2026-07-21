# 文档索引

更新日期：2026-07-21

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
11. `docs/REALTIME_RELAY_PROPOSAL.md`：Cloudflare realtime accelerator 的本地离线实现合同；
    描述架构、协议、授权点和回滚，不表示资源已经 provision 或启用。
12. `docs/RELEASE_PLAN.md`、`docs/VM_CALIBRATION_PLAN.md`、
    `docs/VM_ACCEPTANCE_PLAN.md`：发布候选、窄范围虚拟机校准与后续全面验收。

`docs/BOOTSTRAP_REPORT.md` 是 2026-07-12 初始脚手架的历史快照，不是当前状态
来源。

截至 2026-07-22，当前唯一动态状态入口是 `docs/HANDOFF.md` 顶部的“当前动态状态”。
项目的旧 VM bootstrap/产品 integration 继续受控暂停：不得继续交付或执行任何
既有 onboarding ZIP/prompt，不启动旧 bootstrap、产品测试循环或 Formal Lane。这不禁止
按 D-022 进入已准备好的 VM 执行一次性 relay-only 通信 smoke。暂停前 finalization 及其 bundle、
automation prompt 和 readiness receipt 只绑定暂停前的精确 commit；本次 tracked 文档修改
立即使这些绑定失效。当前四个 readiness/complete 标志全部为 false。独立 Cloudflare
realtime relay 工作流已完成本地离线实现与质量门，而不是继续旧 VM bootstrap。

`REALTIME_RELAY_PROPOSAL.md` 的事实级别为
`LOCAL_GATES_PASSED / EXTERNAL_AUTHORIZED_FREE_ONLY / AUTHENTICATED_READ_ONLY /
BILLING_DASHBOARD_REVIEWED / WORKERS_PAID_NOT_LISTED / VM_RELAY_READY / PROVISIONED /
CROSS_DEVICE_SMOKE_PASSED / NOT_PRIMARY / AUTOMATION_PAUSED`。外部步骤 1–7 已获 Free-only
授权，且用户已明确允许直接复用既有 encrypted keyring `default` OAuth profile；generation-1
adoption receipt 与 Cloudflare 四 GET preflight 已完成，确认单账号、既有 workers.dev subdomain、
目标 Worker 不存在，并报告 `WorkersUsageModel=STANDARD / BillingPlanVerified=false`。任何 usage
model 都不是 subscription receipt。经用户授权复用个人 Edge 既有登录态的只读 Dashboard 核对已
确认 Billing → Subscriptions 未列出 Workers/Workers Paid；active 的 Teams Free Base 与无关 R2
Paid 不把整个账号变成 Free，也不授权 relay 使用 R2。D-022 接受该人工观察作为
当前 Free-only 部署依据；machine receipt/ticket、coordinated DPAPI 与 staging receipt
只是 optional hardening，不再阻断 resource/secret write 和一次性 relay-only smoke。
用户回传的 `VM_RELAY_READINESS_V1` 为 `Ready=true`，VM 上的 PowerShell 7、Git、
`ClientWebSocket`、时钟、出站网络和本地 relay 工作目录已就绪。Free-only Worker、SQLite-backed
Durable Object、两项 secret binding、精确 postdeploy readback、Host HTTP smoke 和跨设备双向
relay-only smoke 已完成。生产 WebSocket reconnect/Hibernation 尚未真实 E2E，因此 relay 不是主路径。
该部署也不能启用持久 watcher、改变 automation
状态或绕过现有 Git control repository、Formal Lane 与 P12 人工门。
本文及其他稳定设计文档中的“已实现”摘要若与 `HANDOFF.md` 顶部或实际机器证据冲突，
以后两者为准。

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
| `docs/REALTIME_RELAY_PROPOSAL.md` | realtime Fast Lane accelerator 的提案、威胁模型、实施/授权/回滚边界 | relay 架构评审、实现状态或授权状态变化时 |
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

P2-P10B 的纯/fake 合同与宿主机支撑已经建立；P10A-0A 的 public protected repositories、
固定 Git outbox、readiness、onboarding、reset 和 automation 合同也已建立。暂停前的
phase2-only builder/loader、execution boundary、HostSandbox path binding、semantic ACL、
captured-byte load、atomic/idempotent state、no-reparse 非递归 cleanup 与完整正负测试已经
通过其绑定提交的机器门，但这不构成暂停后的执行许可。HostCoordinator automation 必须保持
暂停；VM automation 的实际存在/状态没有来自最新 bundle 的可靠 receipt，因而不得推断，
也不得进入 VM 核验或启用旧 automation。D-022 的一次性 relay-only smoke
是与该历史 automation 分离的人工 operator 动作。

`docs/HANDOFF.md` 只保存当前逻辑状态、下一工作包与停止线，不在 tracked 文档中复制
最终 commit/tree、bundle digest、测试 RunId 等 post-commit 精确锚点，避免文档提交改变
自身锚点。包含文档闭环的新 clean HEAD 的精确证据必须由 retained owner-marked bundle
output 的 manifest/inventory/marker、同一暂停 HostCoordinator automation、PR CI 和实际
Git/remote 四方持久事实交叉核验。controlled pause 期间即使四方一致，readiness 也始终为
false；只有未来另有显式恢复决定、完整 finalization 和新 readiness receipt 后，才可重新
考虑 bootstrap-only readiness。下一任务不需要依赖聊天记录。

三个 repositories 的 public 与 protected-history 合同已经建立；公开前审计的剩余存量风险
已按既定决策接受，但 credential、Authorization 数据和未脱敏 secret 仍绝对禁止进入公开
仓库。窄权限角色凭据、runtime protection assertion、VM 负向权限、真实双向交换、reset
与 unattended evidence 尚未完成，因此 VM integration 继续阻断；Formal Lane 仍要求外部
clean snapshot receipt、独立 CAS 与签名。受控暂停期间不交付“一份 ZIP、一次提示”目标
流程，也不把拟议 realtime relay 当作绕过这些门的替代路径。整个过程不增加宿主机产品 Live，
VM 也不得修改产品代码。

其他文档可以保留便于理解的稳定摘要；动态结论由 `docs/HANDOFF.md` 的条件式与 retained
owner-marked bundle output、同一暂停 automation、PR CI、实际 Git/remote 四方持久事实
共同派生；任一事实冲突即 fail closed。

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
