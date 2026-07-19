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
The version-3 onboarding manifest separately pins five tools: Git, OpenSSH,
OpenSSH key generation, PowerShell 7, and Windows PowerShell. Device-local
deploy-key hashes are added only by provisioning
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

## One-prompt VM bootstrap

For the current bootstrap, `supervisor` is just the normal VM application used
to start the guest, and `baseline` is the guest's starting state. A Formal
clean-snapshot receipt is not required now; it is a later Formal P10A/P11
requirement.

The ordinary user performs only four actions: start the disposable VM, install
and sign in to Codex, put the single onboarding ZIP in a new empty folder and
open that folder in Codex, then paste the final host handoff prompt once. The
prompt carries the external expected ZIP hash/length, product commit/tree, and
manifest/inventory/content tokens. It never asks the VM to inspect the host's
retained path, host automation, PR/CI, worktree, or remote refs; host
finalization already owns those checks.

This four-action path assumes a prepared baseline already contains the exact
manifest-pinned Git, OpenSSH, `ssh-keygen`, PowerShell 7, and Windows
PowerShell binaries. The current bootstrap validates them and does not install
or download them. A generic new Windows guest can therefore stop before any
persistent write. Adding tool self-install requires separate user authority
for bootstrap-time network/install plus pinned origin, hash, signature, path,
and cleanup contracts.

After the outer ZIP length and hash match with zero writes, VM Codex may use a
new owner-marked bootstrap staging root to load only the manifest-bound reviewed
runtime. The target side-effecting operator entry is
`Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding`. It receives only the
original ZIP, the eleven external ZIP/manifest/inventory/content/commit/tree
anchors, `-BootstrapExecutionContext`, explicit roots, canonical `CodexHome`,
the expected automation target token, and the acknowledgement. It reruns
package/onboarding validation and reads the real local Codex automation TOML
before constructing the public result. Canonical app-written identity keys are
scanned without imposing the target schema on unrelated tasks; a matching ID,
name, or target directory must then satisfy the exact target schema. Live also
requires the TOML target thread to equal the process-local `CODEX_THREAD_ID`.
Phase2 rescans after local staging even when the initial match count was zero;
any zero-to-one change or invalid/duplicate rescan fails closed and compensates
the roots created by that attempt. A successful readback is a point-in-time
observation bound to the held TOML bytes, not a claim that an external actor
cannot mutate the automation after return, so every Handoff invocation performs
a fresh scan and readback while the task remains `PAUSED`.
TestSafe/DryRun contexts bind every readable input to one owner-marked direct
child of the harness temporary root, so a forged fake context cannot probe host
paths. Caller-supplied result, prompt,
observation, `ObservationJsonBase64`, or derived directories are forbidden.
Plan/core, mutation, failure, and direct handoff helpers are internal and fail
closed when called as operator entry points. Codex does not assemble substitute
shell, Git, ACL, extraction, observation, or key-generation logic.

The local runner is idempotent for one exact binding. It may create only its
owner-marked VM-local state, stage three distinct keypairs, and create or update
the unique `cddsi-fast-lane-vmtester-minute-poll` automation with a one-minute
cadence and `PAUSED` status. New keys are `KEYPAIR_STAGED`, not credential-ready;
registration and positive/negative remote permission tests happen later. A
successful runner first returns `VM_BOOTSTRAP_LOCAL_STAGED`; only after the
Codex automation update is persisted and phase2 proves the unique paused task
from the authoritative TOML may the public redacted handoff return
`VM_BOOTSTRAP_STAGED` and stop.

Existing loader roots require current-user ownership, a protected DACL, and
exactly current user plus SYSTEM explicit inheritable FullControl. Dependency
hashing, parsing, and loading consume one captured byte sequence while its
read handle remains open. New authority markers are create-only; state changes
use verified same-directory atomic replacement and skip byte-identical updates.
Failure cleanup first validates every descendant without following reparse
points, then deletes files and directories deepest-first without recursive
delete.

The bootstrap runner's narrow local-write authority is not inherited by the
poll task. While runtime protection assertion/hash/token is `UNPROVISIONED`, an
accidental task invocation must return `BLOCKED` with zero network requests,
zero Git operations, zero credential probes, and zero runtime-state writes.

Current deployment state (2026-07-19):

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
- The host-side diagnostic implementation is present and has passed its dirty
  WIP gate; clean-commit and external finalization are pending. The shared
  worktree has tracked changes based on commit
  `809942943bfeb0547fa36f57aedb8e75e1d45e29`; phase2 tests, builder/loader
  wiring, execution boundaries, HostSandbox path binding, semantic ACL,
  captured-byte loading, atomic/idempotent state, and no-reparse non-recursive
  cleanup are present and have passed the standard dual-engine full-tree gate
  in the dirty WIP. The clean exact commit must still rerun that gate and finish
  external finalization. No current clean final anchor exists and
  `CanStartVmBootstrap=false`.
- Host Codex heartbeat: `cddsi-fast-lane-hostcoordinator-minute-poll`, paused.
  Its post-commit bundle/runtime/prompt bindings must be verified outside tracked
  documentation. A narrow HostCoordinator credential and the runtime protection
  authority assertion are still required before any polling.
- VM Codex task: the one-prompt bootstrap creates it from the VM Codex device,
  or idempotently updates the same unique ID if it already exists, and verifies
  it remains paused. It may be activated only
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
- The three VM keypairs are only `KEYPAIR_STAGED` until a one-time authorized
  GitHub provisioner registers the public keys and real positive/negative
  permission tests pass. That administrator identity is never stored as an
  automation credential. Runtime assertion/hash/token also remain
  `UNPROVISIONED`, so both tasks remain `PAUSED`.

The readiness states are deliberately separate:

- `CanStartVmBootstrap`: currently no. It becomes true only when the final clean HEAD has the matching
  external bundle/task/CI/Git finalization facts. Bootstrap remains limited to
  offline bundle verification, owner-marked VM-local staging, three
  `KEYPAIR_STAGED` keypairs, tool/hash reporting, and creation or update of the
  same still-paused VM task. The VM consumes the external binding; it does not
  repeat host-only finalization checks.
- `CanStartVmIntegration`: no. Protected history is independently evidenced;
  the narrow HostCoordinator credential and runtime authority assertion are
  not. VM polling, remote negative-permission tests, reset smoke, and
  unattended smoke remain pending.
- `P10A0AComplete` and `CanStartFormalP10A`: no. The first Formal P10A run also
  requires an external clean-snapshot receipt, independent CAS, and signatures.
  None of those Formal items is a prerequisite for the current offline
  bootstrap.

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
