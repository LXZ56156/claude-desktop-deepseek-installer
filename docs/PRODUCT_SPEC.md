# 产品规格

更新日期：2026-07-25

## D-027 首版范围

- 唯一正式支持环境：Windows 11 x64。
- 唯一产品 PowerShell 运行时：Windows PowerShell 5.1。
- Windows 10、Arm64 和 PowerShell 7 不在首版支持矩阵；PS7 仅可作开发诊断。
- 用户闭环固定为 Git + Claude Desktop + Chat + Code + Cowork；不能以 Chat-only
  或 synthetic readiness 代替。
- 候选必须从 ZIP 启动，在 clean disposable VM snapshot 真实通过首次安装、复用/
  幂等、失败矩阵、API、三个 surface、Diagnose/Repair/Restore，才可标记
  `D027_RELEASE_READY`。

## 产品定位

本项目为 Windows 用户提供 Claude Desktop + DeepSeek 的中文引导式一键安装器。
它从一次双击开始，完成环境判断、官方应用部署、按需依赖、第三方推理配置、
安全凭据保存、Chat + Code + Cowork 固定配置、启动和验收。

“一键”表示一次双击发起完整流程，不表示绕过 Windows 或 Claude 的安全确认。

## 目标用户

- 希望使用 Claude Desktop，但不愿手工进入 Developer Mode 配置第三方网关的
  Windows 用户。
- 使用 DeepSeek API，并希望 Chat、内置 Code 和条件允许时的 Cowork 能开箱使用
  的用户。
- 不熟悉 PowerShell、MSIX、Git、VMP、注册表策略和 API 配置的用户。

## 产品承诺

安装器最终应做到：

- 只从官方来源获取 Claude Desktop 和 Git for Windows。
- 首次启动前部署 Claude Desktop 官方 Third-Party managed configuration。
- 不要求 Anthropic 账号登录，不要求用户进入 Developer Mode。
- API Key 只在本机安全输入，不进入命令行、日志、状态、报告或发布包。
- Chat、Code 和 Cowork 是固定完整功能目标，不向普通用户展示功能选择页。
- Git 必须可用：合格版本直接复用，缺失或不合格时安装/升级官方 Git for
  Windows。
- 三项分别验收；任一必要前置失败都不能用一个总 PASS 或 Chat-only 降级掩盖。
- 安装、诊断、修复、恢复和报告均提供中文界面。
- 既有 Claude、Claude Code、Git 和其他用户配置默认不被静默覆盖。

## 暂定最终用户流程

### 1. 启动

用户解压 Release ZIP 后双击 `开始安装.cmd`。启动器定位自身目录、检查文件完整
性，并进入 PowerShell 编排器。

### 2. 环境预检

安装器检查 Windows build、x64/Arm64、管理员能力、Claude Desktop 版本、
Git、硬件虚拟化、VirtualMachinePlatform 和 Cowork readiness。

预检必须先输出能力矩阵，再请求任何可能产生系统修改的确认。

### 3. 固定完整功能目标

首版不展示 Chat/Code/Cowork 选择页，也没有可取消单项的复选框。编排器固定以
三项全部可用为目标，并自动决定：

- 使用 P10 根据固定版本 VM 证据冻结的单一 MSIX 部署范围；不让用户选择，也不在
  运行时静默 fallback 或双装。
- 每次检查 Git，合格则复用，缺失或不合格则进入官方安装/升级流程。
- 检查硬件虚拟化和 VMP，必要时进入独立确认、checkpoint 和人工重启流程。
- managed policy 中三个 surface 字段固定为 `true`。

`RequestedSurfaces` 固定为三项；`EffectiveSurfaces` 由 readiness 自动计算，只
决定需要执行的前置动作和最终状态，不修改 policy 目标。若 Cowork 遇到 BIOS 等
阻断，已经安全完成的 Chat/Code 部分可以保留，但顶层只能报告 `PARTIAL` 或
`ACTION_REQUIRED`；不得改成 Chat-only 后宣称成功。未知部分修改或补偿失败必须
直接 `FAILED`。

### 4. Claude Desktop 部署

安装器从 Anthropic 官方来源获取与架构匹配的 MSIX。下载、验签和安装分离：

