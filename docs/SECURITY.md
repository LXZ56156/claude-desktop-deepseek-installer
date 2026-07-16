# 安全设计

更新日期：2026-07-17

## 安全目标

- 默认拒绝真实系统修改。
- 宿主机开发测试不接触真实用户配置或系统资源。
- 安装只消费完整、当前、路径绑定的官方 artifact 验证证据。
- API Key 不进入不允许的持久面或可分享证据。
- 项目拥有的 policy、credential、state 和备份在任何写入失败点可精确恢复；
  共享系统资源使用显式补偿矩阵，不承诺整机事务式回滚。
- 未测试能力不能被报告为成功。

## 执行许可

执行模式为 `TestSafe`、`DryRun`、`Live`：

- 默认 `TestSafe`。
- TestSafe/DryRun 的潜在修改操作必须 `Changed=false`。
- 环境变量不能单独授权真实操作。
- Live 需要独立确认、适用 stage、ExecutionContext 和 operation-specific grant。
- 当前 `Scaffold` 阶段无条件拒绝 Live。
- 开发机和 CI 即使代码未来实现 Live，也不得加载或执行 live provider。
- 首次真实系统操作只允许在 `VM_CALIBRATION_PLAN.md` 的 P10A 专用 disposable VM
  中由限域 calibration runner/provider 执行；它只采集冻结候选前所需事实，不是
  全面产品 Live，也不得加载宿主机 Live provider。
- P10A evidence 必须经受信外部 CAS 原子提交并冻结事实，随后才可构建 P10B 双
  候选；对候选精确字节的首次全面产品 Live 只在 `VM_ACCEPTANCE_PLAN.md` 的 P11
  disposable VM 执行。
- stage/profile 来自完整性保护的 embedded manifest 与 detached sidecar，不由
  环境变量或普通命令行开关单独授权。VM grant 绑定候选 hash、runId、operation、
  expiry 和交互确认，但不冒充 OS 级 VM 身份证明。
- `VM_TEST_RELAY.md` 定义的 monitor/control repo 属于独立 operator coordination
  plane，不扩展产品 Live 权限，也不能用消息、通知或 automation 绕过 grant。
- 截至 2026-07-16，`config/fast-lane-policy.psd1`、`lib/vm-test-relay.ps1`、
  `lib/vm-fast-lane-readiness.ps1`、`lib/vm-reset.ps1` 和 `operator/fast-lane/*` 已实现
  DevelopmentOnly 的固定 Git transport、确定性 onboarding、VM-only reset 边界与
  synthetic 演练。它们不进入 bootstrap、ProductCore 或 Release；也不因代码存在而
  获得宿主机 Live、VM product-write、remote credential 或无人值守执行授权。

## 宿主机保护

`TEST_ISOLATION.md` 是完整零接触合同。保护区包括真实 Claude/Claude Code/Git
配置、managed policy、Credential Manager、AppX、VMP、服务、任务计划、PATH、
进程和网络服务。

本地自动化不读取、Test-Path、枚举、哈希、备份、监视或修改这些资源。系统能力
必须经过不可缺省的 ExecutionContext/provider；缺 fake 时 fail closed。

P1 Sandbox Foundation 已完成；后续阶段必须持续保持该门全绿，不得增加宿主机
可加载的产品 live adapter 或 sandbox 外 I/O。P1 trusted harness 只可创建/清理
自有 sandbox，并启动精确 allow-list 的测试工具；其调用与产品 ledger 分开记录。

## 供应链

### 来源

- Claude Desktop MSIX 只接受 Anthropic 官方来源。
- Git for Windows 只接受 Git for Windows 官方来源。
- Release 默认不捆绑或重新分发上游安装包。
- URL、版本、架构和身份事实以 `EXTERNAL_CONTRACTS.md` 为入口。

### Git readiness 边界

Git 是产品必备前置，但“确保可用”不授权盲目重装：

