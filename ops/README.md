# Loom operations (v1)

Bash 3.2+, git, `gh`, `jq` 1.6+, and `ps`. No service, no runtime, no
installer. ShellCheck only for linting.

## The lifecycle

```bash
# 1. Eval happened: the Ticket is a GitHub issue with a "## Mandate" block.
LOOM_REPO=/path/to/consumer bash ops/dispatch.sh consumers/<repo>.toml 42
#    → prints the workdir and the assignment id, e.g. smriti-pyz.1

# 2. Run any worker in it (blocks until the worker exits; background it).
bash ops/launch.sh smriti-pyz.1 -- codex exec -s workspace-write "Read WORK.md ..." &

# 3. Every heartbeat:
bash ops/watchdog.sh          # silent when healthy
bash ops/status.sh            # only what waits for a person

# 4. On ready: bring the branch home, re-run the checks yourself, then PR.
bash ops/collect.sh smriti-pyz.1
```

## What each script guarantees

| Script | Guarantee |
| --- | --- |
| `dispatch.sh <consumer.toml> <issue#>` | Reads the issue's Mandate via `gh`; refuses if the ticket already has a live worker. Creates `<worktrees>/<short>.<attempt>` as a **private clone** (own `.git`, **no remote**, so it can commit but cannot push), on branch `<short>` at the default branch, with the consumer's git identity. Writes `WORK.md` (mandate + laws + how to report), excluded from git. Records the assignment. |
| `launch.sh <id> -- <cmd...>` | Runs the worker in its workdir with **no stdin** and its **own process group**; records PID + start time; logs to `$LOOM_STATE/<id>.log`. On exit, harvests the newest `state:` line the worker wrote **this launch** (older lines are skipped by offset). Exit with no line → `failed / worker_exit_no_report (exit N)`. |
| `watchdog.sh [--limit-min N]` | Live worker silent past N minutes (default 30) → kills its **whole process group**, records `failed / watchdog_kill` once, keeps the workdir. Worker gone without its launcher (e.g. the conductor session died) → harvests its report or records `failed / worker_lost_no_report`. A recycled PID never matches the recorded start time and is never signalled. |
| `status.sh` | One line per assignment whose latest report is `ready`, `blocked` or `failed` and has no live worker: `id<TAB>state<TAB>fact`. Silent when healthy. |
| `collect.sh <id>` | Fetches the ticket branch from the worker clone into the consumer checkout and prints the commits over the recorded base. Never pushes. |
| `report.sh <id> <state> "<fact>"` | Conductor-side manual report (e.g. recording a review verdict). |

## The worker contract

A worker only ever:

1. reads `WORK.md` in its workdir,
2. works and commits on its branch inside the workdir,
3. ends its turn by appending one line to `REPORT.md`:

```
state: <ready|blocked|failed|waiting> — <one-line fact>
```

It never writes `$LOOM_STATE`, never pushes (the clone has no remote), and
never leaves its workdir. Everything else is the conductor's.

## State

`$LOOM_STATE` (default `~/.loom`), conductor-only: one JSON record per
assignment plus its log. Writes take a lock that records its owner; a lock
whose owner died is broken automatically, a live one is waited on for
`LOOM_LOCK_WAIT` seconds (default 10). Records are validated on every read;
a corrupt record stops the scripts instead of reading as healthy.

## Consumer config

```toml
repo      = "owner/name"                  # where Tickets (issues) live
checks    = "python3 -m pytest -q"        # what the conductor re-runs on ready
worktrees = "~/Work/name-workdirs"        # where workdir clones go
laws      = ["…", "…"]                    # copied verbatim into every WORK.md
```

A bounded TOML subset: double-quoted strings, string arrays (multiline,
trailing comma), `#` comments outside strings. Unknown or duplicate keys are
rejected; nothing is ever evaluated. `checks` is documentation for the
conductor; loom never executes it.

## Proof

`bash ops/selftest.sh` runs the whole lifecycle offline against a throwaway
repo with a stubbed `gh` and fake workers: ready, blocked, silent exit, hung
worker with a child process, lost launcher, recycled PID, stale and live
locks, corrupt state. Every guarantee in the table above has a test that a
deliberate mutation of the code makes fail.