1. 下载到本次运行独占的安全临时目录。
2. 验证来源、artifact type、绝对路径绑定、SHA-256、Authenticode、可信链、
   Publisher 和 package identity。
3. 安装前对同一文件重新计算 SHA-256 并复核身份。
4. 证据不完整或版本不满足最低要求时 fail closed。

标准 MSIX 与离线 MSIX 的产品选择在固定版本实测后确定。安装器不重新打包或
修改 Anthropic MSIX。

### 5. 确保完整功能前置

- Git 是产品必备前置。合格 Git for Windows 直接复用，不重复安装、不读取或修改
  全局 Git 配置。
- Git 缺失、过旧或不合格时，安装器使用已验签的官方安装器完成安装/升级；来源、
  PATH 变化或现有安装冲突不明确时 fail closed。
- Cowork 必须满足 MSIX、管理员权限、硬件虚拟化和 VMP 等条件。

启用 VMP 可能需要重启。默认方案是写入不含凭据的 checkpoint，提示用户重启并
重新双击启动器后续跑；不默认创建计划任务、RunOnce 或自动重启。

### 6. 安全输入 API Key

Key 通过本地 `Read-Host -AsSecureString` 或等效安全 UI 获取。安装器使用
DPAPI CurrentUser 保护凭据，并通过 Anthropic credential helper 合同按需提供。

Key 不得静态写入 Claude policy、configLibrary、环境变量、状态或备份明文。

### 7. 部署第三方配置

安装器在 Claude 首次启动前写入经过版本验证的 managed configuration：

- provider 使用 Anthropic 官方 `gateway` 类型；
- endpoint 使用 DeepSeek Anthropic-compatible 地址；
- 认证方案使用 `x-api-key`；
- 关闭不受支持的 model discovery；
- 部署带验证日期的 Claude tier 到 DeepSeek 模型映射；
- 固定设置 `chatTabEnabled=true`、`isClaudeCodeForDesktopEnabled=true` 和
  `coworkTabEnabled=true`；
- 在验证通过后隐藏 deployment chooser。

首版只写当前用户 HKCU managed policy。发现既有 HKLM、HKCU 或本地 3P 配置时，
默认报告冲突并要求用户选择；HKLM 冲突直接停止，不静默覆盖，也不混写配置源。

### 8. 启动与验收

安装器启动 Claude Desktop，但不内置脆弱的 UI 自动化。产品自身分别报告：

- Chat：配置和可选 API validation 是否通过；UI E2E 为 `NOT TESTED`。
- Code：配置、Git 和 readiness 是否通过；UI E2E 为 `NOT TESTED`。
- Cowork：配置和 readiness 是否通过；UI E2E 为 `NOT TESTED`。
- Secret：日志、状态、报告和临时产物中是否存在凭据。
- Repair/Restore：项目拥有的 policy、credential、state 和备份是否精确恢复。

真实 Desktop UI 的 Chat/Code/Cowork E2E 由后续 VM Codex 外部执行。未来只有
Anthropic 提供稳定机器接口并经过决策后，才考虑内置 E2E。

### 9. 完成报告

报告分为三个互不混用的层级：

| 层级 | 允许状态 | 含义 |
|---|---|---|
| 运行 | `SUCCEEDED/PARTIAL/RESTART_REQUIRED/ACTION_REQUIRED/CANCELLED/FAILED` | 整个编排结果 |
| 能力 | `READY/BLOCKED/PENDING_RESTART/UNSUPPORTED/UNKNOWN` | Chat、Code、Cowork readiness |
| UI 证据 | `PASS/FAIL/NOT_TESTED` | 真实 Desktop 交互是否已经验证 |

`Success=true` 只允许用于 `SUCCEEDED`，它要求三项配置与 readiness 全部为
`READY`。D-027 的真实 UI E2E 只由 clean Windows 11 x64 snapshot 上对精确候选
执行的 Computer Use 产生 `PASS/FAIL`；三个 surface 和完整真实矩阵通过后才可支持
`D027_RELEASE_READY`。用户取消必要确认使用 `CANCELLED`，不能伪装
成技术失败或成功。

