# Claude Desktop 第三方配置设计

更新日期：2026-07-24

## 目标

在 Claude Desktop 首次启动前部署 DeepSeek Third-Party 配置，使用户无需登录
Anthropic、无需进入 Developer Mode，同时保证既有配置可检测、可恢复、凭据不
明文落入 Claude 配置或项目状态。

本文件描述目标设计，不表示当前 Scaffold 已实现。

## 配置面

Claude Desktop 当前有三个 Windows 配置来源：

1. `HKLM\SOFTWARE\Policies\Claude`：机器级 managed configuration。
2. `HKCU\SOFTWARE\Policies\Claude`：用户级 managed configuration。
3. `%LOCALAPPDATA%\Claude-3p\configLibrary`：本地配置库。

这些来源不能按项目期望做字段级合并。首版只写 HKCU managed policy；HKLM 与
local source 仍必须检测，因为它们会影响实际生效结果。

## 暂定部署策略

- 首版固定写当前用户的 HKCU managed policy，符合单用户和 DPAPI CurrentUser
  所有权。
- HKLM 只检测不写。发现 HKLM policy 时停止，因为它会完全覆盖 HKCU。
- configLibrary 只检测、研究脱敏导出和验证兼容性，不作为首版写入目标。
- 发现现有 HKLM 配置时，低优先级写入必须停止并报告冲突。
- 发现现有 HKCU 或 configLibrary 配置时，默认不覆盖；用户必须看到来源、所有权
  和回滚影响后单独确认。
- 一个运行只拥有 HKCU 目标，不同时写 HKLM 或 configLibrary。

未来组织/多用户版本若增加 HKLM，必须另建 machine-wide helper、每用户 DPAPI
blob、无凭据用户行为、ACL、更新和卸载合同；不能扩展首版 writer。

## 内部 Desired State 与外部 Payload

项目内部应维护稳定、无凭据的 desired state，例如：

~~~text
SchemaVersion
ContractVersion
ProviderKind
Endpoint
AuthScheme
ModelPolicy
Surfaces
DeploymentChooserPolicy
CredentialReference
Ownership
~~~

它不是 Claude payload。首版每个 Desktop 合同版本只通过独立 serializer 转换为
Windows policy value set。local JSON serializer 仅属于未来研究：只有官方提供与
credential helper 等价的安全 local 合同并通过新决策后才可加入。

内部字段不得混入外部 payload。未知字段、未知 schema 或未识别 Desktop 版本
必须 fail closed。

## P2 冻结的外部配置

目标方向来自 `EXTERNAL_CONTRACTS.md`：

| 目的 | 暂定值 |
|---|---|
| Provider | `inferenceProvider=gateway` |
| Credential kind | `inferenceCredentialKind=helper-script` |
| Base URL | 从 `EXTERNAL_CONTRACTS.md` 的版本化 endpoint fixture 注入 |
| Auth | `inferenceGatewayAuthScheme=x-api-key` |
| Discovery | `modelDiscoveryEnabled=false` |
| Models | 两个带 label 和 `supports1m=true` 的版本化 `inferenceModels` 条目 |
| Chat | `chatTabEnabled=true` |
| Code | `isClaudeCodeForDesktopEnabled=true` |
| Cowork | `coworkTabEnabled=true` |
| Auto mode | `autoModeEnabled=false` |
| Mode chooser | HKCU MDM 中启用 `disableDeploymentModeChooser`，VM 实物验证 |
| Credential | `inferenceCredentialHelper` 绝对路径、TTL、timeout，不含 Key |

三个 surface 值是固定产品不变量，不接受用户选择或 readiness 覆盖。Readiness 只
决定依赖准备和验收结果；即使前置失败，也不得在 serializer 中把 Code/Cowork 改
为 `false` 后宣称成功。

Registry serializer 的首版 canonical 形式为 policy key 下的直接 `REG_SZ` value；
数组/对象使用无歧义的 compact JSON 字符串。虽然官方允许布尔/整数用
`REG_DWORD`，本项目不在同一合同内混用表示。禁止 `REG_EXPAND_SZ`、`REG_QWORD`、
`REG_MULTI_SZ` 和 `REG_BINARY`；精确字符串和值集合由版本化 fixture 固定。

## 模型策略

模型配置不能只列未记录来源的字符串。P2 维护带版本和验证日期的两类事实：

- Opus tier → DeepSeek V4 Pro。
- Sonnet/Haiku tier → DeepSeek V4 Flash。
- UI label 与真实请求模型必须同时验证。
- 不支持的 alias 不允许静默落到默认模型后仍报告成功。

前两项是 DeepSeek Anthropic-compatible 服务端映射，不等同于 Desktop
`anthropicFamilyTier` serializer。该字段一次只能表示一个 tier，而官方没有确认
重复 model ID 的语义，因此 P2 serializer 明确省略 `anthropicFamilyTier` 和
`isFamilyDefault`，不编造 Sonnet/Haiku 双绑定。VM 必须验证服务端映射、UI 和实际
request model；若固定版本实物提供可验证的重复条目语义，再通过新 fixture 更新。

fixture 至少覆盖：

- Chat 的默认模型和显式选择。
- Code 继承 provider、credential 和 model list。
- Pro/Flash UI label 与 API 请求的对应关系。
- DeepSeek 更新模型后的兼容失败。
- model discovery endpoint 缺失或返回错误。

## Credential Helper

### 设计原则

