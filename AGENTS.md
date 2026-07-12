# AGENTS.md

本文件是仓库内所有人工与自动化开发代理的强制约束。

## 模块依赖规则

1. `lib/bootstrap.ps1` 只负责定位根目录、按固定顺序加载库和初始化日志；顶层
   加载不得触发网络、系统探测、文件写入、提权或进程控制。
2. `lib/logger.ps1` 无项目依赖，所有日志 sink 必须先统一脱敏。
3. `lib/common.ps1` 只放纯数据、序列化、安全策略和通用结果结构，不得加载
   领域模块。
4. `lib/state.ps1` 只依赖 common；状态中禁止凭据、Authorization header、
   原始配置正文和可逆密钥材料。
5. `desktop-env-check.ps1`、`desktop-msix.ps1`、`git-for-windows.ps1`、
   `cowork-readiness.ps1`、`deepseek-api.ps1`、`desktop-config.ps1`、
   `desktop-lifecycle.ps1` 之间不得形成循环依赖；跨领域协调只能放在入口或未来
   orchestrator。
6. `desktop-acceptance.ps1` 可以消费领域结果，但不得成为安装实现的依赖。
7. `scripts/check.ps1` 是薄质量门；行为验证放在 Pester，Release 文件分类只以
   `scripts/release-manifest.psd1` 为事实来源。

## 安全边界

- 当前 `Scaffold` 阶段禁止任何真实 MSIX/Git 安装、Windows 功能修改、重启、
  DeepSeek API 请求、Claude 配置写入以及 Claude 进程关闭或启动。
- 所有潜在系统修改函数必须有显式 `Mode=TestSafe|DryRun|Live`，默认 TestSafe。
  非 Live 只能返回计划且 `Changed=false`；Live 还必须要求独立确认。脚手架阶段
  即使有确认也必须 fail closed。
- 禁止绕过、跳过、降级或伪造 MSIX/EXE 签名验证。安装必须消费结构化且有效、
  并通过路径绑定 token、SHA-256、artifact type 与目标文件绑定的验签证据；Live
  实现还必须在执行安装前重新计算文件 SHA-256。
- 禁止修改全局 Git 配置、全局/CurrentUser PowerShell 模块配置、用户 PATH、
  Windows 功能或任务计划，除非未来任务明确授权并已有 Live 合同与测试。
- 禁止读取、解析、备份、写入或删除 `%USERPROFILE%\.claude\settings.json`。
  在哈希策略确认前，也不得自行读取该文件计算哈希。
- 禁止在日志、异常、状态、报告、测试夹具、发布包、提交或 CI 输出中出现真实
  API Key。日志 sink 与报告生成器必须默认完整脱敏，不保留末尾字符。
- 可恢复备份与可分享脱敏快照是两个不同合同。脱敏快照永远不得作为恢复源；
  未来跨重启恢复材料必须使用 DPAPI CurrentUser 或经评审的等效保护。

## 禁止引入的旧项目逻辑

不得加入 Claude Code Native/npm/npmmirror 安装、Node.js、npm、WSL、VS Code、
`install_wsl.sh`、Claude Code CLI 卸载/诊断、`~/.claude/settings.json` env 合并、
CLI PATH/fresh-shell 检查，或旧项目的日志、备份、报告、状态和凭据。

## 测试要求

- 使用仓库本地 Pester 5；依赖由 `scripts/bootstrap-dev.ps1` 初始化。
- 每个公开函数变更必须同步更新 `config/public-functions.psd1` 和 Unit/Contract
  测试；公开函数文件集合、Mandatory 参数和 Mode ValidateSet 必须精确匹配。
- 每个真实操作的未来实现必须先覆盖 TestSafe、DryRun、Live 许可门、失败注入、
  回滚和脱敏证据。
- MSIX/Git 安装测试必须证明“验签成功证据先于安装”，且没有 bypass 参数。
- configLibrary 测试必须覆盖目标路径限制、同目录临时写、写后重读、flush、原子
  替换、备份、失败恢复和 secret 扫描。
- Cowork 测试必须覆盖 readiness、重启确认、checkpoint schema 和续跑清理。
- 验收测试必须分别覆盖 Chat、Code、Cowork、API Key 泄露与 Claude Code 配置
  完整性策略。
- 测试只允许写 `TestDrive:`、仓库内被忽略的 `.dev`，或唯一 OS 临时目录。

## 编码规则

- `.cmd` 必须是纯 ASCII、无 BOM、CRLF；文件名可以是中文，内容不可含中文。
- 需要在 Windows PowerShell 5.1 执行且包含中文的 `.ps1/.psd1` 必须 UTF-8
  BOM、CRLF。
- 不得在 `.cmd` 中调用 `chcp 65001`。控制台编码只能由 logger 的单一入口按
  PowerShell 版本处理，且不得修改系统代码页。
- JSON/YAML/Markdown 使用 UTF-8；所有文本必须有末尾换行且无尾随空格。

## 文件与 Release 规则

每次新增、删除或重命名文件，都必须同时：

1. 更新 `scripts/release-manifest.psd1`，明确标为 `PackageFiles` 或
   `DevelopmentOnlyFiles`；
2. 更新或新增相应 Pester/静态检查；
3. 必要时更新 README、架构和安全文档；
4. 运行 `scripts/check.ps1`、`scripts/build-release.ps1 -DryRun` 和
   `git diff --check`。

Release 必须采用精确白名单：复制前扫描源文件，staging 后再次扫描，ZIP 条目与
白名单精确比较；不得打包 `.git`、`.dev`、tests、CI、日志、备份、状态、报告、
临时文件或任何凭据。
