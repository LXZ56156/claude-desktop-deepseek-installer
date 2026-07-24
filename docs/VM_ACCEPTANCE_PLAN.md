# 后续虚拟机 Codex 验收计划

更新日期：2026-07-24

## 状态

本计划只定义最终冻结候选的全面产品 Live 验收。D-026 在它之前增加可写的
`VmDevelopment` lane：VM Codex 可以在 disposable VM 中修改现有开发分支的源码、
测试和文档，反复执行真实安装、配置和 GUI 场景，直到用户路径收敛。该开发结果
本身不是最终验收；进入本计划前，必须从 clean commit 构建并冻结 P10B 两套候选。

本计划对两个候选的精确字节执行全面产品 Live，包括 VMP、重启、API、Claude
配置、Desktop 进程和 Chat/Code/Cowork。正式验收 lane 恢复为只读：源码 checkout
只读或不存在，VM 不得编辑源码、测试期望、ZIP、sidecar 或 runbook。任何失败都
回到 `VmDevelopment` 修复，并从新 commit 重建新候选；任何真实操作都不得发生在
宿主机或 CI。

`VmDevelopment` 期间，VM Codex 是现有开发分支/PR 的临时唯一写入者，宿主机停止
写入；只允许普通 fast-forward commits，不得 force push 或创建重复 PR。候选冻结后
该写入租约结束，最终验收只消费精确 artifact bytes/hash。

历史 Fast Lane、relay、outbox、Automation、scheduler 和旧 onboarding 不再是当前
开发或验收前置，不得恢复。其 retained evidence 只能作历史诊断，既不阻断本计划，
也不能伪造为真实用户路径、Computer Use、clean snapshot 或候选 PASS。

## 进入条件

P11 VM 阶段只有在以下条件全部满足后开始：

- `IMPLEMENTATION_PLAN.md` P0-P10B 完成。
- 完整 L0-L4 质量门通过。
- `VmDevelopment` 已在每个声明支持的环境或可验证等价 clean snapshot 上走通真实
  用户入口：安装、配置、重复运行、必要重启、Repair/Restore 和三项 surface。
- P10A evidence 已由受信外部 CAS 提交，消费与事实冻结 receipt 均可验证。
- P10B 已冻结 `VmAcceptance` 与待发布 `UserLive` 两套 ZIP；各自的 SHA-256、内容
  摘要、版本、commit 和 detached signed sidecar 均已生成。
- live adapter 在宿主机从未执行。
- 最终验收请求已绑定两个候选的精确字节、SHA-256、sidecar、runbook 和固定 VM
  snapshot receipt；不得通过移动分支头、历史 relay 消息或开发 checkout 替换。
- VM runbook、预置故障注入 fixture、允许变更清单、停止线、资源级补偿矩阵和
  有效期有限的 `VmAcceptance` operation grant 已经冻结。
- 用户准备专用、可撤销、限额的 DeepSeek 测试 Key，并只在 VM 本地遮罩式安全
  输入面输入；Key 不得进入 Codex prompt/chat、argv、环境变量、fixture 或 evidence。
- Computer Use 可用，并已冻结 Chat、Code、Cowork 的可见成功判据、允许的专属
  测试目录和截图脱敏规则。

## VM 隔离

- 每个正式 P11/里程碑场景由 VM 外部的 hypervisor supervisor 恢复固定 Windows
  快照并签发 receipt；VM Codex 不能恢复自身正在运行的整机快照，也不能自证
  “已干净”。VMP/重启/卸载、补偿未知、baseline drift 或 guest reset 失败也必须
  返回由外部 supervisor 恢复快照的正式流程。
- 使用独立测试用户，不复用宿主 Microsoft/Anthropic/Git 凭据。
- 默认关闭共享剪贴板、共享用户目录、浏览器资料、自动登录和可写映射盘。
- Release ZIP 通过一次性 ISO、只读共享或经 hash 校验的受控传输进入 VM。
- 不把 API Key 放入 Codex 对话、脚本参数、环境变量、文件 fixture、宿主剪贴板、
  截图或报告。需要 Key 时，由用户直接在 VM 本地遮罩式输入面完成。
- 非正式的日常修复重测可按冻结 runbook 做 deterministic guest reset：只卸载本项目
  产物，清除项目拥有的 HKCU policy、credential、checkpoint 和 ownership
  marker/token 匹配的 `cddsi-vm-test-<GUID>` 目录，再核验 baseline。该结果不能替代
  正式 P11 的 clean-snapshot 证据。
- 每个正式场景结束后导出脱敏证据并由外部 supervisor 恢复快照。
- 最终验收 VM 不得拥有产品 branch write workflow；即使本机还留有开发凭据，也
  不得在该轮 commit、push 或修改任何候选输入。

## 首版矩阵

### 固定镜像

P10 生成 runbook 时必须把表中的 `<UBR>`、镜像 SHA-256、SKU、语言、补丁日期、
虚拟化能力和 Desktop/MSIX 精确版本替换为具体值；存在占位符不得开始 P11。

