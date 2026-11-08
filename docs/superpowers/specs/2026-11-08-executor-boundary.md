# Executor boundary: Loom-owned coordination and optional orchestrator adapters

Date: 2026-11-08. Status: implementation design, not an implemented capability.

## 1. Decision and constraints

Loom owns the coordination needed to execute its workflows: runs, tasks,
dependencies, gates, assignments and attempts, placement, mailboxes, lifecycle,
recovery, events, evidence and receipts. No external orchestrator is required.
Native process execution and native SSH execution implement the same contract.
Orca, Herdr and future orchestrators are optional execution adapters; compatibility
means implementing and passing this contract, not guessing another product's API.
An adapter may mirror Loom coordination into an external product, but that mirror
does not become the authority for a new Loom-owned run.

Preserve the owner's remote-only compute policy: all real agents and their checks
run on explicitly approved compute hosts, never by fallback to the main device.
The reusable local transport exists for explicitly permitted deployments and test
fixtures. Making it independent of Orca does not authorize local real-agent use.
No real agent is launched as part of this design. No active worker is migrated.

Keep the current trusted-config/trusted-host model. This is process management,
not a sandbox or a security boundary against an agent with the same OS account.
Workers do not stage, commit or push; Loom seals work and the conductor alone
pushes, reviews and merges under the owner's GitHub identity. No database,
resident coordination service, message broker, new package stack or IDE/browser
reimplementation is required. Bounded, explicit polling is sufficient and must
not be described as continuous monitoring when no poller is running.

GitHub remains a separate ticket integration dependency. Orchestrator independence
does not mean offline ticket creation, a replacement issue tracker, or removal of
`gh`, Git or the conductor's GitHub workflow.

Normative words MUST, MUST NOT and MAY below specify implementation requirements.
The staged plan is the implementation boundary; this document changes no runtime.

## 2. Source-grounded inventory

Audit base: `0caf4a6bf8d2151ff9dfc5cc4c84cce40dadb135`. Locations below refer to
that revision, not an assertion that a concurrently developed fix has landed.
The first local-independence slice is being developed separately; its merge and
acceptance status must be checked before dispatching duplicate work.

| Source | Behavior actually present | Required boundary |
| --- | --- | --- |
| `ops/dispatch.sh:24-38`, `ops/lib.sh:278-303` | Config accepts only `auto/local/orca`; auto detects Orca, otherwise chooses local. Explicit Orca refuses if unavailable. | Keep legacy resolution; v2 config explicitly pins provider, transport and placement. |
| `ops/dispatch.sh:55-149` | Reads GitHub issue/default branch, pins mandate/base/config commit, limits workers, creates a remote-less local clone or an Orca pending record. | Ticket source and assignment planning remain Loom operations; workspace creation is provider/transport specific. |
| `ops/launch.sh:21-60` | Native argv launch already exists; explicit local still refuses when Orca is ready unless overridden. Uses job-control process group, PID plus `ps lstart`, waits and harvests. | Remove presence veto for explicit local; retain policy enforcement. Add durable detached supervisor, receipt and recovery rather than claiming the existing launcher is a remote lifecycle. |
| `ops/lib.sh:16-136` | Private JSON records, PID-only directory lock, atomic rename, local PID/start identity; Orca liveness is recorded state. Validator recognizes only local/Orca. | Versioned state and locks, host/boot/start identity, unknown liveness distinct from dead. |
| `ops/loom:183-211,285-310` | Start/harvest/stop/release, show/read/list, coordination proxies and hosts route to `orca.sh`; capacity infers suggestions from Orca or one local worker. | Provider-neutral dispatcher and native coordination; capacity is declared limits/observations, not a guessed resource guarantee. |
| `ops/orca.sh:175-303` | Start resolves connected Orca hosts and project setup, pins base, writes starting before `worker-start`, records provider IDs; raw receipt parsing includes recursive key search. | Isolate in adapter; replace recursive guessing with version-specific parsers and identity checks. |
| `ops/orca.sh:60-110,313-475` | Completion checks distinguish durable evidence from live status; stop/release require confirmation; read archives output, abandon fences without claiming stop. | Preserve these safety properties in normalized results, including retained resource versus active work. |
| `ops/orca.sh:480-583` | Send marks continuation pending before delivery; reconcile verifies parent/task/run/workspace and report boundary, archives prior evidence. | Preserve uncertain-send fencing and attempt history; new native send must not implicitly reopen a task. |
| `ops/orca.sh:587-717` | Ask/reply, gates/tasks/runs, references, workspace/repo operations and automations are Orca proxies. | Native mail, DAG/gates and run ownership; core Git references and explicit schedule execution; optional UI operations remain extensions. |
| `ops/lib.sh:140-272`, `ops/collect.sh` | Workspace commands, reports, evidence and branch retrieval already work over SSH via recorded `ws_host`; harvest seals changes and tracks report offsets. | Reuse workflow behavior through explicit workspace identity; bound transfers and enforce completion before sealing. |
| `ops/verify.sh:42-138` | Checks already use declared reachable SSH hosts, transfer an exact Git bundle, create a fresh clone and record check exit/SHA/host; declared-host failure refuses local fallback. | Keep check execution separate from agent lifecycle. Pin selected host and distinguish transport/setup failure from captured check exit. |
| `ops/watchdog.sh:35-57`, `ops/status.sh`, `ops/heartbeat.sh` | Local timeout can issue group KILL then clear PID without confirmation; Orca silence is surfaced for owner decision. Watch loops until settlement, not an independently bounded monitor. | Native timeout becomes an observation; authorized stop is identity-guarded and confirmed. Watch has a wall deadline and never consumes mail. |
| `ops/calibrate.sh:137-264` | Fingerprints source, config, bridges and tools; Orca executable/selector affect tool digest even for explicit local, although local skips runtime probe. Schema 1 recognizes only local/Orca. | Selected-provider fingerprint only; versioned snapshot readers, source/config drift and remote helper identity. |
| `ops/calibrate.sh:82-135,267-353` | Fixed offline fixture, reobservation, private proof, bounded tool calls; real agent execution and project acceptance explicitly `not_run`. | Preserve this truth boundary; calibration is not launch verification or acceptance. |
| `ops/ticket.sh`, `ops/dispatch.sh`, `ops/mutate.sh` | GitHub CLI issue operations and mutation rehearsal are independent of Orca lifecycle. | Keep ticket integration visible and test failures separately. |
| `ops/selftest.sh` | Existing local, Orca stub, remote verification, follow-up and calibration regressions. | Retain them; add contract/native SSH suites rather than replacing existing coverage. |

### External evidence and limits

The installed `orca agent-context --json` returned `schemaVersion: 1` and 311
command descriptions. It is a command-discovery schema, not proof that every
runtime/remote host supports every response shape. Evidence and a selected
command subset are retained under `.loom/executor-boundary/`. Relevant facts:

- `orchestration worker-start` supports explicit placement, model/effort,
  `--spec-file` and `--retry-request`; partial/unknown starts require inspection.
- `worker-show --full` supplies identity/evidence; `worker-stop` may report
  `stop_unknown` even after issuing a close. `worker-release` can succeed while
  reporting retained/pending, so exit zero is not proof of release.
- `worker-read` has a source-pinned cursor. Source change is explicit.
- Plain `orchestration check` consumes mail; `--peek` is non-consuming. Loom
  observers must not call consuming check to implement polling.
- Agent/model selection is agent and host dependent. No model catalog follows
  from the existence of a command flag.

