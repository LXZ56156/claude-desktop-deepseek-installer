# CDDsi realtime relay operator client

Status: **PROVISIONED / CROSS_DEVICE_SMOKE_PASSED /
FOREGROUND_RUNNER_LOCAL_TESTED / HOST_FOREGROUND_CREDENTIAL_READY /
VM_FOREGROUND_CREDENTIAL_READY / VM_DEPLOY_KEY_REGISTERED /
CLEAN_ROOM_EPOCH_DEPLOYED / FOREGROUND_CANARY_PENDING / NOT_PRIMARY /
AUTOMATION_PAUSED**.

This directory is an operator-coordination plane. It is DevelopmentOnly, is not
loaded by the product bootstrap, and is excluded from every release package.
The existing protected-history control repositories remain the durable audit
path and fallback. Their minute-poll contract is retained but inactive; the
foreground path does not require Automation or a scheduler. HostCoordinator
and VM automation remain `PAUSED`.

## D-024 foreground two-dialog diagnostic

The current path is a bounded foreground cycle in two new Host/VM Codex
dialogs. `invoke-foreground-cycle.ps1` exposes `Status`, `WaitPointer`, and
`PublishPointer`. Role fixes opposite read/write lanes. Wait may receive the
next valid pointer without knowing its MessageId, or use an optional expected
pointer; `AfterSequence` skips retained older messages. It validates, persists,
ACKs, and returns only pointer fields. It never calls fixed Git wake, Codex
resume, an Automation API, or a payload.

D-024 supersedes D-023's Automation create/readback/start path. Existing
Automation stays `PAUSED`, and VM Automation may stay `ABSENT`; neither is a
foreground canary gate. Control repos hold bodies and audit history, while the
relay carries only pointers. The Host remains the only product writer and the
VM remains read-only for product testing. Host/VM foreground DPAPI credentials
are ready, and VM deploy key `158030457` is registered only to the VM-to-host
control repo. The old room lanes were at 4/2; a clean
`RELAY_ROOM_EPOCH=2` is now deployed without changing the auth environment or
runtime secrets, and both new lanes start from sequence zero. The public
WebSocket canary is next. This grants no
product Live, Formal P10A/P10B/P11, merge, release, promotion, or P12 authority.

### Current foreground execution order

The bootstrap dialogs are used only for the public canary. After it passes,
the user starts a fresh VM Codex dialog and the Host creates a fresh project
dialog. The VM dialog waits first; the Host then publishes `SESSION_START`,
waits on `vm-to-host`, and accepts `SESSION_READY`. Only those fresh dialogs
run the Host-fix/VM-test loop. The old dialogs are not wake targets.

Each dialog reads its repository-external `%LOCALAPPDATA%` `active-session.json`
and maps only `Endpoint`, `StateRoot`, `RunId`, `OwnerSid`,
`OwnershipTokenSha256`, `Environment`, and `KeyId` to the runner. It must not
splat the receipt object or copy credential bytes into a prompt. The runner
strictly derives the same-host WSS root from the HTTPS endpoint. A blocked
result is JSON plus exit code 1.

For epoch 2, the first `WaitPointer` on each machine uses `AfterSequence=0`.
Do not copy the superseded room's 4/2 cursors into a canary or fresh-dialog
prompt. After the first ACK, local state is authoritative and reconnect resumes
from its saved sequence. Use bounded 60-second waits and repeat them in the
foreground so the dialog can report progress between waits.

Before `PublishPointer`, the sender appends one fixed-schema body to its own
protected control repository and computes the exact body SHA-256. The relay
pointer uses that body MessageId, payload hash, and control-repository commit.
The receiver treats the pointer as a notification only, fetches that exact
commit, verifies the one added outbox file and its hash/schema, and only then
acts on a fixed message kind. No body or free text is executed.

The lean foreground body is canonical UTF-8 JSON with exactly these fields:

