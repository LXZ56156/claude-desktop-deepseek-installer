# 贡献指南

提交变更前先阅读 `AGENTS.md`、`docs/README.md`、`docs/HANDOFF.md` 和
`docs/TEST_ISOLATION.md`，再按工作包阅读架构、安全和实现计划。

## 本地验证

先显式选定 PowerShell 7、Windows PowerShell 5.1 和 Git 的绝对路径，并分别计算
SHA-256；不得让产品代码搜索 PATH 或选择替代工具。然后：

```powershell
.\scripts\bootstrap-dev.ps1
$evidence = .\scripts\check.ps1 `
    -PowerShell7Executable $pwsh7 `
    -PowerShell7Sha256 $pwsh7Sha256 `
    -WindowsPowerShellExecutable $windowsPowerShell `
    -WindowsPowerShellSha256 $windowsPowerShellSha256 `
    -GitExecutable $git `
    -GitSha256 $gitSha256 `
    -PassThru

if ($evidence.Scenario -cne 'Quality' -or $evidence.CLEANUP_OUTCOME -cne 'Succeeded') {
    throw 'Isolated quality evidence is not clean.'
}

.\scripts\build-release.ps1 -DryRun
```

`check.ps1` 在 owner-marked HostSandbox 中运行双引擎 Pester 与隔离 Git
`diff --check`；不要在外部再直接运行 Pester 或 Git 质量门。Release Simulation
只能在 clean quality evidence 之后运行，只允许 `-DryRun`；不得使用
`-SkipQualityGate` 或指定输出目录。

Pester 5.6.1 的精确 runtime tree 随仓库提交。`scripts/bootstrap-dev.ps1` 只验证
`config/dev-dependencies.psd1` 固定的文件数、字节数和 SHA-256，不下载、修复、
安装或导入模块。除该精确 vendored tree 外，`.dev/modules` 仍被忽略，也不得作为
一般测试工作区；不得修改全局 `PSModulePath`、PowerShellGet 仓库信任或用户级
模块配置。

CI checkout 必须固定到 action 的完整 commit SHA 并设置
`persist-credentials=false`。CI 的受信前置可以从 runner 已知工具解析绝对路径并
计算 hash，但所有项目测试仍必须只通过 `check.ps1` 的精确授权入口运行。

本地和 CI 不得加载或执行 live provider。所有系统能力测试必须通过不可缺省的
ExecutionContext、fake provider、AccessLedger 和 owner-marked sandbox；真实
Live 只在项目完成后的 disposable VM。

## 变更规则

1. 新增或删除文件时同步更新 `scripts/release-manifest.psd1`。
2. 修改公开函数时同步更新合同测试和架构文档。
3. 系统修改代码必须先有 TestSafe/DryRun 测试，并且只能在明确的 Live
   模式与独立确认后执行。
4. 不得提交真实 API Key、用户日志、备份、状态或验收产物。
5. 不得读取、写入或迁移 Claude Code CLI 的配置。
6. 新增系统能力前必须先满足 P1 Sandbox Foundation；缺 fake/context 时不得
   回退真实系统。
7. 新增、删除或重命名文件时同步文档完整性检查和 Release manifest。
8. 每个工作包完成后更新 `docs/HANDOFF.md`。
