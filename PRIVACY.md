# 隐私与数据边界

> 当前状态：本仓库尚未提供可用 Live 安装器或真实候选包，现有入口不会读取真实
> 用户配置、保存 API Key、访问网络或修改系统。本文件是未来候选通过 P11 虚拟机
> 验收后，正式发布包必须满足的数据处理合同，不是对当前未实现能力的完成声明。

## 最小化原则

正式发布包只能为安装、readiness、修复、恢复和验收处理必要数据，并以
default-deny、显式许可、最短明文生命周期和逐资源所有权为原则。未测试或无法
证明的数据访问必须被拒绝，不能为了“诊断方便”扩大收集范围。

## Claude Code 配置零读取

本项目不得定位、`Test-Path`、枚举、读取、解析、哈希、监视、备份、写入或删除：

`%USERPROFILE%\.claude\settings.json`

安装、诊断、修复、恢复、日志和支持报告都不得以该文件内容或前后 hash 为证据。
用户也不需要编辑该文件来使用 DeepSeek 配置。未来 disposable VM 中的专用测试
基线不能反向授权安装器访问真实用户的同类文件。

## DeepSeek API Key

- Key 只允许通过本地安全交互输入；不接受明文命令行参数、环境变量、配置文件
  导入或标准输入重定向。
- 明文只可短暂存在于安全输入、DPAPI adapter 和 credential helper 输出边界。
- 持久化凭据必须使用 DPAPI CurrentUser 与受限 ACL；该 blob 绑定当前 Windows
  用户/环境，不能作为可分享或跨用户、跨机器、跨 VM 的备份。
- Claude managed configuration 只引用已验证 helper 的绝对路径，不保存明文 Key。
- helper 不接收明文参数，不经 shell；其 stdout 不得进入日志、状态、报告、截图
  或剪贴板。
- 怀疑泄露时，用户必须先在 DeepSeek 侧撤销或轮换 Key；删除本地 blob不能撤销
  已暴露的上游凭据。

## 本地可能处理的数据

经独立许可后，正式发布包可能处理以下脱敏或结构化事实：

- Windows 版本、架构和受支持能力；
- Claude Desktop、MSIX scope、Git for Windows、VMP、硬件虚拟化及相关 readiness；
- managed configuration 的逻辑来源、键名/类型、所有权和冲突状态，而非支持报告
  中的原始值；
- 下载 artifact 的来源、版本、路径绑定 token、SHA-256、签名、Publisher 和
  package identity；
- 运行状态、稳定错误码、checkpoint 标识、备份 ID/hash、补偿状态和测试证据
  token。

状态文件不得保存 Key、Authorization、helper stdout、原始配置正文、可逆密钥
材料或原始 API 响应敏感正文。

## 日志、报告、备份与快照

- 日志、异常、ledger、状态、报告和截图必须先完整脱敏，不保留 Key 的前缀或
  后缀，也不记录真实用户名、完整用户路径、代理口令或原始配置。
- 可分享的脱敏快照只用于支持，永远不能作为恢复源。
- 可恢复备份可能包含敏感配置，必须由 DPAPI/ACL 保护，并与 owner、target、版本
  和绑定 token 一起验证；不得上传到支持工单。
- 清理或恢复失败必须明确报告，不能以删除日志或隐藏错误冒充数据已清除。

## 网络与上游服务

正式安装流程只应在用户可见的计划和许可下连接该版本列明的上游：

- Anthropic 官方元数据/下载来源，用于获取并验证 Claude Desktop；
- Git for Windows 官方来源，用于必要的 Git 安装或升级；
- DeepSeek API，用于明确的凭据验证以及安装后由 Claude Desktop 发起的模型请求。

安装器不得把诊断报告、凭据或原始配置自动上传给项目维护者。Claude Desktop、
DeepSeek 及下载服务对其收到数据的处理和保留受各自条款约束，不由本安装器控制；
用户应在使用前查阅对应上游政策。

## 保留与删除边界

- 独占临时下载和 staging 只为当前运行存在，流程完成后应按所有权 token 清理；
  清理失败必须出现在脱敏报告中。
- checkpoint 只保留到安全续跑、过期或显式清理，不得包含凭据。
- 项目 credential blob 只保留到用户撤销、轮换、恢复或卸载该项目拥有的凭据；
  删除本地 blob 不会删除 DeepSeek 账户侧记录。
- 可恢复备份只保留到该版本声明的恢复/清理边界；删除前必须确认不再承担恢复
  义务。脱敏支持报告可由用户自行删除。
- 项目只能删除有明确所有权和绑定 token 的状态、临时资源、policy 与 credential。
  不得为清理本项目而删除组织策略、他人配置或共享系统资源。
- Desktop/Git、VMP、PATH 等共享资源不一定能自动恢复或删除；结果必须逐项报告
  `FULL`、`PARTIAL`、`UNSUPPORTED` 或 `FAILED`，不承诺整机事务式回滚。

需要支持时，只分享 `一键诊断.cmd` 生成的脱敏报告，并遵循
`TROUBLESHOOTING.md` 的安全提交清单。
