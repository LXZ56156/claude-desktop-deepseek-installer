# D-027 practical handoff

## Binding

- Branch: `codex/repair/p10a-0a-fast-lane`
- PR: <https://github.com/LXZ56156/claude-desktop-deepseek-installer/pull/1>
- Simplification base checkpoint: `58e46d40ad32d67e636b2ac6402a38b7f8342bd9`
- Base tree: `d3b87a30dd871ddeda2b3b5ef4a4ac6d32c41d27`

宿主机在开始修改前已 fetch 并确认 local/remote/PR 与以上 checkpoint/tree 一致且
worktree/index clean。2026-07-27 用户明确授权宿主机改为 practical happy-path-first；
旧 VM exclusive-write、D-026、P10、relay 和 evidence 路径不再继续。

## Current implementation

- `Start-Here.ps1` 默认 DryRun；六个 `.cmd` 为 Live 用户入口。
- Git：可信 canonical reuse；否则官方 immutable metadata、size/SHA-256、预期 signer、
  pre-exec rehash、UAC silent install、readback。
- Claude：官方 x64 endpoint、bounded download、Anthropic signer、manifest identity /
  publisher、pre-install rehash、per-user AppX、publisher/version readback。
- Key/config：遮罩输入、DPAPI CurrentUser、无参数 helper、8 个 HKCU REG_SZ、ownership、
  update snapshot/readback、聚焦诊断和 allow-list restore。
- Runtime 5 个模块；Pester 2 个文件；Release 22 个文件。

本文件不声称 VM 已验证。宿主机门通过后状态为
`HOST_PRACTICAL_GATE_PASS_AWAITING_VM_HAPPY_PATH`。

## Next action

按 `VM_ACCEPTANCE_PLAN.md` 从 clean Windows 11 x64、无 Git、无 Claude 开始。用户只在
VM 遮罩输入框输入 Key。先要求真实 Chat、诊断、rerun、restore；遇到具体失败才返回
宿主机补丁。

Cowork machine provisioning/VMP 不属于这一轮完成门。不要恢复 snapshot RSA、
P10A/P10B/P11、relay/outbox/Automation、worker/shard 或 historical diagnostics。