```json
{"Schema":"CDDsi_FOREGROUND_CONTROL_V1","Lane":"host-to-vm","MessageId":"00000000-0000-4000-8000-000000000000","CycleId":"00000000-0000-4000-8000-000000000000","Kind":"SESSION_START","SenderRole":"HostCoordinator","ProductCommit":"0000000000000000000000000000000000000000","TestProfile":"FOREGROUND_CANARY","ResultStatus":"NONE","ResultCode":"NONE","EvidencePath":null,"EvidenceSha256":null,"CreatedAtUtc":"2026-07-22T00:00:00Z","ExpiresAtUtc":"2026-07-22T00:10:00Z"}
```

The exact `Kind` set is `SESSION_START`, `SESSION_READY`, `TEST_REQUEST`,
`TEST_RESULT`, `FIX_READY`, `HOST_ACK`, and `STOP`. `TestProfile` is one of
`FOREGROUND_CANARY`, `FOCUSED_REGRESSION`, `QUALITY`, or `RELEASE_DRYRUN`.
`ResultStatus` is `NONE`, `READY`, `PASSED`, `FAILED`, or `BLOCKED`;
`ResultCode` is `NONE` or an uppercase underscore-delimited stable code.
Evidence fields are both null or a repository-relative safe path plus a
lowercase SHA-256. They never contain prose, commands, logs, or prompts. The
sender role/lane pair is fixed, both UUIDs are lowercase UUIDv4, the product
commit is lowercase 40-hex, and expiry is no more than ten minutes after
creation. A control commit adds exactly one `outbox/<12 digits>-<MessageId>.json`
body plus any separately hashed evidence files referenced by it.

The semantic pairs are also fixed. `host-to-vm` accepts only `SESSION_START`,
`TEST_REQUEST`, `FIX_READY`, `HOST_ACK`, or `STOP`, all with
`ResultStatus=NONE` and `ResultCode=NONE`. `vm-to-host` accepts
`SESSION_READY` with `READY/NONE`, or `TEST_RESULT` with `PASSED`, `FAILED`, or
`BLOCKED`; a passed result uses `NONE`, while failed or blocked results require
a non-`NONE` stable code.

`foreground-control.ps1` exposes the pure
`ConvertFrom-CddsiRealtimeRelayForegroundControlBody` validator. Each Host/VM
dialog obtains the exact Git blob as raw bytes from its fixed control-repository
read path and calls the validator with `-BodyBytes`, its fixed `-ExpectedLane`,
and an explicit `-NowUtc`. Do not round-trip the blob through console text or
PowerShell redirection. The validator rejects a body over 4 KiB, a UTF-8 BOM,
NUL, invalid UTF-8, or any literal ASCII control character before canonical
parsing; its `BodySha256` binds the original raw bytes. It accepts only the
canonical 14-field bytes above, returns parsed data, and never reads Git, files,
or the network or executes body content. The
receiver compares that hash to the relay pointer before dispatching only the
fixed `Kind` state transition.

## D-022 lean delivery profile

The immediate objective is working Host/VM communication, not completion of
every possible hardening mechanism. The policy in this section takes
precedence over stricter early provisioning language later in this document.

- Free-only Worker/DO deployment and a manually invoked relay-only VM smoke do
  not wait for a machine Billing receipt, two-phase write ticket, coordinated
  provisioner, Host/VM DPAPI receipts, bulk semantics, or a two-secret staging
  receipt. Existing implementations of those mechanisms are optional
  hardening and may remain in place without acting as current gates.
- The first smoke may supply the Host secret through current process memory or
  secure input. For the VM, the operator may manually drag in one repository-
  external, owner-only, one-use `cddsi-relay-vm-handoff-v1` JSON package. The
  fixed `invoke-vm-smoke.ps1 -PackagePath` entry reads at most 4 KiB, rejects a
  non-current owner, any ACL wider than one owner FullControl rule, a reparse
  package, and schema drift, then deletes the package before parsing or any
  network request, and clears secret bytes in `finally`. The package is never
  Git, prompt, log, or evidence content and is not long-term plaintext storage.
  Without explicit `-AcknowledgeRelayOnlyLive`, the entry is Plan-only and does
  not read, delete, or contact the network; the acknowledgement applies only to
  this relay smoke and grants no product authority.
  DPAPI CurrentUser is required only before a persistent, cross-process or
  cross-reboot unattended watcher is enabled.
