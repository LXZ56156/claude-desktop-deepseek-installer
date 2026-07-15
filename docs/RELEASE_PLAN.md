# Release 计划

更新日期：2026-07-14

## 当前状态

项目还没有可发布安装器。`build-release.ps1 -DryRun` 只验证白名单和安全合同，
不生成对外 Release。P10 构建候选，P11 验证精确字节，P12 才允许发布。

## 分发原则

- Release ZIP 只包含 `scripts/release-manifest.psd1` 的 `PackageFiles`。
- Claude Desktop MSIX 与 Git 安装器在运行时从官方来源获取，不重新打包分发。
- 不包含 tests、CI、开发文档、`.dev`、日志、状态、备份、报告、缓存或凭据。
- 不修改、解包再封装或汉化上游签名二进制。
- 每个 Release 都能从一个干净 commit 重现。

## 构建阶段

1. **源树冻结**
   - 工作树和 submodule 状态明确。
   - VERSION、CHANGELOG、许可证和决策状态一致。
   - 公开函数、defaults、fixtures 与文档同步。
2. **源树扫描**
   - 严格 UTF-8/编码与换行。
   - secret、private key、Authorization、真实路径和运行产物扫描。
   - 二进制文件只允许来自精确 manifest。
3. **白名单复制**
   - 仅复制 PackageFiles。
   - staging 位于构建器拥有的唯一临时目录。
   - 每个文件 hash 与源树绑定。
4. **Staging 二次扫描**
   - 重复 secret、编码、禁止路径和二进制策略检查。
   - 不允许 development-only 文件。
5. **ZIP 构建**
   - 固定条目名和可复现时间/排序策略。
   - ZIP 条目集合与 manifest 精确相等。
6. **解压仿真**
   - 解压到包含中文、空格、`&`、`!` 和括号的路径。
   - 只运行 TestSafe/HostSandbox。
7. **产物证据**
   - ZIP SHA-256。
   - 文件清单、版本、commit、构建环境和质量门摘要。
   - SBOM 或脚本依赖清单。
   - embedded content manifest 与 detached signed sidecar。embedded manifest
     绑定排除其自身/签名的 content digest；sidecar 绑定最终 ZIP hash、profile、
     version、commit 和 content digest。
   - manifest 从 sidecar 外部固定 signer 证书/public-key 指纹、request ID 与 nonce；
     sidecar 携带实际 X509 DER 和 RSA-PSS-SHA256 签名字节并执行真实公钥验签。
     signer 自报时间不冒充 RFC3161 可信时间戳。

P10 构建两个冻结产物：

- `VmAcceptance`：用于 VM 故障矩阵，要求一次性 operation grant，不对外发布。
- 待发布 `UserLive`：带最终版本号但保持未发布；P11 在干净 VM 测试其精确字节。

## 上游 artifact 策略

运行时下载的 MSIX/Git 必须：

- 来自 `EXTERNAL_CONTRACTS.md` 允许的官方元数据入口。
- 下载到本次运行独占目录。
- 绑定 artifact type、绝对路径、SHA-256、架构和来源。
- 验证 Authenticode、可信链、Publisher 和 package identity。
- 安装前重新计算 hash 并复核签名，防止 TOCTOU。
- 不提供 skip/bypass 参数。

Release 不固定未经实物验证的 signer/identity；它应携带版本化信任策略或受签名
的官方元数据解析器，并对未知变化 fail closed。

## Helper 和二进制

Credential helper 已由 D-010 冻结为签名的 .NET EXE：

- 源码、工具链和依赖必须可复现。
- helper 本身签名并进入精确 manifest。
- 建立 SBOM、静态扫描、恶意软件扫描和二进制内容策略。
- Claude 配置引用绝对路径，并校验文件 hash/signature。
- 更新或卸载必须处理旧 helper 和 DPAPI blob。
- helper 必须消费 `CLAUDE_HELPER_CONTEXT`；`mid-session-refresh` 的有效超时为
  20 秒，其他已知 context 为 60 秒，所有 context 均不得提示或阻塞等待输入。

