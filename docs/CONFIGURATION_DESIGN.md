# Configuration design

安装器写入 `HKCU\SOFTWARE\Policies\Claude` 的 8 个 REG_SZ：

1. `inferenceProvider=gateway`
2. `inferenceCredentialKind=helper-script`
3. `inferenceCredentialHelper=<absolute helper path>`
4. `inferenceGatewayBaseUrl=https://api.deepseek.com/anthropic`
5. `inferenceGatewayAuthScheme=x-api-key`
6. `modelDiscoveryEnabled=false`
7. `inferenceModels=<JSON string for deepseek-v4-pro and deepseek-v4-flash>`
8. `chatTabEnabled=true`

Code/Cowork 使用 Claude 自身默认值，本项目不把标签显示等同于环境已就绪。

Key 保存在 `%LOCALAPPDATA%\ClaudeDeepSeekInstaller\credential.bin`，由 DPAPI
CurrentUser 和私有 ACL 保护。helper 在目标机用 Windows 11 自带 .NET Framework C#
编译器生成，绝对路径固定，无参数，只向 stdout 写 token 字节。

`state.json` 只记录 owner、固定 policy 名称和 helper/source SHA-256，不含 Key。重跑
在 source/helper/state 一致时复用 helper。Restore 只接受固定 8 名 allow-list，并在
其他删除成功后最后移除 ownership。

若存在非本项目 HKCU policy、有效的 HKLM 非更新 policy 或非空 configLibrary，
安装器停止而不覆盖。
