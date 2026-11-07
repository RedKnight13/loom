# Loom — handover (2026-11-07)

Read this first if you are picking loom up: a new conductor session, another
machine, or ARGOS integration. Then PROTOCOL.md (the law), ops/README.md (the
tools), ROADMAP.md (the bar), drills/EVIDENCE-2026-11-07.md (the proof).

## What loom is, in one paragraph

A generic, repo-agnostic protocol plus a dozen small bash scripts for running
agent workers (codex today, anything scriptable tomorrow) on repository work
with as little human attention as possible. A request becomes a **Ticket** (a
GitHub issue with an immutable **Mandate**); dispatch makes the worker a
**private clone with no remote**; the worker writes files and one structured
line in `REPORT.md` and never touches git; loom commits for it, watches it with
a **watchdog** keyed to PID + start time and process group, re-runs the
consumer's checks itself in a **fresh clone**, and surfaces only what needs a
person. The conductor is the only role that pushes, opens PRs and merges,
under the owner's GitHub name.

## State at handover

| | |
| --- | --- |
| Code | `main` (PRs #2, #3, #15, #16, #17, #18, #21, #23 merged) |
| Scripts | `ticket` → `dispatch` → `launch` → `heartbeat` (watchdog + status) → `verify` → `collect`; plus `report`, `selftest`, `mutate` |
| Proof | `bash ops/selftest.sh` exit 0 · `shellcheck -x ops/*.sh` exit 0 · `bash ops/mutate.sh`: 17 mutants, all caught |
| Drills | **D1, D2, D3, D4 PASS** on real repos — D1 = smriti#43, merged as smriti#44 (first real work through loom) |
| Gaps | 16 found by running real workers, 16 fixed (issues labelled `gap`, all closed) |
| Consumers | `consumers/smriti.toml` (first real consumer), `consumers/loom.toml` (drills only) |
| State dir | `~/.loom` on the conductor's machine: one JSON record + log per assignment |

## How to run one ticket end to end

```bash
cd ~/Work/claude-code/loom
bash ops/ticket.sh consumers/smriti.toml --short NAME --title "…" \
    --scope "…" --out "…" --done "…"                     # prints the issue URL
LOOM_REPO=~/Work/claude-code/smriti bash ops/dispatch.sh consumers/smriti.toml <issue#>
bash ops/verify.sh NAME.<n> --baseline &                  # what was already true
bash ops/launch.sh NAME.<n> -- codex exec -s workspace-write \
    "You are a loom worker. Read WORK.md ... (see ops/README.md)" &
bash ops/heartbeat.sh --until NAME.<n>                    # silent until it settles
bash ops/verify.sh NAME.<n>                               # fresh-clone re-check
bash ops/collect.sh NAME.<n>                              # branch into the checkout
# then: push the branch, open the PR, merge — conductor only.
```

## The gap law (owner, 2026-11-07)

> "when running codex you will find more haps with loom whe n you find a gap
> makesure it is zdded in loomnos lets use for smorti work"

Every gap found while running workers becomes an issue labelled `gap`, is fixed
in loom, and lands with a selftest case **and** a mutant in `ops/mutate.sh`
that makes the selftest fail without the fix. Never work around a gap by hand
without filing it. Smriti work goes through loom.

The other standing law: the conductor (Margin) hand-writes code only in loom;
every other repo's code is built by workers under tickets.

## The 16 gaps real runs found (all fixed)

| # | Gap | Fix |
| --- | --- | --- |
| 11 | codex sandbox makes `.git` read-only even in a private clone | workers never touch git; harvest commits for them |
| — (v1) | worktrees share `.git`; no PID recorded; workers can't write state | private clones; `launch.sh`; `REPORT.md` contract |
| 6 | heartbeat hand-written | `heartbeat.sh` |
| 7 | one watchdog limit for all consumers | `limit_min` per consumer |
| 8 | hand-typed tickets drift from the template | `ticket.sh` + shared parser |
| 9 | conductor's re-check not mechanized | `verify.sh` (fresh clone) |
| 10 | `ps` padding in `worker_start` | trimmed |
| 12 | no baseline → impossible Done-means | `verify.sh --baseline` |
| 13 | checks may be unrunnable | 126/127 reported as *could not run* |
| 14 | reused short names collide | attempts numbered per short name |
| 19 | loom's umask 077 leaked into workers/checks | children get the caller's umask |
| 20 | uncommitted consumer config accepted | refused; config commit pinned |
| 22 | consumer commit hooks rewrite worker files; loom swallowed the failure | re-stage and retry once; rejections logged |
| (drills) | global watchdog would kill other live workers | `watchdog.sh --id` |

## Open items, honestly

- **ARGOS** is not wired yet. The seam exists: argos registers as a consumer
  (`consumers/argos.toml`), and later an ARGOS Source turns its events into
  Triggers. Smriti's `docs/ARGOS.md` (D1's deliverable) is the call contract.
- **The conductor is a single point of failure.** State is plain JSON on disk,
  so any session can resume it, but Eval and merges need a session awake.
  Loom state lives on one machine (`~/.loom`); moving conductors means moving
  that directory.
- **Smriti test hygiene** (not loom's): smriti's suites cannot share one
  process (SMRITI_HOME fixtures; a module named `run`), and `test_isolation`
  silently assumes umask 022. Both deserve smriti tickets, through loom.
- **Push permission** on this machine covers exactly the smriti and loom
  clones (`.claude/settings.local.json` in auden-film). A new consumer needs
  its own allow line, granted by the owner.
- **Commit identity:** dispatch copies `user.name`/`user.email` as git
  resolves them in the consumer checkout. Smriti's checkout has no local
  identity, so loom commits there carry the global one (the owner's second
  GitHub noreply address, as several existing smriti commits already do). If
  every consumer commit must carry the RedKnight13 noreply address, set it in
  the consumer checkout's local git config; loom will copy it.
- **Drill branches** (`drill-d2`, `drill-d3`) live only in
  `~/Work/claude-code/loom-workdirs/` and are never merged; delete freely.