- 只通过 provider 检查版本、Git for Windows 身份和唯一 canonical executable。
- 不读取或修改用户/系统全局 Git 配置。
- 合格且路径唯一时复用，`Changed=false`。
- 缺失、过旧或损坏时才进入已验签官方安装/升级合同。
- 多版本或 PATH 归属歧义时 fail closed，不猜测、不覆盖。
- 用户拒绝安装、UAC 或必要 PATH 影响时返回 `CANCELLED/ACTION_REQUIRED`，不得
  静默退化为 Chat-only 成功。

### 验签证据

下载、验证和安装是三个阶段。安装函数只接受包含以下字段的结构化证据：

- schema/contract version；
- artifact type 和架构；
- official source policy；
- canonical absolute path 与路径绑定 token；
- 当前文件 SHA-256；
- Authenticode status；
- 可信证书链；
- expected Publisher/signing identity；
- MSIX package identity 或 Git artifact identity；
- 生成时间和适用版本。

安装前必须对同一文件重新计算 SHA-256 并重验签名/身份。路径改变、文件替换、
时间过期、未知 signer 或 identity 全部 fail closed。不存在 bypass/skip 参数。

项目自身 Release sidecar 采用另一条精确合同：embedded manifest v2 从 sidecar
外部固定证书/public-key 指纹、Subject、KeyId、request ID、nonce 与最大签名年龄；
sidecar v2 携带实际 X509 DER 和 RSA-PSS-SHA256 签名字节。验证器只在 canonical
claims bytes 公钥验签成功后接受，不能把调用者可重算的 SHA、`Valid=true` 或自报
证书身份当作授权。helper Authenticode、DPAPI、ACL 和 P10A 系统事实仍必须由后续
disposable VM 的受信 provider 产生实物 receipt；宿主机 synthetic evidence 不能
晋升为发布证据。

### 下载

- 唯一 owner-marked 临时目录。
- TLS、重定向域、大小、超时和内容类型限制。
- 部分下载不进入验证。
- cache 命中也重新验证。
- 错误响应正文不直接进入日志。

## API Key

- 不接受明文命令行参数、环境变量或配置文件导入。
- 不静默 Trim；拒绝空白、多行、控制字符和非法格式。
- 使用 SecureString 或不可序列化 credential handle。
- 明文只在安全输入、DPAPI adapter 和 helper stdout 的最短边界出现。
- 使用 DPAPI CurrentUser 与受限 ACL。
- Claude 配置只引用 credential helper，不包含 Key。
- helper 采用签名、固定工具链的最小 .NET EXE，不接受明文参数，不经 shell、不读
  stdin、不提示，stdout 不得被记录。
- helper 精确消费 `CLAUDE_HELPER_CONTEXT`；`mid-session-refresh` 最多 20 秒，其余
  已知 context 最多 60 秒，所有 context 的 stderr 必须为空。
- 日志、异常、ledger、状态、报告、截图和 Release 全量完整脱敏，不保留前后缀。
- 测试 Key 运行时分片构造，fixture 不包含看似真实的 token。

Credential helper 技术形态已由 `DECISIONS.md` D-010 冻结；实际源码、固定工具链、
SBOM、PE、签名身份和 VM provider receipt 仍是发布阻断项。

## 配置所有权

- 首版唯一写入面是当前用户 HKCU managed policy。
- HKLM 和 configLibrary 只检测；HKLM 存在时停止，因为它覆盖 HKCU。
- credential helper、TTL/timeout 和隐藏 chooser 使用 MDM-only 键，不得回退到
  configLibrary 明文 credential。
- 非本项目配置默认不覆盖。
- 写入前必须有可恢复备份和独立确认。
- HKCU registry 备份保留 value 类型和值；首版没有 configLibrary writer。
- 恢复后必须重读验证。
- 恢复失败不得继续启动或验收。

## 备份与快照

