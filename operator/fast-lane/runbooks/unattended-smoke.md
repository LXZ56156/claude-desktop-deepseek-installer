# Unattended Fast Lane smoke runbook

Run only after repository protection and both role credentials pass their
negative tests. Start with both minute tasks paused and both protocol states at
their pinned genesis commits, with no post-genesis message entry. Do not delete
or recreate the initialized `outbox/` directories to make them appear empty.

1. Revalidate the protected refs, repository numeric/node identities, pinned
   genesis ancestry, narrow credentials, exact runner/prompt/bundle hashes, and
   paused status. For each control ref, also validate the operator-plane trust
   root, current receipt-specific protection assertion, independently fixed
   assertion SHA-256/authority token, receipt validity, and monotonic previous
   receipt hash. Only then activate the host task followed by the VM task.
2. Through the fixed outbox runtime, the host fast-forward appends one exact
   `TEST_REQUEST` to `LXZ56156/cddsi-host-to-vm` at `refs/heads/main`. Bind it to
   the immutable product commit and tree from the onboarding manifest, exact
   repair ref, runbook, reset policy, allow-list, VM image, run ID, and expiry.
3. Without manual file transfer, observe `VM_ACK`, diagnostic reset,
   `CLEAN_READY`, `TEST_STARTED`, `TEST_RESULT`, and `HOST_ACK` in strict order.
4. Repeat a pass cycle, an injected fail cycle followed by `FIX_READY` and
   `RETEST_REQUESTED`, an expired message, a duplicate, a wrong previous hash,
   and `STOP`.
5. Verify single-instance locking, bounded retry/runtime/output, local state
   persistence, pinned-genesis ancestry, fast-forward-only append, and no
   payload execution.
6. Verify the product tree at the exact detached commit is unchanged and the VM
   never writes product code, runbooks, test expectations, candidates, or
   product repository refs. The only allowed control ref write is a canonical
   fast-forward append to
   `LXZ56156/cddsi-vm-to-host` at `refs/heads/main`.
7. Pause both tasks and archive only redacted diagnostic evidence hashes.

If protection evidence rotates during the smoke, pause both tasks before
accepting it. Provision the next assertion and each task's new expected
hash/token out of band; a task must never learn those values from relay data.

No Fast Lane result is a snapshot receipt, Formal evidence, P10A fact freeze,
P11 acceptance, merge, promotion, or release authorization.