| ID | 固定 OS 基线 | 用途 |
|---|---|---|
| W11-24H2 | Windows 11 Pro 24H2 x64，`26100.<UBR>` | 主发布矩阵；nested virtualization 已验证 |
| W10-22H2 | Windows 10 Pro 22H2 x64，`19045.<UBR>` | 最低兼容矩阵；记录其生命周期状态，不外推其他 build |

每个镜像从干净快照派生以下场景，不把“19041+”当作可执行测试环境：

- VMP 已启用；VMP 未启用并覆盖重启续跑。
- 管理员启动；标准用户启动并按 runbook 处理 UAC。
- Git 已安装、未安装和版本不合格。
- Claude Desktop 未安装、安装固定旧版和安装固定当前版。

产品支持声明仍以官方最低合同为起点，但只把实际固定镜像的结果写成已验证。
Arm64 在具备真实设备或可靠环境后加入，不阻断首个 x64 Release。

### 必需场景

- 全新安装。
- 重复运行与幂等。
- Desktop 升级。
- Git ensure：合格版本复用，缺失、过旧或损坏时安装/升级。
- Git 多路径歧义和非 Git for Windows 身份安全阻断。
- 用户拒绝 Git/UAC/PATH 必要确认时返回 `CANCELLED`，不得继续为 Chat-only 成功。
- 用户拒绝 VMP/重启时保留安全完成部分，但总结果只能
  `PARTIAL/ACTION_REQUIRED`。
- VMP 启用和重启后 checkpoint 续跑。
- P10 冻结的唯一 MSIX scope，以及相反范围既有安装的冲突阻断。
- 已有 HKLM/HKCU/local 配置冲突。
- 正确、错误和撤销的 API Key。
- 断网、超时、截断下载和错误重定向。
- MSIX/Git hash、签名、Publisher、identity 失败。
- helper 超时、非法输出、损坏 DPAPI blob。
- 固定 `RequestedSurfaces=Chat,Code,Cowork`，没有功能选择页。
- Chat、Code、Cowork 的 readiness 与 UI 证据分别成功/失败/NOT_TESTED。
- Computer Use 真实打开 Claude Desktop，分别验证 Chat 回复、Code 在专属目录
  创建预期文件、Cowork 在专属目录完成预期任务；单纯进程启动或 readiness
  `READY` 不能替代 UI PASS。
- 修复、恢复和中途失败的资源级补偿。
- 中文、空格和特殊字符安装器路径。

断网、TLS、重定向、截断下载、坏 hash、坏签名、helper 异常和部分写入只能通过
P10 已审查、固定 hash 的 fixture/provider 注入。VM Codex 不得临场修改 hosts、
系统代理、证书存储、安全策略或 ZIP，也不得临时下载新的故障工具。

## 资源级补偿边界

VM 验收不得把“恢复”解释为整机事务回滚：

| 资源 | 目标状态 | 允许报告 |
|---|---|---|
| 项目拥有的 HKCU policy、credential blob、状态和备份 | 精确重建安装前值/类型/所有权 | `FULL` 或 `FAILED` |
| 本次全新安装且确认无共享依赖的 Desktop/Git | 仅按固定 runbook 尝试官方卸载 | `FULL`、`PARTIAL`、`UNSUPPORTED` |
| 既有 Desktop/Git 的升级 | 不承诺自动降级 | `PARTIAL` 或 `UNSUPPORTED` |
| VMP、共享服务、系统 PATH | 不自动撤销可能被其他软件使用的状态 | `PARTIAL` 或 `UNSUPPORTED` |

安装器和验收报告必须逐资源给出状态，不能用单一“已回滚”掩盖部分补偿。

## 基线

每个场景开始前，VM Codex 记录仅限 VM 的脱敏基线：

- AppX package、版本和安装范围。
- Claude managed policy 的键名/类型摘要，不输出 Key。
- VMP、硬件虚拟化、相关服务状态。
- Git 版本、PATH 摘要和全局配置 hash。
- 允许目录清单。
- `.claude\settings.json` 零访问证据：不定位、不 `Test-Path`、不枚举、不哈希，
  只由 provider/ledger 和静态门证明没有访问。
- Claude 进程和安装器状态。

该基线政策只适用于 disposable VM，不能反向授权宿主机读取同类资源。

## Codex Runbook

未来应单独生成 VM 专用交接文件。VM Codex 无产品仓库写权限，不拉取源码分支来
替换候选，只消费 `TEST_REQUEST` 指定的精确 artifact bytes/hash，并按以下顺序执行：

1. 验证 VM 身份、外部 snapshot receipt、测试用户、两个 ZIP、embedded content
   manifest、detached signed sidecar 和 SHA-256。
2. 验证 `VmAcceptance` operation grant 的机器/用户/artifact/profile/场景/有效期
   绑定；普通环境变量或命令行开关不能代替 grant。
3. 记录基线和本场景允许变更清单。
4. 仅对故障矩阵使用 `VmAcceptance` ZIP，以真实用户方式双击中文入口。
5. 只处理 runbook 明确允许的 UAC 和重启。
6. API Key 由用户在 VM 本地遮罩式安全输入面输入；VM Codex 和 Computer Use
   不读取、回显、截图或复制该值。
