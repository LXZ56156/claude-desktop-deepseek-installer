# 故障排查

安装器只输出安全错误码，不输出原始异常或本机路径。

- `RUNTIME_UNSUPPORTED` / `WINDOWS_VERSION_UNSUPPORTED`：必须使用 Windows 11 x64，
  并从 ZIP 内的 `.cmd` 启动 64 位 Windows PowerShell 5.1。
- `GIT_METADATA_UNAVAILABLE` / `DOWNLOAD_FAILED`：检查代理、DNS、防火墙和 GitHub /
  Anthropic 域名访问后重试。
- `GIT_HASH_MISMATCH` / `*_SIGNATURE_INVALID` / `*_SIGNER_INVALID`：不要绕过；重新
  获取 Release ZIP 并重试。持续出现时提交错误码和时间，不要附安装包或 Key。
- `USER_CANCELLED`：重新运行并在需要时接受确认或 UAC。
- `CLAUDE_MACHINE_POLICY_CONFLICT`：机器级 Claude policy 会覆盖 HKCU；联系管理员。
- `CLAUDE_LOCAL_CONFIG_CONFLICT` / `CLAUDE_USER_POLICY_CONFLICT`：已有其他 3P 配置，
  安装器为避免覆盖而停止。
- `PRODUCT_DIRECTORY_CONFLICT`：`%LOCALAPPDATA%\ClaudeDeepSeekInstaller` 已存在但
  没有本项目 ownership。确认它不含需要保留的数据后人工处理。
- `API_KEY_INPUT_REQUIRED`：首次配置必须使用交互式遮罩输入。
- `CREDENTIAL_BLOB_INVALID` / `OWNERSHIP_STATE_INVALID`：先尝试恢复配置，再重新安装。
- `INSTALLATION_INCOMPLETE`：重新运行安装；成功步骤会被复用。

报告问题时可提供：Windows edition/build、错误码、发生步骤、是否已有 Git/Claude。
不要提供 Key、credential 文件、注册表导出、个人 Claude 配置或包含它们的截图。