Herdr here means [herdrdev/herdr](https://github.com/herdrdev/herdr), linked from
the owner's [official agents documentation](https://herdr.ink/docs/agents), not
another similarly named project. Those docs distinguish lifecycle-hook authority
from screen-manifest observations. Screen `idle`, `done` or `blocked` is not a
Loom completion receipt.

The [official automation reference](https://herdr.ink/docs/agent-automation)
describes starting an agent in an existing shell pane, passing arguments after
`--`, prompt/read/wait operations, mutable pane addresses and waits that do not
track individual turns. The [socket reference](https://herdr.ink/docs/socket-api)
documents `herdr api schema --json`, request/response/events, snapshots and process
information. This establishes a plausible adapter surface, not verified parity.
Implementation MUST inspect the selected installed version and test it. No Herdr
runtime was exercised here. The initial reader was blocked and `gh` lacked auth;
public official pages were retrieved with the web reader instead. No credentials
were inspected or changed.

## 3. Components, policy and configuration

```text
CLI / worker bridge
        |
Loom core: policy, state journal, ownership, DAG/gates, mail, workflow
        |                          |
execution contract                ticket integration (GitHub/gh)
        |
native provider             optional command adapters
  process transport           Orca / Herdr / third parties
  SSH transport               provider-specific versioned parsers
        |
agent launcher profile (separate from provider and transport)
```

Core decides whether an operation is legal and persists the intent before the
provider acts. Providers report effects and observations; they cannot declare a
dependency satisfied, approve a gate, mark checks passed or choose a different
host/model. A worker bridge invokes Loom commands with its exact assignment and
attempt binding. It has no implicit ambient terminal/run authority.

New configuration uses schema 2. Preserve the existing flat TOML parser as a v1
reader; add a JSON form for v2 instead of inventing nested TOML support or adding
a TOML dependency. The following is a *synthetic* configuration shape; private
host aliases, executable locations and environment values belong in untracked
operator config, not this repository:

```json
{
  "schema": 2,
  "repo": "example/project",
  "execution": {
    "provider": "native",
    "transport": "ssh",
    "placement": {
      "allowed_hosts": ["compute-primary"],
      "selection": "explicit",
      "selected_host": "compute-primary",
      "allow_local": false,
      "fallback": "deny"
    },
    "agent_profile": "worker",
    "model": null,
    "effort": null
  },
  "limits": {"workers": 2, "operation_timeout_ms": 30000},
  "ticket_provider": "github"
}
```

Host/profile registries are separate operator-owned files with revision digests.
Host entries contain an opaque host ID, transport, SSH destination, allowed
workspace root, helper version/digest and pinned identity. Agent entries contain
an executable plus an argv array, supported prompt ingress and explicit parameter
mapping. Command-adapter entries contain an executable and an argv prefix array.
There is no shell command-string field for launching an adapter or agent.
Existing trusted consumer check/setup scripts remain explicitly designated shell
scripts; do not extend that exception to message bodies or launch arguments.

Resolve and persist provider, transport, host ID, host identity, profile digest,
exact model/effort (including explicit null), source/base, setup/check policy and
capability snapshot before launch. No environment-variable override may weaken
`allow_local: false`. Failed SSH connectivity never selects process transport;
adapter failure never selects native; unknown model support never drops the model
flag. An ordered pool MAY select among expressly allowed hosts *before* intent,
with every probe and final selection in the receipt; once intent exists, all
retries and reads target its pinned host. Host changes require a new authorized
attempt after the old attempt is proven stopped or explicitly resolved.

## 4. Portable state and durable operations

Use `$LOOM_STATE/v2/` beside legacy records. One authority store belongs to one
consumer checkout/installation ID, not to a terminal or transient coordinator
process. Remote execution hosts have a small private execution spool; they do not
silently become independent task authorities.

| Record | Required content |
| --- | --- |
| Run | ID, objective, owner actor ID, ownership epoch, state, revision, parent run/null, consumer/config digest, creation time. |
| Task | ID, run, immutable spec digest, dependency IDs and policies, gate IDs, state, revision, attempt IDs, accepted result/null. |
| Assignment | ID, task, issue reference, base SHA, consumer snapshot, branch/workspace reference, allowed placement, report cursor, checks and collect/ack history. |
| Attempt | ID, assignment, ordinal, parent attempt/null, owner epoch, provider/transport/host binding, launch operation, execution state, observations, terminal result/null, resource disposition. |
| Message/delivery | Message ID and digest, sender, concrete recipient, thread/reply reference, kind/body, delivery ID, attempt binding, timestamps, state, retry/lease/dead-letter fields. |
| Gate | ID, task/run, question, options, designated resolver, state, revision, resolution evidence/null. |
| Operation | ID, idempotency key, canonical request digest, pinned target, actor/epoch, stage, receipts and effects. |
| Event | Schema, sequence, event ID, transaction ID, actor/epoch, entity IDs, previous revisions, type, payload, recorded/observed times. |

IDs are opaque strings, not paths or provider handles. A provider resource is a
namespaced opaque reference; an Orca dispatch or Herdr pane is never a Loom task
ID. Private state may contain actual paths/host identities; public summaries and
committed fixtures use synthetic values. Preserve origin provider receipts as
bounded evidence, without putting raw environment or credential values in them.

### Commit protocol

Use immutable, monotonically numbered transaction files containing events and
operation outcomes; JSON snapshots are rebuildable projections. Under a short
store lock: validate schema and expected revisions, allocate sequence, write a
same-filesystem temporary file, flush it, atomically rename to the committed
sequence, flush the containing filesystem, then acknowledge. A committed
transaction is the sole authority; snapshots can lag and are replayed after a
crash. Reject sequence gaps/conflicting transactions; never skip malformed state.
Do not return `durable: true` before the flush barrier.

The first native target is Linux using existing Bash/Git/jq/system tools. Probe
`setsid`, `/proc` identity and `sync -f` capability; `sync -f` on the temporary
file and containing directory provides the filesystem flush barriers without a
new package service. Other platform implementations must provide equivalent
barriers and identity proofs or return `unsupported_capability`. No claim of
durability on an untested network filesystem. Schema portability does not mean
every OS has a validated process adapter on day one.

Validate private ownership/mode and reject symlinked state roots, ancestors and
records; use unpredictable same-directory temporary names, never shared
`.pending`. Evidence import rejects nested links, special files and archive
traversal as well as enforcing byte/file-count limits. These checks guard
mistakes and untrusted data, not hostile same-account code.

The lock records host/boot identity, PID/start token and random owner nonce.
Only break a lock after proving that exact local owner gone; foreign/ambiguous
locks block. Unlock/reclaim must compare the owner nonce, and all retry paths
have a deadline; concurrent reclaim cannot remove a replacement owner's lock.
Locks are short, not held over SSH, provider calls or agent waits.
Reserve intent under lock, call outside it, reconcile under lock using revision
and ownership-epoch comparisons. A stale response is evidence, not permission to
overwrite newer state. Each host spool applies the same per-operation exclusion.

Every mutation has an idempotency key scoped to store/actor/operation. Same key
and canonical request returns the existing operation; a changed request with
the same key returns `idempotency_conflict`. Keep key tombstones for the life of
the run and its retained history. Expired history returns `replay_expired`, never
starts anew. This is deduplicated operations, not exactly-once agent execution.

Intent, partial effects, accepted launch, terminal outcome, message enqueue/ack,
gate resolution and ownership changes are persisted events. Clock time is for
display and deadlines; event sequence and revision determine order. No hidden
telemetry, inferred token usage or invented model catalog is added.

### Ownership and state machines

Run ownership is an explicit actor plus monotonically increasing epoch. `run use`
selects context, not ownership. `run claim` requires current-owner release or an
explicit conductor-authorized takeover with expected revision and reason. Every
mutating call carries epoch. Native host helpers reject stale epochs. A takeover
must reconcile each host's epoch before lifecycle mutations; disconnected hosts
remain unknown and occupy their slots. An adapter unable to fence an in-flight
old-owner operation cannot claim safe takeover for that operation.

Task states are `pending`, `ready`, `running`, `waiting`, `review`, `succeeded`,
`failed`, `cancelled`. Pending becomes ready only when all dependency results are
accepted as succeeded and all required gates are approved. Reject missing IDs,
cross-run edges unless explicitly linked, self-edges and cycles atomically.
Default dependency failure blocks dependents; no implicit skip-as-success.
Graph edits while an affected task is running are refused. Retry creates a new
attempt; it does not erase failure or satisfy a dependent early.

Gate states are `open`, `approved`, `rejected`, `cancelled`. Only its designated
resolver or authorized run owner resolves it, with expected revision, decision
and evidence. Conflicting resolutions fail. No timeout approves a gate. A gate
opened while a task runs records a waiting/stop request but does not prove that
process paused; settlement of the active attempt is required before redispatch.

Execution states are `reserved`, `starting`, `running`, `stop_requested`,
`exited`, `start_failed`, `unknown`. `unknown` is uncertainty, not terminal
failure. Resource state is independent: `owned`, `retained`, `released`, `unknown`.
Fencing/abandonment is an authority flag, not proof of exit. A task can be in
review while an adapter retains an idle UI resource, only with exact evidence
that the assigned turn is settled and workspace writes are quiescent.

Worker `REPORT.md` keeps its four existing states. Ready means reviewable work,
not task success or verification. A current-attempt report plus confirmed native
exit, or exact adapter turn-completion evidence, permits harvest to review.
The conductor records acceptance after the required fresh-clone checks and
review; only that transition satisfies dependencies. Message ack, shell exit 0,
UI idle and an old ready line cannot complete a task. Preserve report offsets,
immutable attempt history, checked SHA and moved-tip rejection. Report entries
carry structured source (`worker`/`conductor`), attempt and content digest;
prose claiming verification cannot impersonate a structured check result.
Collection for inspection may be unverified and must be labeled accordingly;
verified promotion/acceptance requires a successful branch check for the exact
collected SHA and pinned check/config identity. Cancelling a task or run does
not by itself stop its processes; unresolved attempts still occupy capacity.

## 5. Versioned operations and receipt contract

### Wire format and negotiation

Protocol name is `loom.execution`; initial version is `1.0`. Store schema 2,
protocol major 1, provider schema versions and Loom release version are distinct.
Do not infer compatibility from a release number. Before an effectful call, send
`hello` offering supported majors/minors and required capabilities. Select the
highest mutually supported version of a common major, record it and pin the
capability digest. No common major means `protocol_mismatch`, with no effects.
Unknown operations/required capabilities are refused before side effects. Minor
extensions are optional and namespaced under `extensions`; new required fields
or changed meanings need a new major. Readers reject unexpected core fields.

One UTF-8 JSON object followed by newline on stdin; exactly one object on stdout.
No progress text or provider JSON is mixed into stdout. Stderr is a bounded
diagnostic stream, never interpreted as the result. Duplicate JSON member names,
NUL in string arguments, non-finite numbers, invalid UTF-8 and trailing documents
are invalid. Use a bounded lexical duplicate-key check before jq decoding; jq's
last-key-wins parsing alone does not enforce this contract. Publish JSON Schema
2020-12 documents and matching jq/CLI validation fixtures in slice S1; no runtime
JSON Schema library is required.

Schema compilation rules: identifier/reference fields are nonempty strings,
nullable only where specified; lists are arrays with unique IDs when they denote
a set; booleans are JSON booleans, never string coercions. Revisions, epochs,
counts and millisecond durations are nonnegative safe JSON integers with the
stated bounds. Agent argv is an array of strings with a nonempty executable at
index zero. Digest values name their algorithm; initially use the existing
`git-blob-sha1-v1` drift digest, not an authenticity signature. Native start ticks
are decimal strings to avoid 64-bit JSON rounding. All nested records are closed
except namespaced extension objects. The following hello request is a normative
valid fixture; `versions` lists supported exact pairs and capabilities are
version-suffixed strings:

```json
{
  "protocol": "loom.execution", "version": {"major": 1, "minor": 0},
  "request_id": "hello-example", "operation_id": null,
  "idempotency_key": null, "op": "hello",
  "actor": {"id": "conductor-example", "run_id": null, "epoch": 0},
  "target": {"assignment_id": null, "attempt_id": null, "host_id": null},
  "expected_revision": null, "timeout_ms": 5000,
  "args": {
    "versions": [{"major": 1, "minor": 0}],
    "required_capabilities": ["execution.stop.group.v1"]
  },
  "extensions": {}
}
```

Normative common envelope (all listed fields required, nullable where stated;
`additionalProperties: false` except `extensions`):

| Request field | Type / constraint |
| --- | --- |
| `protocol`, `version` | Literal `loom.execution`; `{major: integer >= 1, minor: integer >= 0}`. |
| `request_id` | Nonempty opaque string, at most 128 bytes, correlates this call. |
| `operation_id` | Opaque string for mutations and replay; null only for pure reads/hello. |
| `idempotency_key` | Nonempty string for mutations; null for pure reads/hello. |
| `op` | Exact operation name from the registry below. |
| `actor` | `{id: string, run_id: string\|null, epoch: integer >= 0}`; worker binding is validated separately. |
| `target` | `{assignment_id: string\|null, attempt_id: string\|null, host_id: string\|null}`. |
| `expected_revision` | Integer >= 0 for an existing entity mutation; null for creation/pure read. |
| `timeout_ms` | Integer 1..300000; elapsed call deadline, not agent runtime limit. |
| `args` | Operation-specific closed object; validate before acting. |
| `extensions` | Object with namespaced keys; unknown optional entries ignored. |

Responses echo protocol/version/request/operation/op/target and add:

| Response field | Type / meaning |
| --- | --- |
| `ok` | Boolean: request handled in the stated sense; not agent success. |
| `status` | `completed`, `accepted`, `pending`, `unknown`, `refused`, `failed`. |
| `revision` | Committed entity revision or null. |
| `durable` | Whether acknowledged state has passed the durability barrier. |
| `result` | Operation-specific object or null. |
| `error` | Null or `{code: string, message: string, retry: "never"\|"same_operation"\|"after_reconcile"}`. |
| `effects` | Array of `{kind: string, resource: string, disposition: "created"\|"updated"\|"retained"\|"unknown"}`. |
| `evidence` | Array of `{kind: string, ref: string, digest: string\|null, bytes: integer >= 0, truncated: boolean}`. Refs are store-relative opaque artifact IDs, never instructions to fetch arbitrary paths. |
| `observed_at` | RFC3339 UTC observation timestamp. |
| `extensions` | Namespaced optional object. |

Transport exit code is 0 for a valid `ok:true` completed/accepted/pending response,
2 for a valid refusal or request/schema error, 1 for a valid failed/unknown
response. Absence of valid JSON, mismatch of stdout and exit, truncated output or
SSH exit 255 becomes a caller-generated `unknown` receipt for any mutation that
may have crossed the effect boundary. A provider must not hide that behind
`failed_start` or `stopped`. The caller stores actual `transport_exit` separately;
agent/check exit is nullable and populated only from a captured wait result.

Errors include `unsupported_capability`, `protocol_mismatch`, `policy_denied`,
`identity_mismatch`, `revision_conflict`, `owner_fenced`, `idempotency_conflict`,
`replay_expired`, `host_unreachable`, `outcome_unknown`, `invalid_receipt`,
`resource_busy`, `quota_exceeded` and `cursor_expired`. `unsupported_capability`
names the missing capability in `result` and reports no effects. Uncertainty can
have effects; neither `ok:false` nor a timeout proves nothing happened.

Example refusal, using synthetic IDs:

```json
{
  "protocol": "loom.execution", "version": {"major": 1, "minor": 0},
  "request_id": "req-example", "operation_id": "op-example",
  "op": "execution.prompt",
  "target": {"assignment_id": "assignment-example", "attempt_id": "attempt-example", "host_id": "compute-primary"},
  "ok": false, "status": "refused", "revision": 3, "durable": true,
  "result": {"missing_capability": "prompt.live.v1"},
  "error": {"code": "unsupported_capability", "message": "Agent accepts input only at turn boundaries", "retry": "never"},
  "effects": [], "evidence": [], "observed_at": "2026-11-08T00:00:00Z",
  "extensions": {}
}
```

### Operation registry

In the table, fields separated by commas are required; `?` means optional.
Unmentioned arguments are refused. All entity IDs must resolve in the target
store and ownership scope. Each operation gets a closed args/result schema and
positive/negative fixture in S1. Core operations use the same receipt conventions
under protocol name `loom.coordination`; they are not delegated to an executor.

| Operation | Args | Result / conditions |
| --- | --- | --- |
| `hello` | `versions`, `required_capabilities` | Selected version, provider ID/version, capabilities, negotiated limits, schema digest; no effects. |
| `hosts.list` | `cursor?`, `limit` | Configured host IDs, transport, reachability/evidence time and next cursor; no registration or scan outside allowlist. |
| `agents.discover` | `host_id`, `profile_ids` | Per-profile evidence records as defined in section 8. |
| `workspace.prepare` | `workspace_id`, `base_sha`, `bundle_ref`, `bundle_digest`, `branch`, `manifest_digest` | Exact workspace/host/base binding and created/existing disposition; refuses different content on replay. |
| `execution.start` | `workspace_id`, `profile_id`, `profile_digest`, `argv`, `prompt_ref`, `model`, `effort`, `limits`, `manifest_digest` | Attempt binding, process/provider identity, start evidence, prompt acceptance, resource refs; accepted is not completion. |
| `execution.inspect` | `operation_id?` | Execution state, identity proof, terminal outcome/null, source of observation, observed time, resource state. |
| `execution.list` | `run_id`, `cursor?`, `limit` | Only Loom-owned bound attempts; unmanaged resources may be separately labeled, never adopted automatically. |
| `execution.read` | `source`, `cursor?`, `limit_bytes` | Source/generation, bounded data, next cursor, EOF/truncation/gap metadata. |
| `execution.stop` | `reason`, `grace_ms`, `allow_kill` | Requested signals, identity checks, group observation and `confirmed_stopped` Boolean; only explicit authorization permits signals. |
| `execution.release` | `retention_policy` | Resource disposition; requires settlement and evidence/collection prerequisites, never implies workspace deletion. |
| `execution.reconcile` | `operation_id` | Same operation's durable result or unknown; never relaunches. |
| `execution.prompt` | `message_id`, `delivery_id`, `body_ref`, `mode` | Transport acceptance and exact attempt binding; capability-gated, not semantic compliance. |
| `execution.fence` | `reason`, `new_epoch` | Recorded fencing without a stop claim. |
| `workspace.read` | `artifact`, `cursor?`, `limit_bytes` | Allowlisted report/evidence/manifest bytes, source identity and cursor; no arbitrary path traversal. |
| `workspace.export` | `sha`, `kind`, `limit_bytes` | Bounded Git bundle/evidence artifact with digest; core decides collection. |
| `run.create/use/show/list/claim` | Create: `objective`, `owner_id`, `parent_run_id\|null`; use/show: `run_id`; list: `cursor?`, `limit`; claim: `run_id`, `expected_owner`, `reason` | Run record/context/ownership epoch; never implicit scheduling. |
| `task.create/update/show/list/continue` | Create: `run_id`, `spec_ref`, `spec_digest`, `deps`, `gates`; update: `task_id`, `transition`, `evidence_refs`; show: `task_id`; list: `run_id`, `cursor?`, `limit`; continue: `task_id`, `parent_attempt_id`, `placement_digest`, `message_ids`, `reason` | Validated task/dependency status; continue reserves a new authorized attempt, never edits the old attempt. |
| `gate.create/resolve/list` | Create: `task_id`, `question`, `resolver_id`, `options`; resolve: `gate_id`, `decision`, `evidence_ref`; list: `run_id`, `cursor?`, `limit` | Durable gate record and dependent readiness changes in the same transaction. |
| `mail.send/poll/claim/read/ack/reply/status/retry/pump` | Section 6 | Per-recipient receipts; no task settlement. |
| `events.read` | `after_sequence`, `limit` | Committed events and cursor; read-only. |
| `watch` | `run_id`, `every_ms`, `deadline_ms` | Observations/cursor and `settled` or `deadline_reached`; no implicit stop or mail acknowledgement. |

Core commands also own harvest, verify, collect, report and assignment ack. Agent
completion event and resource release are separate from the existing assignment
`ack`, which acknowledges the conductor's handling of a report. `reference`
attaches typed issue/PR/URL metadata in Loom; Git branch/workspace operations use
Loom ownership records. UI navigation remains a provider extension. Native
`automation create/list/run/remove` stores schedule definitions and explicit run
receipts; unattended execution requires an expressly configured external clock
or running bounded watcher. A stored schedule alone does not run itself.

Core-required capabilities are workspace prepare/read/export, start/inspect/list/
read/reconcile, guarded stop, release/fence and discovery with honest unknowns.
Capability names include a version suffix, for example `execution.stop.group.v1`.
Optional capabilities include `prompt.live.v1`, `prompt.boundary.v1`,
`events.push.v1`, `ui.keep_open.v1`, `model.select.v1`, `effort.select.v1`,
`resume.session.v1` and `owner.fence.v1`. State `supported`, `unsupported` or
`unknown`, with evidence and limits; missing is unknown, never supported. Workflow
requirements determine whether a partial adapter can be selected. No UI feature
may be made a prerequisite of native core coordination.

### Safe command adapters and bounds

Invoke a configured executable with an argv array: `"${adapter_argv[@]}"`, request
on stdin. No `eval`, `bash -c "$message"`, interpolated command strings, splitting
selectors on whitespace, terminal typing or inherited implicit current-pane
targeting. Validate executable identity and use a documented environment
allowlist; do not dump the parent's environment. Reject NUL, preserve spaces,
newlines, quotes, dollar signs and backticks literally. A trusted agent profile
maps model/effort to exact argument positions; unknown support is a refusal.

SSH is not a remote argv API. Invoke the SSH executable with a validated
destination as one argument, fixed options (`BatchMode`, host-key verification,
connect deadline, no PTY), and one fixed helper command from trusted installation
config. The helper receives the JSON request on stdin and constructs argv on the
remote side. No request content enters the remote shell command. Provisioning
the helper is an explicit install/update operation, never downloaded and run as
a side effect of `start`. A wrapper path with unsafe shell characters must be
rejected or provisioned at a known safe path. Do not disable known-host checking.

Protocol input/response maximum is 1 MiB each; metadata/hello 64 KiB; message body
64 KiB; read chunk 64 KiB; maximum 100 list rows. UTF-8 messages exceeding limits
are refused, not silently cut. Raw diagnostics are capped at 1 MiB per operation,
with `truncated:true`. Output spool default is 64 MiB per attempt, configurable
in pinned policy. A draining bounded writer rotates chunks and records exact gap
ranges; it must keep draining when full so the agent cannot deadlock on logging.
Never parse truncated JSON or mistake output loss for process exit. Evidence/Git
bundles have a configured transfer quota and separate chunk stream with digest,
not base64 megabytes stuffed into a receipt. Quota failure blocks the relevant
operation without deleting the source.

## 6. Native mailbox and delivery contract

Loom mail exists without Orca. The authoritative inbox is durable state in Loom;
the execution-host spool carries replicated delivery intents and receipts for
native remote agents. A queued message and an agent wake-up are different facts.

The transport topology is explicit: one pinned authority store and outbound
SSH connections from its conductor/pump to execution hosts. The bridge on a
worker host reads its local spool and writes outbound messages/read/ack receipts
there; it never needs an implicit reverse SSH connection, an inbound service or
copied conductor credentials. `loom mail pump --run RUN --deadline-ms N` exchanges
bounded batches of immutable intents/receipts with each pinned host and commits
them by ID/digest. A bounded watch can invoke the same pump. On a same-host native
deployment the bridge uses the authority directly, under the same contract.

Remote-origin sends return `queued_for_authority` until the authority accepts the
recipient and commits enqueue; locally known recipients come from the binding's
revisioned directory snapshot. Unknown/stale directory entries remain unresolved
until validation, not falsely delivered. Only the authority can resolve a gate
or complete a task. The initial startup batch is shipped before releasing the
agent gate. Subsequent delivery requires an active pump and a cooperative read
boundary or supported control channel; without them the status exposes which
stage is waiting. Running a detached supervisor alone does not claim cross-host
mail is continuously transported.

Stable addresses are `run:<id>` (owner inbox), `task:<id>` (task inbox) and
`attempt:<id>` (exact worker attempt). A task inbox survives stopped/replaced
agents; an attempt inbox never silently forwards to the next attempt. The
sender chooses task delivery if a future authorized attempt may receive it.
Unknown recipient returns `unknown_recipient` before enqueue; a known offline
recipient can accept queued mail. Groups resolve once to a persisted recipient
list, with one delivery per recipient. No implicit global broadcast. Replies
reference a question's message ID and return to its recorded sender; arbitrary
new `--to` on reply is refused. No raw terminal handle is a native address.

Minimum CLI (proposed additions; existing assignment `ack` is unchanged):

```text
loom run create --objective TEXT --owner ACTOR
loom run claim RUN --expected-revision N --expected-owner ACTOR --reason TEXT
loom task create --run RUN --spec-file FILE --deps-json JSON
loom task continue TASK --parent-attempt ATTEMPT --placement-digest DIGEST --reason TEXT
loom gate create --task TASK --question TEXT --resolver ACTOR
loom gate resolve GATE --expected-revision N --decision approved --evidence-ref REF
loom mail send --from ACTOR --to task:TASK --message-id ID --body-file FILE --kind guidance
loom mail poll --mailbox attempt:ATTEMPT --after CURSOR --limit 20
loom mail claim --mailbox attempt:ATTEMPT --delivery DELIVERY --expected-revision N
loom mail read --delivery DELIVERY --claim CLAIM
loom mail ack --delivery DELIVERY --claim CLAIM --message-digest DIGEST
loom mail reply --question MESSAGE --message-id ID --body-file FILE
loom mail status --message ID
loom mail retry --delivery DELIVERY --expected-revision N
loom mail pump --run RUN --deadline-ms 30000
loom events read --run RUN --after SEQUENCE --limit 100
loom watch --run RUN --every-ms 1000 --deadline-ms 30000
```

CLI actor claims are checked against the worker's provisioned binding manifest
(store/run/task/attempt/epoch and permitted commands) or conductor context. This
prevents accidental misrouting; it is not cryptographic protection against a
hostile same-account agent. Messages cannot change that binding. Workers do not
write core state files directly.

`mail.send` args are `message_id`, `from`, `to`, `kind`, `subject`, `body`,
`thread_id|null`, `in_reply_to|null`, `expires_at|null`. Kind is `guidance`,
`question`, `reply`, `status` or `completion_proposal`; only a separate validated
completion transition can settle an attempt. Same ID/digest is replay; same ID
with different content fails. Atomically commit the message and its concrete
per-recipient deliveries. Return `queued`, not `delivered`, until a real receiver
bridge has accepted it.

Each delivery records immutable message digest/recipient and monotonic facts:

| Fact/state | Evidence required | What it does not mean |
| --- | --- | --- |
| `pending` | Durable authoritative enqueue. | Agent online or notified. |
| `delivered` | Exact receiver bridge durably spooled/exposed the payload and returned a receipt. | Model has read it. |
| `read` | Bound agent integration explicitly called read/marked presentation at a safe turn boundary. | Agent agrees or complied. |
| `acked` | Bound consumer acknowledges delivery ID and digest with its claim token. | Task complete, check passed, or future exactly-once execution. |
| `dead_letter` | Policy deadline/retry ceiling reached with recorded reason. | Task failed or message erased. |

Poll/list/show are non-consuming and may show identical deliveries to concurrent
observers. `claim` is a CAS lease with actor, attempt, random token and expiry;
only its owner may mark read/ack. Lease renewal is explicit. An expired claim
allows another reader, so duplicate presentation is possible; recipient handlers
deduplicate by message ID/digest. Ack is idempotent, and never deletes history.
Read/ack are separate transactions. A reply MAY ack its exact question delivery
only if explicitly requested and carrying the valid claim; reply alone does not
consume other mail. Return per-recipient state and next action, not a single
ambiguous success bit for a broadcast.

The closed argument schemas for remaining mail operations are: poll
`{mailbox, after_cursor|null, limit}`; claim
`{mailbox, delivery_id, lease_ms, claim_token|null}`;
read `{delivery_id, claim_token}`; ack `{delivery_id, claim_token, message_digest}`;
reply `{question_id, message_id, body, ack_claim_token|null}`; status `{message_id}`;
retry `{delivery_id}`; pump `{run_id, deadline_ms}`. All mutations use the common
operation/idempotency envelope and expected revision, except creation/enqueue.
Claim lease defaults to 30 seconds, maximum 300 seconds; renewing requires the
current token (`mail claim --renew-claim TOKEN`) and revision. Responses include
message/delivery IDs, their revisions, delivery facts, claim expiry/token only
for the claimant, authority
sync state and next cursor/action. Poll never returns another actor's claim
token. Claim/read/ack by the bridge are scoped to its exact attempt manifest.

Native delivery MUST be implemented in three steps:

1. At startup, the supervisor/worker bridge fetches pending task mail and exact
   attempt mail using the pinned binding. Task messages are assigned to one
   authorized attempt under the authority-store lock; replacement races cannot
   deliver to two attempts without a recorded lease expiry/redelivery.
2. At every supported turn boundary, the integration polls, claims, reads and
   presents a bounded batch as quoted external messages. A documented control
   channel MAY deliver while an agent is running only when that agent integration
   advertises it and returns an exact-attempt receipt. Never use blind keystroke
   injection, infer an idle shell or overwrite stdin to simulate a mailbox.
3. For a one-shot or busy CLI without a live control channel, keep mail pending
   (or durably delivered to its bridge but not read), report
   `delivery_mode: next_boundary` / `wake: unsupported`, and expose age/deadline.
   Startup/between-step instructions teach the agent to check, but instructions
   alone are not proof it did. A plain process with no cooperative integration
   has no mid-turn delivery guarantee. After it exits, task mail waits for an
   explicitly authorized continuation; no automatic relaunch follows a send.

The first native agent profile may be noninteractive: prompt file at start,
inbox commands between its tool steps, no live injection. A follow-up uses
`task continue` to create a new attempt with a report boundary, parent link,
approved placement and pending task-mail IDs. Agent-native session resume is
optional and capability-checked; never fabricate a session identifier.

Remote mail outbox/spool uses the same message/delivery IDs and digests. SSH loss
after remote receipt but before authority update is reconciled by ID; do not send
a fresh message. Remote ack remains `ack_pending_sync` until imported by the
authority. Stopped/offline agents leave mail visible. Deadline expiry moves the
delivery to dead letter without resuming or killing anything. Default delivery
retry is at most five attempts with 1/2/4/8/16-second delays while an explicit
pump/watch is running; without a pump, `next_attempt_at` is a plan, not evidence
of background work. Retry exhaustion is visible and operator retry is explicit.

Payloads are data: no shell/template evaluation, no implicit tool invocation,
no approval from a body saying “approved,” no executor/policy changes from a
message. Store and render escaped text; cap bytes before parsing. Gate approval,
ownership transfer and task completion require their respective authorized
commands. Adapters may provide wake-up/transport bridges, but native mail, read
and ack semantics cannot depend on them.

## 7. Native lifecycle: process and SSH

Both transports call the same Loom-owned helper. Process transport executes it
on an explicitly allowed local host; SSH transports framed requests to an
explicit remote host. A per-attempt supervisor is a child process that exists
only for that attempt, not a daemon/service to install. The coordinator can exit
without making that supervisor or its output writer depend on its terminal/SSH
connection. No real-agent tests run on the main device.

### Start transaction and exact identity

1. Core validates run ownership, ready task/gates, worker cap, selected provider
   capabilities, remote-only policy and calibration. Reserve operation/attempt
   and worker slot durably. Unknown attempts still consume capacity.
2. Prepare the remote workspace from an exact base Git bundle, manifest and
   digest. The host helper verifies the bundle and base commit, creates a private
   clone under its configured root, removes origin, writes WORK and binding
   manifest, excludes Loom evidence files, and returns workspace identity.
   No GitHub credential provisioning or implicit fetch-to-change-base occurs.
   Host-side setup, if configured, is a pinned trusted script with its own exit
   receipt. Setup failure never starts the agent.
3. Host spool atomically records the same operation ID/request digest as
   `reserved`. A detached session/group keeper starts with a gated child. Record
   keeper PID, process group, session ID and start identity before releasing the
   child to exec the argv. A failed persistence barrier leaves the child gated;
   do not run it first and try to reconstruct ownership afterward.
4. Record prompt ingress and exec/start handshake. A valid PID is only process
   evidence; agent readiness/launch verification needs the profile's explicit
   handshake or remains unknown. Return accepted with the identity. The
   supervisor waits on the exact child and writes its captured exit/signal,
   observed descendants, final output cursor and completion receipt atomically.
5. Core imports receipts by operation ID and revision. The report/evidence and
   workspace quiescence checks precede harvest/seal. No user-facing command
   reinterprets a transport exit as the agent exit.

Linux process identity MUST include configured host ID, verified transport-host
identity, persistent host-installation UUID, boot ID, UID, PID, `/proc` start ticks,
PGID, SID, supervisor start ticks, attempt ID and launch nonce. Host UUID is a
Loom-created installation identity, not a scraped machine name. SSH host-key
verification authenticates the transport; a copied UUID alone does not. Compare
all binding fields available for a claimed identity, not PID or `ps lstart`
alone. Cross-boot PID reuse must never match.

The keeper remains an identifiable session/group leader through controlled
termination until the worker's group members have been accounted for. The
output writer and control helper have separately recorded ownership so stopping
the worker does not lose the ability to persist its outcome. Agent profiles
declare that managed descendants stay in the owned group. This trusted process
model cannot contain a child that deliberately daemonizes into a different
session; report such detected escapes and refuse to claim complete descendant
termination. A containment guarantee would need a separately approved sandbox
or OS resource-control scope, outside this design.

### Stop and timeout

Only an explicit conductor stop, or a preauthorized runtime-limit policy pinned
at dispatch, permits signaling. Silence, expired watch, model UI idle or network
loss does not. Native default is to surface stale work. A policy limit must be
expressed as an authorized stop condition, not inherited from an old watchdog's
unconfirmed kill behavior.

Stop compares exact host/boot/keeper/process identity and current ownership epoch
immediately before each signal. Refuse conductor/helper/parent/system groups and
unrelated resources. Send the durable stop intent to the attempt's private control
spool. The keeper validates nonce/epoch and sends TERM to its own owned group,
trapping TERM itself to remain the group's identity anchor. Observe for bounded
`grace_ms`; escalate to group KILL only when `allow_kill` was authorized. The
keeper issues that group signal while it is still a member: this prevents group
number reuse between an external `ps` check and `kill`. An external helper must
not substitute a later bare PGID signal. If the keeper disappears or group
identity becomes ambiguous, return unknown and stop signaling. KILL may prevent
the keeper's final receipt, so the independent control helper must confirm exit.
Do not fall back from group kill to an arbitrary PID kill. Tests must exercise
the identity-check/signal race, not just PID reuse before the call.

After signaling, observe the exact known process identities and group membership
on the pinned host. A successful `kill` syscall or SSH exit zero is only signal
delivery. `confirmed_stopped:true` requires captured exit or proof that the owned
worker group has no live members, plus no unresolved descendant ownership. A
zombie is exited but awaiting reaping, not a running worker. If the group leader
exited but a child is alive, stop is not confirmed. If post-signal observation is
unavailable, preserve `stop_requested/unknown`, resource ownership and slot; never
clear identity or harvest as though stopped. Release never issues a blind kill.

### Restart, reconnect and partial effects

| Failure point | Required recovery |
| --- | --- |
| Before host reservation | Replay same operation; host can prove absence under its lock. |
| After reservation, before gated launch | Inspect durable phase and keeper/child gate; continue only a positively proven unexecuted reservation under the same operation. |
| After possible exec, reply lost | Inspect same host spool and identity; return existing receipt. If the exec boundary cannot be resolved, remain unknown. |
| Coordinator exits/restarts | Replay journal/snapshots; list unresolved operations; query their recorded hosts. Do not enumerate processes by agent name and adopt them. |
| SSH disconnects | Supervisor continues remotely; bounded inspect reports host unreachable and last confirmed observation. Reconnect imports receipts/output from cursor. |
| Host reboots | Boot mismatch prevents signaling/relaunch; mark prior process identity gone with exit code unknown. Reconcile report/artifacts before any new authorized attempt. |
| Supervisor dies without terminal receipt | Inspect original group; do not infer agent exit from supervisor loss. Unknown descendants keep the attempt unresolved. |
| Stop reply lost | Replay stop's operation ID; inspect whether original group is gone before considering another signal. |
| Local state lost but remote spool survives | Explicit recovery import with store/host/attempt/digest checks; no automatic adoption into another run. |
| Provider IDs changed after restart | Adapter proves replacement mapping with durable identity; ambiguous/stale handle returns unknown, never dual-send. |

Output cursors bind attempt, stream/source and generation plus byte offset. A
restart continues that stream or reports a gap/source change; a changed source
cannot silently reuse an old cursor. Artifact paths reject symlink traversal and
escaping archive entries. Archive output before releasing provider UI resources;
if output is unavailable, say so. No terminal output regex supplies completion
authority. Retained evidence and operation tombstones survive resource release.

## 8. Discovery and calibration

Separate three inventories: orchestrator/provider capabilities, host/transport
capabilities and agent/model capabilities. An available provider does not imply
an installed agent; an installed executable does not imply authenticated launch;
a configured model string does not imply availability or a successful turn.

For each agent/profile/model tuple, record independent evidence dimensions:

| Dimension | Allowed evidence |
| --- | --- |
| `installed` | Executable resolved on the exact target host and bounded safe version probe; no launch. |
| `configured` | Operator-owned nonsecret profile requests this agent/model/effort and supplies a valid mapping. Authentication remains unknown. |
| `launch_verified` | Exact authorized prior attempt observed expected agent startup/prompt acceptance, with host/profile/model digests and time. Not a performance or correctness guarantee. |
| `unknown` | Probe absent, unsupported, inaccessible, stale or ambiguous, with reason. Never silently false/true. |

These are evidence dimensions, not a linear ladder. Each entry has `value:
true|false|null`, source, observation time and scope digest. Explicit missing
executable can give installed=false; no probe gives null. Optional model discovery
uses only a documented safe public/list command for the selected agent, with
bounded execution and explicit operator permission if it contacts a service.
Do not read credential files, browser stores, tokens, private chat databases or
credential values in environment. No hardcoded catalog extrapolated from a
provider's agent list. Keep opaque model IDs verbatim; never substitute a default.

`loom capabilities --consumer FILE` and `loom agents --host HOST` return these
records. `loom capacity` reports configured concurrency, reserved/live/unknown
attempt counts and timestamped observed constraints; host count is not CPU or
model capacity. The bootstrap advisor catalog owned by the separate coordination
patterns work MUST use provider/transport/agent/profile/model and these evidence
terms. It must not assume Orca runtime IDs or recommend unverified models/hosts.

Calibration schema 2 fingerprints:

- Core source manifest and validator/schema bytes, Loom version and instruction
  bridges; any executed module must be included even if VERSION did not change.
- Exact config content plus canonical parsed policy, tracked config commit when
  present, repository identity and base/config snapshot lineage.
- Selected provider executable/adapter bytes and schema/capability digest;
  selected agent profile and explicitly supplied model/effort mapping.
- Transport executable and relevant nonsecret settings, pinned host identity,
  remote helper source/protocol digest, platform capability probes and workspace
  root identity. Hash relevant data without serializing credentials.

Explicit native/process or native/SSH MUST NOT fingerprint/probe an unrelated
installed Orca/Herdr binary or its selector. Changing selected code/config/host
identity invalidates readiness; changing an unselected orchestrator executable
does not. Legacy auto includes its resolution inputs because they affect choice.
Offline calibration keeps `agent_execution: not_run` and `project_acceptance:
not_run`. A connectivity probe is not a launch test. Optional remote preflight
is explicitly labeled with observed host/time and must not run agent/setup/check
commands under the name of calibration.

Read schema-1 proof with its original semantics and retain it unchanged. A v2
reader can display it as `legacy`, but cannot claim the v2 workflow calibrated
from it. An explicit calibration writes a separate schema-2 proof with predecessor
digest; `--check` never rewrites/upgrades proof. Unknown future schemas are
incompatible, not absent. Reobserve inputs before committing proof and report
named drift fields. Active assignments keep their pinned source/config snapshot;
new policy takes effect for new attempts only, with explicit compatibility
checks. Changed helper/protocol that cannot honor an old attempt blocks mutation
but still allows safe inspection. Never reroute old work to pass calibration.

## 9. Adapter mapping and migration

### Orca compatibility

Preserve `ops/orca.sh` as the explicit legacy provider surface. New core commands
route by the stored provider, not by current PATH or whichever orchestrator is
running. V1 config and records without executor still read as legacy local;
`executor.kind: orca` reads as legacy Orca. No command rewrites live records into
v2 or assumes an old PID has a new boot/group receipt. Ambiguous legacy identity
requires inspection and explicit resolution before destructive action.

Legacy `auto` retains its documented *pre-dispatch* selection behavior for users
who have not opted into v2. It is not a license for fallback after intent or for
violating declared compute policy. Explicit Orca still fails closed. Explicit
local stops consulting installed Orca once the first slice lands. V2 setup
requires a provider/transport/host choice; it does not silently migrate a user's
default away from Orca.

For v2 Orca execution, adapter maps prepare/start to supported workspace/
`worker-start` operations; inspect/read/stop/release/reconcile to their exact
provider operations. It records Loom-to-provider run/task/dispatch/workspace IDs.
If the provider requires its own run/task records, these are execution resources
mirroring the Loom entities, never a competing task graph. Native gates are
checked before calling worker-start. Preserve provider-specific follow-up
parentage, consumed report offsets, durable completion versus stale telemetry,
retained terminals and unknown release/stop results.

Use the installed command schema to validate supported flags and frozen fixtures
to validate response paths. `receipt_get` recursive field search is not allowed
in the v2 adapter. Use provider `--retry-request` only with its documented
same-request rules; a provider that cannot deduplicate a possibly accepted launch
must return unknown and require inspection. Do not map generic send to an Orca
operation that implicitly starts another turn unless the Loom continuation was
explicitly authorized. Reading external mail uses peek/inbox and records provider
message IDs; external ack is a separate operation. If the selected provider
version cannot preserve read/ack separation, use Loom mail instead.

### Herdr compatibility

Build a separate opt-in adapter for the exact official product identified above.
Use installed schema negotiation, not project-name matching. Layout creation,
agent start, inspect/read and prompt APIs are candidate mappings. A pane or agent
alias must be bound to exact process/attempt identity; aliases can change and UI
status alone cannot satisfy completion. A Loom bridge must supply completion
receipts, mail boundaries and any missing durable launch/stop semantics.

Do not advertise guarded stop, idempotent launch, remote placement, exact turn
completion or live mail delivery until a version-specific implementation proves
them. If it needs a native helper to provide these semantics, declare that
composition in capabilities and test it. It must not secretly change a Herdr
assignment into a native assignment. A read-only partial adapter is useful but
is not full lifecycle parity. Future adapters follow the same rule; no universal
untested API compatibility claim.

### Existing CLI and record compatibility

| Existing surface | v2 behavior / compatibility path |
| --- | --- |
| `dispatch`, `start`, `launch ID -- argv` | Resolve by record schema. New start is provider-neutral; launch is a native argv entry point, still subject to pinned placement. Legacy argv behavior preserved where policy permits. |
| `harvest/stop/show/read/list/release/abandon/keep-open` | Provider-neutral lifecycle/result model. Unsupported keep-open is explicit. `abandon` fences; never means stopped. |
| `send/ask/reply/peek/inbox` | Legacy run/record uses legacy Orca bridge. V2 uses Loom mail; new `mail ack` is distinct from assignment ack. Mixed scopes require an explicit run/mailbox. |
| `run/task/gate` | New Loom-owned entities in v2. Legacy external IDs remain namespaced and use the legacy route until a completed-run import. |
| `request` | Looks up a normalized operation; provider request IDs require a provider namespace. |
| `hosts/detect/compute/capacity` | Report configured provider/host and evidence. Explicit `--provider orca` supports old provider diagnostics. |
| `reference/worktree/repo/base-ref` | Loom records and Git operations for Loom-owned resources; legacy provider passthrough retained explicitly. No UI deletion implied by release. |
| `automation` | Native schedule definitions with explicit runner status; provider scheduling is optional and labeled. |
| `status/watch/verify/collect/ack` | Shared workflow using proven attempt settlement, source-pinned checks and report acknowledgements. |

Keep the current public `{v,cmd,ok,state,fact,id,ticket,items,actions}` envelope for
existing commands. Put normalized objects in `items` and add an explicit
`--protocol 1` mode for full contract envelopes; do not reinterpret `v` as the
protocol version. Add compatibility golden fixtures before changing dispatch.

V2 entities live below `v2/`, so existing root `*.json` iteration does not try to
validate runs as assignments. Readers support legacy snapshots and v2 projections;
writers never downgrade. Completed legacy assignments MAY be imported with
origin schema/digest, original receipt refs and explicit owner authorization.
Live assignments remain on their original handler/source compatibility path.
Do not dual-write two authoritative coordination stores. Rollback may run old
commands against legacy records; it must refuse v2 writes, not silently ignore
v2 active capacity. A consumer with active v2 work cannot use an older dispatcher
to evade the shared capacity/ownership fence.

### GitHub remains explicit

`accept`/ticket creation and issue/default-branch discovery in dispatch still
require GitHub/`gh` connectivity and appropriate account authorization. Failures
are `ticket_provider_unavailable` or `ticket_auth_required`, not executor errors.
Existing already-dispatched native work, mail, inspect, stop and recovery can run
without GitHub access from their pinned mandate/snapshots. They do not silently
create replacement tickets or alter mandates. Fresh ticket dispatch still fails
if its GitHub input cannot be obtained. Local test fixtures may stub GitHub; that
is not a claim of a production offline ticket provider. Git fetch/bundle/collect
remains distinct from GitHub API use; pushing/review/merge remains conductor-only.

## 10. Small implementation slices and file ownership

These are proposed implementation tasks, not changes included in this spec.
Paths marked new are files to create. Every slice must retain existing checks.
Shared-file edits are serialized by the dependencies below; separate workers may
develop isolated modules, but must not concurrently edit `ops/loom`, `lib.sh` or
`selftest.sh`. Conductor owns integration order and final push/review/merge.

| Slice / prerequisite | Owned files and smallest deliverable | Required focused tests |
| --- | --- | --- |
| S0: explicit-local independence; already assigned separately | `ops/launch.sh`, `ops/calibrate.sh`, `ops/selftest.sh`, `ops/mutate.sh`, `docs/support.md`. Remove local presence veto and unrelated Orca executable/selector calibration inputs only. | Local fake worker succeeds with Orca present/absent; local calibration unchanged by Orca binary/selector; auto behavior preserved; required Orca unavailable still refuses. No real agent. |
| S1: contract fixtures; after S0 integration | New `ops/protocol.sh`, `schemas/execution-v1/*.json`, `schemas/coordination-v1/*.json`, `tests/contract/`; one serialized `selftest.sh` hook. Exact envelopes, operation args/results, negotiation and bounded safe command invoker. | Every op has valid/invalid examples, duplicate keys, unsupported versions/capabilities, mixed stdout, timeout, overflow, metacharacter argv and mismatched IDs. |
| S2: durable core store; S1 | New `ops/state.sh`, `ops/events.sh`, `schemas/state-v2/*.json`, `tests/state/`; narrow `lib.sh` reader hook. Journal/replay, revision CAS, operation dedupe, identity-aware locks and legacy read-only projections. | Crash before/after rename/flush, corrupt/gapped journal, snapshot lag, concurrent writes, dead/reused-PID locks, same-key/different-payload, old/new schema isolation. |
| S3: policy/config/discovery; S2 | New `ops/policy.sh`, `ops/discover.sh`, `tests/policy/`; serialized config/dispatch hooks in `lib.sh`, `dispatch.sh`, `loom`. Parse v2 JSON; pin provider/transport/host/profile; declared limits; safe probes. | Denied local/host/model changes, unknown discovery, no credential reads, no fallback, legacy config and explicit Orca, capacity counts unknown attempts. |
| S4: native process engine; S3 | New `ops/native.sh`, `ops/native-supervisor.sh`, `ops/output.sh`, `tests/native/`; narrow `launch.sh` compatibility hook. Gated exec, exact identity, detached output, exit/reconcile and guarded stop. | Fixture children only: lost launcher, exec-boundary crash, PID/group reuse, surviving child, stop observation loss, TERM/KILL policy, output quota/drain and captured exits. |
| S5: native SSH engine; S4 | New `ops/transport-ssh.sh`, `ops/remote-helper.sh`, `tests/ssh/`; narrow workspace helpers in `lib.sh`. Helper preflight, private remote spool, bundle workspace, pinned identities and replay. | Fake transport plus approved-host fixture: lost replies at each phase, helper/version/key/boot mismatch, exact argv, no main-device process, reconnect and remote stop confirmation. |
| S6: native run/task/gate core; S3 | New `ops/coordination.sh`, `tests/coordination/`; serialized `loom` command registration. Ownership epochs, graph transitions, gated attempts, event receipts. | Cycles/missing edges, concurrent gate decisions, stale owner, no dispatch before readiness, failed dependency/retry, ready report versus accepted result, cross-host takeover uncertainty. |
| S7: native mail; S5 + S6 | New `ops/mail.sh`, `ops/worker-bridge.sh`, `tests/mail/`; native supervisor integration and serialized `loom` mail verbs. Queue, leases, read/ack, startup/boundary checks, SSH spool reconcile and visible unsupported live delivery. | Full section 11 mail matrix, crash before/after delivery/ack, concurrent readers, offline/stopped recipient and no blind input. |
| S8: neutral lifecycle/workflow facade; S5 + S6 + S7 | `ops/loom`, `ops/lib.sh`, `ops/dispatch.sh`, `ops/launch.sh`, `ops/watchdog.sh`, `ops/heartbeat.sh`, `ops/status.sh`, `ops/verify.sh`, `ops/collect.sh`; new `tests/workflow/`. Route by records, explicit bounded watch, normalized harvest/verification and failure classification. | Full native no-Orca workflow, unchanged legacy JSON fixtures, stale/moved reports/tips, unknown liveness blocks collect/release, check exit distinct from SSH/setup exit. |
| S9: optional Orca adapter; S8 | New `ops/adapters/orca.sh`, `tests/adapters/orca/`; `ops/orca.sh` retained as compatibility wrapper, serialized `loom` integration. Frozen schema parsers and normalized receipts. | Existing Orca regression suite plus partial launch/retry, durable completion/live status conflict, follow-up parent identity, unknown stop/release and non-consuming mail. |
| S10: calibration v2; S9 (or S8 with native-only profiles) | `ops/calibrate.sh`, new `tests/calibration-v2/`, serialized `selftest.sh` hook. Selected-source/provider fingerprints, old proof reader, remote helper/profile drift. | Local and SSH ignore unrelated Orca installation; selected code/config/profile/host/helper drift; legacy proof unchanged, future schema refusal, all unrun acceptance fields truthful. |
| S11: Herdr adapter and open SDK guide; S1 + S8 | New `ops/adapters/herdr.sh`, `tests/adapters/herdr/`, `docs/adapters.md`. Installed schema inspection, explicit capability gaps, candidate mapping, reusable command adapter guide. | Shared conformance plus exact installed-version fixture/approved-host integration; unknown identity, alias changes, UI done without completion and unproven stop refused. No full-parity label until proven. |
| S12: rollout/acceptance; S9 + S10, S11 only for Herdr claims | `ops/selftest.sh`, `docs/setup.md`, `ops/README.md`, new `tests/conformance/`; conductor controls shared files. Opt-in v2, compatibility/rollback fixtures, published evidence. | All matrix cases, existing exact check chain, selected real-agent smoke only on approved compute with explicit launch authorization. |

S4/S5 implement process mechanisms using fake workloads before any real-agent
integration. S6 may build independently of S4/S5 once S3 lands, but S7 binds them.
S0 is a useful immediate fix and is insufficient to claim orchestrator
independence. Native SSH and core coordination must ship together before the
owner's workflow is advertised as independent. The separate bootstrap advisor
and cross-vendor research documents are not edited by this assignment; reconcile
their recommendations against this contract, never let them bypass policy or
invent provider/model capabilities.

## 11. Acceptance and conformance tests

Create one reusable conformance runner parameterized by an adapter executable,
capability fixture and transport fixture. Common scenarios assert normalized
states/effects/receipts; adapter-specific fixtures assert the exact provider
calls. Partial adapters pass unsupported cases but do not receive a full-executor
parity designation. No real agent is needed for deterministic fault injection.

| Case | Setup/action | Required observation |
| --- | --- | --- |
| N1: no orchestrator installed | Hermetic PATH excludes Orca/Herdr and an invocation trap rejects either; create run/task/gate/mail; dispatch/start fake workload through native SSH. | Complete workflow through report, harvest, verify, collect, ack and release; zero orchestrator calls. |
| N2: orchestrator presence irrelevant | Repeat N1 with a reachable, deliberately failing Orca stub and selected native config. | Identical provider choice and calibration inputs; stub invocation count zero. |
| N3: remote-only enforcement | Approved SSH target unavailable; local executable trap records any attempt. | Host-unreachable receipt, no local process, no alternate adapter or host and no erased intent. |
| N4: transport argument safety | argv/body/path fixtures include spaces, quotes, newline, backticks, `$()`, leading dash; NUL and traversal supplied separately. | Exact argv received, no evaluation, invalid fields refused, no secret/environment echo. |
| N5: uncertain launch | Drop replies before reservation, after gate persistence, after exec and after success receipt. | At most one fixture launch per operation; same-key replay/reconcile, unresolved exec boundary remains unknown. |
| N6: restart/reboot | Terminate conductor; reconnect; simulate host boot change and recycled PID/PGID. | Recovered original receipt/output or unknown; no blind relaunch or signal. |
| N7: guarded group stop | TERM-ignoring child; exited leader with surviving child; identity change immediately before signal; disconnect after signal. | Escalation only when authorized; no unrelated kill; confirmed stopped only with group proof; otherwise slot/identity retained. |
| N8: output bounds | Stream past spool limit, rotate, reconnect and read old cursor. | Child keeps progressing, bounded disk/response, labeled loss/gap, valid cursor generation; no fabricated transcript. |
| N9: ownership/capacity | Concurrent starts and competing claims; old-owner response arrives late. | One reservation per operation, capacity enforced including unknowns, stale epoch fenced, old receipt cannot overwrite new authority. |
| N10: DAG/gates | Cycle, missing dependency, failed prerequisite, two resolvers, timeout, running-task graph edit. | Atomic refusal or documented waiting; no premature start or automatic gate approval. |
| N11: report provenance | Old ready line, missing report, ready with nonzero exit, ambiguous adapter completion, moved checked SHA. | Actual evidence retained; no fabricated success; old report excluded; acceptance blocked pending conductor review/checks. |
| N12: journal integrity | Inject failure at each write/flush/rename boundary; stale snapshot; duplicate operation; disk full. | Ack only after durable commit, deterministic replay, no duplicate effects and explicit storage failure. |
| M1: enqueue/dedupe | Same message twice; conflicting body; unknown recipient; partial group failure. | One immutable message/per-recipient delivery, conflict rejected, unknown address refused, explicit per-recipient outcomes. |
| M2: read versus ack | Poll twice; read with claim; crash before ack; second reader competes. | Poll does not consume; exclusive claim until lease expiry; redelivery possible with same ID; ack idempotent. |
| M3: boundary delivery | Start fake cooperative worker, send while busy, advance turn; repeat with noncooperative CLI. | Startup/boundary read receipt for cooperative worker; visible queued limitation for other worker; no injected keystrokes or hidden relaunch. |
| M4: offline/restart | Queue task mail for stopped agent, attempt mail for old attempt, restart bridge, authorize new attempt. | Task mail assigned under lock, old-attempt mail never redirected implicitly; pending/dead-letter mail stays inspectable. |
| M5: remote ack uncertainty | Lose SSH reply after spool delivery or ack. | Same delivery reconciles, no fresh message; ack pending sync labeled until authority imports it. |
| M6: retry/timeout | Exceed retry ceiling/deadline; stop watcher; resume with explicit retry. | Dead letter/reason visible; no retries while no runner exists; no task completion or failure inferred from ack. |
| M7: hostile payload data | Body contains commands, fake approval/identity and oversized/control content. | No execution or policy/gate changes; bounds/escaping enforced; sender identity comes from binding, not body. |
| C1: capability/protocol | Unsupported major, absent live prompt/model/group-stop, oversized or malformed response. | Honest refusal/unknown, no effect or fallback, exact transport exit retained. |
| C2: calibration snapshots | Change core source without VERSION; change selected config/helper/model; change unrelated Orca; load schema 1/future proof. | Named relevant drift; unrelated executable ignored for native; old proof preserved and future proof refused. |
| C3: GitHub separation | Fail `gh` with no Orca; then recover an already-dispatched attempt while `gh` stays unavailable. | New issue/dispatch clearly fails ticket integration; existing lifecycle/mail/stop recovery still works. |
| C4: legacy compatibility | Replay local/no-executor/Orca records, old calibration and public JSON snapshots. | No live-record rewrite, correct original route, explicit unknown legacy identity, no implicit owner migration. |
| C5: provider parity | Run applicable cases against native process, native SSH, Orca and Herdr; poison provider UI status/IDs. | Same contract semantics; documented unsupported capabilities; no UI observation accepted as a durable outcome. |

Real-agent smoke, when separately authorized, must execute only on approved
compute: start exact configured agent/model, confirm launch receipt, exchange
mail through the supported ingress, produce a report, reconnect, inspect, and
confirm controlled termination/release. Record actual versions, capabilities,
host identity, source/config digests and captured exits privately. An adapter
whose live smoke was not run must say `not_run`; fixtures cannot establish model
availability or real-provider compatibility.

## 12. Evidence for this design-only change

The required existing check chain was run in this workspace:

```sh
bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom
```

Captured combined exit code: **0**. The selftest log ends in PASS and the chained
ShellCheck invocation completed successfully. Evidence is in
`.loom/executor-boundary/checks.log` and `checks.exit`. The run exercised existing
fixture behavior; it does not validate the proposed v2 contract or establish a
new native remote lifecycle. Proposed N/M/C tests, Herdr integration and real-agent
smoke: **not run; not implemented by this change**.

No owner decision is required to review this design. Rollout choices remain
explicit per consumer: keep legacy Orca, opt into native SSH, or select a proven
adapter. No choice is inferred from installation presence. Production activation
requires implementation of the relevant slices and their captured acceptance
evidence; this spec alone changes none of those capabilities.