- The minimum live smoke is two successful publish/watch/ACK directions, both
  reverse-lane denials, one wrong/forged-secret denial, and one disconnect and
  resume. It also proves no secret output and no payload execution. Additional
  fault matrices remain useful hardening but are not deployment prerequisites.
- A real Cloudflare paid-plan or upgrade prompt still stops the Free-only
  operation. Deploy OAuth and runtime relay secrets stay separate.
- The user-provided `VM_RELAY_READINESS_V1` reports `Ready=true`: PowerShell 7,
  Git, `ClientWebSocket`, clock synchronization, outbound GitHub/`workers.dev`
  443, VMware Tools, and the VM-local relay state directory are ready with no
  blocker.
- The Free-only Worker, SQLite-backed Durable Object, and two runtime secret
  bindings are deployed at
  `https://cddsi-realtime-relay.lizixuan6383828.workers.dev`. Exact postdeploy
  readback, the Host dual-role HTTP smoke, and the cross-device Host/VM
  publish/read/ACK smoke passed without recording either secret. Production
  WebSocket reconnect and Hibernation have not yet completed public E2E
  verification, so this relay is `NOT_PRIMARY` and both automations stay
  `PAUSED`.
- The one-use VM package, prepared envelope, and VM report copies were deleted.
  The Host's 64-byte plaintext runtime frame was deleted after a DPAPI
  CurrentUser round-trip; only an owner-only DPAPI blob remains outside the
  repository. Host and VM CurrentUser DPAPI credentials are now provisioned
  for the bounded foreground cycle; no persistent watcher or Automation was
  enabled. Primary-path use remains `NOT_ENABLED`.

This profile authorizes only manually invoked relay coordination. Old
onboarding/bootstrap and product integration remain superseded/paused; both
automations remain `PAUSED`. The host remains the only product writer, relay
payload/free text is never executed, and Formal Lane/P12/no-auto-promotion
boundaries remain unchanged.

## Authority boundary

The relay carries only a canonical, small notification pointer. It never
carries a command, prompt, script, report body, log body, screenshot, or code.
The public Worker URL, a valid HMAC, a WebSocket, and an ACK are transport facts;
none grants product-write, test, merge, release, promotion, or P12 authority.

The two lanes are physically logical and directionally fixed:

| Lane | Writer | Reader | Durable source |
|---|---|---|---|
| `host-to-vm` | `host-coordinator-v1` | `vm-tester-v1` | host-to-VM protected control repo |
| `vm-to-host` | `vm-tester-v1` | `host-coordinator-v1` | VM-to-host protected control repo |

The host remains the only product repository writer. The VM may return a
structured proposal or unified diff, but the host must validate and apply it.

## Client contract

`realtime-relay-client.ps1` provides a PowerShell 7 live transport and a fake
provider contract used by PowerShell 7 and Windows PowerShell 5.1 tests. The
following is the persistent unattended watcher contract; it is not a gate for
the one-time manual smoke:

- an explicit `TestSafe`, `DryRun`, or `Live` execution context;
- the exact reader identity for the selected lane;
- a current runtime assertion bound to endpoint, environment/key id, DPAPI
  credential, state root, data-only fixed wake binding, client source hash, and
  Git outbox runner hash; the assertion has exact NoteProperty-only fields,
  canonical issued/expiry timestamps, and a maximum 600-second lifetime;
- an owner-marked state root named `cddsi-realtime-relay-<run-id>`, owned by the
  current Windows user, with inheritance disabled and only that user plus
  `SYSTEM` granted full control;
- no reparse point in the root ancestry, marker, lock, state, or credential
  path;