- 可恢复备份可能含敏感材料，必须 DPAPI/ACL 保护。
- 脱敏快照可分享，但永远不能作为恢复源。
- 状态只记录 backup ID/hash/target metadata。
- DPAPI blob 不跨用户、机器或 VM 声称可恢复。
- owner、expiry 和清理失败必须有稳定错误。
- Fast Lane 日常开发重测只允许按冻结 allow-list 做 deterministic guest reset：
  卸载本项目产物，清除项目拥有的 HKCU policy、credential、checkpoint 和
  owner-marked 目录，再核验 baseline。该 lane 不以 WORM、message signing 或每轮
  snapshot 为前置，结果只用于诊断。
- Formal Lane 的 P10A/P11 正式证据必须由外部 hypervisor supervisor 恢复固定快照
  并出 receipt，再由独立 CAS/receipts/signatures 验真。VMP/重启/卸载、补偿状态
  未知、baseline drift 或 reset 失败必须升级到 Formal Lane。VM Codex 不能恢复
  自身正在运行的整机快照；正式 P11 PASS 必须绑定 clean-snapshot receipt。

## 资源级补偿

- HKCU policy、项目 credential、state、helper 和本项目创建的临时资源要求精确
  恢复/删除。
- 新装 MSIX/Git 是否卸载、Desktop 升级是否可降级，必须服从上游支持和所有权，
  不能默认执行。
- VMP、PATH、服务和 machine-wide package 可能被其他软件使用，默认不自动反向
  修改；报告 `FULL`、`PARTIAL` 或 `UNSUPPORTED` 补偿状态并给出人工步骤。
- “修复/恢复”不能表述为整个 Windows 回到安装前。

## 重启和持久化

- checkpoint 在 VMP 修改前写入，不含凭据。
- 首版使用 `-NoRestart` 和用户重启后重新双击续跑。
- 不默认创建计划任务、RunOnce 或自动重启。
- 陈旧、损坏或 ownership 不匹配的 checkpoint 拒绝续跑。
- 清理只删除本项目拥有且 token 匹配的状态/临时资源。

## 进程和命令

- FilePath 与参数数组分离，不通过 shell 字符串拼接。
- Key 不进入 argv。
- 超时后处理进程树，stdout/stderr 先脱敏再进入结果。
- 不使用 `Invoke-Expression`、动态脚本下载执行或 `ExecutionPolicy Bypass`
  作为信任替代。
- Claude 关闭/启动需要独立许可，不能在诊断或配置读取中隐式发生。

## 日志、报告和隐私

- 默认中文脱敏报告。
- 不记录真实用户名、完整用户路径、代理口令、Key、Authorization、helper stdout、
  原始配置或 API 响应敏感正文。
- Finding 只记录 logical source、相对路径、行号/类型和固定脱敏占位。
- TestSafe/DryRun 文件日志只进入 owner-marked sandbox。
- 失败证据也必须通过 secret scan。

## Claude Code 配置

项目不定位、不 Test-Path、不读取、不哈希、不监视、不备份、不写入或删除
`%USERPROFILE%\.claude\settings.json`。这是冻结决策，不再保留“由本进程计算前后
hash”的矛盾要求。

后续 VM 可以对 VM 内 synthetic/测试用户范围建立基线，但不授权宿主机访问。

## 汉化

不修改 Claude MSIX/Electron 资源，不跳过应用完整性，不集成社区汉化补丁。
中文体验仅由安装器、提示、报告和文档提供。

## 双机 relay 威胁与防护

Fast Lane 的逻辑 control plane 与产品仓库分离。GitHub deploy key 是
repository-scoped、不是 path-scoped；因此 GitHub transport 不能用同一 repository
内的两个目录和两把 writable deploy key 声称精确方向隔离。当前冻结拓扑使用两个
物理单向 public protected repository：HostCoordinator 只写 host-to-VM repository，
VmTester 只写 VM-to-host repository，并分别只读另一方向。三个 repositories 与两个
control `outbox/` 已 bootstrap；三个无 bypass ruleset 已实际施加删除、非快进和线性历史
约束，但方向隔离 writer 凭据尚未发放。两端分钟级 Codex Scheduled Tasks 最终轮询 inbox；可增加低延迟
  watcher 触发受限 `codex exec`/resume，但 transport 和自动化均不进入产品信任根。

本地实现边界如下：

