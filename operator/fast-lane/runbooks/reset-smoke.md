# Deterministic guest-reset smoke runbook

This smoke test is diagnostic and is permitted only in the disposable VM. The
host and CI must remain unable to enter the live reset path.

1. Bind the immutable reset contract and adapter hash from the onboarding
   manifest. Bind the concrete VM image, reset policy, allow-list, expected
   baseline, ownership receipts, and cycle ID from the authenticated request
   plus the device-local provisioning and external-supervisor receipts. These
   dynamic values never rewrite the onboarding bundle.
   Provision and verify the VM-local device attestation/trust material before
   constructing a real provider; the onboarding bundle contains no private key
   and does not itself prove VM identity. The authority public-key fingerprint,
   expected VM identity/image receipt, and validity window must be frozen by
   the external supervisor and independently bound into the paused VM task;
   a trust policy must not authorize an authority key supplied only by itself
   or by relay data.
2. Run TestSafe and DryRun first. Both must report `Changed=false` and zero real
   provider mutations.
3. Create only synthetic, project-owned resources whose exact identities are in
   the allow-list and whose ownership receipts are valid.
4. Immediately before each Live construction, the external supervisor creates
   or updates the SYSTEM-owned provisioning anchor and creates a fresh one-shot
   grant at
   `C:\ProgramData\cddsi-vm-operator\provisioning\grants\<grantId>.grant.json`.
   The anchor binds the exact VM/image, authority/device trust, provider and
   command bytes, `OneShotGrantId`, grant path/SHA-256, execution nonce,
   consumer SID, cycle, reset policy, plan, ownership/resource sets,
   control-auth digest, and validity window. The grant JSON independently
   binds the nonce, cycle, policy, plan, ownership/resource sets, control-auth
   digest, and validity window. The consumer SID receives Read and Delete on
   the grant only; a supervisor ACL receipt must prove it has no WriteData,
   ACL, owner, parent-directory create, or replacement right. The provider
   must verify the parent directory is SYSTEM-owned with no untrusted
   create/replace/delete capability, exclusively open and revalidate the file,
   and atomically delete the grant before registering a Live runtime. A
   missing, writable, reused, or non-atomically consumed grant is `BLOCKED`;
   an in-memory consumed flag is not sufficient.
5. For a development retest only, invoke Live with the separate real-change
   acknowledgement. The adapter may remove only the five frozen resource kinds
   and must produce one action receipt per planned action.
6. Re-capture the exact baseline. Issue diagnostic `CLEAN_READY` only when the
   before/after evidence, final-state fields, receipts, ledgers, and secret scan
   all validate.
7. Repeat once to prove idempotence. Before the second Live construction, the
   supervisor must issue a new anchor/grant pair with a new `OneShotGrantId`,
   `OneShotExecutionNonce`, grant file SHA-256/path, and validity window. The
   second plan must not broaden scope; reusing the first grant or anchor is
   `BLOCKED`.

Missing receipts, path or marker mismatch, reparse point, unknown provider
result, baseline drift, cleanup failure, VMP/reboot/uninstall/compensation
uncertainty, or any milestone other than a development retest requires
`SnapshotRestore` and external-supervisor handling.

The first P10A run, any P10A fact-freeze run, formal P11 PASS, and every release
milestone must not use this guest-reset smoke as its clean-start evidence. They
require a clean snapshot restored outside the guest plus an independently
verifiable snapshot receipt; Formal results also require independent CAS and
signatures.
