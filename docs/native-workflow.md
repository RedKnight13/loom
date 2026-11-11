---
layout: documentation
title: "Opt-in native CLI workflow"
---

# Opt-in native CLI workflow

This slice connects the actual S1–S7 APIs to `ops/loom` and adds a process workflow
importer for explicitly provisioned process or SSH execution. It includes remote
seal/check/collect and preparation-only bootstrap, but **does not establish
production or full S8 acceptance**: independent lifecycle, mail and resource
findings below remain release blockers. No active assignment is migrated.
GitHub remains the ticket integration; these APIs do not create an offline ticket
provider. No models or new packages are required by the fixture tests.

## Routing and API

Legacy TOML and root assignment records keep their handlers and public JSON
shape. V2 JSON must pass S3 validation. It cannot select legacy `auto` or weaken
placement through environment overrides. New legacy dispatch/launch refuses when
a v2 authority exists, including unresolved capacity; this conservative fence is
stronger than merely counting active slots. Existing legacy read/stop/harvest
remain on the old path. Mixed scopes require an explicit context.

Every facade response retains `{v,cmd,ok,state,fact,id,ticket,items,actions}`.
Normalized receipts live in `items`; `v` remains the Loom product version.
For exact contract responses use `--protocol 1` **with** `--request REQUEST`.
Protocol refusal retains the captured handler exit. Wrapper validation errors
that precede a valid request use the public envelope. Requests have the closed
S1 actor, target, expected revision and operation/idempotency fields; consult the
actual contract schemas and module documentation, not guessed command flags.

| CLI form | Actual API / behavior |
| --- | --- |
| `loom run --context CONTEXT --request REQUEST` | S6 run operations |
| `loom task --context CONTEXT --request REQUEST` | S6 task operations |
| `loom gate --context CONTEXT --request REQUEST` | S6 gate operations |
| `loom mail --context CONTEXT --request REQUEST` | S7 send/reply/poll/status/claim/read/ack/retry/pump |
| `loom send/ask/reply/peek/inbox --context CONTEXT --request REQUEST` | Only the corresponding S7 operation; peek/inbox require passive poll |
| `loom start/launch/show/status/read/stop/release/reconcile/list --context CONTEXT --request REQUEST` | Corresponding S4 or S5 execution operation, selected by installed context shape |
| `loom workspace --context EXECUTION_CONTEXT --request REQUEST` | S5 preparation and negotiated seal/check/export/read operations |
| `loom boundary --context WORKER_CONTEXT` | S7 cooperative boundary, at most 20 messages, no implicit ack |
| `loom dispatch --context WORKFLOW` | Replay exact S6 authorization and register a pinned native assignment |
| `loom start/show/status/read ID` | Registered native assignment; start uses pinned argv only |
| `loom harvest/verify/collect ID` | Verified report, checks on the selected host, exact-SHA fetch |
| `loom ack ID --reviewed SHA` | Explicit review of the exact checked/collected SHA; S6 acceptance |
| `loom events ID --after SEQUENCE` | At most 100 journal events, non-consuming |
| `loom capacity --context WORKFLOW` | Actual S3 reservation counts |
| `loom watch ID --deadline-ms N` | Explicit bounded process; 100–30000 ms polling deadline, plus bounded setup and up to one second termination grace; never consumes mail |

`stop` and `reconcile` require an exact request with revision, original operation,
reason and kill policy. A registered ID can accompany `--request` instead of a
context; its stored context selects the actual underlying module. Unsupported
commands refuse without probing Orca or selecting another provider/host.
`list` currently requires an S1 request and is per execution context. Aggregate
status/list and implicit current-run selection are not implemented.

Raw execution calls require already installed trusted authorization and binding
contexts; they are not a shortcut for creating new authority. S4 independently
checks exact policy, binding and durable capacity/launch receipts. Remote calls
use S5's fixed helper and identity pins. Ordinary caller data cannot install a
context. The process facade requires the actual S6 authorization API; a positive
fixture calibration proof is synthetic trusted provisioning, never evidence of
real model authentication or availability.

## Workflow provisioning

Provision the S2 authority/capacity store, S3 config/registries, S6 run/task/gates,
S4 execution spool/context and S6 launch plan using their documented APIs. Retain
private mode-0600 files with canonical paths and safe ancestors. Setup/calibration
and agent availability remain operator responsibilities. There is no installer,
automatic download or resident runner. `dispatch --context` registers an already
pinned mandate/assignment; fresh `dispatch --consumer CONFIG.json --issue N`
refuses pending a v2 GitHub importer. Existing native operations do not call `gh`.

