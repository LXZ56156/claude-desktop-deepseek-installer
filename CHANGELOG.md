# 变更日志

本项目遵循语义化版本。当前处于 0.x 开发阶段，用户 Live 尚不可用。

## Unreleased

- 完成 Claude Desktop 官方 Third-Party、DeepSeek、Windows 部署与中文能力调研。
- 定义一次双击发起的最终用户流程、能力边界和不可避免交互。
- 建立完整文档索引、产品规格、外部合同、配置设计和决策记录。
- 建立宿主机零接触测试合同，并将 Sandbox Foundation 设为所有功能开发的阻断
  前置。
- 建立 P0-P12 实施计划、双候选不可变发布计划和后续 VM Codex Live 验收计划。
- 为报告脱敏测试增加显式 synthetic path-token 注入，移除真实用户名/UserProfile
  fixture 依赖。
- 完成 P1 ExecutionContext、十类 default-deny fake provider、AccessLedger、
  mutation spy、state-store provider 边界和 Live fail-closed 合同。
- 完成 owner-marked HostSandbox、固定工具 hash 授权、双 PowerShell worker、
  isolation evidence v2、精确 trusted-harness ledger 和仓库全树不变性验证。
- 强化 Release DryRun：对 source、staging、ZIP、extracted 四层执行二进制流式
  secret scan、精确白名单、内容 hash、Windows 路径别名和安全失败证据验证。
- 完成 P2 正式 3P managed-policy 纯合同：固定 Desktop 版本门、DeepSeek V4
  endpoint/model、15 个 `REG_SZ` value、官方 fixture 和 8 组 synthetic 来源解析；
  configLibrary writer 与所有真实配置 I/O 继续关闭。
- 取消 Chat/Code/Cowork 功能选择页，固定三项完整目标；Git 改为产品必备前置，
  合格版本复用，缺失或不合格时才安装/升级。
- 增加单一 MSIX scope 冻结和运行/能力/UI 证据分层状态合同，禁止静默退化为
  Chat-only 成功。
- 完成 P3-P7 环境、供应链、credential、配置恢复和重启续跑纯合同，以及 P8 fake
  编排器、P9 synthetic 三 surface 验收和 P10A calibration evidence 合同。
- 冻结 D-010：credential helper 使用签名、固定工具链的 .NET EXE；补充
  `CLAUDE_HELPER_CONTEXT`、20/60 秒有效超时、路径 alias 与无提示合同。
- 增加 P10B frozen facts、helper release、embedded manifest、detached sidecar、
  deterministic ZIP 和双候选 HostSandbox assembler；raw CAS proposal、伪造签名和
  缺少 P11 receipt 的 promotion 均必须 fail closed。
- 增加随包 `USER_GUIDE.md`、`TROUBLESHOOTING.md` 和 `PRIVACY.md`，明确当前仅为
  Scaffold、未来正式包流程与隐私边界。
- 冻结 P10A-0A 双机 VM 测试中继方案：宿主机 Codex 独占代码写入，VM Codex
  只测试、分析和回传；Fast Lane 的一个逻辑双 outbox 由两个物理单向私有 control
  repos 承载，两端定时轮询并在 guest 内执行确定性 reset；Formal Lane 再为
  P10A/P11 接入 CAS、签名和外部快照，且 P11 只验收精确不可变候选。
- 完成 P10A-0A 本地 TestSafe/DryRun 合同切片：增加 `DirectionalRepositoryPair`、
  relay/state/hash、fake reset/`CLEAN_READY`、两端轮询 prompts、synthetic rehearsal，
  并把 operator coordination plane 隔离为 `DevelopmentOnlyFiles`。
- 创建私有产品 remote 与两个物理单向 control repos，推送旧 `main` 基线并初始化两个
  `outbox/`；创建暂停的宿主机分钟级 heartbeat。当前 GitHub 套餐拒绝 private ruleset，
  角色最小权限凭据、VM 产品 remote 负向写验证、真实 VM reset adapter、VM task 与
  无人值守闭环仍未部署，不能宣称 P10A-0A 完成。
- 产品工作流仍保持 Scaffold；未执行任何宿主机 Live、真实系统探测或 VM 验收。

## 0.1.0-dev - 2026-07-12

- 建立 Claude Desktop + DeepSeek 独立安装器的模块边界与安全合同。
- 建立 Pester、静态检查、Release 精确白名单和 CI 基线。
- 所有系统修改、网络请求、配置写入与进程控制均保持未实现并默认阻断。
