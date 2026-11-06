# The loom protocol

Loom coordinates agent executors on repository work. It adapts the domain model
of DeepSeek's dsh-superagent prototype (MIT) to a small, harness-agnostic shape:
no service, no listeners, no panel process — just rules, records on disk, and
scripts a conductor runs. The principle it inherits whole:

**Take as little human attention as possible, and give as much value as possible.**

## Roles

| Role | Who | What it may do |
| --- | --- | --- |
| Owner | The person | Asks for work, answers `blocked` questions, approves anything irreversible. The only authority above the Mandate. |
| Conductor | One trusted agent session (the conductor, or any session the owner runs) | Evaluates requests into Tickets, writes Mandates, dispatches, reviews, and is the **only role that pushes, opens PRs, or merges** — always under the owner's GitHub name. |
| Worker | A headless executor (codex, a Claude subagent, anything scriptable) | Works inside its Assignment's worktree. Never pushes, never leaves the worktree, never touches another Ticket. Ends every turn with a structured report. |

## Domain

| Concept | Here it is | Rules it keeps |
| --- | --- | --- |
| Trigger | A request: the owner's words, a conductor's finding, a failing check | A Trigger alone authorizes nothing. |
| Eval | The conductor's judgement on a Trigger | Output is a Decision: ignore (recorded), or accept → Ticket with Mandate. Accepting the same Trigger twice yields one Ticket. |
| Ticket | A GitHub issue in the consumer repo, labeled `loom` | The unit of authorized work. Carries exactly one Mandate block. Open → ended; a person's message can reopen it under the same Mandate. |
| Mandate | A block on the issue body (see templates/MANDATE.md) | Immutable. Names the scope, the constraints (the consumer's standing laws), and the stop-by-impact line. Wider scope = new Ticket. Only the owner withdraws one. |
| Assignment | One worker bound to one Ticket | A JSON record in the loom state dir: ticket, worker PID, worktree, started-at, report log. Several Assignments per Ticket over time; at most one live. |
| Worktree | `git worktree` named after the Ticket's short name | A PR belongs to a Ticket when its branch matches the Ticket's short name. The conductor creates and removes it. |
| Report | One line of structured facts per worker turn | `ready | blocked | failed | waiting`, plus a short fact string. Appended to the Assignment record by ops/report.sh. Never inferred from prose. |
| Watchdog | ops/watchdog.sh under the conductor's heartbeat | No report within the limit (default 30 min) → kill the PID, mark the Assignment `failed` with `watchdog_kill`, leave the worktree for autopsy. The Ticket stays open and clean for re-dispatch. |

## Report states

| State | Means | The conductor then |
| --- | --- | --- |
| `ready` | A reviewable result exists (diff, report file, artifact) | Reviews it: run the tests yourself, capture exit codes, then PR/merge or send back. |
| `blocked` | Cannot continue without a decision; the report names ONE concrete question | Answers it, or raises it to the owner verbatim. |
| `failed` | The approach failed; the report names what and why | Reads the autopsy, re-mandates or closes. Never silently re-runs. |
| `waiting` | Turn done, nothing owed, work may continue next turn | Leaves it; the next dispatch or Trigger continues it. |

## Verification law

A worker's `ready` is a claim, not a result. The conductor re-runs the
consumer's checks itself and captures real exit codes before any merge.
"Not run" is reported as "not run". This mirrors the consumer repos' own law:
a check that can be talked out of checking is not a check.

## Consumers

A consumer repo registers with one file in `consumers/<repo>.toml`:

```toml
repo       = "example/consumer"     # where Tickets (issues) live
checks     = "python3 -m pytest -q"   # what the conductor re-runs on ready
worktrees  = "~/work/consumer-worktrees"
laws       = [                        # copied into every Mandate, verbatim
  "Workers never push; only the conductor pushes, under the owner's name.",
  "Nothing identifying the owner enters any file.",
  "GPU compute on build2 only; no credits spent without a quote.",
]
```

the governance layer integration is a consumer plus, later, a Source: the governance layer events becoming
Triggers. The domain already has the seam; nothing in loom assumes GitHub is
the only Source kind.

## What loom refuses to grow

Adapted from the prototype's rejected-concepts table, kept deliberately:

- No person/identity entity. The owner's words are quoted; identities are
  never mapped across systems.
- No worker-declared stops. Only the owner stops a Ticket; only Eval ends one.
- No inferring state from free text. Structured fields or nothing.
- No settings where a default serves. Behaviour a person can describe in
  words becomes Mandate text, not configuration.
