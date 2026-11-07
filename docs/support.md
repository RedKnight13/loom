# Support

What works today, what does not, and what it was tested on. Version **0.6.0**.

## Matrix

| Capability | State | Notes |
| --- | --- | --- |
| Ticket rendering + Mandate parser | ✅ | `ticket.sh` proves its own output parses |
| Ticket labels | ✅ | repeatable `--label`; `loom-ready` defaulted when present |
| Eval record (`accept` / `ignore`) | ✅ | ignore is an append-only `decisions.jsonl` |
| Local executor (private clone) | ✅ | no remote, own `.git`, git-free worker |
| Orca executor ([MIT](https://github.com/stablyai/orca)) | ✅ | supervised worker, mail, release; requires 1.4.246+ and a running app |
| Orca placement on `compute` | ✅ | first connected host wins; refuses when none |
| Checks over SSH | ✅ | bundle over stdin, fresh tree, log back |
| `--on HOST` for one verify run | ✅ | for assignments dispatched before a host was declared |
| Watchdog (PID + start time, group kill) | ✅ | per-consumer `limit_min` |
| Worker cap | ✅ | `workers`; `dispatch` refuses past it, `loom capacity` suggests one per connected host |
| Stale Orca worker surfaced, never killed | ✅ | owner decides |
| `ack` settling a handled result | ✅ | history kept; a kept-open workspace still shows |
| Release after collect | ✅ | confirmed by Orca; never deletes worktrees |
| Structured report harvest | ✅ | one state line per turn |
| Consumer commit hooks | ✅ | fixers retried once; rejections logged |
| The one-call JSON envelope | ✅ | every verb |
| Orca read/write verbs (`send ask reply gate task run reference worktree repo base-ref automation`) | ✅ (thin) | pass-through; behaviour is Orca's, smoke-tested |
| Orca task-DAG start (`--task --deps`) | ❌ | mapped, not wired |
| Scheduled heartbeat / automations | ❌ | `automation` is a verb only; bring your own scheduler |
| Push, PR, merge | ❌ | by design: conductor only |
| Non-GitHub ticket source | ❌ | seam exists; not implemented |
| Multi-conductor coordination | ❌ | one state dir, one conductor at a time |
| Windows native | ❌ | bash 3.2+/POSIX shell expected; WSL untested |

## Platform

| Platform | Status |
| --- | --- |
| macOS (bash 3.2) | primary, all selftests |
| Linux (bash 5) | selftests pass; not the daily driver |
| WSL | untested |
| Windows native | unsupported |

The selftest is offline and hermetic: a throwaway repo, stubbed `gh`, `orca`,
`ssh`, and fake workers. It signals no real process.

## Versioning

`VERSION` is the protocol version. `0.x` means the shape may still change. A
breaking change to the call contract gets a new spec in
`docs/superpowers/specs/` and a version bump; additive verbs do not.

## Known gaps

Tracked as issues on the repository. At 0.6.0:

- Orca workers are not started from a task DAG (`worker-start --task --deps`).
- A remote agent whose startup exceeds Orca's readiness wait needs the
  consumer's `start_timeout_ms` raised (for example `300000`).
- The verification drills (D1–D4) were captured at 0.5.0; 0.6.0 changes
  placement and compute, so the evidence needs a refresh against this code.
- `dispatch` accepts a checkout whose `origin` is not the ticket's repo (#54).
- No CI. The gate is `selftest` + `shellcheck` + `mutate` on the conductor's machine.

## Getting help

Open an issue with: `VERSION`, platform, the verb, the captured exit code, and
the relevant JSON object. A report without a captured exit code is a claim, not
a result — the project's own law.