- Key 只在本地安全输入。
- 使用 DPAPI CurrentUser 加密。
- helper 和密文放入当前用户项目专属 LocalAppData 稳定目录，不放临时目录、仓库
  或系统级共享路径；最终目录与解析后路径由版本化安装策略绑定。
- 目录和文件 ACL 仅当前用户和经评审的必要系统主体。
- Claude 配置只包含 helper 的绝对路径和无敏感元数据。
- helper 不接收明文命令行参数，不通过 shell 拼接。
- helper 不读 stdin、不提示；成功时只向 stdout 输出单行 token 或 exact JSON，
  stderr 必须为空。
- 精确消费 `CLAUDE_HELPER_CONTEXT`；`mid-session-refresh` 有效超时 20 秒，其他
  已知 context 为 60 秒，所有非交互 context 均不得等待用户操作。
- 调用方不得记录 helper stdout。
- 支持新增、轮换、撤销、损坏、错误用户、超时和清理。

### D-010 冻结合同

首版采用签名、固定工具链的最小 .NET EXE，不采用 PowerShell helper。源码、依赖
锁、工具链、SBOM、PE、Authenticode、ACL、DPAPI 和调用 receipt 必须全部可验证；
外部材料未齐时保持 fail closed。

DPAPI blob 不是可分享备份，不能跨用户或跨 VM 恢复。

## 所有权和备份

写入前必须捕获“来源、值、类型、ACL 摘要、版本、hash/绑定 token”等恢复所需
信息，并区分：

- **可恢复备份**：可能包含敏感材料，必须 DPAPI/ACL 保护，只用于恢复。
- **脱敏快照**：只用于报告和支持，不含可恢复凭据。

状态文件只记录备份 ID、hash、目标来源和阶段，不记录原始值或 API Key。

发现不是本项目创建的配置时：

1. 默认停止。
2. 生成不含值内容的冲突摘要。
3. 只有用户明确选择替换，才创建恢复备份。
4. 写后重读并验证生效来源。
5. 任一步失败都恢复到原状态。

## 原子性

### Registry

registry 事务应通过 provider 模拟并定义补偿协议：

1. 读取精确目标值集合和类型。
2. 创建受保护恢复记录。
3. 写入全部目标值。
4. 重读并与 expected value set 精确比较。
5. 失败时按原类型和值恢复，删除本次新增值。
6. 再次重读，确认恢复。

不能把“部分值写成功”当成可用配置。

### configLibrary

configLibrary 首版没有 writer。若未来官方提供与 helper 等价的安全 local
credential 方案并单独批准 writer，才允许实现，且必须满足：

- 目标路径精确绑定到注入的 synthetic/live LocalAppData。
- sibling temp、flush、重读 schema、原子 Replace/Move、写后 hash。
- 拒绝重解析点、路径逃逸和不属于本运行的临时文件。
- `_meta.json` 与配置文件更新顺序必须来自固定版本 fixture。

## 生效与生命周期

配置在 Desktop 启动时读取。真实写入前必须：

- 确认 Desktop 进程状态。
- 获取独立的进程控制许可。
- 完成备份。
- 写入并重读验证。
- 只在用户确认后关闭或重启 Desktop。

本地 Unit/Contract 不启动或停止真实 Claude 进程；所有生命周期行为由 fake
provider 记录。

## 测试矩阵

- HKLM、HKCU、local source 的单独和冲突组合。
- 目标来源无权限、部分写入、重读不一致和恢复失败。
- registry value 类型错误、JSON 序列化错误和 schema 漂移。
- helper 成功、超时、非零退出、多行输出、非法字符和 stderr 泄露。
- DPAPI protect/unprotect 失败、错误用户和损坏 blob。
- 模型 tier、label、默认项和静默降级。
- Desktop 启动前/后部署差异。
- Key 在日志、状态、报告、备份、临时文件和 Release 中的全量扫描。

全部本地测试必须遵守 `TEST_ISOLATION.md`，使用虚拟 registry、fake helper、
fake DPAPI 和 fake lifecycle。D-026 先在 `VmDevelopment` disposable VM 实现完整
配置、DPAPI、lifecycle、API，并从不可 promotion 的 development ZIP 真实测试；该结果
只产生 `READY_FOR_FORMAL_P10A`。随后 P10A 按 `VM_CALIBRATION_PLAN.md` 冻结
helper/chooser/HKCU 事实，P10B 构建双候选，P11 再按 `VM_ACCEPTANCE_PLAN.md` 对精确
候选字节执行首次正式验收；开发 evidence 不得晋升为 P11 receipt。

## P2 实现状态

已完成：

1. 内部 desired state 与 Windows managed-policy value set 分离。
2. 固定 15 个 `REG_SZ`、V4 Pro/Flash、三项 surface、helper 默认和最低版本。
3. 建立带官方 URL、核验日期、适用版本和 8 组来源组合的 fixture。
4. configLibrary 只保留 synthetic detection；writer、backup、snapshot、restore
   全部指向逻辑 HKCU policy token 且 `Changed=false`。
5. 未确认的 family-tier 重复绑定明确省略并转入 VM 验收。

D-010 helper 技术形态已经冻结，但实际 helper binary、provider、DPAPI、签名、
备份、补偿和 Live grant 仍未完成；在这些外部门满足前，
`Write-CddsiClaudeDesktopConfigAtomic` 始终 plan-only、Live fail closed。