- a short-lived `.lifecycle.lock`, independent watcher and per-lane publisher
  operation locks, and canonical, size-bounded atomic state.

Reader and writer authority are separate contracts. `New-CddsiRealtimeRelayLiveProvider`
constructs only a watcher context: HostCoordinator may read `vm-to-host`, and
VmTester may read `host-to-vm`. `New-CddsiRealtimeRelayLivePublisher` constructs
only a publisher context: HostCoordinator may write `host-to-vm`, and VmTester
may write `vm-to-host`. `Invoke-CddsiRealtimeRelayPublish` checks that exact
writer/lane pair before credential resolution, state access, or network access.
The publisher has its own current, maximum-600-second runtime assertion and an
independent `-AcknowledgeOperatorPlaneLive` gate; a watcher assertion cannot be
reused as publisher authority.

Non-Live modes require fake providers. They do not use the network, registry,
Credential Manager, processes, or paths outside the declared synthetic state.
Caller-supplied scriptblocks are permitted only in those fake providers. A Live
context is recursively data-only: state, DPAPI credential, WebSocket/HTTP
transport, clock, and fixed wake are exact NoteProperty-only descriptors bound
to the current client source SHA-256. Live operations dispatch only to fixed,
statically named internal functions, which revalidate descriptor/source and the
relevant current-user ACL, owner marker, and no-reparse binding at every use.
The live endpoint is restricted to root-path `wss://<worker>.<account>.workers.dev/`
on the default TLS port, with no user info, query, or fragment.

Each notification is independently checked for exact keys and field types,
canonical JSON, lane, identity, fixed repository numeric ID and ref, UUIDv4
MessageId, JavaScript-safe integer sequence, previous-message SHA-256, payload
SHA-256, commit SHA, UTC-second timestamps, clock skew, expiry, and maximum TTL.
The publisher accepts exactly a `cddsi-realtime-relay-publish-pointer-v1`
object with `SchemaVersion`, `Lane`, `MessageId`, `PayloadSha256`, and `Commit`.
The caller copies the lowercase UUIDv4 MessageId from the already-created
immutable control-repository envelope, and the relay notification preserves it
exactly. Repository ID, ref, sender role, sequence, previous hash, creation
time, and ten-minute expiry are fixed or derived locally. No report body,
model text, prompt, code, command, or caller-selected repository/ref can enter
the canonical publish body. The supplied MessageId is correlation data, not
sender or command authority: the notification remains untrusted until the
fixed Git poll validates that exact protected envelope. The HMAC-signed request
is always an exact `POST /v1/publish/<lane>`.

Publisher state is lane-specific and locked separately from watcher state.
Before the first HTTP attempt, the exact canonical body and its SHA-256 are
atomically recorded as `PendingPublish`. A lost response, process restart, or
retry reuses those identical bytes, MessageId, sequence, previous hash, and
timestamps. Only an exact `201/PUBLISHED` or `200/PUBLISHED_IDEMPOTENT` response
bound to that message promotes the sequence/hash chain and clears pending
state. An exact pending message is retried unchanged even after its notification
TTL: a message already accepted by the relay can still receive the idempotent
success response, while an unseen expired message is rejected by the relay.
Pointer drift or state drift fails closed, and neither case silently replaces
the pending body with a new MessageId or sequence. The protected control
repository remains the fallback, and retiring an abandoned publisher chain
requires an explicitly reviewed new relay environment epoch.

Watcher and publisher startup briefly acquire `.lifecycle.lock` only while
revalidating the owner root/tombstone and acquiring their respective long-lived
operation lock; they then release the lifecycle lock before transport work.
The watcher lock and each publisher-lane lock are independent, so a connected
but idle watcher cannot starve a publisher. This ordering prevents cleanup from
racing a new operation without serializing unrelated receive and publish work.

