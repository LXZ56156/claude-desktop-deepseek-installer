# D-027 practical product specification

## 用户结果

在大多数 Windows 11 x64 环境中，用户解压 ZIP、双击安装、确认变更并遮罩输入 Key 后：

- 有一个可工作的可信 Git for Windows；
- 当前用户安装了不低于官方下载包版本的 Claude Desktop；
- Key 以 DPAPI CurrentUser 密文保存；
- Claude 读取 8 个最小 HKCU REG_SZ 第三方推理值；
- Claude 打开，用户可以验证 DeepSeek 文本 Chat；
- 重复运行不会无意义重写健康组件；
- 诊断不读取 Key，恢复只删除项目拥有内容。

## 非目标

- Windows 10、Windows Server、ARM64。
- Node/npm/WSL/VS Code 或 Claude Code CLI 安装。
- 全局 Git 配置或持久 PATH 编辑。
- machine-wide Claude provisioning。
- VMP、重启 checkpoint 或 Cowork 完整可用性。
- 自动 API 余额/Key 探测。
- snapshot RSA、CAS、relay、Automation、P10/P11/P12。

首个 VM 完成门是安装、配置和真实文本 Chat。Code 可观察但不阻塞；Cowork 明确延期。
