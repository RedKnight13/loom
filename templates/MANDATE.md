# Mandate template

Paste this block into the Ticket (issue) body, filled. It is immutable once a
worker is dispatched; wider scope means a new Ticket.

```markdown
## Mandate

**Ticket short name:** <kebab-short-name>   <!-- names the worktree and branch -->
**Scope:** <exactly what may be built or changed, and in which paths>
**Out of scope:** <what the worker must not touch, even if tempting>
**Laws:** <copied verbatim from consumers/<repo>.toml>
**Done means:** <the check that proves it: command + expected exit code / artifact>
**Stop by impact:** a reviewable result ends the turn `ready`; a design
decision ends it `blocked` with one concrete question. Effort is not a
stopping reason.
**Report:** end every turn with ops/report.sh <ready|blocked|failed|waiting> "<fact>"
```

## Rules of use

- The conductor writes the Mandate at accept time (Eval), never the worker.
- "Done means" is written before the work starts — the check before the code.
- A Mandate never contains credentials, personal names, or anything
  identifying the owner.
- A Ticket's end does not end its Mandate: a person's message on the issue
  resumes the Ticket under the same Mandate. Only the owner withdraws one.
