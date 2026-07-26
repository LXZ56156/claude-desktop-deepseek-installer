# Security

## Key

- 只从 `Read-Host -AsSecureString` 取得。
- 只接受 8–4096 个可打印非空白 ASCII 字符。
- 转换缓冲区使用后清零；持久副本仅为 DPAPI CurrentUser 密文。
- 私有目录/文件 ACL 只授予当前用户、SYSTEM 和 Administrators。
- helper 不接受参数或环境中的 Key，不写 stderr，不写文件，stdout 只有 token。
- 安装器不做会把 Key 放入 HTTP 调试/错误的远程预检。

## Supply chain

- Git 有官方 immutable metadata SHA-256；下载长度有上限，执行前重新哈希。
- Claude endpoint 当前不发布独立 digest，因此使用官方 HTTPS host、bounded download、
  有效且预期的 Anthropic Authenticode、manifest identity/publisher 和安装前重哈希。
- 任意有效签名、任意 PATH `git.exe` 或同名 AppX 都不被当作可信。

## Configuration ownership

- 不访问 `.claude\settings.json`。
- HKLM、其他 HKCU 或 configLibrary 冲突时不覆盖。
- 新建目录拒绝 reparse point；已有非 ownership 产品目录拒绝接管。
- policy 写入后检查值与 REG_SZ 类型；更新失败恢复目标值快照。
- Restore 的 state 名称必须精确属于固定 allow-list，ownership 最后删除。

## Remaining limitations

- 安装器可控制自己的持久 Key 副本，不能承诺 Claude 运行时永不创建临时凭据文件。
- per-user MSIX 不等同于 machine-wide Cowork 支持。
- 首个 practical 版本依赖 disposable VM 发现代理、AppLocker、企业 policy 等真实差异。