Only the fixed event verb `CONTROL_REPO_POINTER_AVAILABLE` can be emitted by
the watcher. Live does not accept a caller-supplied wake scriptblock or closure.
The data-only provider is re-hashed at construction and use, rejects executable
properties, and first calls the statically named
`Invoke-CddsiFastLaneGitOutbox -Operation Poll` with frozen parameters and the
exact schema-validated target fields (lane, repository/ref, commit, MessageId,
sequence, and payload hash). The outbox returns a target-bound `CONSUMED_NOW` or
`ALREADY_CONSUMED` receipt after validating repository identity, protected
history, commit, MessageId, and payload hash.

For `CONSUMED_NOW`, the client atomically records a lane-specific `PENDING`
wake proof and then starts the hash-bound absolute `codex.exe` directly as
`exec resume --json <fixed-session-uuid> <fixed-source-prompt>`. Neither the
relay pointer nor any control-repository/model/free-text field is placed in the
arguments, prompt, environment, executable path, or working directory. The
process uses the already-loaded bounded Fast Lane runner, a Windows job object,
empty stdin, a fixed timeout, and bounded output that is discarded even when
truncated. It receives only machine `SystemRoot`/`WINDIR`, bound
`HOME`/`USERPROFILE`/`LOCALAPPDATA`/`CODEX_HOME`, a dedicated owner-marked
no-reparse `TEMP`/`TMP`, and `NO_COLOR`; it inherits no `PATH`, proxy,
OpenAI/Cloudflare, Node, or parent-process environment variables.

Only job assignment plus a non-timeout, non-tree-termination exit code 0 can
advance the proof to `SUCCEEDED`, after the runtime assertion is revalidated.
`ALREADY_CONSUMED` with a matching `SUCCEEDED` proof returns
`PreviouslyInvoked` without spawning; a matching `PENDING` proof may retry the
same fixed resume for at-least-once recovery. Missing or drifting proof fails
closed. A process or proof transition failure does not advance watcher state or
send ACK, and only an actually successful Codex resume is reported as
`FixedEntryInvoked`.

A crash after Codex exits 0 but before the atomic `SUCCEEDED` proof commit
leaves `PENDING`; recovery therefore invokes the same fixed resume again. This
is deliberately at-least-once, not exactly-once. The fixed downstream inbox
handler must be idempotent against the already verified control-repository
message identity and must not infer a second product action merely from a
repeated resume.

State is committed before ACK. A lost ACK therefore reconnects from
`LastAckedSequence`, replays the exact MessageId, and does not repeat a completed
wake. Connection and ACK failures have independent bounded exponential backoff
with jitter. Total observed frames are bounded so duplicate traffic cannot
livelock the watcher. Unknown provider exceptions are mapped to a fixed public
code and are never copied into results or logs.

A 60-second receive window that expires while the WebSocket remains open is a
healthy `REALTIME_WEBSOCKET_IDLE` observation. The watcher keeps the connection
loop alive without consuming reconnect budget. A remote close or real transport
failure still closes the session and consumes the bounded reconnect budget.

State replacement uses a write-through `watcher-state.next.json`, validates the
canonical candidate before promotion, and uses an exact-path atomic replace.
A validated backup is promoted only when the current state is absent. A sole
validated `.next` candidate is recovered; when current state and `.next` both
exist, current state wins and the candidate is discarded. Partial, oversized,
noncanonical, directory, and reparse-point state artifacts fail closed.

The runtime assertion is revalidated before receive, fixed wake, each persistent
state mutation, ACK signing, and ACK transmission. Expiry therefore prevents
new DPAPI signing, relay network attempts, or control-repository wake effects.
`OperatorRelayNetworkRequestCount` records each attempted WebSocket connect,
WebSocket receive, HTTP ACK send, and publisher HTTP send, whether it succeeds
or fails. Operator Git, local-state, fixed Codex spawn, and successful fixed
wake effects are reported separately. `Changed` remains true after any proven
persistent operator-state mutation or successful fixed wake even if a later
ACK or proof transition fails.
`ProductNetworkRequestCount` and the retained compatibility metric
`RealNetworkAccessCount` both describe forbidden product-plane network access
and must remain zero; neither hides authorized operator-relay transport.

