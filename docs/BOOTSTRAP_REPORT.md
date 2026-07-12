# 开发前脚手架汇报

日期：2026-07-12

新项目：`D:\projects(WIN)\claude-desktop-deepseek-installer`

只读参考：`D:\projects(WIN)\claude-deepseek-installer`

## 结论

新的 Windows PowerShell 项目已完成开发前脚手架搭建。当前版本为
`0.1.0-dev`、阶段固定为 `Scaffold`，只包含模块边界、函数合同、数据结构、
安全门、TODO、Pester 测试和 CI/Release DryRun 基线。

没有实现或执行 Claude Desktop MSIX/Git 安装、Windows 功能启用、系统重启、
DeepSeek API 请求、Claude 配置写入或 Claude 进程控制。没有读取、修改或计算
`%USERPROFILE%\.claude\settings.json` 的真实哈希。

## 路径确认与旧项目只读证明

- 开始前确认两个绝对路径均存在且为目录。
- 新目录初始项目项数为 0，随后在该目录初始化 Git，默认分支为 `main`。
- 旧目录只做文件读取与哈希/元数据复核，没有运行旧脚本。
- 旧目录 4541 个文件的元数据清单摘要在开始和结束时均为
  `49892ea2e26dca10c2b5aa25908c5c0bfebb7f544ad4f3c40880971232c0e214`，
  文件数与总字节数（38119399）也完全一致。
- 六个重点参考文件的 SHA-256 在只读审计前后保持不变；旧仓库原有的工作树
  状态保持原样。

## 创建的目录和文件

仓库共有 50 个受控文件：Release 包精确白名单 26 个，开发专用 24 个。
`.dev/modules/Pester/5.6.1` 是被 Git 忽略的仓库本地开发依赖，不属于受控文件。

```text
claude-desktop-deepseek-installer/
├─ 开始安装.cmd
├─ Start-Install.cmd
├─ Start-Here.ps1
├─ 一键诊断.cmd
├─ Run-Diagnostics.cmd
├─ 恢复配置.cmd
├─ Restore-Config.cmd
├─ AGENTS.md
├─ README.md
├─ CONTRIBUTING.md
├─ CHANGELOG.md
├─ LICENSE
├─ VERSION
├─ .gitignore
├─ .gitattributes
├─ .editorconfig
├─ lib/
│  ├─ bootstrap.ps1
│  ├─ logger.ps1
│  ├─ common.ps1
│  ├─ state.ps1
│  ├─ desktop-env-check.ps1
│  ├─ desktop-msix.ps1
│  ├─ git-for-windows.ps1
│  ├─ cowork-readiness.ps1
│  ├─ deepseek-api.ps1
│  ├─ desktop-config.ps1
│  ├─ desktop-lifecycle.ps1
│  └─ desktop-acceptance.ps1
├─ config/
│  ├─ deepseek-desktop.defaults.json
│  └─ public-functions.psd1
├─ scripts/
│  ├─ bootstrap-dev.ps1
│  ├─ check.ps1
│  ├─ build-release.ps1
│  ├─ elevated-install.ps1
│  └─ release-manifest.psd1
├─ tests/
│  ├─ Unit/
│  │  ├─ Common.Tests.ps1
│  │  ├─ State.Tests.ps1
│  │  └─ DeepSeekApi.Tests.ps1
│  ├─ Contract/
│  │  ├─ PublicFunctions.Tests.ps1
│  │  ├─ SafetyBoundary.Tests.ps1
│  │  ├─ Config.Tests.ps1
│  │  └─ Encoding.Tests.ps1
│  └─ Fixtures/
│     └─ safe-config.json
├─ docs/
│  ├─ ARCHITECTURE.md
│  ├─ IMPLEMENTATION_PLAN.md
│  ├─ TESTING.md
│  ├─ SECURITY.md
│  └─ BOOTSTRAP_REPORT.md
└─ .github/workflows/
   ├─ ci.yml
   └─ release-dry-run.yml
```

## 从旧项目复用或改造的内容

这里只复用了通用设计思想，并按新项目边界重新实现，没有整体复制旧文件。

- **薄 bootstrap 与单向加载**：保留集中定位根目录和固定依赖顺序，移除旧入口
  中的网络默认值与 CLI 模块；dot-source 只定义函数，不启动工作流。
- **Windows PowerShell 5.1 中文兼容**：保留单一编码入口思路；`.ps1/.psd1`
  使用 UTF-8 BOM + CRLF，`.cmd` 使用 ASCII + CRLF 且无 BOM，不调用 `chcp`。
