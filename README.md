# loom

A work-coordination protocol for agent executors. Tickets, mandates, dispatch,
structured reports, a watchdog. One conductor, many workers, as little human
attention as possible.

A loom holds many threads under tension and turns them into one fabric. This
repo holds the rules and the small tools that do the same for agent work: a
request becomes a **Ticket**, the Ticket carries a **Mandate** that says why the
work may be done and how far it may go, an **Assignment** binds the Ticket to
one worker in its own worktree, and the worker ends every turn with a
**structured report** — never free text a conductor has to interpret.

**One call.** 0.5.0 adds `ops/loom`: one command, one JSON object, the same for
Claude, Codex, or any later harness. The caller cannot tell which executor ran
the work. Contract: [docs/superpowers/specs/2026-11-07-loom-0.5.0-design.md](docs/superpowers/specs/2026-11-07-loom-0.5.0-design.md).

Loom is repo-agnostic. A consumer repo (smriti, argos, anything) adds a small
config and uses loom's scripts against its own issues.

**Where it runs.** 0.6.0 adds `compute`: checks run on the consumer's compute
host over SSH and workers are placed there through Orca. A declared host that
is unreachable refuses; it never falls back to the conductor's machine.
Contract: [docs/superpowers/specs/2026-11-07-loom-0.6.0-design.md](docs/superpowers/specs/2026-11-07-loom-0.6.0-design.md).

## Why it exists

Hand-run delegation fails the same ways everywhere: a worker hangs for 92
minutes looking alive, liveness gets inferred from a PID, a dead worker's spec
is re-dispatched from memory, and the rules the work ran under live in nobody's
file. Loom turns each of those into a mechanism.

Lineage: the domain model is adapted from DeepSeek's dsh-superagent prototype
(MIT), stripped of its service layer. We keep the law, not the plumbing.

## The law (short form)

1. **Work starts only from a Ticket.** A Ticket is a GitHub issue carrying a
   Mandate block. No Ticket, no worker.
2. **The Mandate is immutable.** Scope, constraints, stop-by-impact line.
   Wider scope means a new Ticket.
3. **Workers never push.** A worker works in its worktree and reports. Only
   the conductor pushes, reviews, and merges, under the owner's name.
4. **Reports are structured facts.** Every turn ends in one of
   `ready | blocked | failed | waiting`, written to the Assignment record.
   Liveness is never inferred from a PID or from prose.
5. **The watchdog is the clock.** No structured report within the limit
   (default 30 minutes) → kill by PID, mark the Assignment `failed`, leave the
   Ticket clean for re-dispatch. Accepting the same Ticket twice creates one
   unit of work, not two.
6. **Stop by impact, not effort.** A reviewable result ends a turn `ready`.
   A design decision ends it `blocked` with one concrete question.
7. **Speak only when a person must act.** A healthy loom is silent.

The full protocol, with the domain table and the report format, is in
[PROTOCOL.md](PROTOCOL.md). The mandate template is
[templates/MANDATE.md](templates/MANDATE.md).

## Layout

    PROTOCOL.md            the domain and its rules
    templates/MANDATE.md   mandate block for a Ticket (issue) body
    ops/dispatch.sh        issue → worktree → worker, records the Assignment
    ops/report.sh          worker writes its end-of-turn structured report
    ops/watchdog.sh        enforces the report clock, cleans up hung workers
    ops/status.sh          one screen: what waits for a person, and nothing else
    consumers/             per-repo config (one file per consumer repo)

## Status

Seeded by hand. The ops tooling is built and maintained through loom's own
protocol — its first Tickets are its own tools.