Only after the complete Live context and session binding validate does the
watcher capture an internal trusted session id. Its `finally` path looks up that
exact internal session-table entry, attempts both socket abort and disposal with
fixed redaction, and removes the entry even if either cleanup operation throws.
Cleanup never re-trusts a descriptor that may have drifted after a network
attempt, and no caller-facing parameter can supply a cleanup session id.

## Threat model

Protected assets are the two runtime HMAC secrets, the local sequence/hash
state, control-repository credentials, runtime assertion, fixed runner bytes,
and the host-only product write boundary. Relevant attackers include an
anonymous Internet client, a holder of only one directional capability, a
malicious or compromised relay response, stale/replayed traffic, malformed
provider implementations, and untrusted report/model text.

Controls include `CDDsi-HMAC-SHA256-v2` binding audience, environment, key id,
client id, method, canonical target, timestamp, nonce, and exact body hash;
per-identity lane ACLs; canonical schemas; bounded bodies and retention;
MessageId idempotency, sequence/hash chaining, short TTL, rate and connection
limits, ACK target binding, no-secret responses, owner-only local state,
fail-closed provider results, and a second independent validation against the
protected control repository. Formal Lane receipts, CAS, signatures, clean
snapshots, exact candidates, and P12 remain outside relay authority.

The SHA-256 bindings verify the expected on-disk client, Git runner, Codex
executable, and related fixed artifacts and fail closed on ordinary byte drift.
They are not a cryptographic provenance or in-memory attestation mechanism:
they do not prove that an already-loaded PowerShell `ScriptBlock` body or the
already-loaded `Cddsi.FastLane.BoundedProcessRunner` IL is uncompromised against
an arbitrary same-current-user or in-process attacker. Live operation therefore
requires a fresh trusted PowerShell 7 process/runspace created only after the
exact on-disk bytes have been verified and then loaded from those verified
paths. A suspected same-user or runspace compromise requires stopping watcher,
publisher, and fixed wake activity; discarding that process/runspace; rotating
both affected runtime relay credentials; and re-establishing the client from a
clean trusted environment before Live resumes.

Residual risks are handled by fallback rather than guessed recovery. A missing
retained sequence, expired notification, chain mismatch, unknown key id,
credential rotation, or runtime assertion drift stops realtime consumption.
The minute poll then reconstructs durable truth from the protected control
repository. No relay state is promoted to formal evidence.

## Credential provisioning and rotation

No credential exists in this repository. Runtime HMAC secrets are distinct
from Wrangler OAuth/API deployment credentials and from Git control-repository
credentials. Each runtime secret is a random 256-bit value. Cloudflare receives
it only through a secret-binding operation after explicit authorization; the
corresponding client copy must be a DPAPI CurrentUser blob under its validated
owner root. Plaintext TOML, environment-variable, prompt, command-line, log, or
Git storage is forbidden.

`Set-CddsiRealtimeRelayDpapiCredential` is the only local credential write
entry point. `TestSafe` and `DryRun` validate only the exact data-only provider
shape and return a fixed `PLANNED` result; they do not resolve provider source,
touch a path, or invoke protected-data APIs. A `Live` call requires Windows,
PowerShell 7, `-AcknowledgeCredentialWrite`, and a source-bound CurrentUser
state provider. Initial provisioning additionally requires `-AllowCreate` and
forbids a compare-and-swap value; it may create only the exact owner-marked root.
Rotation forbids implicit root creation and requires the lowercase SHA-256 of
the current canonical credential blob in
`-ExpectedCurrentCredentialBlobSha256`.