- **日志与报告脱敏**：从“调用方自行记得脱敏”改为日志 sink、报告、检查失败
  输出统一脱敏；覆盖 DeepSeek 风格 token、Bearer、JSON/赋值凭据、私钥块、
  用户名和本机路径。Finding 只保留文件、行号、类型和固定脱敏值。
- **API Key 输入规则**：保留拒绝空白、多行、控制字符、非预期格式和禁止静默
  Trim 的原则；当前只定义 SecureString/credential handle 接口，不读取真实输入。
- **备份分层**：明确“受保护可恢复备份”与“可分享脱敏快照”是两个合同；脱敏
  快照永远不能作为恢复源。未来跨重启备份建议使用 DPAPI CurrentUser 或经评审
  的等效机制。
- **状态语义**：保留首次运行/完成状态分离的思想，重建为 schemaVersion、runId、
  phase、completed steps、restart/resume、backup metadata 和安全错误字段；使用
  精确字段白名单、强类型与状态关联不变量，禁止凭据和原始配置。
- **TestSafe 与产物隔离**：潜在修改函数统一 `Mode=TestSafe|DryRun|Live`，默认
  TestSafe；Scaffold 阶段即使确认 Live 也 fail closed。文件日志只允许显式唯一
  OS 临时目录，拒绝 Live 与重解析点祖先。
- **Release 质量门**：保留逐文件 allow-list、源树扫描、staging 二次扫描和 ZIP
  精确条目比较的思路；改为一个 manifest 同时分类所有 Git tracked/非忽略文件，
  使用严格 UTF-8 解码、精确集合比较和仅清理自有临时目录。
- **公开函数合同**：新增 `config/public-functions.psd1` 作为单一事实来源，精确
  校验每个库文件的函数集合、Mandatory 参数、Mode 默认值/ValidateSet 和确认
  开关，避免旧式大段源码正则与实现强耦合。

## 明确排除的旧逻辑

以下旧项目专属内容没有复制或迁移：

- Claude Code Native、npm、npmmirror 安装与回退；
- Node.js、npm、WSL、VS Code 检测、安装、PATH 或 fresh-shell 处理；
- `install_wsl.sh`；
- Claude Code CLI 卸载、诊断和进程逻辑；
- `~/.claude/settings.json` 的读取、env 合并、写入、备份或恢复；
- 旧项目的 CLI 安装状态字段和用户支持报告字段；
- 旧日志、备份、报告、状态、测试运行产物和任何真实凭据。

新项目源码中也没有 `Add-AppxPackage`、Windows feature 修改、下载/API、进程
启停、计划任务、重启或原生安装命令的当前实现。

## 当前架构

入口只负责选择 `Install/Diagnose/Repair/Restore` 和执行模式；bootstrap 加载
logger/common/state 与各领域合同。领域模块之间不形成循环依赖，未来编排只放在
入口/orchestrator，acceptance 只消费结果。

统一操作结果包含 `Operation/Status/Success/Changed/Mode/ErrorCode/MessageSafe/`
`Data/RestartRequired/PlannedChanges/Warnings`。当前所有潜在修改操作在
TestSafe/DryRun 下都保持 `Changed=false`，Live 无条件拒绝。

主要合同已经预定义：

- Claude Desktop MSIX 检测、官方元数据、下载计划、完整验签证据、安装与升级；
- Git for Windows 检测、官方元数据、下载、验签和静默安装；
- VirtualMachinePlatform、硬件虚拟化、Cowork 服务、checkpoint 和重启续跑；
- DeepSeek 安全凭据接口与 HTTP/网络错误的稳定分类；
- configLibrary 精确路径、重解析点拒绝、固定模型、关闭 discovery、
  Chat/Code/Cowork、备份、原子写入和恢复；
- Claude Desktop 进程生命周期；
- Chat、Code、Cowork、Repair、API Key 泄露和中文脱敏验收报告；
- Claude Code settings 的零读取策略与可注入完整性 token 决策合同。

## 测试和检查结果

| 检查 | 结果 |
|---|---|
| 仓库本地 Pester 5.6.1 初始化 | 通过；仅写入被忽略的 `.dev/modules`，未修改全局/CurrentUser 模块配置 |
| PowerShell AST 与 JSON/defaults 安全合同 | 通过 |
| PowerShell 7.6.2 Pester Unit + Contract | 38/38 通过，0 failed/skipped/not-run/inconclusive |
| Windows PowerShell 5.1 Pester Unit + Contract | 38/38 通过，0 failed/skipped/not-run/inconclusive |
| PowerShell 7 与 Windows PowerShell 5.1 无副作用模块加载 | 通过 |
| 公开函数精确集合与参数合同 | 通过 |
| Scaffold 禁止命令、Live fail-closed 与路径边界 | 通过 |
| CMD ASCII/no-BOM/CRLF；PS UTF-8 BOM/CRLF | 通过 |
| 严格 UTF-8、凭据/私钥扫描与脱敏报告 | 通过 |
| Release manifest | 50/50 精确分类：26 package + 24 development |
| `build-release.ps1 -DryRun` | 通过；未创建 staging、ZIP、checksum、上传或发布 |
| 6 个中英文 `.cmd` TestSafe 入口 | 全部 ExitCode 0 |
| 旧目录只读基线复核 | 文件数、总字节数、元数据摘要和重点文件哈希均不变 |

