# Decisions

## D-027-P1 — Happy path first

2026-07-27，用户要求停止先建大规模证明框架。完成定义收敛为大多数 Windows 11 x64
用户能安装可信 Git、官方最新版 Claude、配置 Key 并完成真实文本 Chat。之后只补 VM
复现出的失败。

## D-027-P2 — External snapshot, not product authorization

Clean disposable VM snapshot 是测试操作前置，不是最终用户运行时 RSA/receipt 门。
snapshot authorization、CAS-style binding、relay/outbox/Automation 和 P10 系列退役。

## D-027-P3 — One practical runtime

运行时固定为 5 个模块、3 个动作和 6 个 wrapper。拒绝通用 provider/ledger/stage
抽象。质量门固定为一次 PS5.1 Pester + parser + Release DryRun + diff check。

## D-027-P4 — Per-user MVP

Claude 首版使用官方 per-user x64 MSIX。machine-wide provisioning、VMP、重启和 Cowork
是独立后续，不是当前 Chat happy path 阻塞项。

## D-027-P5 — Keep essential security

简化不删除 Key 隔离、官方来源、Git digest、预期 signer/publisher、执行前重哈希、
HKCU ownership/readback/rollback、Restore allow-list 和 `.claude\settings.json` 零访问。
