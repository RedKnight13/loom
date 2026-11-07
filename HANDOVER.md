# Loom — handover

Read this first if you are picking loom up: a new conductor session, another
machine, or an integration. Then [PROTOCOL.md](PROTOCOL.md) (the law),
[ops/README.md](ops/README.md) (the tools), [ROADMAP.md](ROADMAP.md) (the bar),
[docs/setup.md](docs/setup.md) (install and configuration), and
[drills/EVIDENCE-2026-11-07.md](drills/EVIDENCE-2026-11-07.md) (the proof).

## What loom is, in one paragraph

A generic, repo-agnostic protocol plus a dozen small bash scripts for running
agent workers on repository work with as little human attention as possible. A
request becomes a **Ticket** (a GitHub issue with an immutable **Mandate**);
**dispatch** gives the worker an isolated workspace (a private clone with no
remote, or an Orca worktree); the worker writes files and one structured line in
`REPORT.md` and never touches git; loom commits for it, watches it with a
**watchdog** keyed to PID + start time and process group, re-runs the consumer's
checks itself in a **fresh clone** (on the consumer's compute host when one is
declared), and surfaces only what needs a person. The conductor is the only role
that pushes, opens PRs and merges, under the owner's GitHub name.

**The call.** Any harness uses `ops/loom`: one command, one JSON object, exit 0
iff `ok`. It cannot tell which executor ran the work. Specs in
`docs/superpowers/specs/`.

## State at handover (0.6.0)

| | |
| --- | --- |
| Version | `VERSION` = `0.6.0` |
| Code | `main` after PRs #39–#55; the conductor's hotfix and lint commits included |
| Scripts | `ticket` → `dispatch` → `launch` / `orca start` → `harvest` → `watch` → `verify` → `collect` → `ack`; plus `release`, `report`, `selftest`, `mutate` |
| Proof | `bash ops/selftest.sh` exit 0 · `shellcheck -x ops/*.sh ops/loom` exit 0 · `bash ops/mutate.sh`: 50 mutants, all caught |
| Drills | D1–D4 passed at 0.5.0 on real repos. **Not yet re-run at 0.6.0.** |
| Gaps | Found by running real workers; tracked as issues. Open: #35 (task-DAG start) and #54 (checkout origin check). |
| Consumers | `consumers/consumer.toml` (first real consumer), `consumers/loom.toml` (drills) |
| State dir | `~/.loom`: one JSON record + logs per assignment, plus `<id>.evidence/` and receipts |

## How to run one ticket end to end

```bash
cd path/to/loom
bash ops/loom accept --consumer consumers/NAME.toml --short NAME --title "…" \
    --scope "…" --out "…" --done "…"                     # prints ticket, in the object
LOOM_REPO=/path/to/consumer bash ops/loom dispatch --consumer consumers/NAME.toml --issue N
bash ops/loom verify NAME.1 --baseline &                  # what was already true
bash ops/loom start NAME.1                                # Orca executor
# or: bash ops/loom launch NAME.1 -- codex exec -s workspace-write "Read WORK.md"
bash ops/loom watch --until NAME.1                        # silent until it settles
bash ops/loom harvest NAME.1                              # Orca executor only
bash ops/loom verify NAME.1                               # fresh-clone re-check
bash ops/loom collect NAME.1                              # branch into the checkout
# then: push the branch, open the PR, merge — conductor only.
bash ops/loom release NAME.1                              # Orca, after collect
bash ops/loom ack NAME.1 "merged as #N"
```

## The gap law (owner, 2026-11-07)

> "when running codex you will find more haps with loom whe n you find a gap
> makesure it is zdded in loomnos lets use for smorti work"

Every gap found while running workers becomes an issue labelled `gap`, is fixed
in loom, and lands with a selftest case **and** a mutant in `ops/mutate.sh` that
makes the selftest fail without the fix. Never work around a gap by hand without
filing it.

The other standing law: the conductor hand-writes code only in loom; every other
repo's code is built by workers under tickets.

## Current open work

- **#35** — every Orca row is a verb except starting from an Orca task
  (`--task --deps`). The real two-worker run is still the acceptance gate.
- **#54** — `dispatch` accepts a checkout whose `origin` is not the ticket's
  repo; a mistyped `LOOM_REPO` produces a base from the wrong project.
- **First real run at 0.6.0** — `ci-all-suites` (a consumer ticket) had several
  attempts: wrong checkout, then `agent_readiness` timeouts, then abandons. The
  readiness wait is now raised via the consumer's `start_timeout_ms`.
- **Drill refresh** — D1–D4 evidence is from 0.5.0; placement and compute
  changed, so re-run and commit a new evidence file before calling 0.6.0
  certified.
- **License** — no `LICENSE` file. Open-sourcing needs one; D3 is the question.

## Standing risks, named

- **The conductor is a single point of failure.** State is plain JSON on disk,
  so any session can resume it; Eval and merges still need a session awake.
- **Executor sandboxes differ.** Loom assumes a worker can read/write its own
  workspace. Anything stricter is the consumer's problem to declare.
- **`gh` is a dependency** for tickets. A non-GitHub Source is a later seam.
- **Private names in-tree.** `consumers/consumer.toml`, this file, the drills and
  the specs name private projects and hosts. Review them before making the
  repository public; the public README/docs are already scrubbed.
