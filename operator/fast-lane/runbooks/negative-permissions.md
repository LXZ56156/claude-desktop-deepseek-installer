# VM negative-permission runbook

Run this from the VM with three distinct repository-scoped identities recorded
in the device-local provisioning receipt: product read, host-to-VM read, and
VM-to-host append. Use repository and trust facts from the onboarding bundle,
and record only command class, repository identity, expected/actual allow
or deny result, exit code class, timestamp, and a redacted evidence hash.

## Required denials

The VM identity must be denied all of the following:

- push any ref to the product repository, including a new branch or tag;
- update or delete the product repair ref;
- create releases, issues, pull requests, or workflow dispatches for the
  product repository;
- append to `host-to-vm`;
- force-push, delete a ref, or rewrite history in either control repository;
- use the HostCoordinator identity or access its credential material.
- use any one VM deploy key against either of the other two repositories.

Use non-mutating permission probes where the provider supports them. A Git push
probe must use `--dry-run` and a unique synthetic ref. An API capability is
considered denied only when the VM has no applicable API credential or the
provider returns an authorization denial. Do not create then delete a real
resource as a negative test.

## Required allows

The VM identity must be able to:

- fetch the exact product commit read-only;
- fetch `LXZ56156/cddsi-host-to-vm` at `refs/heads/main` and prove the exact
  host-to-VM genesis from the onboarding manifest is an ancestor;
- fetch `LXZ56156/cddsi-vm-to-host` at `refs/heads/main` and prove the exact
  VM-to-host genesis from the onboarding manifest is an ancestor;
- after a valid host request, append one canonical VM message to
  `LXZ56156/cddsi-vm-to-host` at `refs/heads/main` through the fixed outbox
  runtime.

Any broader allow, ambiguous result, missing provider protection, or use of an
interactive administrator credential is `BLOCKED`.

Before recording protection as present, validate its observation through the
operator-plane `control-protection-trust` owner marker and the current
receipt-specific authority assertion. The expected assertion SHA-256 and
authority-binding token must be supplied independently, and the receipt ID,
validity window, observation hash, and previous-receipt hash must match. A
self-consistent receipt/assertion pair, a relay-supplied hash, a stale/forked
rotation, or an assertion stored in relay state is `BLOCKED`.
