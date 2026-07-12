# 新任务交接

更新日期：2026-07-13

## 一句话状态

开发前脚手架已经完成并通过本地质量门；真实安装器功能尚未开始。新任务应从
“核验外部合同”开始，不得直接打开 Live、下载、安装、写配置或控制进程。

## 新任务启动信息

- 项目目录：`D:\projects(WIN)\claude-desktop-deepseek-installer`
- 只读参考目录：`D:\projects(WIN)\claude-deepseek-installer`
- Git 分支：`main`
- Remote：无
- 当前版本：`0.1.0-dev`
- 当前阶段：`Scaffold`
- 初始脚手架提交：`67730758955c17410c1fccdc9811d148153a1fc3`
- 脚手架报告提交：`3453c5c`

新任务开始后先运行 `git status --short --branch` 和 `git log -3 --oneline`，以
仓库实际 HEAD 为准。本交接文件本身可能由后续独立文档提交引入，因此不硬编码
该提交自己的哈希。

## 必读顺序

1. `AGENTS.md`：强制依赖、安全、测试、编码和 Release 规则。
2. `README.md`：项目定位、明确边界和当前入口。
3. `docs/ARCHITECTURE.md`：模块方向、统一结果和状态/config 合同。
4. `docs/SECURITY.md`：Live 门、供应链、密钥、备份和隐私边界。
5. `docs/TESTING.md`：本地依赖与完整质量门。
6. `docs/IMPLEMENTATION_PLAN.md`：下一阶段顺序和每阶段退出条件。
7. `docs/BOOTSTRAP_REPORT.md`：旧项目只读分析、创建清单和已验证结果。

公开函数的机器可读事实来源是 `config/public-functions.psd1`，Release 文件分类的
唯一事实来源是 `scripts/release-manifest.psd1`。

## 已完成

- 建立中英文 `.cmd` 入口、`Start-Here.ps1`、12 个领域/基础库边界、默认配置、
  开发脚本、Pester Unit/Contract、CI 和 Release DryRun。
- 所有潜在修改操作默认 TestSafe；Scaffold 阶段 Live 无条件 fail closed。
- 定义 MSIX/Git 验签、Cowork readiness/续跑、DeepSeek 错误分类、configLibrary
  原子写/备份/恢复、Chat/Code/Cowork 验收和密钥扫描合同。
- Release 使用精确白名单；`.cmd` ASCII/no-BOM，PS 5.1 中文脚本使用兼容编码。
- 未复制 Claude Code CLI 专属逻辑，未带入旧日志、状态、备份、报告或凭据。

## 当前明确未实现

- MSIX 或 Git for Windows 的下载、验签实现、安装和升级；
- Windows 功能修改、任务计划、系统重启和重启续跑实现；
- DeepSeek API 请求或真实 API Key 输入；
- `%LOCALAPPDATA%\Claude-3p\configLibrary` 的读取、写入、备份或恢复；
- Claude Desktop 进程关闭、启动与真实 Chat/Code/Cowork 验收；
- `%USERPROFILE%\.claude\settings.json` 的读取、哈希或任何修改。

## 下一任务的首个安全工作包

只做“外部合同核验与测试固化”，不要实现真实系统动作：

1. 从官方资料核验 Anthropic MSIX 来源、Publisher、包身份和更新机制。
2. 核验 Claude Desktop `configLibrary` schema、固定模型、model discovery 以及
   Chat/Code/Cowork 开关；无法从官方资料确认的字段保持 `null`/未实现。
3. 核验 Git for Windows 官方下载元数据和签名身份。
4. 核验 Cowork 与 VirtualMachinePlatform、硬件虚拟化、服务状态的真实关系。
5. 把确认结果写成可测试的数据合同和 Fixtures；先实现可注入的只读 provider，
   仍不得下载、安装、写配置、请求 API 或控制进程。

该工作包的退出条件：来源可追溯、未确认值 fail closed、相应 Pester 合同通过、
Release manifest 同步、完整质量门通过，并更新本交接文件的“当前状态”。

## 不可突破的停止线

- 不修改只读参考项目。
- 不读取或修改 Claude Code CLI 配置。
- 不引入 Node.js/npm/npmmirror、WSL、VS Code 或 Claude Code CLI 安装诊断逻辑。
- 不允许跳过签名验证；未经确认的 Publisher/identity 不得猜测填入。
- 非 Live 不得产生真实系统修改；当前 Scaffold 阶段即使指定 Live 也必须拒绝。
- 不在日志、Fixture、报告、状态、提交或 CI 输出中放入真实 API Key。
- 每次新增/删除/重命名文件必须同步测试和 Release 白名单。

## 未决决策

最大矛盾是“完全不读取 `~/.claude/settings.json`”与“证明其前后 SHA-256 不变”
不能同时由本进程完成。当前政策是零读取，只接受调用方提供的不透明完整性 token。
除非用户明确改变边界，否则新任务不得自行实现哈希读取。

其他未决项包括 configLibrary 官方 schema、MSIX/Git 官方身份、Cowork 依赖、
DPAPI 恢复材料生命周期以及未来二进制 Release 扫描策略。详见
`docs/BOOTSTRAP_REPORT.md` 的风险章节。

## 标准验证命令

```powershell
pwsh -NoProfile -File .\scripts\bootstrap-dev.ps1
pwsh -NoProfile -File .\scripts\check.ps1
pwsh -NoProfile -File .\scripts\build-release.ps1 -DryRun
git diff --check
git status --short --branch
```

`bootstrap-dev.ps1` 只把固定版本 Pester 放入被忽略的 `.dev/modules`，不得改为
全局或 CurrentUser 安装。任何检查失败都应先修复脚手架，再开始下一工作包。

## 建议给新任务的开场指令

> 在 `D:\projects(WIN)\claude-desktop-deepseek-installer` 继续开发。先完整阅读
> `AGENTS.md` 和 `docs/HANDOFF.md`，核对 Git 状态并运行现有质量门。严格停留在
> TestSafe/只读范围；本轮只执行交接中“首个安全工作包”，不实现或执行任何真实
> 下载、安装、Windows 功能修改、重启、API 请求、Claude 配置写入或进程控制，
> 也不得读取或修改旧项目及 `~/.claude/settings.json`。
