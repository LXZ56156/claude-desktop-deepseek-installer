# 用户指南

## 安装前

- Windows 11 x64。
- 能访问 GitHub、`claude.ai`、`downloads.claude.ai` 和 DeepSeek API。
- 一个有效的 DeepSeek API Key。
- 安装 Git 时可能需要管理员批准；Claude per-user MSIX 本身不要求 machine-wide
  provisioning。

不要把 API Key 粘贴到命令行、聊天、截图或问题报告中。

## 安装

双击 `开始安装.cmd`。窗口会保留到按键关闭。安装器先说明将执行的动作，只有输入
`y` 才继续。

流程依次是：

1. 验证 Windows 11 x64 和 Windows PowerShell 5.1。
2. 复用可信的常见 Git for Windows，或下载并安装官方最新版。
3. 下载并验证官方 Claude x64 MSIX，按需升级当前用户安装。
4. 关闭正在运行的 Claude，使新配置在下次启动时生效。
5. 遮罩读取 Key，保存 DPAPI CurrentUser 密文并写入最小 HKCU policy。
6. readback 配置并打开 Claude。

重复运行会复用健康的 Git、Claude、helper、密文和一致的 policy。

## 诊断与恢复

`一键诊断.cmd` 只检查组件、项目文件哈希和 policy；不会解密或输出 Key。

`恢复配置.cmd` 只删除本项目拥有的 HKCU policy、helper、DPAPI 密文和状态。它不会
卸载 Git 或 Claude，也不会读取或修改 Claude Code 的个人配置。

## 已知范围

- Code/Cowork 标签可能由 Claude 默认显示，但本版只把文本 Chat 作为首个 VM 完成门。
- Cowork 可能需要 machine-wide provisioning、管理员权限、Virtual Machine Platform
  和重启；本版不自动执行这些动作。
- 更换 Key 的最小路径是先运行恢复，再重新安装。
