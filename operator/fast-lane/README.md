# P10A-0A Fast Lane operator bundle

This directory is development-only operator coordination material. It is not
loaded by `lib/bootstrap.ps1`, is not part of the product execution plane, and
must never enter a Release ZIP.

The Fast Lane uses one logical control plane backed by two physical public Git
repositories:

- `host-to-vm`: only `HostCoordinator` can append; `VmTester` is read-only.
- `vm-to-host`: only `VmTester` can append; `HostCoordinator` is read-only.

Those are the only authenticated Git transport sender roles. A
`SNAPSHOT_READY` message is appended by `HostCoordinator` only after an
independent external verifier supplies the expected snapshot-receipt hash and
HypervisorSupervisor authority-binding token out of band. The relay
`SenderRole` never proves receipt authority. `STOP` is also transported by
`HostCoordinator` as a bounded forwarding action for a local human or external
supervisor decision; Human and HypervisorSupervisor are not Git sender roles.

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

`trust/github-known-hosts` freezes the three GitHub SSH host keys returned by
the official GitHub Meta API. Its SHA-256 is fixed in
`config/fast-lane-policy.psd1` and cross-bound to the onboarding inventory.
The onboarding manifest separately pins Git, OpenSSH, PowerShell 7, and Windows
PowerShell. Device-local deploy-key hashes are added only by provisioning
receipts and are never accepted from relay data.

The outbox state root is a direct child of the separately owner-marked operator
workspace and uses the exact short leaf `fl-<32 lowercase hex>`. This is
part of the Windows path-budget contract, not a relaxed ownership check. Git is
always invoked with command-local `core.longpaths=true`; no global Git setting
or inherited `PATH` is read or changed. A failed Git command exposes only its
per-run invocation ordinal and numeric exit code, never stderr or a local path.
The short repository-directory discriminator is only a cache locator; owner and
state records still bind the full repository identity and URI hash, so a path
collision fails closed.

A repository-protection observation is also untrusted input. The fixed outbox
runtime requires a separate operator-plane `control-protection-trust` root, an
owner marker, a receipt-specific authority assertion, and independently
provisioned expected assertion SHA-256 and authority-binding token. The
assertion binds repository numeric/node identity, ref, policy, observation
hash, receipt ID, validity, and the previous receipt hash. Rotation is
fail-closed: pause both consumers, provision the next assertion and task
bindings out of band, then resume only after the new chain validates.

The host is the only product-code writer and must never execute product Live.
The VM may test, analyze, reset only allow-listed owned test resources, and
append diagnostic results to its one control repository; it must not edit,
commit, or push product code, change runbooks, or build candidates.

Current deployment state (2026-07-18):

- Product code: `LXZ56156/claude-desktop-deepseek-installer` (public;
  repository ID `1301870422`, node ID `R_kgDOTZj3Vg`, protected-history
  ruleset ID `19068339` covering `main` and `codex/repair/*`).
- Host to VM: `LXZ56156/cddsi-host-to-vm` (public; repository ID
  `1301870499`, node ID `R_kgDOTZj3ow`, ref `refs/heads/main`, genesis
  `179cb95df432392e6ecd901c9008c01e4b41003e`, protected-history ruleset
  ID `19068292`).
- VM to host: `LXZ56156/cddsi-vm-to-host` (public; repository ID
  `1301870545`, node ID `R_kgDOTZj30Q`, ref `refs/heads/main`, genesis
  `d88fe54d624bb5699751522e80e1cc4cd367ec33`, protected-history ruleset
  ID `19068313`).
- All three rulesets are active with no bypass actor and apply deletion,
  non-fast-forward, and required-linear-history rules to their effective refs.
- The host-side diagnostic implementation is feature-complete. Tracked
  documentation does not embed a self-referential final commit/tree/hash. The
  current clean HEAD is bootstrap-only ready only when the same paused
  automation, PR CI, actual Git/remote, and a validated 18-entry immutable
  bundle all bind that HEAD. This never authorizes polling or a product test.
- Host Codex heartbeat: `cddsi-fast-lane-hostcoordinator-minute-poll`, paused.
  Its post-commit bundle/runtime/prompt bindings must be verified outside tracked
  documentation. A narrow HostCoordinator credential and the runtime protection
  authority assertion are still required before any polling.
- VM Codex task: not created; it must be created from the VM Codex device after
  bundle verification and must initially be paused. It may be activated only
  after three distinct repository-scoped identities (product read,
  host-to-VM read, and VM-to-host append) pass negative permission tests, the
  current protection assertion/hash/token is independently provisioned, and
  the VM reset authority/device/anchor-grant trust gates are ready.
- GitHub rejected private-repository rulesets for the account plan. The user
  accepted the irreversible history/metadata exposure and chose public transport
  without history rewrite. The versioned PUBLIC contract passed first; all three
  remotes are now public and protected. Each new tracked commit still requires
  its own externally verified bundle/task/CI finalization.
- Narrow, non-admin credentials for both roles remain an external integration
  gate. The interactive bootstrap administrator credential must never be used
  by either minute task.

The readiness states are deliberately separate:

- `CanStartVmBootstrap`: true only when the current clean HEAD has the matching
  external bundle/task/CI/Git finalization facts. Bootstrap remains limited to
  offline bundle verification, VM-local key creation, tool/hash reporting, and
  creation of the still-paused VM task.
- `CanStartVmIntegration`: no. Protected history is independently evidenced;
  the narrow HostCoordinator credential and runtime authority assertion are
  not. VM polling, remote negative-permission tests, reset smoke, and
  unattended smoke remain pending.
- `P10A0AComplete` and `CanStartFormalP10A`: no. The first Formal P10A run also
  requires an external clean-snapshot receipt, independent CAS, and signatures.

Historical finalization anchor:

- product commit: `3e843912df2543c1da05b09061970faff511d016`
- product tree: `5d2d18317e0dfa9359d8caed6b30c5ddad984985`
- onboarding ZIP SHA-256:
  `58bf3d26930b1c2eda78c29b4d53a89a28794fc7d74ef6ecdb90b6858cb88832`
- onboarding manifest binding token:
  `c9309d30b02168a3a33552eb0d1dabd7374492a50d06f64e53d6b8e703ad2a54`
- final host quality evidence:
  `RunId=dd9af0ff-6230-4b42-9420-4f9f7d3048a4`, 427/427 on both engines,
  all required zero metrics satisfied

The VM reset contract is limited to resources with exact project ownership
receipts. Missing receipts, baseline drift, unknown mutation, or uncertain
VMP/reboot/uninstall/compensation state returns `BLOCKED` and requests an
external snapshot restore. A Fast Lane `CLEAN_READY` or `PASS` is diagnostic
only and cannot freeze P10A facts or satisfy P11.

Each disposable-VM Live reset also requires a fresh SYSTEM-owned supervisor
anchor/grant pair under `C:\ProgramData\cddsi-vm-operator\provisioning`. The
anchor binds VM/image, consumer SID, grant ID/path/hash, execution nonce, and
all trust/input bindings; the grant JSON binds nonce, cycle, policy, plan,
ownership/resource sets, control authentication, and expiry. The consumer
receives Read and Delete on the grant only, and a supervisor ACL receipt must
prove it cannot create or replace files in the parent directory. The provider
also verifies the parent directory is SYSTEM-owned with no untrusted mutation
ACE, then exclusively verifies and atomically deletes the grant before
registering a runtime. Every Live construction, including an idempotence rerun, needs a new
pair; an in-memory consumed flag is not a cross-process one-shot control.