The entry point accepts exactly one 32-byte array, immediately copies it, and
clears every internal plaintext, entropy, protected-byte, and canonical-byte
buffer in `finally`. It deliberately does not clear or alter the caller-owned
array; the authorized caller must clear that array in its own `finally`. The
encrypted candidate is created with write-through semantics, re-read under the
exact schema and root binding, unprotected, compared in fixed time, and only
then atomically installed. Rotation first attempts
`File.Replace(candidate, current, null)`; a runtime that rejects a null backup
uses same-volume `File.Move(candidate, current, overwrite: true)` and never
creates a plaintext or DPAPI backup. A successful replacement leaves neither
`.next` nor `.backup`. A stale candidate or historical backup blocks provider
construction and every
validation/sign operation before the current blob is read, DPAPI is invoked, or
relay network transport can begin. Public results contain only fixed metadata
and the encrypted blob SHA-256, never the blob, path, secret, or provider
exception.

Host and CI tests replace only the fixed internal protect/unprotect wrappers
with a reversible fake and assert zero real credential access. They do not call
DPAPI. For the one-time manual smoke, the Host credential may enter only its
target process through secure input; the VM credential may use the one-use,
owner-only, repository-external handoff package described above. Before a
persistent unattended watcher is enabled, each relay runtime credential is
provisioned and round-tripped device-specifically in the CurrentUser context of
its target HostCoordinator host or VM tester device. Neither path authorizes
product Live execution.

Rotation is fail-closed and coordinated:

1. keep both automations and realtime watchers paused;
2. create a new key id and two new 256-bit secrets through the authorized
   provisioner;
3. write new Cloudflare secret bindings and new DPAPI CurrentUser blobs without
   logging either plaintext;
4. issue a new runtime assertion binding environment, endpoint, current key id,
    credential file hash, state-root token, fixed wake-binding hash, client
    adapter hash, and Git outbox runner hash;
5. allow a short current/previous key-id verification window and run both
   positive directions plus wrong-key, wrong-lane, replay, and expiry tests;
6. revoke the previous key id, verify it is rejected, and retain only
   public-safe rotation metadata.

Interactive Wrangler credentials stay in the OS keyring and are never used by
the watcher.

## Offline, smoke, and persistent activation gates