A workflow context has exactly these fields. Paths are synthetic examples:

```json
{
  "schema": 2,
  "transport": "process",
  "coordination": "/srv/loom/coordination.json",
  "execution": "/srv/loom/execution.json",
  "binding": "/srv/loom/binding.json",
  "pin": "/srv/loom/pin.json",
  "plan": "/srv/loom/plan.json",
  "mail": "/srv/loom/mail-owner.json",
  "manifest": "/srv/loom/manifest.json",
  "checkout": "/srv/project",
  "check_script": "/srv/loom/check.sh",
  "source_digest": "OUTPUT_OF_loom_workflow_source"
}
```

`mail`, `checkout` and `check_script` may be null when those operations are unused.
The manifest is `{schema:1,base_sha:SHA,check_digest:DIGEST,report_offset:INTEGER}`.
Its exact Git-blob digest must equal the S4 binding's `manifest_digest` before S6
authorization. `report_offset` is the already consumed line count, measured during
trusted provisioning; old ready lines cannot count as this attempt's report.
`check_digest` is the exact trusted shell script digest, or null. The source pin
is produced by sourcing `ops/workflow.sh` and calling `loom_workflow_source`:
it hashes installed ops and schema content, including installed mail modules and
explicitly selected external modules with their adjacent shell dependencies and
schemas, plus the
check interpreter bytes.
No real paths or environment contents belong in tracked consumer configuration.

Process execution and checks require explicit process placement with
`allow_local:true`. The reusable process path does not authorize real agents on
a deployment with a remote-only policy. SSH failure cannot invoke this path.
For SSH, provision the preparation-only context first, then verify actual helper
capabilities and the prepared workspace before issuing the S6 launch receipt.
Explicitly install and pin the execution context afterward. Remote seal/check
requires an owner helper installation with the approved workflow descriptor;
worker routing alone grants neither operation. The facade negotiates all four
seal/check/export/read capabilities, runs checks on that host and downloads only
the resulting bounded immutable bundle. See [native-artifacts.md](native-artifacts.html)
for the closed installation and operation interfaces. No execution operation
installs authority or upgrades a preparation-only context.

Registration is a private routing snapshot at
`$LOOM_STATE/v2/workflows/<hashed-assignment>/context`. The journal remains the
coordination authority. Routing snapshots never overwrite a different registration
or rewrite a legacy record. Uncertain authorization retains the S6 preparation
and capacity slot. There is no new-attempt retry or active migration.

Harvest requires an exact identity-verified terminal receipt with captured exit,
plus a current bounded regular `REPORT.md`. Only ready plus exit zero moves to
review. Other report states/nonzero exits produce a failed task, retaining the
actual report and exit evidence. Missing/currently stale reports refuse. A private
Git index seals the result on its existing branch; no push or merge occurs.
Verification runs the pinned check script in a fresh clone of that exact SHA,
with a finite group keeper and continuously drained bounded output. Both paths
retain a check intent before execution; replay returns its receipt, and an
intent without a terminal receipt remains unknown without running again. Check timeout/setup failure cannot become
successful acceptance. Collection fetches to a dedicated `refs/loom/collected/`
reference and does not change the conductor's worktree. Native recollection uses
a compare-and-swap against its recorded ref; a conductor-moved ref is refused. `ack --reviewed SHA`
rechecks quiescence, task binding, source/config, workspace cleanliness and both
checked/collected SHA before supplying an exact S6 acceptance proof.

Evidence files are private reconstructable workflow receipts, while the S6 task
transition retains its verified proof in the journal. Remote promotion reads the original immutable check artifact and refuses missing
host intent/receipt; it never creates a check to recover lost proof. A crash
between evidence capture and transition may require explicit inspection/replay; the facade does
not promise automatic recovery at every workflow write boundary. The authority
capacity slot remains reserved after process exit/acceptance until a separately
verified S3 settlement; this slice does not automatically settle capacity or grant
release permission. Raw S4 release requires its existing explicit provisioning.

## Startup and cooperative mail

Install S7 `mail.sh` and `worker-bridge.sh` beside the other runtime modules.
Split development can set `LOOM_WORKFLOW_MAIL_MODULE` or
`LOOM_WORKFLOW_BRIDGE_MODULE` to the actual files, with S7's documented dependency
overrides. These are trusted installation settings, never message fields.
No S7 duplicate files are committed by this slice.

