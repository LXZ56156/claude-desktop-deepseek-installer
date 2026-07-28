# External contracts

## Git for Windows

- Metadata：`https://api.github.com/repos/git-for-windows/git/releases/latest`
- 只接受非 draft、非 prerelease、`immutable=true` 的正式 Windows tag。
- x64 installer URL 必须位于官方 `git-for-windows/git` release。
- GitHub asset `digest=sha256:...` 与 size 必须匹配。
- Authenticode 必须有效且 signer organization 为 Johannes Schindelin。
- 执行前重新计算 SHA-256；安装后验证签名后的常见 canonical `git.exe` 和版本。

## Claude Desktop

- x64 MSIX：`https://claude.ai/api/desktop/win32/x64/msix/latest/redirect`
- 最终 HTTPS host 必须是 `downloads.claude.ai` 且路径属于 win32/x64 MSIX。
- Authenticode 必须有效且 signer 为 Anthropic, PBC。
- `AppxManifest.xml` identity 必须是 `Claude`、x64，publisher 与 signer subject 一致。
- 安装前重新哈希，使用 `Add-AppxPackage` 为当前用户安装并按 publisher/version readback。

官方 Windows 部署说明：
<https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows>

## Claude third-party configuration

HKCU/HKLM precedence、REG_SZ、helper 和 model schema：
<https://claude.com/docs/third-party/claude-desktop/configuration>

Credential helper：
<https://claude.com/docs/third-party/claude-desktop/credential-helper>

## DeepSeek

Anthropic-compatible base URL、x-api-key 和当前模型：
<https://api-docs.deepseek.com/guides/anthropic_api/>

这些合同会变化。VM 若观察到官方 metadata/schema 漂移，先核对官方文档，再做最小
兼容补丁；不得通过关闭签名、publisher、hash 或 source 检查来“修复”。
