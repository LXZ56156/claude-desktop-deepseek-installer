# 旧 Claude Code 安装项目复用指南

更新日期：2026-07-13

只读参考项目：

`D:\projects(WIN)\claude-deepseek-installer`

## 原则

旧项目最有价值的是“如何证明安装器没有做错”的测试、进程和 Release 方法，不是
Claude Code 的具体安装实现。新项目只能只读参考，不在旧仓库修改、提交或运行
旧安装流程。

任何迁移都必须按当前项目的 ExecutionContext/provider、三态 Mode、完整脱敏、
验签证据和零接触测试合同重新实现，不能整文件复制。

## 推荐复用

| 领域 | 可复用内容 | 新项目改造要求 |
|---|---|---|
| 双击启动器 | 工作目录、ZIP 预览、缺文件、退出码和暂停 | 保持 CMD ASCII/CRLF；替换 Claude Code 文案 |
| Bootstrap | 固定加载顺序和显式初始化 | 不带入网络默认值或旧领域模块 |
| 控制台编码 | Windows PowerShell 5.1 与新版终端分支 | 只由 logger 入口处理，不调用 chcp |
| 安全输入 | SecureString、BSTR、ZeroFreeBSTR | 不固化旧 Key 格式，不展示任何前后缀 |
| 进程执行 | FilePath/argument 边界、stdout/stderr、timeout、进程树清理 | 通过 Process provider；不记录 argv 中的 secret |
| Release | 源树、staging、ZIP 三阶段扫描和精确条目比较 | 只消费当前 release manifest |
| 验收 | 数据驱动状态、required/forbidden、证据 drain | 改成 Chat/Code/Cowork/Secret/Restore |
| 故障注入 | 特殊字符、exit code、timeout、临时文件清理 | 迁移到 Pester 和 HostSandbox |
| 特殊路径 | 中文、空格、`&`、`!`、括号 | 加入 Release Simulation |
| 验证编排 | 唯一 RunRoot、子进程、失败证据、成功清理 | 使用 owner marker 和 synthetic 环境 |

可重点阅读：

- `00-点我开始安装.cmd`
- `lib/bootstrap.ps1`
- `lib/common.ps1` 中安全输入部分
- `lib/claude-install.ps1` 中受控进程执行思路
- `scripts/build-release.ps1`
- `scripts/interactive-user-acceptance.ps1`
- `scripts/simulate-user-release.ps1`

这些路径仅用于定位思路，不能视为已满足新项目安全要求。

## 禁止复制

### Claude Code 领域逻辑

- Native/npm/npmmirror 安装和回退。
- Node.js、npm、WSL、VS Code 和 PATH。
- 独立 Claude Code CLI 卸载、诊断和 fresh-shell。
- `install_wsl.sh`。
- `~/.claude/settings.json` 的 env 合并、备份、写入、读取或哈希。

### 旧日志与脱敏

旧 logger 会把调用方消息直接写入 sink，旧 Key mask 保留前后字符。新项目必须：

- 每个 sink 统一先完整脱敏。
- 不保留 Key suffix/prefix。
- 异常、argv、stdout/stderr、Finding 和报告使用同一保护边界。

### 旧下载信任

旧流程主要验证“内容看起来像脚本”后执行，不能迁移。新项目必须有：

- 官方元数据。
- artifact type。
- canonical path binding。
- SHA-256。
- Authenticode、chain、Publisher 和 identity。
- 安装前重算和重验。
- 无 bypass 参数。

### 旧状态和备份

旧状态允许宽松字段，旧备份面向 Claude Code settings。新项目必须：

- exact schema/field allow-list。
- 禁止 credential/raw config。
- provider/owner-bound atomic state。
- managed policy/configLibrary 的独立恢复合同。
- DPAPI 可恢复备份与脱敏快照分离。

### 旧 TestSafe

旧项目的 switch 不等于当前 `TestSafe|DryRun|Live`，也没有 EnvironmentTier、
provider 和 AccessLedger。不能只改参数名复用。

## 推荐迁移顺序

1. 先迁移旧项目的特殊路径、参数边界、故障矩阵和 Release 测试用例。
2. 通过 P1 建立 fake provider、process contract、owner sandbox 和 static gate。
3. 重写安全输入、日志和状态，不复制实现。
4. 独立实现官方 artifact 获取与验签。
5. 再实现 Desktop/Git/config/Cowork 领域。
6. 最后迁移数据驱动验收和 ZIP 用户仿真。

## 复用验收

每次声称“复用旧项目”都必须在 PR/提交说明中回答：

- 复用的是行为、测试用例还是代码片段？
- 已删除哪些 Claude Code 专属假设？
- 如何适配 ExecutionContext/provider？
- 新增了哪些失败注入和 secret scan？
- 为什么不会访问旧项目或宿主机真实配置？
- 相应文件是否已更新 Release manifest 和公开函数合同？

若无法回答，默认不迁移。
