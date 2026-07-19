# VM bootstrap runbook

Status: **NOT EXECUTABLE — host clean-commit finalization is incomplete as of
2026-07-19.** This runbook defines the reviewed target workflow. It does
not authorize entering the VM, Fast Lane integration, Formal P10A, product
Live, repository polling, reset, or product testing.

## User-visible contract

The ordinary user performs only these actions after the host explicitly reports
`CanStartVmBootstrap=true`:

1. Start the prepared disposable VM in the normal VM application.
2. Install Codex in the VM and sign in.
3. Put the one host-delivered onboarding ZIP in a new empty folder, without
   extracting or renaming it, and open that folder in Codex.
4. Paste the one exact host-delivered prompt.

Codex performs the hash, extraction, PowerShell, key-generation, and automation
work. It must not ask the user to reconstruct commands or observations.

This path currently assumes the prepared baseline already contains the exact
manifest-pinned Git, OpenSSH, `ssh-keygen`, PowerShell 7, and Windows PowerShell
binaries. Bootstrap validates them and does not download or install them. A
generic new Windows guest can therefore block before any persistent write.
Automated prerequisite installation requires separate user authority for
bootstrap-time network/install plus pinned origin, hash, signature, path, and
cleanup contracts.

For this bootstrap, `supervisor` simply means the normal VM application and
`baseline` means the guest starting state. A Formal clean-snapshot receipt is a
later P10A/P11 requirement, not a prerequisite for this offline bootstrap.

## Host authorization gate

Do not enter the VM until the host has completed all of the following for one
clean exact commit:

- standard dual-engine HostSandbox full-tree quality gate;
- Release Simulation DryRun, encoding checks, and `git diff --check`;
- deterministic Store onboarding bundle self-check: 18 ZIP entries, 16
  inventory entries, 1980 timestamps, and exact ZIP/manifest/inventory/content
  bindings;
- in-place update of the existing
  `cddsi-fast-lane-hostcoordinator-minute-poll`, still `PAUSED`;
- clean worktree, exact remote ref, PR #1 still OPEN/DRAFT, and all final-HEAD
  CI successful.

The host then supplies the one ZIP and the exact generated prompt, including
the eleven external anchors plus loader/prompt hashes and lengths. The VM does
not inspect host retained paths, host automation, PR/CI, worktree, or remotes.

## Autonomous bootstrap algorithm

The final prompt and fixed loader must perform the following fail-closed flow:

1. Before any write or ZIP-content read, require exactly one ordinary ZIP in
   the opened folder, no reparse ancestor, and an exact system length/SHA-256
   match to the host anchors.
2. Write only the exact ASCII/LF loader carried by the prompt, then verify its
   length, SHA-256, bytes, and PowerShell parser before execution.
3. Revalidate the original ZIP, Store layout, manifest v3, inventory, content
   digest, product commit/tree, repository identities, protected-history facts,
   known-hosts, and all five pinned tools.
4. Extract only the manifest-bound reviewed runtime into new owner-marked,
   no-reparse roots with the exact owner and protected DACL contract.
5. Invoke only
   `Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding`, passing the original ZIP,
   eleven external anchors, `BootstrapExecutionContext`, fixed roots, canonical
   `CodexHome`, target token, and acknowledgement.
6. The phase2 entry internally reruns package/onboarding validation, stages
   three distinct VM-local keypairs, persists only public/redacted receipts,
   and reads the authoritative local Codex automation TOML after the unique
   `cddsi-fast-lane-vmtester-minute-poll` has been created or updated with exact
   bindings, one-minute cadence, and `PAUSED` status.
   It rescans after local staging even when the initial match count was zero;
   any state transition, duplicate, or invalid readback compensates the roots
   created by that attempt and blocks. The held TOML bytes provide a point-in-time
   readback, so each Handoff invocation performs a fresh scan while the task
   remains `PAUSED`.
7. Return only `VM_BOOTSTRAP_STAGED`, delete the fixed loader with explicit
   deepest-first no-reparse cleanup, retain the original ZIP and owner-marked
   public receipt, and stop.

Caller-supplied result, automation prompt, observation,
`ObservationJsonBase64`, derived roots, direct core, direct handoff, mutation
helpers, and failure helpers are forbidden. Duplicate task ID/name, unexpected
TOML keys, prompt mismatch, wider ACL, tool drift, hash drift, or reparse points
return `VM_BOOTSTRAP_BLOCKED` without improvised repair.

## What bootstrap does not finish

The three private keys remain device-local and their state is only
`KEYPAIR_STAGED`. They are not credentials until a one-time authorized GitHub
provisioner registers the public keys and real positive/negative permission
tests prove:

- VM: product and host-to-VM read only; VM-to-host append only;
- host: repair ref and host-to-VM append only; VM-to-host read only;
- product write, wrong-direction write, force-push, delete, history rewrite,
  and broad administrator capability are rejected.

The interactive administrator identity may perform that one registration but
must never be stored or reused as either automation credential. Runtime
protection assertion/hash/token are also separately provisioned. Until both
gates pass, host and VM tasks remain `PAUSED`; accidental invocation must stop
before network, Git, credential probe, or runtime-state write.

Only a later integration authorization may activate the tasks and run real
publish/poll, deterministic reset, cleanup receipts, unattended host-fix/
VM-retest cycles, and broad scenario testing. VM Codex never edits, commits, or
pushes product code; the host never executes product Live.

Formal P10A/P11 later add external clean-snapshot receipts, immutable CAS, and
signatures. P12 remains a human release confirmation. There is no automatic
merge, promotion, or release.

## Current implementation blockers

The phase2 surface, caller-input removal, execution-boundary contraction,
canonical TOML/current-task binding, HostSandbox path binding, semantic ACL,
captured-byte loading, atomic/idempotent state, and explicit-stack cleanup are
implemented in the current dirty worktree with positive and negative tests.
The dirty WIP has passed the standard dual-engine HostSandbox full-tree gate,
with all failure, skip, forbidden/live/outside/secret/unexpected-ledger/mutation
metrics at zero. Before this runbook becomes executable, the host must still:

1. commit and non-force-push the exact reviewed bytes to the existing repair
   branch, without creating another PR;
2. rerun the full clean-commit HostSandbox and Release Simulation gates, encoding
   and diff checks, then build and self-check the exact onboarding bundle;
3. update the existing host automation in place, still `PAUSED`, and prove clean
   worktree, exact remote ref, PR #1 OPEN/DRAFT, and final-HEAD CI success.

Until those steps and the host gate are complete:

- `CanStartVmBootstrap=false`;
- `CanStartVmIntegration=false`;
- `P10A0AComplete=false`;
- `CanStartFormalP10A=false`.