没有完成上述流程前，不得把临时本地二进制放进 Release。

## Release Gate

候选版本必须同时满足：

- PowerShell 7 和 Windows PowerShell 5.1 的全部 L0-L4 质量门。
- HostSandbox 中产品 live/process/network/registry 和外部写入为零；trusted
  harness 调用与声明精确一致。
- 全部故障注入、回滚、重复执行和 secret 扫描通过。
- PackageFiles 与 ZIP 条目精确一致。
- 中文特殊路径仿真通过。
- 许可证版权主体已确定。
- 外部合同重新核验并记录日期。
- 固定 all-surfaces profile；不存在 capability selector 或 Chat-only 成功路径。
- Git ensure、三项 readiness、分层状态和“禁止静默降级”矩阵通过。
- 本 Release 的唯一 MSIX scope 已由固定版本 VM 证据冻结，无运行时 fallback。
- 形成 VM 专用 runbook 和候选 ZIP。
- 生成随包 `USER_GUIDE.md`、`TROUBLESHOOTING.md`、`PRIVACY.md` 或等效用户
  文档，并加入 PackageFiles。

候选版本仍不是正式发布。P11 必须同时验证 VmAcceptance 与待发布 UserLive 的
精确 hash；P12 只上传已测试的 UserLive 原字节。

## 版本和变更

- 开发期使用 `0.x.y-dev`。
- VmAcceptance profile 使用内部候选标识，不作为公开版本。
- 待发布 UserLive 在 P10 就冻结最终语义化版本号和 ZIP 字节，P11 后不得从
  `rc.N` 重建成另一个 ZIP。
- 外部配置 schema、状态 schema 或恢复格式的不兼容变化必须提高相应 contract
  version，并提供迁移或 fail-closed 行为。
- 每次发布记录支持的 Desktop、Windows、DeepSeek 合同和已知限制。

## 发布物

最终至少包括：

- 安装器 ZIP。
- ZIP SHA-256。
- 中文 Release Notes。
- 支持矩阵和已知限制。
- 上游下载与信任策略说明。
- 脱敏的 VM 验收摘要。
- 修复、恢复和卸载说明。

不得发布真实测试 Key、VM 磁盘、用户截图、原始日志或可恢复凭据备份。

## 回滚与支持

- 安装器必须保留项目自身配置的可恢复备份和所有权记录。
- 上游 MSIX/Git 的回滚能力要与官方支持范围一致，不伪造降级。
- VMP、PATH、machine-wide package 等共享资源使用 `FULL/PARTIAL/UNSUPPORTED`
  补偿矩阵，不承诺自动恢复整个系统。
- 支持报告只使用脱敏快照；快照不能恢复。
- 失败的 Release 必须撤回下载入口并保留 checksum/版本说明，不能复用同一版本号
  静默替换 ZIP。

## 发布前未决项

- MIT copyright holder。
- MSIX/Git 精确 signer、identity 和元数据稳定性。
- helper 源码、固定 .NET 工具链、依赖锁、SBOM、实际 PE 与签名服务。
- Standard/Offline MSIX。
- `disableDeploymentModeChooser` 和 HKCU helper 的 VM 实物行为。
- Anthropic 与 DeepSeek 的分发/商业条款复核。

## P12 不可变晋升

P12 不是重建步骤：

1. 从 P11 evidence 读取待发布 UserLive ZIP SHA-256。
2. 本地文件、detached sidecar 和上传后下载文件必须完全匹配。
3. 发布 Release Notes、checksum、支持矩阵和脱敏验收摘要。
4. 不修改 ZIP、VERSION、CHANGELOG 或内含文件。
5. 任何字节变化都生成新版本并返回 P10/P11。
