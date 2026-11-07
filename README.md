# loom

**Work coordination for coding agents.** You write the work as a ticket. One
agent gets one isolated copy of the repo. Every turn ends with one structured
line. A watchdog holds the clock. Only you push.

Version **0.6.0** · MIT · ~2,700 lines of bash and rules · no server, no
database, no model of its own · [site](https://redknight13.github.io/loom/)

---

## What this is

You have a coding agent. You want it to do real work in your repo without
handing it the keys: no pushes, no merges, no ninety minutes of silence you
cannot explain afterwards.

Loom is the thin layer between you and the agent that makes that safe and
boring.

1. **You write the work down once.** A ticket is a GitHub issue with a fixed
   scope, an explicit out-of-scope, and a "done means" check. It cannot drift
   mid-run, because the worker is not allowed to widen it.
2. **Loom gives one agent one workspace.** A private clone with no remote, or an
   Orca-supervised worktree. It records who started, when, and where.
3. **The agent reports in one line.** Not prose. `ready`, `blocked`, `failed` or
   `waiting`, plus one fact. If it exits without one, that is a failure, not a
   mystery.
4. **If it goes quiet, it dies.** The watchdog matches the PID *and* its process
   start time, kills the whole process group, records `failed / watchdog_kill`
   once, and leaves the ticket clean for one new attempt.
5. **"Ready" is a claim, not a result.** Loom re-runs your checks itself, in a
   fresh clone the worker never touched — on your build host if you name one.
   Exit 126 means "could not run", never "tests failed".
6. **Only you finish.** Loom fetches the branch into your checkout and stops.
   You review, push, open the PR, merge. Every commit is yours.

Everything else is deliberately absent: no agent framework, no scheduler, no
memory store, no model router, no multi-tenant service. Loom is the part that
makes delegation *bounded*; the agent, the harness and the machine stay
replaceable.

### A ticket, concretely

```text
Issue #42: "Add --json to the CLI"

Mandate (written before any code):
  scope:      cmd/main.go, cmd/main_test.go
  out:        everything else
  done means: make check exits 0

Loom:      dispatch → private clone, branch add-json, no remote
Agent:     edits two files, appends REPORT.md:
             state: ready — added --json and a golden test
Loom:      commits that work as one commit on add-json
Watchdog:  fires only if the turn goes past limit_min
You:       loom verify add-json.1 → fresh clone, make check, exit 0
           loom collect add-json.1 → branch in your checkout
           git push, open PR, merge            ← the only manual step
```

### What it is not

- **Not an orchestrator service.** There is no daemon and nothing to deploy.
- **Not an agent.** It does not call a model; it bounds one.
- **Not a CI system.** `verify` runs your existing checks; it does not replace them.
- **Not a replacement for review.** It makes review the only human step left.

Loom's domain model is adapted from DeepSeek's `dsh-superagent` prototype (MIT),
stripped of its service layer. The lineage is MIT; so is this repository.

---

## What is supported

Every row below is exercised by `ops/selftest.sh` and protected by a mutant in
`ops/mutate.sh` (50 mutants, 0 survivors).

| Area | Supported |
| --- | --- |
| **One call** | `ops/loom` — one command, one JSON object on stdout, exit 0 iff `ok`. The same call for any harness. |
| **Tickets** | Rendered from `templates/MANDATE.md`; the renderer proves the parser accepts its own output. Repeatable `--label`; `loom-ready` defaulted when the repo has it. |
| **Eval record** | `accept` opens a Ticket; `ignore` records the decision without one. |
| **Executors** | `local` (private clone, no remote) and `orca` (supervised worker; [Orca](https://github.com/stablyai/orca) 1.4.246+, MIT). `auto` detects Orca. |
| **Placement** | Consumer `compute` hosts; `start` uses the first one Orca reports connected, and refuses when none is. Never a silent local fallback. |
| **Checks** | `verify` runs the consumer's checks in a fresh clone, locally or over SSH on the compute host. Unreachable host or failed setup is *could not run*. |
| **Reports** | `ready | blocked | failed | waiting` in `REPORT.md`; harvest folds the newest line into the record and commits the work. |
| **Watchdog** | PID + process-start identity, process-group kill, per-consumer limit, `failed / watchdog_kill` exactly once. Orca workers are surfaced `stale`, never signalled. |
| **Capacity** | `loom capacity` reads Orca's connected hosts and suggests a worker count; `workers` caps open assignments and `dispatch` refuses past it. |
| **Attention** | `status` prints only what a person must act on. `ack` settles a handled result and keeps history. |
| **Orca map** | `show read abandon keep-open list request peek inbox send ask reply gate task run reference worktree repo base-ref automation`. Harvest asks `worker-show` first; `check` only with `--peek`. |

**Not supported, on purpose:** push/PR/merge automation, a scheduler, a daemon,
per-worker credentials, a non-GitHub ticket source, Orca task-DAG starts, and
any behaviour inferred from prose.

---

## Recommended install

One path. It is the one the project itself uses and tests.

```bash
# 1. Dependencies (macOS shown; on Linux use your package manager)
brew install jq gh shellcheck
gh auth login
# Optional supervised backend (MIT): https://github.com/stablyai/orca  (1.4.246+)

# 2. Clone once, outside any other repo
git clone https://github.com/RedKnight13/loom.git ~/loom

# 3. Put the single entry point on PATH
echo 'export PATH="$HOME/loom/ops:$PATH"' >> ~/.zshrc   # or ~/.bashrc
exec $SHELL -l
loom version                                            # {"v":"0.6.0",...}

# 4. Prove the machine before trusting it
cd ~/loom
bash ops/selftest.sh                                    # exit 0
shellcheck -x ops/*.sh ops/loom                         # exit 0
bash ops/mutate.sh                                      # exit 0, SURVIVED=0
```

That is the whole install. Nothing runs in the background, nothing is written
outside `$LOOM_STATE` (default `~/.loom`).

Prefer to let an agent do it? Paste the [bootstrap prompt](docs/bootstrap.md)
into Claude Code or Codex; it installs, proves, and stops before touching your
repository.

**Other options:** call `ops/loom` by path instead of putting `ops/` on PATH;
run from any checkout with `LOOM_STATE=/path/to/state`; skip Orca if you only
want the local launcher. Nothing else changes.

## Recommended setup

For a first real use, this is the configuration and the loop that will not
surprise you.

```bash
cp consumers/example.toml consumers/myrepo.toml
```

```toml
# consumers/myrepo.toml
repo      = "you/your-repo"
checks    = "make check"                  # the command you already trust
worktrees = "~/work/your-repo-workdirs"
limit_min = 45                            # generous enough for one honest turn
executor  = "auto"                        # Orca if ready, else local
workers   = 3                             # max open assignments; omit = unlimited
laws = [
  "Workers never push; only the conductor pushes, reviews and merges.",
  "Captured exit codes only; a check that was not run is reported as not run.",
]
```

Then, for every ticket:

```bash
# 0. One ticket, one scope, written down.
loom accept --consumer consumers/myrepo.toml --short add-json \
  --title "Add --json" --scope "cmd/main.go, cmd/main_test.go" \
  --out "everything else" --done "make check exits 0"

# 1. Dispatch it. Prints the workdir and the assignment id.
LOOM_REPO=~/src/your-repo loom dispatch --consumer consumers/myrepo.toml --issue 42

# 2. Record what "already true" means, then start one worker.
loom verify add-json.1 --baseline &
loom start add-json.1          # Orca; or: loom launch add-json.1 -- codex exec ...

# 3. Hold the clock. Silent while healthy.
loom watch --until add-json.1

# 4. On ready: re-check in a fresh clone, bring the branch home.
loom verify add-json.1
loom collect add-json.1

# 5. Review, push, PR, merge — yours. Then settle it out of status.
loom ack add-json.1 "merged as #43"
```

**Recommendations that come from running it, not from taste:**

- **Write "done means" before the code.** A check you cannot run is a ticket
  you cannot close.
- **One ticket, one attempt.** If it comes back `blocked`, answer the question
  and re-dispatch; do not edit the Mandate (it is immutable — open a new ticket
  for wider scope).
- **Run `verify --baseline` before or beside the worker.** Without it, "no new
  failures" is an opinion.
- **Keep `limit_min` at 45 for real work, less for drills.** The watchdog is the
  only thing that can end a silent worker.
- **Declare `compute` when checks are slow.** Checks are the expensive part;
  moving them to a build host is the single biggest quality-of-life change.
- **Set `workers` to what your hosts can carry.** `loom capacity` suggests one per connected Orca host; dispatch refuses past the cap instead of piling up.
- **Use Orca when you want supervision and placement.** Orca is MIT
  (<https://github.com/stablyai/orca>), supported from **1.4.246**; its app must
  be running. Use the local executor when you want the smallest setup. The call
  above does not change.
- **Start with a docs or single-test ticket.** Let the first real ticket be one
  whose failure teaches you the system cheaply.

A pre-flight checklist and a troubleshooting table live in
[docs/setup.md](docs/setup.md).

---

## The call

```bash
$ loom status
{"v":"0.6.0","cmd":"status","ok":true,"state":"waiting","fact":"nothing waits for a person","id":null,"ticket":null,"items":[],"actions":[]}
```

Every invocation prints exactly one JSON object. Diagnostics go to stderr. Exit
`0` iff `ok` is true; `2` on a usage error (the object is still printed).

| Key | Meaning |
| --- | --- |
| `v` | Protocol version, from `VERSION` |
| `cmd` | The verb |
| `ok` | The command did what it claims |
| `state` | `accepted ignored dispatched launched started harvested stopped released verified collected acked waiting ready blocked failed stale release complete` |
| `fact` | One line, safe for a log |
| `id`, `ticket` | Assignment id and issue number when they apply |
| `items` | Status rows: `{id, state, fact}` |
| `actions` | Watchdog lines emitted by `watch` |

Harnesses read that object and nothing else. The scripts under `ops/` are the
mechanism; `ops/loom` is the contract.

## Consumer config

```toml
repo      = "owner/name"            # where Tickets (issues) live
checks    = "make check"            # verify.sh runs this in a fresh clone
worktrees = "~/work/name-dirs"      # local executor workspace root
laws      = ["…", "…"]              # copied verbatim into every WORK.md
limit_min = 45                      # optional watchdog limit (default 30)

executor  = "auto"                  # auto | local | orca
compute   = ["build1", "build2"]    # optional SSH hosts, first reachable wins
compute_setup = ". ~/.venvs/checks/bin/activate"   # optional, runs on the host
compute_selector = "--host ssh:<id>"               # optional exact Orca selector
workers   = 3                       # optional: max open assignments; omit = unlimited
model     = "…"                     # optional: worker-start --model
effort    = "high"                  # optional: requires model
start_timeout_ms = 300000           # optional: worker-start --timeout-ms
```

Unknown or duplicate keys are rejected. Nothing in the config is evaluated at
parse time. Private consumer configs are gitignored; `consumers/example.toml`
and `consumers/loom.toml` are the tracked ones.

## Execution models

| Mode | Workspace | Who supervises | Why |
| --- | --- | --- | --- |
| `local` | private clone, no remote, own `.git` | `launch.sh` + watchdog | a sandboxed worker can commit; no remote means it cannot push |
| `orca` | Orca-created worktree, optionally on a compute host | [Orca](https://github.com/stablyai/orca) 1.4.246+ (MIT) | supervised terminals, placement, release, mail |

`compute` applies to both: checks run there over SSH, and Orca workers are placed
there. A declared but unreachable host refuses. Loom never quietly uses the
conductor's laptop.

## Guarantees

- **One live assignment per ticket.** A second dispatch refuses.
- **Reports are facts, not prose.** Four states; a worker that exits without one
  is recorded `failed / worker_exit_no_report`.
- **A recycled PID is never signalled.** Identity is PID plus process start time.
- **Corrupt state is not healthy.** Every record is validated on read; a bad one
  stops the scripts.
- **The conductor re-runs the checks.** A worker's `ready` is a claim. Verified in
  a fresh clone; exit 126/127/255 is *could not run*.
- **Workers never push.** The local clone has no remote; Loom never runs `git push`.
- **A healthy loom is silent.** `status` speaks only when a person must act.
- **Every mechanism has a mutant.** A fix without a selftest case and a mutant is
  not landed.

## Limits

- The conductor is a single point of failure. State is plain JSON in
  `$LOOM_STATE` (default `~/.loom`), so another session can resume it, but
  dispatch judgement and merges need a session awake.
- `watch` stops when the conductor stops. There is no scheduler yet.
- Tested on macOS (bash 3.2) and Linux; the selftest is offline and hermetic.
- Tickets are GitHub issues (`gh` is a dependency). A non-GitHub source is a
  later seam, not a feature.
- `VERSION` is `0.x`: the call contract may still change; breaking changes get a
  new spec.

## Documentation

- [PROTOCOL.md](PROTOCOL.md) — the law: roles, domain, report states
- [templates/MANDATE.md](templates/MANDATE.md) — the Mandate block
- [ops/README.md](ops/README.md) — every script and its guarantee
- [ROADMAP.md](ROADMAP.md) — layers and the certification bar
- [docs/setup.md](docs/setup.md) — install, consumer config, Orca, compute host
- [docs/support.md](docs/support.md) — support matrix and known gaps
- [docs/bootstrap.md](docs/bootstrap.md) — a copy-paste setup prompt for an agent
- `docs/superpowers/specs/` — the 0.5.0 call contract and the 0.6.0 additions
- [HANDOVER.md](HANDOVER.md) — current state, for whoever picks this up

## Contributing

Small, evidenced changes. A fix lands with a selftest case *and* a mutant, and
`bash ops/selftest.sh`, `shellcheck -x ops/*.sh ops/loom`, and
`bash ops/mutate.sh` must all exit 0. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE). The domain model is adapted from DeepSeek's
`dsh-superagent` prototype (MIT); this repository keeps the law and drops the
service layer.
