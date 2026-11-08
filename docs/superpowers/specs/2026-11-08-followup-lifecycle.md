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
evidence, commit log and receipts. Reports and dispatch history remain intact.
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
A live, failed, stopped or uncertain observation vetoes harvest, with one narrow
exception for expired telemetry after durable success. That exception requires
an explicitly completed dispatch with a nonempty completion timestamp, the same
worker dispatch identity in state `succeeded`, projection outcome `succeeded`,
`evidence.durable: true`, `evidence.liveStatus: stale`, and liveness exactly
`unverifiable` with reason `stale_status`. A mismatched worker or projection
identity, explicit live observation, or contradictory failure still vetoes it.
Generic unknown telemetry and partial durable proof remain insufficient. Resource states
such as `retained` or `released` are never completion evidence. A failed command,
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
uncertain send recovery, and durable successful completion with stale telemetry. Mutation cases remove dispatch adoption, positive
completion, identity checks, the live veto, report boundaries, ancestry checks,
and evidence preservation; the suite must reject each mutant.

Run `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`, then
`bash ops/mutate.sh`. For a focused lifecycle gate, use
`LOOM_MUTATE_PREFIX=mlife bash ops/mutate.sh`; an unmatched prefix fails the
harness. All fixtures are offline and launch no real agents.
