# 故障排查

> 当前状态：本仓库仍是 Scaffold，没有可用 Live 安装器或真实安装候选。当前入口
> 返回 `scaffold_only` 是预期行为。本文件仅规定未来候选通过 P11 虚拟机验收后，
> 正式发布包应采用的排查方式。

## 先做什么

1. 记录整体状态、稳定错误码和受影响的 surface，不要反复点击或手工修改系统。
2. 保留安装器生成的脱敏报告；不要复制 helper stdout、原始配置值或 API 响应
   正文。
3. 如果涉及 ZIP hash、签名、Publisher、package identity、来源、sidecar 或授权
   范围不匹配，立即停止。重新从正式发布页获取原始包，仍失败则联系支持。
4. 不要使用跳过验签、关闭证书检查、`ExecutionPolicy Bypass`、禁用安全软件、
   修改系统代理/证书或编辑包内文件等方式绕过错误。

自动化调用应同时记录固定四字段 `Status/ErrorCode/Changed/NextStep` 和进程退出码。
退出码 `0/1/2/3/4/5` 分别对应
`SUCCEEDED/FAILED/PARTIAL/RESTART_REQUIRED/ACTION_REQUIRED/CANCELLED`；非零状态不能
当作成功，即使没有额外 PowerShell exception。

## 常见问题

### 包校验或安全门失败

- **ZIP hash、embedded manifest 或 detached sidecar 不匹配**：包可能不完整、被
  修改或版本混用。删除该副本，从正式发布页重新下载并重新核对；不得继续执行。
- **MSIX/EXE 签名、证书链、Publisher、identity 或文件 hash 失败**：安装器必须
  fail closed。不要用另一条未记录的下载地址，也不要关闭签名检查。
- **授权、profile、候选 hash 或有效期不匹配**：该操作不属于当前候选的允许范围。
  普通命令行开关或环境变量不能替代有效授权。
- **UAC 被取消或显示的发布者不符合该版本说明**：取消是安全结果。仅在确认请求
  来自正在运行的正式包且发布者与 Release Notes 一致时重新发起；否则停止。

### Claude Desktop / MSIX

- **下载失败、超时、重定向异常或内容截断**：检查普通网络连通性后重试。安装器
  必须重新下载并重新验签，不能把部分下载或旧缓存当成已验证 artifact。
- **已有安装范围与本 Release 冻结范围冲突**：返回 `ACTION_REQUIRED` 是预期行为。
  不要双装、静默迁移或改用另一个 scope；按该版本支持说明处理。
- **旧版升级失败**：保留脱敏报告。Desktop 升级未必支持自动降级，不要把
  `PARTIAL` 或 `UNSUPPORTED` 误认为完整恢复。

### Git for Windows

- **Git 已合格**：安装器应复用唯一的 canonical Git for Windows，结果为未修改。
- **Git 缺失、过旧或损坏**：按提示确认已验签的官方安装或升级。
- **发现多个路径、身份不明或不是 Git for Windows**：流程必须阻断，不会猜测
  可执行文件。不要为通过检查而手工改全局 Git 配置或覆盖 PATH；先由管理员或 IT
  清理归属歧义，再重新运行。
- **拒绝 Git、UAC 或必要 PATH 影响确认**：整体结果应为 `CANCELLED` 或
  `ACTION_REQUIRED`，不能继续报告 Chat-only 成功。

### Cowork、VMP 与重启

- **`PENDING_RESTART` / `RESTART_REQUIRED`**：保存工作，手动重启，再以同一用户
  从同一原始发布包重新双击 `开始安装.cmd`。
- **硬件虚拟化不可用**：按设备厂商或组织 IT 的受控流程启用虚拟化。安装器不会
  绕过 BIOS、组织策略或平台限制。
- **VMP 修改被拒绝**：已安全完成的项目可以保留，但总结果只能是 `PARTIAL`、
  `ACTION_REQUIRED` 或 `CANCELLED`。
- **checkpoint 陈旧、损坏或所有权不匹配**：不要编辑 checkpoint。使用正式诊断
  确认原因；必要时从干净状态重新发起。

### Credential helper 与 DeepSeek API

- **Key 被拒绝**：在 DeepSeek 控制台确认 Key 的状态、权限和余额，然后只通过
  本地安全输入重新录入。不要把 Key 放进命令行、环境变量、文件或工单。
- **helper 超时、非零退出、输出非法或 DPAPI blob 损坏**：停止使用该凭据，运行
  正式包的诊断/修复流程并在提示下重新录入或撤销 Key。不要执行 helper 手工输出，
  也不要复制其 stdout。
- **网络或 API 校验失败**：区分断网、超时、认证失败和服务端错误。日志只应包含
  稳定脱敏错误码；原始响应正文和 Authorization 不应进入报告。
- **怀疑 Key 泄露**：立即在 DeepSeek 控制台撤销或轮换该 Key，再处理本机项目
  credential。安装器恢复不能替代上游撤销。

### 配置冲突、修复与恢复

- **检测到 HKLM managed policy**：机器级策略优先，低优先级写入必须停止。联系
  组织管理员；不要自行删除组织策略。
- **检测到非项目拥有的 HKCU/configLibrary 配置**：默认不覆盖。只有在来源、
  所有权和恢复影响明确且用户独立确认后，发布流程才可处理。
- **恢复为 `PARTIAL` / `UNSUPPORTED`**：查看逐资源结果。VMP、PATH、既有
  Desktop/Git 等共享资源可能不适合自动反向修改。
- **恢复为 `FAILED` 或重读不一致**：不要启动 Claude Desktop 或继续验收；保留
  脱敏报告并联系支持。
- 不要定位、读取、哈希、备份或编辑 `%USERPROFILE%\.claude\settings.json`。

## 提交安全的支持信息

优先运行正式包中的 `一键诊断.cmd`，并只提交其脱敏报告。可以提供：

- 安装器版本、原始 ZIP SHA-256 和 Release Notes 标识；
- Windows build、架构和报告中的场景/运行标识；
- 整体状态、稳定错误码、各 surface 的能力与 UI 状态；
- MSIX/Git/VMP 的脱敏身份与 readiness 摘要；
- 逐资源补偿状态和复现步骤。

不要提交：DeepSeek API Key、Authorization、helper stdout、DPAPI blob、原始
registry/policy 值、原始 API 响应、凭据备份、VM 磁盘、用户资料、完整用户名路径，
或可能显示秘密的截图。脱敏支持快照不能用于恢复。