- `config/fast-lane-policy.psd1` 冻结产品 remote、两个 control repository、角色、
  reset 与禁止 promotion 的安全策略；
- `lib/vm-test-relay.ps1` 只做 canonical validation、双向身份、hash chain、CAS、
  单 active cycle、STOP 和状态迁移，没有 Git/network transport；
- `operator/fast-lane/invoke-git-outbox.ps1` 绑定固定 Git/SSH/key/known-hosts hash，
  清空继承环境并限制进程树、runtime、output 和 message 数量；它验证 repository
  数字/node identity、当前 protection evidence、pinned genesis、linear history 与
  fast-forward-only CAS，不解释 payload；protection evidence 还必须匹配隔离的
  operator trust root、owner marker、receipt-specific authority assertion、独立预置的
  assertion SHA-256/authority token 和 previous-receipt chain，不能由 relay、receipt
  或 state root 自举；state root 使用固定短叶名 `fl-<32 lowercase hex>`，Git
  long-path 支持只作为 command-local config 注入，失败信息不包含 stderr 或本地路径；
- `operator/fast-lane/build-vm-onboarding.ps1` 只在 owner-marked HostSandbox 从 clean
  exact commit 生成确定性 diagnostic ZIP，绑定 tree/blob/working bytes、工具 hash 和
  runbook。bundle 不包含 credential、用户路径或 Formal evidence；
- `lib/vm-reset.ps1` 只做 owner receipt、allow-list、baseline、升级判定和
  `CLEAN_READY` 的 pure/fake 合同；TestSafe/DryRun 使用 fake provider，Scaffold
  Live 在 provider dispatch 前 fail closed；
- VM-only reset dispatcher/provider 还要求精确 VM/device/command trust、preflight、
  postcondition 与 receipt 绑定；宿主机/CI、伪造上下文、未知 mutation 或里程碑场景
  在 mutation 前 fail closed 或升级外部 snapshot；
- 每次 VM reset Live authorization 还必须消费 supervisor 签发的 SYSTEM-owned one-shot
  anchor/grant pair。anchor 绑定 VM/image、consumer SID、grant id/path/hash、execution
  nonce 与本轮全部 trust/input；grant JSON 绑定 nonce、cycle/policy/plan/ownership/
  resource/control-auth/time。consumer 对 grant 只有 Read+Delete，且 supervisor ACL
  receipt 必须证明其不能在父目录 create/replace；provider 还会验证父目录 SYSTEM owner
  与无非受信 mutation ACE，并在注册 runtime 前独占复验、原子删除 grant。进程内标志、
  可写 grant 或仅自洽 hash 都不是防重放证据；
- `operator/fast-lane/*` 还包含固定 prompt 和 pure synthetic rehearsal。prompt 中不
  放 deploy key、token 或其他凭据；relay message、日志、Markdown 和模型自由文本
  全部是不受信数据，不能直接执行。

必须防御以下威胁：

- VM 获得产品仓库写凭据，或越权写宿主 outbox；
- 旧 cycle 重放、乱序/重复消息、moving-ref 或 candidate hash 替换；
- 把失败日志、markdown、issue 文本或模型输出当作可执行命令造成 prompt/command
  injection；
- API Key、Authorization、helper stdout、原始 policy 或用户路径进入 control repo；
- guest reset 漏项、baseline drift 或 VM 自报快照恢复，形成虚假 clean start；
- 把 relay ACK/`TEST_RESULT` 当作 CAS、签名、snapshot 或 P11 acceptance receipt；
- PASS 自动 merge、自动发布或越过 P12 人工门。

对应控制为：产品仓库 VM credential 必须只读，两个物理 control repository 分别
发放最小单向写权限；Fast Lane 消息至少绑定 CycleId、单调 sequence、前序 hash、
物理 repository/outbox identity、精确 commit/candidate 与内容 hash；free text 永远
只作为数据，runner 只执行冻结 allow-list；所有消息与附件先脱敏和 secret scan；
baseline 不一致即升级 Formal Lane。宿主机不得执行 product Live，VM 不得编辑、提交
或推送产品代码。Fast Lane 不把 WORM/message signing/snapshot 当作日常前置，也不
产生正式 evidence；Formal Lane 才由独立 CAS、签名和 receipt validator 判断。始终
禁止自动 merge/P12。Git 只是可替换 transport，不是证据信任根。

