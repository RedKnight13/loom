---
layout: documentation
title: "Platform support and known gaps"
---

# Platform support and known gaps

What works today, what does not, and what it was tested on. Version **0.6.0**.

## Standard workflow

| Capability | State | Notes |
| --- | --- | --- |
| Ticket rendering + Mandate parser | Available | `ticket.sh` proves its own output parses |
| Ticket labels | Available | repeatable `--label`; `loom-ready` defaulted when present |
| Eval record (`accept` / `ignore`) | Available | ignore is an append-only `decisions.jsonl` |
| Local executor (private clone) | Available | no remote, own `.git`, git-free worker |
| Orca executor ([MIT](https://github.com/stablyai/orca)) | Available | supervised worker, mail, release; requires 1.4.246+ and a running app |
| Orca placement on `compute` | Available | first connected host wins; refuses when none |
| Checks over SSH | Available | bundle over stdin, fresh tree, log back |
| `--on HOST` for one verify run | Available | for assignments dispatched before a host was declared |
| Local watchdog and settlement | Available | per-consumer `limit_min`; verified group settlement is required before clearing the assignment |
| Worker cap | Available | `workers`; `dispatch` refuses past it, `loom capacity` suggests one per connected host |
| Stale Orca worker surfaced, never killed | Available | owner decides |
| `ack` settling a handled result | Available | history kept; a kept-open workspace still shows |
| Release after collect | Available | confirmed by Orca; never deletes worktrees |
| Structured report harvest | Available | one state line per turn |
| Consumer commit hooks | Available | fixers retried once; rejections logged |
| Calibration and read-only drift check | Available | fixed offline drill; acceptance remains `not_run` |
| The one-call JSON envelope | Available | every verb |
| Orca read/write verbs (`send ask reply gate task run reference worktree repo base-ref automation`) | Adapter only | pass-through; behaviour is Orca's, smoke-tested |
| Orca task-DAG start (`--task --deps`) | Not available | mapped, not wired |
| Scheduled heartbeat / automations | External scheduler | `automation` is a verb only; bring your own scheduler |
| Push, PR, merge | Conductor-owned | by design: conductor only |
| Non-GitHub ticket source | Not available | seam exists; not implemented |
| Multi-conductor coordination | Not available | one state dir, one conductor at a time |
| Windows native | Unsupported | bash 3.2+/POSIX shell expected; WSL untested |

## Local execution and optional native runtime

Explicit `executor = "local"` (or `--executor local` where the consumer permits
it) works independently of Orca installation or runtime readiness. Dispatch
records the selected executor; a local assignment stays local if Orca later
appears. The native launcher never probes Orca, including for older local
records without an executor field. `LOOM_ALLOW_LOCAL` remains accepted but is
ignored; it grants no authority and is no longer needed. Local harvest requires
positive group-completion evidence. Watchdog signal delivery alone does not
settle an assignment; unreadable or missing supervision remains pending.

Required `executor = "orca"` still refuses an unavailable runtime and never
falls back to native execution. `auto` selection is unchanged: ready Orca wins
at dispatch, otherwise local is selected. The standard flow does not provide a general orchestrator adapter. The separate
[native workflow](native-workflow.html) adds opt-in process and SSH capabilities
with explicit provisioning and acceptance requirements.

Explicit-local calibration excludes Orca discovery, executable path/bytes and
`LOOM_ORCA` from the effective tools fingerprint. Installing, changing or
removing Orca cannot drift that local baseline. `auto` and `orca` still track
Orca's selector, executable and readiness, including when auto currently picks
local. This source/fingerprint update can invalidate existing baselines once:
review the drift, then explicitly run `loom calibrate --consumer FILE` and
verify with `--check`. Do not edit the stored ledger or silently rebaseline;
checks and failed recording preserve the existing evidence.

## Bootstrap and continuity limits

The [bootstrap prompt](bootstrap.txt) supports capability-based setup: shell
execution, tool-enabled inspection/editing without execution, and explicitly
unwired plain chat. It preserves existing files and asks only for unresolved
consequential decisions. Installation is limited to granted authorization.

[LOOM_SESSION.md](https://github.com/RedKnight13/loom/blob/main/templates/LOOM_SESSION.md) is a project checklist, not an
automatic hook. Its bridge requires `loom-calibration:v1` in root `AGENTS.md`
or `CLAUDE.md`, only after supported loading conventions are inspected. Both
files are fingerprinted when present; neither may be substituted with a global
instruction overwrite. Fresh-session loading must be observed;
otherwise continuity is unverified. Unsupported clients must open it manually.
Rechecking at session entry, before delegation and after dependency changes is
an agent instruction, not guaranteed runtime enforcement or background repair.

The root session bridge is also the per-repo permission for catalog patterns;
a repo without it uses the base Loom turn only. Selection reads every complete
`catalog/<id>/PATTERN.md` in the trusted Loom checkout. Incomplete entries are
not offered or used. A named pattern wins; ambiguous names list matches without
picking, and unknown names get no substitute. Manual choice lists all complete
entries with attribution. Explicit no opinion means the session says "Let me
propose an ideal flow for us," applies the
[selection criteria](patterns.html#recommendations),
and picks one. It states the reasoning, name, author, upstream, license and
task-grounded cost, effectiveness and intelligence estimate, then **using this
pattern**, in the same session. Silence asks once, then continues the authorized
base turn without a pattern and records no choice. A saved choice that still
fits is reused; a changed recommendation remains a proposal until accepted or
the person asks the session to pick. Selection grants no execution permission.

Save a selection in one `loom-pattern:start` / `loom-pattern:end` section in
that repo's root bridge. This changes fingerprinted bytes: run `loom calibrate
--consumer FILE --check`, review named drift, explicitly record with `loom
calibrate --consumer FILE`, then check again before delegation. If that flow is
unavailable, keep the choice session-only and report it was not persisted;
dependent delegation still requires a successful check. Linked pattern content
is not fingerprinted and needs separate review. New entries arrive with the
normal Loom checkout update through owner-reviewed and merged PRs; see the
[catalog contribution and review checklist](https://github.com/RedKnight13/loom/blob/main/catalog/README.md).

The confirmed schema-1 contract provides `loom calibrate --consumer FILE`
(explicit record plus fixed offline drill) and `loom calibrate --consumer FILE
--check` (comparison without writes, locks or drill rerun). Both ship in
`ops/loom`; older installations must be checked for command availability.
Hermetic regressions compose the shipped bridge with record/check, including
concurrent input changes, SHA-256 caller repositories and relative state paths.
This does not prove actual fresh-session instruction loading or live worker
execution. No additional TOML keys are required.

Ready means current prerequisites and offline drill only; acceptance is always
`not_run`. Exit 0 is ready, 1 is blocked/failed and 2 is usage failure. Sanitized
private baselines are under `${LOOM_STATE:-$HOME/.loom}/calibration/<key>.json`.
Fingerprint changes require review before explicit re-recording; check never
refreshes evidence. A failed record preserves the previous baseline. Observable changes during
record/check are refused; adversarial filesystem races remain outside the
contract. Relative `LOOM_STATE` resolves from invocation cwd; existing state
directories require mode 0700 and proof files mode 0600. No model,
provider authentication, real worker, consumer checks or remote compute is
proved by calibration. The tools' byte hashes detect accidental change; they
are not cryptographic attestation or proof that an executable is trustworthy.

Schema 1 does not automatically guard existing dispatch/start/launch commands.
The session agent must invoke and inspect the check, confirm it read the bridge,
and stop delegation on failure. The comparison-to-delegation gap remains.
Structural wiring, offline selftest/lint and live ticket-to-verification proof are separate
evidence levels. The first two never imply the third. A prompt cannot establish
universal security, automatic monitoring or full dependability. Setup uses
selftest/lint; contributors also use the longer portable mutation gate, locally or
on a compute host with `bash ops/mutate.sh --on HOST`.

## Platform

| Platform | Status |
| --- | --- |
| macOS (bash 3.2) | primary, all selftests |
| Linux (bash 5) | selftests pass; not the daily driver |
| WSL | untested |
| Windows native | unsupported |

The selftest uses throwaway repositories, stubbed services and fixture workers.
Process tests may start and signal fixture processes; passing them does not
establish acceptance with a real coding agent.

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
- `dispatch` checks checkout origin against the ticket repository; the explicit
  `LOOM_ALLOW_ANY_CHECKOUT=1` override relaxes it and must not be enabled by
  bootstrap merely to bypass a mismatch.
- CI runs selftest, ShellCheck and legacy lifecycle regressions on Linux and
  macOS; native supervision and mail regressions run on Linux. The mutation
  suite is a separate contributor check, not a routine setup requirement.
- Native runtime follow-ups cover [state read latency](https://github.com/RedKnight13/loom/issues/122),
  [supervisor overhead](https://github.com/RedKnight13/loom/issues/123),
  [legacy settlement](https://github.com/RedKnight13/loom/issues/124) and
  [real SSH, adapters and calibration acceptance](https://github.com/RedKnight13/loom/issues/125).
  Check each issue for its current status; opt-in availability is not rollout acceptance.

## Getting help

Open an issue with: `VERSION`, platform, the verb, the captured exit code, and
the relevant JSON object. A report without a captured exit code is a claim, not
a result — the project's own law.
