# Claude Desktop + DeepSeek practical installer

这是一个面向 Windows 11 x64 的小型安装器。目标很直接：双击后准备 Git、安装官方
最新版 Claude Desktop，并把 DeepSeek API Key 安全地配置给 Claude Desktop。

## 使用

1. 下载并完整解压 Release ZIP。
2. 双击 `开始安装.cmd`。
3. 阅读变更说明后输入 `y`。
4. 如果缺少 Git，接受官方 Git for Windows 安装器的 UAC。
5. 在遮罩输入框中输入 DeepSeek API Key。
6. Claude 打开后先发送一条普通文本消息验证。
7. 需要检查时双击 `一键诊断.cmd`；需要移除本项目配置时双击 `恢复配置.cmd`。

安装器会复用已验证的常见 Git for Windows 安装；否则读取官方 GitHub immutable
release metadata，核对 SHA-256 和 Authenticode 后安装。Claude MSIX 来自 Anthropic
官方 x64 endpoint，并核对最终域名、签名、publisher、manifest 和安装前哈希。

Key 不会出现在命令行、环境变量、日志或状态中。安装器只保存 DPAPI CurrentUser
密文，Claude 通过本地 credential helper 取用。

当前 practical MVP 使用 per-user MSIX，完成安装与第三方推理配置；它不自动启用
Virtual Machine Platform，也不承诺 Cowork 在每台机器可用。先把 Chat happy path
在 disposable VM 跑通，再根据真实故障补兼容。

开发状态见 [docs/HANDOFF.md](docs/HANDOFF.md)。