7. 验证首次启动跳过 Anthropic 登录和 Developer Mode。
8. 使用 Computer Use 观察 Chat 返回唯一 `CHAT_OK_<runId>`。
9. 使用 Computer Use 观察 Code 只在专属目录创建 `CODE_OK_<runId>.txt`。
10. 使用 Computer Use 观察 Cowork 只在专属目录创建
    `COWORK_OK_<runId>.txt`。
11. 扫描日志、状态、报告、截图和临时目录中的 secret。
12. 对比基线，只允许 manifest 声明的变化。
13. 执行修复/恢复，并逐资源验证补偿状态。
14. 请求外部 hypervisor supervisor 恢复干净快照并取得新 receipt；随后使用待发布
    `UserLive` ZIP 的精确字节执行最终 happy path、重复运行、首次启动和 secret
    smoke；不得用 `VmAcceptance` 结果代替。
15. 生成分别绑定两个 artifact hash 和 snapshot receipt 的脱敏证据包，关闭场景并
    请求外部 supervisor 恢复快照。

## 证据

每个场景产生：

- 场景 ID、runId、Windows/Desktop/installer 版本。
- acceptance request/candidate ID 和外部 snapshot receipt 的 hash/引用。
- artifact profile、ZIP hash、embedded content digest 和 sidecar 验证结果。
- 固定 RequestedSurfaces、派生 EffectiveSurfaces、MSIX scope 和 Git ensure 结果。
- 运行/能力/UI 证据三层状态。
- 允许变更与实际变更 diff。
- MSIX/Git 签名和绑定证据摘要。
- checkpoint/restart 结果。
- Chat/Code/Cowork 的独立状态。
- Computer Use 的逐 surface 判定、可见状态摘要和已脱敏截图引用。
- 每项资源的 compensation/restore 状态。
- secret scan 计数。
- 脱敏截图或日志引用。

只导出脱敏摘要；不导出 Key、DPAPI blob、原始 policy 值、用户资料或 VM 磁盘。
历史 relay/`TEST_RESULT` 即使仍存在，也只能作不可信诊断引用；正式通过必须由受信
validator 消费精确候选、CAS、签名与 snapshot/acceptance receipt，不能由消息自证。

## 停止线

VM Codex 遇到以下情况立即停止当前场景，不自行扩大权限或绕过：

- Release hash 不匹配。
- 签名、Publisher、identity 或来源不匹配。
- 需要修改 runbook 未授权的系统/用户资源。
- 发现宿主共享目录可写或 Key 可能离开 VM。
- 需要关闭宿主进程、修改宿主配置或访问宿主凭据。
- 需要编辑源码、ZIP、runbook、fixture，或跟随移动分支头替换本轮候选。
- 需要把正式验收切回可写 `VmDevelopment` checkout，或发现候选测试期间发生
  任何源码/测试/候选字节变化。
- 资源级补偿证据不足。
- operation grant 或 sidecar 缺失、过期、范围不符。
- UI 与固定版本预期显著不同。
- 任意 secret 泄露。

## 通过标准

- 必需矩阵全部记录运行、能力、UI 证据三层状态；Release happy path 的 UI 必需项
  为 PASS，预期阻断场景必须命中指定非成功状态。
- 首次启动无需 Developer Mode 或 Anthropic 登录。
- happy path 没有功能选择页，Git ready，Chat、Code、Cowork readiness 全部 READY，
  Computer Use UI 证据分别 PASS。
- 阻断/取消场景返回预期 `PARTIAL/ACTION_REQUIRED/CANCELLED/FAILED`，绝不静默
  关闭 Code/Cowork 后报告成功。
- 重启续跑、重复运行、失败补偿和恢复按资源矩阵通过。
- 未授权资源变更为零。
- secret findings 为零。
- 每个对外声明支持的固定环境都从干净快照可重复得到相同结果；没有对应镜像时
  必须收窄支持声明，不得用单一 VM 外推。
- 待发布 `UserLive` ZIP 的精确 SHA-256 与最终 smoke 证据一致。
- 外部 snapshot receipt、受信 CAS、签名与 exact acceptance receipt 均有效；relay
  ACK 或 `TEST_RESULT` 不计为上述任一证据。
- 正式 P11 PASS 必须绑定 clean-snapshot receipt；日常 guest-reset 重测只能产生
  诊断结果，不能提升为正式通过。

VM 失败后必须结束本轮只读验收，返回可写 `VmDevelopment` 修复、运行完整门并
提交；随后为新 commit 重新冻结 P10A 输入/事实，再由 P10B 重建并签名新的
`VmAcceptance` 与 `UserLive` 候选，以新 candidate ID/hash 发起下一轮验收。开发
lane 的 PASS 不能晋升为正式通过；验收 lane 也不得
临时修改 ZIP 或源码后继续把原版本标成通过。最终通过只说明候选可以提交 P12
人工决定；P12 只能发布证据中已经测试过的 `UserLive` 原字节，不得自动 merge、
promotion 或 release。
