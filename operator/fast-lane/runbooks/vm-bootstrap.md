# VM bootstrap runbook

This runbook starts diagnostic P10A-0A VM bootstrap only. It does not authorize
Fast Lane integration, Formal P10A calibration, or product Live acceptance.

## Preconditions

- Start from the external supervisor's named disposable-VM baseline. This
  bootstrap baseline label is not a Formal clean-snapshot receipt.
- Verify the onboarding bundle SHA-256 and every inventory entry before use.
- Keep the operator workspace separate from the product checkout.
- Generate three repository-scoped VM private keys on the VM: product read,
  host-to-VM read, and VM-to-host append. A deploy key is not reused across
  repositories. Never copy a private key, token, or
  credential into the repository, relay, report, prompt, or conversation.
- The host registers only the VM public keys after reviewing them.

Protected history and narrow role credentials are not required for this
offline bootstrap subsection. Until the host provides current, independently
verified evidence for both gates, do not poll either control repository, fetch
the product remote, execute a product test, or run reset Live.

## Bootstrap-only steps

1. Verify the bundle ZIP, canonical manifest, inventory, every entry hash, the
   product commit/tree binding, expected `PUBLIC` visibility for all three
   repositories, all repository numeric/node identities, both
   pinned genesis commits, every fixed tool hash, and the policy-pinned GitHub
   `known_hosts` hash. OpenSSH and host-key expectations come only from this
   immutable binding, never from relay data.
2. Generate separate VM-local credentials for product read, host-to-VM read,
   and VM-to-host append. Return only public material and redacted fingerprints
   to the host; do not reuse a deploy key across repositories. Bind each
   device-local private-key hash to its one exact repository and direction.
3. Record the VM-local fixed Git/OpenSSH/PowerShell tool paths and hashes. Any mismatch
   with the immutable manifest is `BLOCKED`; do not rewrite the bundle locally.
4. Create `cddsi-fast-lane-vmtester-minute-poll` from the VM Codex device at a
   one-minute cadence and leave it paused. Bind it to the exact VM prompt,
   policy, runner, product commit/tree, bundle, and manifest hashes.
   Also bind the OpenSSH/known-hosts hashes and the three distinct credential
   profile receipts; none may be inferred from a message. Freeze
   `VmInitialStatus=PAUSED`. Until repository protection is provisioned, bind
   the protection assertion/hash/token fields as explicitly `UNPROVISIONED`
   so the task can only return `BLOCKED`.
5. Stop at `VM_BOOTSTRAP_STAGED`. This state authorizes no repository polling,
   product test, product Live, or product-code mutation.

## Integration gate

Continue only after the host supplies current receipts proving expected
`PUBLIC` visibility plus protected history and its narrow HostCoordinator credential, and after the VM
credentials have been registered without broad administrator capability. Run
`negative-permissions.md`; any ambiguous or broader allow is `BLOCKED`. While
both tasks remain paused, independently provision the current
`control-protection-trust` owner marker, receipt-specific assertion, expected
assertion SHA-256, and authority-binding token. The assertion must bind the
repository ID/node/ref, policy, observation hash, validity window, receipt ID,
and previous receipt hash; none of these expected values may come from relay
data or the receipt being validated.

## Immutable product materialization

This subsection is integration work, not bootstrap-only work.

1. Use the VM product read-only identity to fetch the exact product commit from
   the bundle manifest. Never follow the moving branch head as the test object.
2. Verify that the fetched commit and tree match the manifest.
3. Materialize the exact tree into a new test directory. The Git mirror and
   relay state remain outside that directory.
4. Make the materialized product tree read-only for the VM Codex identity.
5. Verify the complete tree hash before and after every test. Any difference is
   `BLOCKED`, not a repair opportunity inside the VM.

## Device-local automation

The VM task created during bootstrap remains paused until the
negative-permission runbook passes. The host task also remains paused until
expected `PUBLIC` visibility, protected history, and the HostCoordinator credential have independently
passed their host-side gates and the current protection assertions are
out-of-band hash-bound. Activate neither task merely because the other
one exists. The tasks must not target a writable product checkout, share a
credential, or receive an interactive administrator credential.

## Stop conditions

Stop and request human or external-supervisor action on any hash mismatch,
history rewrite, missing ownership receipt, baseline drift, cleanup failure,
unknown mutation, credential overreach, unexpected product-tree change, VMP or
reboot uncertainty, or relay transition failure.
