# Assignment-bound Orca follow-ups

A Loom assignment may contain multiple Orca dispatches. Sending guidance to a
settled worker can create a new task and dispatch in the same workspace. The
assignment must follow that identity before it can harvest the continuation.
Terminal retention, an idle agent, and unrelated nested completion metadata do
not establish that the assignment's dispatch completed.

## Commands and transitions

`loom send ID --subject TEXT [--body TEXT]` takes a Loom assignment ID, resolves
its recorded dispatch, and saves the receipt. For compatibility, a raw dispatch
ID is accepted only when it belongs to exactly one stored assignment; unknown
or ambiguous dispatch IDs are rejected before delivery. Assignment IDs are
preferred, and no unrestricted dispatch passthrough exists. Before delivery it records a
pending continuation and report boundary under the assignment lock. A queued
message acknowledgement for a running assignment leaves the dispatch unchanged.
For a settled assignment, a queue-only receipt does not establish whether an
asynchronous follow-up will start: Loom returns unresolved and keeps the pending
fence until an explicit child dispatch is reconciled. A follow-up receipt
must name the old dispatch in `followUpOf`; Loom verifies the resulting worker
with the same checks used by reconciliation, then adopts the new identity and
marks the assignment running. A send error or unrecognized receipt leaves the
continuation pending: never resend automatically, collect, release, or harvest
on the strength of the old completion.

`loom reconcile ID --dispatch NEW` is the recovery path for a follow-up sent
outside Loom, or a send whose receipt was lost. It sends no work and changes no
worker files. It reads full worker-show records and walks at most sixteen
`followUpOf` links to the recorded dispatch. Each response must identify the
requested dispatch; every link must preserve the exact workspace and run and
introduce a distinct task. The final ancestor must match the assignment's
recorded task, run, and workspace path. Missing, cyclic, overlong or mismatched
chains fail without updating the assignment. Reconciliation can adopt a live
follow-up for tracking; that does not authorize harvest. Repeating reconcile for
the current dispatch does not reopen settled work or clear an uncertain send.

Before adopting a continuation, Loom archives the prior assignment record,
evidence, commit log and receipts. New receipt names end in `.receipt.XXXXXX`
when passed to `mktemp`, so both BSD/macOS and GNU implementations atomically
create a unique private file. History includes both these names and legacy
`*.receipt` names; repeated ancestor, show and send reads never overwrite prior
observations. Reports and dispatch history remain intact.
The current dispatch/task changes, executor state becomes running, and old
collection, acknowledgement and release flags are cleared. No recovery requires
manual JSON edits. The original workspace host remains authoritative; send
refuses a worker outside the assignment's declared compute hosts and never
starts a local replacement. Remote start placement retains its existing refusal
when no configured host is connected.

## Positive completion and report boundaries

`loom harvest ID` serializes against send/reconcile, queries the recorded
current dispatch with worker-show, and requires a successful JSON envelope
identifying that dispatch with explicit `completed` status. Only the documented
full dispatch/worker/projection envelope or concise worker-show fields count.
A failed, stopped, explicitly working/running or uncertain observation vetoes
harvest. Two narrow exceptions distinguish durable task success from terminal
liveness:

- A fresh retained terminal may still have liveness verdict `live` after its
  task finishes. Acceptance requires **all** of: dispatch status `completed`,
  a nonempty string or positive numeric `completedAt`, worker `dispatchId`
  matching the requested dispatch and state `succeeded`, projection `dispatchId`
  matching that same dispatch and outcome `succeeded`, `evidence.durable: true`,
  and `evidence.liveStatus: fresh`. The full proof is checked before the ordinary
  live veto; incomplete live observations still fail closed. A compact response
  with a successful state or settled stage cannot establish this proof.
- Expired telemetry retains the existing `stale_status` support: an explicitly
  completed dispatch with a nonempty completion timestamp, the same worker
  dispatch identity in state `succeeded`, projection outcome `succeeded`,
  `evidence.durable: true`, `evidence.liveStatus: stale`, and liveness exactly
  `unverifiable` with reason `stale_status`.

A mismatched worker or projection identity, contradictory failure, or explicit
working/running worker or liveness state still vetoes completion. Generic unknown
telemetry and partial durable proof remain insufficient. `show` requests the
same full worker-show envelope as harvest so its verdict uses durable evidence.
Resource states such as `retained` or `released` are never completion evidence.
A failed command,
malformed response, mismatched identity, missing completion, or completion buried
in another object's metadata leaves the assignment, index, HEAD and evidence
unchanged, apart from saving a fresh diagnostic receipt.

Harvest records the consumed report line count. Continuation uses that boundary,
so a new dispatch without a new state line records a missing-report failure
instead of reusing an old ready report. For settled records from older Loom,
reconcile requires a unique exact match between the newest recorded report found in the file and a
state line in REPORT.md to recover the boundary. An absent or ambiguous match
fails safely. A second harvest needs a newly adopted dispatch and a new positive
completion read; duplicate harvests of a settled dispatch are refused.

## Proof

The hermetic selftest uses synthetic Orca receipts and disposable workspaces. It
covers changed dispatch identity, retained/live receipts, failed and malformed
reads, wrong-dispatch and unrelated nested completion, a second committed
harvest, externally created completed follow-ups, invalid ancestry/workspace/run/
task links, legacy report boundaries, evidence preservation, missing new reports,
uncertain send recovery, durable success with stale telemetry, and fresh durable
success with a retained live terminal. Fresh-live negative cases remove or alter
each proof field and cover failed, mismatched, explicitly working/running and
compact responses; refusals preserve the assignment, index, HEAD and evidence.
Successful fresh-live harvest commits once and consumes the new report. BSD
`mktemp` emulation checks unique private receipts and byte-preserving archives
for both new and legacy names. Mutation cases remove dispatch adoption, positive
completion, identity checks, the live veto, report boundaries, ancestry checks,
individual fresh-live proof requirements and evidence preservation; the suite
must reject each mutant.

Run `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`, then
`bash ops/mutate.sh`. For a focused lifecycle gate, use
`LOOM_MUTATE_PREFIX=mlife bash ops/mutate.sh`. Portability and fresh-live proof
checks use `LOOM_MUTATE_PREFIX=mportable bash ops/mutate.sh` and
`LOOM_MUTATE_PREFIX=mproof bash ops/mutate.sh`, respectively; an unmatched prefix
fails the harness. The full combined mutation gate belongs to the conductor.
All fixtures are offline and launch no real agents.