An optional private sibling of the native context, `CONTEXT.mail`, has exactly
`{schema:1,context:WORKER_CONTEXT,context_digest:DIGEST,bridge:BRIDGE_PATH,
bridge_digest:DIGEST}`. The startup bridge must be the co-installed
`worker-bridge.sh` beside the native supervisor so its adjacent dependencies are
covered by the runtime pin. Provision it with the exact S7 worker binding (or remote
native context) and exact Git-blob digests. The supervisor checks those digests
and binding equality, then invokes the actual bridge **before releasing the exec
gate**. Failure leaves execution gated; it cannot silently start without mail.
The bridge call has a 30-second deadline. This descriptor is trusted provisioning
under the existing same-account model, not a cryptographic authorization token.

The child receives `LOOM_STARTUP_MAIL_FILE`, `LOOM_MAIL_CONTEXT` and
`LOOM_MAIL_BRIDGE` only when a startup boundary succeeded. The startup file holds
escaped message data, claim tokens and read receipts. At a subsequent cooperative
turn, invoke `bash "$LOOM_MAIL_BRIDGE" boundary "$LOOM_MAIL_CONTEXT" 20` or the
facade's boundary command. Ack is a separate mail request with the token, message
digest and current revision. With no startup descriptor the supervisor records
`delivery_mode:"disabled"`. Busy/noncooperative clients have no injected keys,
hidden wakeup or automatic continuation. Watch/status never call a mail boundary.

## Validation and remaining acceptance

Run the explicit suites; install/bootstrap does not invoke them:

```sh
bash tests/conformance/legacy.sh
bash tests/conformance/native-workflow.sh
bash tests/conformance/remote-artifacts.sh
LOOM_ARTIFACT_CASE=worker-failed bash tests/conformance/remote-artifacts.sh
LOOM_ARTIFACT_CASE=check-nonzero bash tests/conformance/remote-artifacts.sh
LOOM_ARTIFACT_CASE=check-timeout bash tests/conformance/remote-artifacts.sh
bash tests/conformance/check-keeper.sh
bash tests/conformance/git-boundary.sh
bash tests/conformance/status.sh
bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom
```

Until S7 is integrated, set `LOOM_CONFORMANCE_MAIL_ROOT` to its actual installation
containing `ops/mail.sh`, `ops/worker-bridge.sh` and `tests/mail/run.sh`. The test
stages actual modules under a private temporary directory and removes them.
Evidence goes under `.loom/conformance/`: normal API elapsed milliseconds and
captured exits are separate from fault-suite measurements. The suite uses actual
Linux processes, S2 transactions, S3 policy, S6 authorization and S7 delivery.
It is not a real-agent or network SSH acceptance test. The S5 fake transport suite
and S7 remote-mail suites are separate evidence; no successful local fixture
clears the documented real-network SSH execution blocker.

Remaining gaps: fresh v2 ticket dispatch, automatic remote authorization install,
aggregate lifecycle views, automatic capacity settlement,
workflow-wide crash recovery, keep-open/abandon/scheduling, and deployment-specific
calibration/real-agent readiness. Explicit wire APIs cover run/task/gate/mail and
native lifecycle, including unsupported capability refusals. There is no claim of
S9 adapters, S10 calibration or full S8/S12 acceptance.

The merge includes fixes for stale-owner mutation replay, cancelled-attempt
settlement, stop/release control-cache recovery, delivery/route fairness, sparse
output publication and EOF-read scanning. Legacy sealing failures now block
verification/collection, and collection protects conductor-edited references.
These fixes do not establish production acceptance.

Remaining tracked limits are [state replay latency and contention](https://github.com/RedKnight13/loom/issues/122),
[supervisor scan CPU](https://github.com/RedKnight13/loom/issues/123),
[legacy local descendant settlement](https://github.com/RedKnight13/loom/issues/124),
and [real SSH, adapters, calibration and rollout acceptance](https://github.com/RedKnight13/loom/issues/125).
The native runtime remains an explicitly provisioned, opt-in integration surface.
Do not select it automatically from installation presence or claim the missing
acceptance checks have passed.

Remote fixture evidence is written under `.loom/artifacts/`, with source hashes,
normal facade timings and fault timings recorded separately. The transport is a
deterministic executable substitute for SSH; the helper, authority journal, Git
operations, startup mail and worker/check processes are real. Real network SSH
is not run. A check deadline bounds approved check execution, while compound
facade operations make several bounded RPCs and have additional validation and
Git costs; their observed total latency is not a single-RPC deadline guarantee.
Install/bootstrap never runs the regression suites.
