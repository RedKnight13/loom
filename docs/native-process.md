# Native process execution

`ops/native.sh` is the source-safe Linux execution-provider surface. It does not
register commands in the shared CLI or change legacy launch behavior. Source it
and call `loom_native_handle CONTEXT REQUEST`, or `loom_native_serve CONTEXT` with
one S1 `loom.execution` request on stdin. The executable forms are
`bash ops/native.sh handle CONTEXT REQUEST` and `bash ops/native.sh serve CONTEXT`.
Responses and exit codes follow protocol 1.0. The complete handler is bounded by
the request deadline; deadline loss yields unknown for possible mutations. Agent exits occur only in captured
terminal receipts; transport status never substitutes for them.

Install S1 `protocol.sh` and its schemas, S2 `state.sh` and its schemas, and S3
`policy.sh` and its schemas beside these modules. Tests of independently developed
slices may set `LOOM_NATIVE_PROTOCOL_MODULE`, `LOOM_NATIVE_STATE_MODULE` and
`LOOM_NATIVE_POLICY_MODULE` to their actual files. These are trusted installation
settings, not request fields or transport fallback choices.

## Provisioned context for process and SSH

The following is the closed context shape. All values here are synthetic. Files
must be canonical absolute paths, owned by the invoking UID, private (mode 0600
files / 0700 directories), without symlink components. Shared ancestors must be
root-owned sticky directories or not writable by other users. Configuration and
registry files use S3's ownership and mode checks. No request field supplies paths.

```json
{
  "schema": 1,
  "state_root": "/srv/loom/spool",
  "store_id": "execution-spool",
  "authority_store_id": "consumer-authority",
  "installation_id": "installation-example",
  "transport_identity": "verified-transport-example",
  "config": "/srv/loom/config.json",
  "hosts": "/srv/loom/hosts.json",
  "profiles": "/srv/loom/profiles.json",
  "pin": "/srv/loom/attempt/pin.json",
  "binding": "/srv/loom/attempt/binding.json",
  "authorization": "/srv/loom/attempt/authorization.json"
}
```

`installation_id` is a persistent random installation UUID provisioned by the
installer, not a machine name. The SSH helper must verify transport host-key and
helper identity before selecting this context. `transport_identity` must equal
S3's selected host identity. A copied UUID is not transport authentication. Process
transport requires the explicit process policy and `allow_local:true`; SSH policy
is honored on the already authenticated execution host, never rerouted locally.

The closed binding has these fields:

```json
{
  "schema": 1,
  "actor": {"id":"owner-example","run_id":"run-example","epoch":0},
  "target": {"assignment_id":"assignment-example","attempt_id":"attempt-example","host_id":"compute-example"},
  "workspace_id": "workspace-example",
  "workspace": "/srv/workspaces/attempt-example",
  "prompt_ref": "prompt-example",
  "prompt": "/srv/loom/attempt/prompt.txt",
  "manifest_digest": "git-blob-sha1-v1:1111111111111111111111111111111111111111",
  "profile_digest": "git-blob-sha1-v1:2222222222222222222222222222222222222222",
  "prompt_digest": "git-blob-sha1-v1:4444444444444444444444444444444444444444",
  "executable_digest": "git-blob-sha1-v1:3333333333333333333333333333333333333333",
  "limits": {"runtime_ms":null,"stop_on_timeout":false,"allow_kill":false,"output_bytes":67108864},
  "stop_authorized": true,
  "release_authorized": false
}
```

The profile digest is S3's canonical selected-profile digest. `argv`, model and
effort must equal the S3 pin exactly. The executable is checked by content digest
before reservation and immediately before exec. The prepared workspace must be
below the selected host's workspace root. S5 prepares workspace, prompt and
manifest; this module does not clone, fetch, run setup or create work mandates.
The prompt is digest-checked and copied into the private spool before the gate.
Stdin ingress reads that immutable prompt copy; file ingress exposes its literal path
as `LOOM_PROMPT_FILE`. The agent environment is only `PATH=/usr/bin:/bin`,
`LANG=C.UTF-8`, `HOME` set to its workspace and `LOOM_BINDING_FILE`, plus that prompt
file variable when applicable. No parent credentials or arbitrary environment
values are forwarded. Argv uses NUL-delimited decoding and an array, never eval.

Hello validates the trusted installation, binding shape and current S3 pin before
returning capabilities, but does not require the authorization file to exist.
This permits negotiation before the authority can approve launch. Every lifecycle
operation still requires the complete authorization; hello creates no reservation.

The authorization document contains exactly `capacity_receipt` and
`launch_receipt`, each a durable S2 transaction outcome from `authority_store_id`.
The capacity outcome is produced by committing the exact transaction from
`loom_policy_reserve_request`; its result must contain the exact attempt and full
policy pin. The launch outcome's result must be
`{actor, target, binding_digest}` matching the binding. Compute `binding_digest`
by removing `stop_authorized` and `release_authorized`, then passing the remaining
JSON to `loom_policy_scope`. The authority creates this outcome after checking
current run ownership/epoch, task readiness, gates, capacity, calibration and
prepared workspace identity. The focused fixtures use real S2 transactions to exercise this handoff. The
separate coordination integration uses the actual S6 authorization API and checks
that process completion never accepts a task or frees its global reservation.