`TestSafe` and `DryRun` remain the default automated validation paths and do not
contact Cloudflare, npm, Credential Manager, the registry, or product
resources. The user has separately and explicitly authorized Free-only
Cloudflare items 1–7, reuse of the existing encrypted-keyring Wrangler default
profile, Worker/DO creation, two runtime secrets, `workers.dev` deployment, and
real positive/negative smoke tests. D-022 permits that manual smoke now without
machine-receipt or DPAPI-receipt gates. It does not convert the ordinary test
suite into a networked suite.
The authoritative request is the proposal's
[external authorization point](../../docs/REALTIME_RELAY_PROPOSAL.md#外部授权点);
the exact command, resource, credential, verification, and rollback procedure
is maintained in the sibling infra workspace's
[OPERATIONS runbook](../../../cddsi-relay-infra/docs/OPERATIONS.md).
HostCoordinator and VmTester automation stays `PAUSED` before and after any
deployment verification; this relay never enables automation or starts VM
product integration.

## Rollback and cleanup

Rollback does not require the Worker to be healthy:

1. pause the watcher and leave both Codex automations `PAUSED`;
2. close the WebSocket and stop creating new connections;
3. revoke/rotate the two runtime secrets and disable the Worker route or
   deployment when authorized;
4. continue the two protected control repositories and minute polling;
5. resynchronize unacknowledged pointers from Git, validating the existing
   control-repo chain;
6. invoke `Remove-CddsiRealtimeRelayOwnedState` only with the exact execution
   context, exact state-provider object, and action-bound cleanup assertion for
   the current-user owner root.

`Remove-CddsiRealtimeRelayOwnedState` requires an exact assertion bound to
`REMOVE_OWNED_RELAY_STATE`, mode, client ID, state-root token, current client
adapter hash, issued time, and expiry of at most 600 seconds. `TestSafe` and
`DryRun` return only `PLANNED`, `Changed=false`, and zero path/ACL/DPAPI/network/
process activity. Live additionally requires PowerShell 7 and the independent
`-AcknowledgeOwnedStateCleanup` confirmation.

Cleanup never claims or deletes an absent/unknown directory. It holds
`.lifecycle.lock`, then the watcher lock, then any existing per-lane publisher
locks in stable lane order; only after all applicable locks are held does it
re-enumerate the root and mutate state. It writes an immutable cleanup
tombstone, deletes only the exact current/candidate/backup watcher-state,
wake-proof, and encrypted credential files, and leaves the protected owner
root, locks, owner marker, and tombstone for auditable manual removal.

Publisher state, including a canonical pending publish and its current/next/
backup artifacts, remains outside the cleanup allow-list and blocks cleanup
rather than silently retiring outbound sequence/hash history. An inactive
`.publisher-<lane>.lock` file alone is tolerated and is not publisher-chain
authority. Operators must preserve actual publisher state evidence, fall back
to the protected control repository, and enter a separately reviewed new environment epoch
for chain retirement. Cleanup never recursively deletes a computed path or
retained evidence.

## Troubleshooting

- `REALTIME_SYNTHETIC_ASSERTION_INVALID` or
  `REALTIME_RUNTIME_ASSERTION_INVALID`: do not retry with relaxed checks. Verify
  the lane, exact reader id, environment, endpoint, bindings, and validity.
- `REALTIME_STATE_ROOT_INVALID`: stop. Inspect only the configured owner root;
  do not replace ACLs or follow reparse points automatically.
- `REALTIME_CREDENTIAL_ROTATION_CAS_MISMATCH`, a stale credential `.next`, or a
  stale credential backup: keep automation paused, preserve the current blob,
  and reconcile the exact owner root before retrying. Never bypass CAS or delete
  an unknown entry.
- `REALTIME_SEQUENCE_GAP`, `REALTIME_PREVIOUS_HASH_MISMATCH`, or an expired
  notification: close realtime and use the protected control-repo poll to
  rebuild durable truth.
- `REALTIME_ACK_PENDING_NOT_REPLAYED`: the transport stopped before replaying a
  consumed but unacknowledged message. Preserve state and reconnect/fallback;
  never advance the ACK cursor manually.
- `REALTIME_PUBLISH_PENDING_CONFLICT` or `REALTIME_PUBLISH_REJECTED`: preserve
  the canonical pending bytes and protected-repository evidence. Retry only the
  identical pending body; do not generate a replacement message in the same
  environment epoch or delete publisher state to advance the chain. An unseen
  expired message remains a relay rejection, while an already accepted
  MessageId may return `PUBLISHED_IDEMPOTENT`.
- `REALTIME_STATE_CLEANUP_ENTRY_INVALID` with publisher state/pending artifacts
  present: cleanup is correctly refusing to retire an outbound chain. Preserve
  the root and use the reviewed new-environment-epoch procedure. An inactive
  `.publisher-<lane>.lock` alone is permitted and is not chain evidence.
- `REALTIME_WAKE_PROOF_*` or `REALTIME_FIXED_WAKE_REJECTED`: preserve the
  owner-root proof and use the protected control-repository fallback. Never
  change `PENDING` to `SUCCEEDED` manually, and never edit/substitute the fixed
  prompt, argv, executable, wrapper, or environment to force a retry. Repair
  the exact binding or process failure and let the fixed idempotent inbox
  handler recover through the normal at-least-once path.
- `REALTIME_RECONNECT_EXHAUSTED` or `REALTIME_ACK_RETRY_EXHAUSTED`: remain on
  minute polling. Do not widen retry counts or timeouts to hide the fault.
- `REALTIME_WATCH_BLOCKED`: an untrusted provider or unexpected runtime error
  was deliberately redacted. Use local, secret-free diagnostics and focused
  tests; never echo credential/resolver exception text.

No troubleshooting step enables automation, changes product state, weakens
permissions, force-pushes, or removes the control-repository fallback.