每个非成功状态必须给出稳定错误码、下一步和是否可以安全续跑。报告还必须说明
必要的 UAC、重启、BIOS 或权限动作，不能把未测试能力写成成功。

## 资源级补偿承诺

产品不承诺把整台 Windows 机器做成单一事务。恢复/补偿按资源分别报告：

| 资源 | 首版承诺 |
|---|---|
| 项目拥有的 HKCU policy、credential blob、state、backup | 精确恢复原值、类型和所有权；失败即总流程失败 |
| 本次全新安装且确认无共享依赖的 Desktop/Git | 仅通过官方卸载路径尝试，可报告 `FULL/PARTIAL/UNSUPPORTED` |
| 既有 Desktop/Git 升级 | 不自动降级，明确报告 `PARTIAL/UNSUPPORTED` |
| VMP、共享服务、系统 PATH | 不自动撤销可能被其他软件使用的状态，明确报告 `PARTIAL/UNSUPPORTED` |

任何完成报告都必须列出每项资源的安装前状态、项目所有权、实际变化和补偿状态，
不得只写一个含糊的“已回滚”。

## 能力范围

| 能力 | 首版目标 | 条件 |
|---|---|---|
| Windows 11 x64 | 必须 | 完整开发与 VM 验收 |
| Arm64 | 不支持 | 不进入 D-027 发布或验收范围 |
| Windows PowerShell 5.1 | 必须 | 唯一产品运行时 |
| PowerShell 7 | 非阻塞诊断 | 不属于发布门，不维护 parity |
| Chat 文本 | 必须 | DeepSeek API 有效 |
| 内置 Code | 必须 | Git 和协议能力必须满足 |
| Cowork | 必须 | 管理员、MSIX、VMP、虚拟化必须满足 |
| 离线 MSIX | 待决策 | 体积、更新与首次运行实测 |
| 升级、修复、资源级补偿 | 必须 | 按补偿矩阵给出证据，不承诺整机回滚 |

## 不可避免的用户交互

安装器不得承诺绝对零点击。以下交互可能必须保留：

- Windows UAC。
- API Key 输入。
- Git 安装/升级及其经验证的 PATH 变化确认。
- VMP 启用后的重启。
- BIOS/UEFI 中启用硬件虚拟化。
- Claude 对高风险工具或工作目录的安全授权。
- 经固定版本验证后仍存在的首次 3P 确认。

## 中文能力边界

- 安装器、诊断、恢复、错误说明、报告和用户文档全部使用中文。
- Claude 和 DeepSeek 可以使用中文对话。
- Anthropic 当前未提供中文 Desktop UI，项目不承诺汉化 Claude 本体。
- 禁止通过修改 Electron/MSIX 资源集成非官方汉化补丁，因为这会破坏签名、
  更新和供应链完整性。

## 明确非目标

- 不安装独立 Claude Code CLI、Node.js、npm、WSL 或 VS Code。
- 不读取、备份、迁移或修改 `%USERPROFILE%\.claude\settings.json`。
- 不直接或静默修改全局 Git 配置、用户 PATH 或 PowerShell 全局模块配置。若
  官方 Git 安装器不可避免地精确修改 PATH，必须先披露并取得独立确认，且有检测
  和补偿合同。
- 不绕过 UAC、签名验证、应用权限、工具确认或 Windows 安全边界。
- 不宣称 DeepSeek 与 Anthropic 原生协议 100% 等价。
- 不重新分发经过修改的 Claude Desktop 或 Git 安装包。

## 产品完成定义

只有同时满足以下条件，才可宣称“一键安装器完成”：

1. 所有阶段 Pester、静态检查、Release DryRun 和故障注入通过。
2. 宿主机测试证据显示真实 provider 未加载，禁止资源访问和真实副作用均为零。
3. Release ZIP 的白名单、secret 扫描、特殊路径仿真和校验值全部通过。
4. 后续干净 VM 中完成 UAC、安装、必要重启、3P 直达、Chat、Code、Cowork、
   泄露扫描、重复运行和资源级补偿矩阵。
5. 不存在功能选择页，三个 surface 固定启用；Git 合格复用或由官方安装器准备。
6. 未通过或未测试的能力在报告和发布说明中明确标示，任何单项失败都不能发布为
   完整成功。
