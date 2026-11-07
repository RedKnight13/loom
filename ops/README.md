# Loom operations (v1)

Bash 3.2+, git, `gh`, `jq` 1.6+, and `ps`. No service, no runtime, no
installer. ShellCheck only for linting.

## The lifecycle

```bash
# 0. Eval happened. Record the decision, then render the Ticket.
bash ops/loom ignore --consumer consumers/<repo>.toml --short NAME --reason "…"
bash ops/loom accept --consumer consumers/<repo>.toml --short NAME --title "…" \
    --scope "…" --out "…" --done "…"

# 1. Dispatch it.
LOOM_REPO=/path/to/consumer bash ops/loom dispatch --consumer consumers/<repo>.toml --issue 42
#    → {"id":"pyz.1","fact":"<workdir>", …}

# 2. Run the worker (local executor; Orca configs use `loom start`).
bash ops/loom launch pyz.1 -- codex exec -s workspace-write "Read WORK.md ..."

# 3. Keep the clock.
bash ops/loom watch --until pyz.1

# 4. On ready: re-check in a fresh clone, collect, then PR.
bash ops/loom verify pyz.1 --baseline
bash ops/loom verify pyz.1
bash ops/loom collect pyz.1

# 5. When a person has dealt with a result, settle it out of status.
bash ops/loom ack pyz.1 "reviewed, PR merged"
```

Every call prints one JSON object and exits 0 only when `ok` is true. The
scripts under `ops/` remain the mechanism; `ops/loom` is the contract.

## What each script guarantees

| Script | Guarantee |
| --- | --- |
| `loom <verb> …` | The call. One JSON object on stdout, exit 0 iff `ok`. `version`, `accept`, `ignore`, `dispatch`, `launch`, `start`, `harvest`, `stop`, `release`, `watch`, `status`, `verify` (`--on HOST`), `collect`, `report`, `ack`, `detect`, `compute`, `hosts`, `show`, `read`, `abandon`, `keep-open`, `list`, `request`, `peek`, `inbox`, `send`, `ask`, `reply`, `gate`, `task`, `run`, `reference`, `worktree`, `repo`, `base-ref`, `automation`. See the specs. |
| `ack.sh <id> "<why>"` | A person has dealt with this assignment: sets `.acked` once, refuses a live worker. Status drops the report row; history stays. |
| `ticket.sh <consumer.toml> --short … --title … --scope … --out … --done … [--label NAME]… [--no-default-label]` | Renders the Mandate exactly from the template, proves dispatch's own parser accepts it, opens the issue with its labels. `loom-ready` is added by default when the repo has that label (#38). Ticket text is literal, never evaluated. `--dry-run` prints the body. |
| `dispatch.sh <consumer.toml> <issue#>` | Reads the issue's Mandate via `gh`; refuses if the ticket already has a live worker. Creates `<worktrees>/<short>.<attempt>` as a **private clone** (own `.git`, **no remote**, so it can commit but cannot push), on branch `<short>` at the default branch, with the consumer's git identity. Writes `WORK.md` (mandate + laws + how to report), excluded from git. Records the assignment. |
| `launch.sh <id> -- <cmd...>` | Runs the worker in its workdir with **no stdin** and its **own process group**; records PID + start time; logs to `$LOOM_STATE/<id>.log`. On exit, harvests the newest `state:` line the worker wrote **this launch** (older lines are skipped by offset). Exit with no line → `failed / worker_exit_no_report (exit N)`. |
| `watchdog.sh [--limit-min N]` | Live worker silent past N minutes (default 30) → kills its **whole process group**, records `failed / watchdog_kill` once, keeps the workdir. Worker gone without its launcher (e.g. the conductor session died) → harvests its report or records `failed / worker_lost_no_report`. A recycled PID never matches the recorded start time and is never signalled. |
| `heartbeat.sh --until <ID\|all> [--every SEC] [--limit-min N]` | The conductor's clock: runs the watchdog every SEC (default 60), prints only its actions, stops when the assignment (or all) has settled, then prints status. |
| `status.sh` | One line per assignment whose latest report is `ready`, `blocked` or `failed` and has no live worker: `id<TAB>state<TAB>fact`. Silent when healthy. |
| `verify.sh <id> [--baseline]` | Runs the consumer's `checks` in a **fresh clone** the worker never touched — at the base (`--baseline`) or at the ticket branch tip. Records every run; a branch run records a conductor report (`ready` = verified, `failed` = checks failed). Exit 126/127 is reported as **could not run**, never as a test failure. |
| `collect.sh <id>` | Fetches the ticket branch from the worker clone into the consumer checkout, prints the commits over the recorded base, and records `.collected_sha`. Never pushes. |
| `report.sh <id> <state> "<fact>"` | Conductor-side manual report (e.g. recording a review verdict). |

## The worker contract

A worker only ever:

1. reads `WORK.md` in its workdir,
2. works inside the workdir and **never runs git** (some executor sandboxes make
   `.git` read-only); loom commits what it leaves when it reports,
3. ends its turn by appending one line to `REPORT.md`:

```
state: <ready|blocked|failed|waiting> — <one-line fact>
```

