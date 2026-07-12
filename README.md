# Claude Desktop DeepSeek Installer（开发前脚手架）

这是一个面向 Windows PowerShell 的独立 Claude Desktop 安装器项目。它不要求
预先安装 Claude Code CLI，也不会复用 Claude Code CLI 的安装或配置链路。

> 当前版本只有模块边界、数据结构、TODO、安全门和测试框架。所有系统操作、
> 网络请求、配置写入和进程控制都尚未实现；入口固定运行在 TestSafe。

## 目标能力

- 从 Anthropic 官方来源下载 Claude Desktop MSIX，并在安装或升级前验证
  Authenticode、证书链、Publisher 和包身份。
- 检测 Git for Windows；缺失时未来只允许从官方来源静默安装，不修改全局
  Git 配置。
- 检测 `VirtualMachinePlatform`、硬件虚拟化与 Cowork 服务，支持显式确认后的
  重启续跑。
- 安全获取和验证 DeepSeek API Key；Key 不得进入日志、报告、状态、测试夹具
  或提交历史。
- 原子写入 Claude Desktop 的
  `%LOCALAPPDATA%\Claude-3p\configLibrary`，并提供受保护的可恢复备份、脱敏
  诊断快照和回滚。
- 固定 `deepseek-chat`、`deepseek-reasoner` 模型，关闭 model discovery，启用
  Chat、Code、Cowork。
- 提供诊断、修复、恢复、重启续跑和中文脱敏验收报告。

## 明确边界

本项目不读取、不修改 `%USERPROFILE%\.claude\settings.json`，不安装、卸载或
诊断 Claude Code CLI，不安装 Node.js/npm，不使用 npmmirror，不操作 WSL 或
VS Code，也不修改用户 PATH。

需求同时提出“Claude Code settings 前后哈希不变”。计算真实文件哈希必然读取
文件字节，因此当前只定义了可注入的不透明完整性 token 合同，没有访问该文件。
Live 实现前需要确认是否允许独立验收器执行“只哈希、不解析、不记录内容”；在
确认前继续执行零读取策略。

## 当前可运行入口

- `开始安装.cmd` / `Start-Install.cmd`
- `一键诊断.cmd` / `Run-Diagnostics.cmd`
- `恢复配置.cmd` / `Restore-Config.cmd`
- `Start-Here.ps1 -Action Install|Diagnose|Repair|Restore -TestSafe`

这些入口只加载合同并报告 `scaffold_only`，不会执行真实动作。直接传入 `-Live`
会被强制拒绝。

## 开发验证

```powershell
pwsh -NoProfile -File .\scripts\bootstrap-dev.ps1
pwsh -NoProfile -File .\scripts\check.ps1
pwsh -NoProfile -File .\scripts\build-release.ps1 -DryRun
```

`bootstrap-dev.ps1` 把固定版本 Pester 保存到 `.dev/modules`，不会安装到全局或
CurrentUser，也不会持久修改 `PSModulePath` 或 PowerShellGet 配置。

更多内容见 `docs/ARCHITECTURE.md`、`docs/IMPLEMENTATION_PLAN.md`、
`docs/TESTING.md` 和 `docs/SECURITY.md`。
