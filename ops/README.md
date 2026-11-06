# Loom operations

Run these scripts with Bash (3.2 or later). Runtime tools are Git, GitHub CLI
(`gh`), and `jq` (1.6 or later), plus the ordinary filesystem utilities
`mkdir`, `mv`, `rm`, and `rmdir`. The self-test also uses `chmod` and `cat`.
There is no service, language runtime, TOML package, or worker launcher.
ShellCheck is needed only for linting.

## Dispatch

```bash
LOOM_REPO=/path/to/consumer bash ops/dispatch.sh /path/to/consumer.toml 7
```

`LOOM_REPO` selects an existing local consumer checkout; it defaults to the
current directory. The config's `repo` is the GitHub `organization/repository`,
not a local path. Dispatch reads the issue's number, title and body with
`gh issue view`, and its repository's default branch with `gh repo view`.
These are the only network calls. It never clones, fetches, pushes, writes to
GitHub, or starts a worker.

The config accepts the registration format shown in `PROTOCOL.md`:

```toml
repo = "example/project"
checks = "bash check.sh"
worktrees = "~/work/project-worktrees"
laws = [
  "Workers never push.",
  "Captured exit codes only.",
]
```

This deliberately bounded TOML reader supports double-quoted strings with
JSON-compatible escapes, multiline arrays of those strings, trailing array
commas, blank lines, and `#` comments outside strings. Required keys are
`repo`, `worktrees`, and `laws`; `checks` is accepted but not executed.
Duplicate/unknown keys and other TOML constructs are rejected. Paths must be
absolute or start with `~/`; shell substitutions are never evaluated.

The issue must contain a `## Mandate` section with a line such as
`**Ticket short name:** fixture-task` (an optional trailing HTML comment is
accepted). Short names consist of lowercase letters/digits separated by
single hyphens. The section ends at the next level-two heading or end of body.
The worktree and new branch use this short name. The base is the locally
available `origin/<default-branch>`, falling back to the local default branch.
The conductor is responsible for fetching a current base beforehand.

Dispatch writes the issue title, mandate, and verbatim consumer laws into
`WORK.md`. An existing destination, branch, `WORK.md`, or live assignment for
the ticket causes failure. It never overwrites a prior assignment or removes
a worktree. If an error occurs after worktree creation, the worktree is kept
for conductor inspection. Re-dispatch after a prior assignment requires the
conductor to resolve the existing branch and worktree first.

On success stdout is exactly two lines: the worktree path, then the assignment
ID. Git progress and errors go to stderr.

## Assignment records and worker attachment

`LOOM_STATE` defaults to `~/.loom`. Each assignment lives directly in
`$LOOM_STATE/<assignment-id>.json`:

```json
{
  "ticket": 7,
  "repo": "example/project",
  "short_name": "fixture-task",
  "worktree": "/path/to/worktrees/fixture-task",
  "worker_pid": null,
  "started_at": "2026-01-01T00:00:00Z",
  "reports": []
}
```

Timestamps are UTC ISO 8601 strings. Each report is an object with `at`,
`state`, and `fact`. Dispatch leaves `worker_pid` null. The conductor launches
the chosen worker, then attaches its positive numeric PID in this field.
It must use the same state lock and atomic replacement described below and
preserve all existing reports. Clear the PID after the worker exits. Start
the worker promptly: until the first report, the deadline is `started_at`.

State writers acquire `$LOOM_STATE/.lock` with `mkdir`, write `.pending`, and
rename it onto the record. A competing writer fails nonzero rather than
losing an appended report; retry after the operation finishes. Normal exits
remove the lock. If a writer is forcibly killed, the conductor must check
that no writer is active before removing an abandoned `.pending` and `.lock`.
Do not edit records concurrently without this lock. The state directory and
registered consumer configuration are trusted, local conductor inputs.

## Report

```bash
bash ops/report.sh assignment-id ready "Checks passed; review the diff."
bash ops/report.sh assignment-id blocked "Which compatibility target applies?"
```

Only `ready`, `blocked`, `failed`, and `waiting` are accepted. The ID must refer
to an existing valid record and the fact must be nonempty. The new timestamped
report is appended without replacing history. Exit 0 means it was recorded;
invalid arguments, corrupt state, lock contention, or write errors return
nonzero. Successful reporting is silent. `report.sh` also supplies the private
state helpers sourced by the other scripts; sourcing it does not record a report.

## Watchdog

```bash
bash ops/watchdog.sh                 # 30 minutes
bash ops/watchdog.sh --limit-min 10
```

For each live numeric worker PID, compare the newest report timestamp (or
`started_at` if there are no reports) to the deadline. A stale worker receives
SIGKILL, ensuring a hung process cannot ignore termination. The watchdog then
appends `failed` / `watchdog_kill`, clears the PID, and prints
`<assignment-id> failed watchdog_kill`. It keeps the worktree and all previous
reports. Fresh, absent, and dead PIDs produce no output. Dead PIDs are not
silently classified as failed. A second run does not repeat a completed kill.
The limit is a nonnegative integer in minutes; zero permits immediate expiry.

PID-only tracking cannot distinguish a reused OS PID. The conductor must keep
the field current and point it at the actual worker, not a process group or
launcher. The watchdog signals only that PID, not its descendants. Errors go
to stderr with a nonzero exit; a kill followed by a storage error is not a
successfully recorded failure and requires conductor inspection.

## Status

```bash
bash ops/status.sh
```

Only the latest report determines what currently needs a person. Each
`blocked`, `ready`, or `failed` assignment prints one TSV line containing ID,
state, and fact. Tabs/newlines/backslashes in facts are escaped, keeping each
assignment on one line. `waiting`, no reports, or no assignments are silent.
Malformed records produce an error instead of appearing healthy. Status does
not modify state.

## Verification

```bash
bash ops/selftest.sh
shellcheck ops/*.sh
```

The self-test creates its throwaway repository, state, and worktrees under a
temporary `ops/.selftest-*` directory and removes it on exit. It stubs only
GitHub reads, makes no network calls, and uses disposable Bash child PIDs in
place of real workers. Bash may print expected `Killed: 9` job notifications.
It checks default-branch dispatch, paths with spaces, copied laws, duplicate
dispatch rejection, report validation and preserved history, status filtering
and escaping, fresh/stale/never-reporting workers, retained worktrees,
watchdog repeat safety, invalid limits, lock contention, and corrupt records.
It does not access real assignments. Both commands must exit 0.
