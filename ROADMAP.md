# Roadmap: loom to a reliably confirmed layer

Loom is the cornerstone: everything after it is built *through* it. So loom is
not "done" when its scripts exist; it is done when its failure drills pass
against a real repository with a real worker, with evidence recorded. This
document defines that bar and the path to it.

## Definition of "loom works" (written before the code)

Loom works when all four drills below pass, each leaving captured evidence
(exit codes, assignment records, PR links) in `drills/EVIDENCE-<date>.md`:

| Drill | Proves | Pass means |
| --- | --- | --- |
| D1 happy path | the full lifecycle | real ticket → dispatch → worker builds → `ready` → conductor re-runs checks (exit 0) → PR merged. One assignment record, ending `ready`. |
| D2 hung worker | the watchdog | a worker that never reports is killed at the limit; its assignment ends `failed/watchdog_kill`; re-dispatching the same ticket yields exactly one new live assignment. |
| D3 blocked worker | the attention contract | a worker ends `blocked` with one concrete question; `status.sh` prints exactly that line and nothing else. |
| D4 idempotence | one ticket, one live worker | dispatching a ticket that already has a live assignment refuses, exit nonzero. |

Until D1–D4 are green, nothing outside loom is dispatched through it except
as a drill subject.

## Layers

### L0 — the law (merged)
PROTOCOL.md, MANDATE template, consumer registration. Done 2026-11-07.

### L1 — mechanics v0 (merged, PR #2)
dispatch / report / watchdog / status / selftest. Built by a codex worker
under the hand-run protocol; conductor re-ran selftest (0) and shellcheck (0).

### L1.5 — mechanics v1: close the gaps the bootstrap run found
Three real defects, discovered by running v0 with a live codex worker:

1. **Worktrees break sandboxed workers.** A `git worktree` shares the main
   checkout's `.git`; a workspace-write sandbox denies those metadata writes,
   so the worker could not commit. → `dispatch.sh` creates a **local clone**
   of the consumer checkout instead. The worker owns its whole `.git` and
   commits freely; the conductor fetches the branch from the clone path.
2. **Nobody records the worker PID.** Dispatch deliberately does not launch,
   so `worker_pid` stays null and the watchdog has nothing to watch.
   → `launch.sh <assignment-id> -- <worker command...>`: runs the worker in
   its workdir, writes the PID into the assignment record, and on worker
   exit harvests the report (below). Executor-agnostic: codex today,
   anything scriptable tomorrow.
3. **Sandboxed workers cannot write `$LOOM_STATE`.** So the worker-facing
   contract is only ever `REPORT.md` in its own workdir (`state: <s> — <fact>`
   lines). A **harvest** step (in launch.sh and watchdog.sh) folds the latest
   state line into the assignment record. A worker that exits with no state
   line is recorded `failed / worker_exit_no_report`. `$LOOM_STATE` is
   conductor-only, which also matches the law: workers never touch shared
   state.

Loom code is written by the conductor (owner's law, 2026-11-07); workers are
used here only as drill subjects.

### L2 — confirmation: run the drills
`drills/` holds one script or checklist per drill. D2's hung worker is
`sleep`-based, costless. Evidence file committed per run. This layer is the
gate: green drills = loom is certified as the coordination layer.

### L3 — adoption
- the consumer ticket #42 (`pyz`) completes through loom machinery end to end.
- The conductor's heartbeat runs `watchdog.sh` and `status.sh` every beat;
  status output is the only thing surfaced to the owner.
- the governance layer registers as the second consumer when its side has a shape; later, an
  the governance layer Source turns its events into Triggers.

## Standing risks, named

- **The conductor is a single point of failure.** Loom state is plain JSON on
  disk, so any future conductor session resumes it; but dispatch judgement
  (Eval) still needs a session awake. Mitigation lives outside loom: the
  heartbeat and, later, the consumer wake bundles.
- **Executor sandboxes differ.** v1 assumes only: worker can read/write its
  own workdir and run git locally. Anything stricter is the consumer's
  problem to declare in its config.
- **gh is a dependency** for issue reads. Acceptable: tickets are GitHub
  issues by design; a non-GitHub Source is an L3+ concern.
