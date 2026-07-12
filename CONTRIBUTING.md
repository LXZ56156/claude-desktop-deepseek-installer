# 贡献指南

提交变更前请先阅读 `AGENTS.md`、`docs/ARCHITECTURE.md` 和
`docs/SECURITY.md`。

## 本地验证

```powershell
pwsh -NoProfile -File .\scripts\bootstrap-dev.ps1
pwsh -NoProfile -File .\scripts\check.ps1
pwsh -NoProfile -File .\scripts\build-release.ps1 -DryRun
```

开发依赖只保存到仓库内被忽略的 `.dev/modules`，不得修改全局
`PSModulePath`、PowerShellGet 仓库信任或用户级模块配置。

## 变更规则

1. 新增或删除文件时同步更新 `scripts/release-manifest.psd1`。
2. 修改公开函数时同步更新合同测试和架构文档。
3. 系统修改代码必须先有 TestSafe/DryRun 测试，并且只能在明确的 Live
   模式与独立确认后执行。
4. 不得提交真实 API Key、用户日志、备份、状态或验收产物。
5. 不得读取、写入或迁移 Claude Code CLI 的配置。
