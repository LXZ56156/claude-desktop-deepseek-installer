# P10A-0A Fast Lane operator bundle

This directory is development-only operator coordination material. It is not
loaded by `lib/bootstrap.ps1`, is not part of the product execution plane, and
must never enter a Release ZIP.

The Fast Lane uses one logical control plane backed by two physical private Git
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

Current deployment state (2026-07-16):

- Product code: `LXZ56156/claude-desktop-deepseek-installer` (private;
  repository ID `1301870422`, node ID `R_kgDOTZj3Vg`).
- Host to VM: `LXZ56156/cddsi-host-to-vm` (private; repository ID
  `1301870499`, node ID `R_kgDOTZj3ow`, ref `refs/heads/main`, genesis
  `179cb95df432392e6ecd901c9008c01e4b41003e`).
- VM to host: `LXZ56156/cddsi-vm-to-host` (private; repository ID
  `1301870545`, node ID `R_kgDOTZj30Q`, ref `refs/heads/main`, genesis
  `d88fe54d624bb5699751522e80e1cc4cd367ec33`).
- The host-side diagnostic implementation is VM-bootstrap ready: the fixed Git
  outbox runtime, readiness resolver, deterministic onboarding builder, VM-only
  reset dispatcher/provider boundary, prompts, and runbooks can be bound into
  one immutable, inventory-checked ZIP. This does not authorize polling or a
  product test.
- Host Codex heartbeat: `cddsi-fast-lane-hostcoordinator-minute-poll`, paused
  until a narrow HostCoordinator credential, append-only server protection,
  and its protected authority assertion are verified.
- VM Codex task: not created; it must be created from the VM Codex device after
  bundle verification and must initially be paused. It may be activated only
  after three distinct repository-scoped identities (product read,
  host-to-VM read, and VM-to-host append) pass negative permission tests, the
  current protection assertion/hash/token is independently provisioned, and
  the VM reset authority/device/anchor-grant trust gates are ready.
- GitHub rejected private-repository rulesets for the current account plan.
  The repositories remain private; force-push/deletion protection is therefore
  an open fail-closed deployment gate rather than a policy downgrade.
- Narrow, non-admin credentials for both roles remain an external integration
  gate. The interactive bootstrap administrator credential must never be used
  by either minute task.

The readiness states are deliberately separate:

- `CanStartVmBootstrap`: yes after the final immutable bundle is validated and
  the host heartbeat remains hash-bound and paused. Bootstrap is limited to
  offline bundle verification, VM-local key creation, tool/hash reporting, and
  creation of the still-paused VM task.
- `CanStartVmIntegration`: no until protected history and the narrow
  HostCoordinator credential are independently evidenced. VM polling, remote
  negative-permission tests, reset smoke, and unattended smoke remain pending.
- `P10A0AComplete` and `CanStartFormalP10A`: no. The first Formal P10A run also
  requires an external clean-snapshot receipt, independent CAS, and signatures.

Finalization values are intentionally not guessed in this tracked document:

- product commit: `<FINAL_PRODUCT_COMMIT_SHA_AFTER_COMMIT>`
- product tree: `<FINAL_PRODUCT_TREE_SHA_AFTER_COMMIT>`
- onboarding ZIP SHA-256: `<FINAL_ONBOARDING_ZIP_SHA256_AFTER_BUILD>`
- onboarding manifest binding token:
  `<FINAL_ONBOARDING_MANIFEST_BINDING_TOKEN_AFTER_BUILD>`
- final host quality evidence: `<FINAL_HOST_QUALITY_EVIDENCE_AFTER_GATES>`

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