These copied receipts are trusted, verified provisioning inputs, not signatures.
The helper must obtain them through its authenticated binding-installation path;
it must not accept arbitrary user-uploaded receipts as authority. `state_root`
is a separately initialized **execution spool**, never a second task authority.
It records only S2 `host` facts under a null-run system actor. It cannot grant
run ownership, approve gates, reserve global capacity or settle tasks. Authority
receipts remain with the attempt, and unknown outcomes retain the authority slot.

## Lifecycle and recovery

Start rechecks S3 policy and exact binding, commits the S2 host reservation, then
starts a detached session keeper with closed inherited stdio. A gated child can
exec only after keeper/worker identity has passed file and directory flush
barriers. The keeper records host ID, transport identity, installation ID, boot
ID, UID, PID/start ticks, PGID/SID, keeper PID/start ticks, attempt and random nonce.
The output writer has its own separately recorded process identity and session.

Reservation is a permanent no-relaunch fence. Same canonical semantic request
(excluding request ID and call timeout) reads the existing attempt. Any changed
request conflicts; a crash before a usable launch receipt remains unknown and
requires explicit resolution, never a fresh launch under the same attempt.
Identity, exec-intent and terminal facts are also immutable S2 journal events;
inspect/reconcile rebuild missing identity/completion cache files from those
committed outcomes. The exec-intent file distinguishes the gate from a possible exec. It is not an
agent readiness handshake: prompt acceptance and launch verification remain
unknown. The keeper captures the exact Bash wait status and retains surviving
children in the group before completion. A wait value of 128+n is not interpreted
as a proven signal because an agent can explicitly exit with that value.

Stop requires the exact actor/epoch/target, current S3 pin, explicit binding
permission and a revision CAS. The keeper reads a durable stop request, compares
its own identity and the current provisioned binding immediately before each
signal, and signals its own group. It traps TERM to stay the identity anchor.
Only `args.allow_kill:true` authorizes group KILL; there is no external bare-PGID
fallback. Stop replay never creates another stop request. A separate observer can
confirm an empty original group after KILL, with exit code unknown if no wait
receipt survived. Lost observation, keeper identity mismatch or observed escaped
descendants stays unknown. No silence, timeout or read operation sends a signal.

Inspect and reconcile never launch or stop anything. Reconcile accepts only a
recorded start/stop operation ID. Completion and output remain retained. Release
requires confirmed settlement, drained output and explicit authority provisioning
of `release_authorized:true` after evidence/collection prerequisites; it marks the
resource released without deleting workspace, output, receipts or tombstones.
This initial context is per attempt: list returns only that bound attempt and
requires the exact run. Cross-attempt listing belongs to the host routing layer.

## Bounded output

The independent writer continuously drains a combined stdout/stderr FIFO in
4096-byte chunks. It retains a whole-chunk tail within `limits.output_bytes` and
records the exact discarded prefix `[from_byte,to_byte)`. Quota never stops the
drain. On-disk transient overhead is at most one incoming chunk, one new chunk,
small metadata and bounded reader scratch; retention is not a filesystem quota.
Chunks are flushed before publishing their index. A crash can leave an orphan
chunk, but it never turns lost output into process completion.

Read source is `combined.base64`: `data` is base64 for arbitrary binary output,
including NUL and invalid UTF-8. Decode it before display. `limit_bytes` bounds
encoded data (minimum four bytes); cursors count original stream bytes and bind
source generation to the attempt's random nonce. Gaps are exact raw-byte ranges.
A changed generation, future offset or unknown source is refused. Reads and
rotation share a short lock. EOF is recorded only after the FIFO drains.

## Supported boundary and validation

Hello advertises only start, inspect, per-context list, read, reconcile, guarded
stop and release. Workspace operations, live prompt injection, safe owner takeover,
automatic runtime-limit signaling are not advertised. Model/effort selection is
advertised only when the selected S3 profile has an explicit mapping; this proves
argument selection, never model availability or authentication. A requested automatic stop policy is explicitly refused.
Runtime limits without automatic stop remain observations for the authority.
This is trusted process management, not containment: profiles must keep children
in the group. Observed escapes prevent completion; deliberately daemonized children
that escape between observations cannot be contained by Bash process groups.

Linux Bash 4+, `/proc`, `setsid`, `sync -f`, `flock`, GNU core utilities, Git and jq
are checked explicitly. No resident daemon, new dependency or telemetry is used.
No network-filesystem durability, hardware power-failure recovery, real-agent
readiness or real SSH launch is claimed by fixture tests. Focused tests are
`bash tests/native/run.sh`. `bash tests/native/coordination.sh` exercises the actual
S6 authorization API, S3 capacity and S2 journal before launching a fake S4 worker;
set `LOOM_NATIVE_COORDINATION_MODULE` only when S6 lives outside the installed
`ops/` directory. Its launch proof is synthetic trusted provisioning, not real
agent calibration. The existing gate remains
`bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`.
