# P10A-0A Fast Lane operator bundle

This directory is development-only operator coordination material. It is not
loaded by `lib/bootstrap.ps1`, is not part of the product execution plane, and
must never enter a Release ZIP.

The Fast Lane uses one logical control plane backed by two physical private Git
repositories:

- `host-to-vm`: only `HostCoordinator` can append; `VmTester` is read-only.
- `vm-to-host`: only `VmTester` can append; `HostCoordinator` is read-only.

The repository pair is intentional. Git repository credentials are not
path-scoped, so a shared writable credential for two directories would violate
the frozen relay contract. A future single-repository deployment is allowed
only when two independently authenticated GitHub Apps or an equivalent narrow
relay service enforce the directional write boundary.

Every message is canonical JSON and belongs to one immutable hash chain. A
consumer validates schema, role, sequence, previous-message hash, expiry,
exact input bindings, transition, and diagnostic-only status before exposing a
small structured result to Codex. Message payloads and free text are never
executed as commands.

The two automation prompts in `prompts/` are templates. Deployment replaces
only logical repository and local checkout tokens; credentials stay in each
machine's secure credential store and never enter a prompt, repository, report,
or Codex conversation.

Current deployment state (2026-07-15):

- Product code: `LXZ56156/claude-desktop-deepseek-installer` (private).
- Host to VM: `LXZ56156/cddsi-host-to-vm` (private, `outbox/` initialized).
- VM to host: `LXZ56156/cddsi-vm-to-host` (private, `outbox/` initialized).
- Host Codex heartbeat: `cddsi-fast-lane-hostcoordinator-minute-poll`, paused
  until a narrow HostCoordinator credential and append-only server protection
  are verified.
- VM Codex task: not created; it must be created from the VM Codex device after
  its read-only product identity and single-direction writer identity pass
  negative permission tests.
- GitHub rejected private-repository rulesets for the current account plan.
  The repositories remain private; force-push/deletion protection is therefore
  an open fail-closed deployment gate rather than a policy downgrade.

The VM reset contract is limited to resources with exact project ownership
receipts. Missing receipts, baseline drift, unknown mutation, or uncertain
VMP/reboot/uninstall/compensation state returns `BLOCKED` and requests an
external snapshot restore. A Fast Lane `CLEAN_READY` or `PASS` is diagnostic
only and cannot freeze P10A facts or satisfy P11.