迭代测试中发现并修复了 bootstrap 函数作用域、StrictMode 空集合、路径注入、
字符串布尔值、模型覆写、state 额外/嵌套字段、验签证据伪造与错包绑定、同路径
文件替换、授权字段/私钥脱敏、UTF-16/无效 UTF-8 绕过、临时日志重解析点和
Release inventory 漏检等脚手架问题。

## Git 状态和初始提交信息

- Git 仓库：已初始化。
- 默认分支：`main`。
- Remote：无；没有创建远程仓库，也没有推送。
- 全局 Git 配置：未修改。
- 可用身份：`LXZ56156 <lizixuan6383828@outlook.com>`。
- 初始提交：`67730758955c17410c1fccdc9811d148153a1fc3`
  （`chore: scaffold Claude Desktop DeepSeek installer`，root commit）。
- 初始提交包含 50 个受控文件、3609 行新增；提交前
  `git diff --cached --check` 通过，staged 集合与 manifest 精确一致。
- 本段在 root commit 后通过独立纯文档提交回填；最终工作树再次确认 clean。

## 下一阶段建议的开发顺序

1. 先用官方资料确认 configLibrary schema、固定模型/feature/discovery 字段、
   Anthropic MSIX URL/Publisher/package identity、Git 官方签名身份和 Cowork 服务。
2. 实现可注入的只读 environment providers，先完成 Windows/Claude/Git/Cowork
   检测，不写状态。
3. 完善 Release 二进制内容/签名扫描和中文、空格、`&` 路径的 ZIP 解压仿真。
4. 只实现下载元数据、缓存、SHA-256 与 Authenticode 证据；安装继续关闭。
5. 实现 state/config 的 sibling-temp、重读 schema、flush、原子替换与故障注入。
6. 实现 DPAPI 恢复包、脱敏快照和失败回滚，证明两类备份不会混用。
7. 实现 SecureString/credential adapter 和伪服务 API 合同测试，再评审真实验证。
8. 实现 Cowork restart checkpoint/cleanup，自动重启仍保持禁止。
9. 最后实现生命周期与 Chat/Code/Cowork 验收；证据齐全且用户另行授权后才讨论
   Live 安装。

## 风险和待确认事项

- **settings 哈希冲突**：零读取与真实 SHA-256 无法同时成立。当前不定位、不读取
  文件，只比较调用方提供的不透明 token。后续需确认是否允许隔离 provider 只
  哈希字节，或继续零读取并使用文件系统监控/外部审计证据。
- **官方身份尚未固定**：MSIX/Git 的 URL、Publisher、包身份目前保持 `null`；
  未经官方核验不得打开下载或安装。
- **Desktop schema 尚未核验**：当前 desired config 是逻辑合同，不宣称已经符合
  真实 Claude Desktop configLibrary 内部格式。
- **Cowork 依赖尚未核验**：服务名称、版本兼容和 VirtualMachinePlatform 的实际
  关系需要后续官方资料与只读探测。
- **恢复材料设计**：跨重启保存真实凭据必须决定 DPAPI/ACL 生命周期、清理顺序
  和失败证据保留策略。
- **TOCTOU**：Live 实现必须在同一不可变 artifact 上于安装前重新计算 SHA-256
  并重验 Authenticode/chain/Publisher/identity；当前只定义合同和测试 seam。
- **二进制扫描策略**：当前仓库没有受控二进制。未来新增 MSIX/EXE/图片等必须
  明确更新 Release 分类、二进制签名/内容扫描与测试，不能只依赖文本扫描。
- **许可证署名**：MIT 文本已建立，但版权持有人尚未填写具体个人或组织名称。

## 停止点

本次工作在“开发前脚手架”完成后停止。下一阶段真实安装器功能没有开始实现。

## 交接补充（2026-07-13）

已新增 `docs/HANDOFF.md` 作为不依赖当前对话的单一交接入口，包含当前提交基线、
必读顺序、已完成/未实现范围、首个安全工作包、停止线、未决决策、标准验证命令
和可直接用于新任务的开场指令。README、实现计划、测试文档和 Release manifest
已同步；后续任务应以仓库实际 HEAD 和该文件为准。
