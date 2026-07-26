# Implementation plan

## 当前

- 5 模块 practical runtime 已接线。
- Git、Claude、DPAPI helper、HKCU config、diagnose、restore 已实现。
- snapshot/evidence/operator 和重复门已从当前树删除。
- Host focused gate 通过后推送唯一 PR。

## 下一步

1. 在 clean disposable VM 跑无 Git/无 Claude happy path。
2. 验证真实 DeepSeek Chat、rerun 和 restore。
3. 对第一个可复现失败做最小补丁和一个聚焦回归。
4. 重建 ZIP，从 clean snapshot 重测。
5. 重复到常见 Windows 11 场景稳定。

## 可选后续

只有用户明确需要且基础路径稳定后，才单独设计 machine-wide Claude、VMP/restart 和
Cowork。它们不得反向阻塞当前 Chat practical release。