It puts logs and other evidence under `.loom/` in its workdir: loom copies that
directory into `$LOOM_STATE/<id>.evidence/` and never commits it. It never
writes `$LOOM_STATE`, never pushes (the clone has no remote), and never leaves
its workdir. Everything else is the conductor's.

## State

`$LOOM_STATE` (default `~/.loom`), conductor-only: one JSON record per
assignment plus its log. Writes take a lock that records its owner; a lock
whose owner died is broken automatically, a live one is waited on for
`LOOM_LOCK_WAIT` seconds (default 10). Records are validated on every read;
a corrupt record stops the scripts instead of reading as healthy.

## Consumer config

```toml
repo      = "owner/name"                  # where Tickets (issues) live
checks    = "python3 -m pytest -q"        # run by verify.sh; shown to the worker in WORK.md
limit_min = 45                            # optional: this consumer's watchdog limit
worktrees = "~/Work/name-workdirs"        # where workdir clones go
laws      = ["…", "…"]                    # copied verbatim into every WORK.md
```

A bounded TOML subset: double-quoted strings, string arrays (multiline,
trailing comma), `#` comments outside strings. Unknown or duplicate keys are
rejected; nothing in the config is evaluated at parse time. `checks` is run
only by `verify.sh`, in a fresh clone, as the conductor's explicit act.

## Proof

`bash ops/selftest.sh` runs the whole lifecycle offline against a throwaway
repo with a stubbed `gh`, a stubbed `orca`, and fake workers: ready, blocked,
silent exit, hung worker with a child process, lost launcher, recycled PID,
git-free worker, per-consumer limits, reused short names, verify (fresh clone,
baseline, could-not-run), the Orca executor (workspace receipt, release only
after collect, stop only on confirmation), evidence handling, ack, the `loom`
call, stale and live locks, corrupt state, ticket labels, compute-host checks, Orca placement, and the
0.6.0 Orca verbs.

`bash ops/mutate.sh` proves the selftest has teeth: each mutant re-introduces
a fixed defect and the selftest must fail on every one. A gap fix lands with
its selftest case **and** its mutant. 0.5.0 adds m25–m29; 0.6.0 adds m30–m39.

## Executors: Orca first

Owner's rule (2026-11-07): workers "only start or stop through orcacli".
Loom detects the Orca CLI (`orca status`: runtime reachable and ready) and
routes through it.

| Policy (`executor` in the consumer config, or `dispatch --executor`) | Behaviour |
| --- | --- |
| `auto` (default) | Orca when detected, else the local launcher |
| `orca` | Orca required; refused while Orca is not ready — never a silent fallback |
| `local` | the local launcher (`launch.sh`) |

While Orca is detected, `launch.sh` refuses to start anything unless
`LOOM_ALLOW_LOCAL=1` is set explicitly.

The Orca lifecycle:

```bash
bash ops/orca.sh detect                       # exit 0 = ready
bash ops/dispatch.sh consumers/<repo>.toml 42 # record only; no clone
bash ops/verify.sh <id> --baseline
bash ops/orca.sh start <id> [--agent codex]   # worker-start in a new top-level worktree
# ... end the turn: Orca wakes the conductor when the worker is done ...
bash ops/orca.sh harvest <id>                 # fold REPORT.md, commit, settle
bash ops/verify.sh <id> && bash ops/collect.sh <id>
```

- Orca creates and owns the worker's workspace (a worktree of the consumer
  checkout, which must be registered once: `orca repo add --path <checkout>`).
  Loom adopts it: writes WORK.md, excludes loom's files, commits on harvest.
- Loom **never signals an Orca worker**. Past its limit, `status.sh` shows it
  as `stale` for the owner's decision (Orca: a timeout alone never authorizes
  a stop). `orca.sh stop` asks Orca to stop it and records a stop only when
  Orca confirms one; `stop_unknown` changes nothing.
- A failed `worker-start` is recorded (`failed_start`) and never retried.
- Raw Orca receipts are kept as `$LOOM_STATE/<id>.orca-*.receipt`.
- Do not poll Orca's mailbox from scripts: Orca wakes the conductor.

## Compute hosts and placement

Owner (2026-11-07): compute runs on build, never the conductor's laptop.

```toml
compute       = ["build1", "build2"]                     # SSH hosts, first reachable wins
compute_setup = ". ~/.venvs/checks/bin/activate" # run on the host before the checks
```

- `verify.sh` ships the exact commit to the first reachable host as a git
  bundle, builds a fresh tree there, runs `compute_setup` then `checks` under
  the caller's umask, streams the log back to `$LOOM_STATE/<id>.checks-<kind>.log`,
  records the host in `checks_runs`, and removes its remote folder.
- No host reachable: `verify.sh` **refuses**. It never falls back to the
  conductor's machine.
- A failing `compute_setup` (or ssh itself failing) is reported as
  **could not run** (126/255), never as a test failure.
- Without `compute`, checks run locally as before (generic consumers).
- `--on HOST` names a host for one run (an assignment dispatched before its
  consumer declared one).
- Worker placement: `orca.sh start` uses the first `compute` host. It refuses
  when Orca does not know the host or has not connected it (#37); it never
  places the worker on the conductor's machine.