## 安全验证

每个真实操作未来都必须先覆盖：

- TestSafe、DryRun、Live 许可门。
- fake provider 和 access ledger。
- 失败注入、取消、超时、幂等和补偿。
- secret scan。
- 特殊路径和 reparse point。
- Release 白名单。
- disposable VM Live 验收。

## 当前阻断风险

- P1 已证明项目控制的本地自动化满足零接触合同，但 HostSandbox 不是 OS 权限边界；
  真实 adapter 和不受信任代码仍只能在 disposable VM 首次执行。
- P10B 新合同必须重新通过统一双引擎质量门；旧 P1/P2 数量不能代表当前全树。
- MSIX/Git 每版本 signer/identity 仍需 P10A VM 实物证据冻结。
- helper 形态已经冻结，但源码、工具链、SBOM、实际 PE、Authenticode/ACL/DPAPI
  provider receipt 和签名服务均未完成。
- P10A consumption、release facts 和候选冻结只能消费 store-issued CAS receipt；
  调用者可重算的 SHA 摘要不能证明提交或授权。
- detached sidecar 必须验证真实签名字节和外部固定信任身份；P11 receipt 不存在时
  P12 promotion 必须保持 fail closed。
- Fast Lane 本地 policy、relay/reset pure/fake contract、固定 prompt 和 synthetic
  rehearsal，以及固定 outbox/onboarding/VM-only reset 边界已实现。旧 commit
  `3e843912...` 曾完成 VM bootstrap finalization；当前 tracked 变更重新 finalization 前
  `CanStartVmBootstrap=false`，且 bootstrap 本身不足以宣称 P10A-0A 完成。
- GitHub Free public 迁移不是单纯配置切换：visibility/protection receipt、policy、
  readiness、outbox/onboarding、prompt/runbook 和测试合同已先升版；三仓随后一并公开，
  并以 ruleset/effective-rules receipt 验证服务端历史保护。产品 ruleset 为 `19068339`，
  host-to-VM 为 `19068292`，VM-to-host 为 `19068313`，均无 bypass actor。交互式 bootstrap
  admin 仍不得交给 automation。
- 用户已设置 `PrivacyDecision=ACCEPTED`、`HistoryRewrite=NO`、
  `ResidualPrivacyAudit=NOT_PERFORMED_ACCEPTED_RISK`。这些选择只接受存量个人/运营信息
  暴露，不放松 credential、Authorization、API key、未脱敏日志或配置进入 public outbox
  的禁令；不能依赖“仓库不易发现”保护 secret。
- 两个方向的最小角色凭据、VM 产品 remote 只读负向验证、real guest reset 证据、VM
  automation、安全启用两端 paused tasks、无人值守执行和外部 hypervisor receipt 流程
  仍未完成；这些证据完成前 integration 与双机自动闭环保持阻断。
- protection receipt 轮换必须 fail closed：先暂停消费者，由外部 provisioner 生成下一
  authority assertion 并把其 hash/token 写入固定 task binding，再允许恢复；自动化不得
  从新 receipt、relay payload 或旧本地 state 学习新的信任值。
- 首次 P10A、P10A 事实冻结轮、正式 P11 PASS 和发布里程碑必须由 VM 外部 supervisor
  恢复 clean snapshot 并签发 receipt，且 Formal Lane 使用独立 CAS 与签名。guest
  reset、Fast Lane PASS 或 control-repo commit 均不能替代。
- `disableDeploymentModeChooser`、Standard/Offline MSIX 的 VM 行为未验证。
- DPAPI 恢复材料生命周期和 ACL 尚未实现。
- LICENSE copyright holder 尚未确定。

这些风险未关闭前，Live 和正式发布保持阻断。
