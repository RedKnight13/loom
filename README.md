# loom

**Work coordination for agent executors.** A request becomes a Ticket. The
Ticket carries an immutable Mandate. One worker gets one isolated workspace and
ends every turn with a structured report. A watchdog holds the clock. Only the
conductor pushes, reviews and merges.

Loom is not an agent and not an orchestrator service. It is a small protocol and
a set of bash tools that make delegation bounded, observable and resumable —
with as little human attention as possible.

```text
request ──► Ticket (issue + Mandate) ──► Assignment (one worker, one workspace)
                                              │
                                              ▼
                            REPORT.md: ready | blocked | failed | waiting
                                              │
                     watchdog ──► verify (fresh clone) ──► collect ──► PR
                                              │
                                       status: only what needs a person
```

Version **0.6.0**. MIT lineage, but see [License](#license) — a licence file is
not yet in the tree.

---

## What is supported

Everything below is exercised by `ops/selftest.sh` and protected by a mutant in
`ops/mutate.sh` (50 mutants, 0 survivors).

| Area | Supported |
| --- | --- |
| **One call** | `ops/loom` — one command, one JSON object on stdout, exit 0 iff `ok`. The same call for Claude, Codex or any scriptable worker. |
| **Tickets** | Rendered from `templates/MANDATE.md` by `ticket.sh`; the renderer proves the parser accepts its own output. Repeatable `--label`, `loom-ready` defaulted when the repo has it. |
| **Eval record** | `accept` opens a Ticket; `ignore` records the decision without one. |
| **Executors** | `local` (private clone, no remote) and `orca` (Orca supervises the worker). `auto` detects Orca. |
| **Placement** | Consumer `compute` hosts; `start` uses the first one Orca reports connected and refuses when none is. Never a silent local fallback. |
| **Checks** | `verify` runs the consumer's checks in a fresh clone, locally or over SSH on the compute host. Unreachable host or failed setup is *could not run*, never a test failure. |
| **Reports** | `ready | blocked | failed | waiting`, written to `REPORT.md`; harvest folds the newest line into the assignment record and commits the work. |
| **Watchdog** | PID + process-start identity, process-group kill, per-consumer limit, `failed / watchdog_kill` exactly once. Orca workers are surfaced `stale`, never signalled. |
| **Attention** | `status` prints only `ready`, `blocked`, `failed`, `stale` and unreleased workspaces. `ack` settles a handled result while keeping history. |
| **Orca map** | `show read abandon keep-open list request peek inbox send ask reply gate task run reference worktree repo base-ref automation`. Harvest asks `worker-show` first; `check` only ever with `--peek`. |

### Not supported (on purpose)

- Loom does not start agents itself. A harness or Orca does.
- Loom never pushes, opens a PR, or merges. `collect` brings the branch home and stops.
- No daemon and no scheduler. `watch` is the conductor's clock while a session is awake.
- No identity layer, no per-worker credentials, no multi-tenant server.
- Orca task-DAG starts (`worker-start --task --deps`) are mapped but not wired.
- Automations are a pass-through verb; Loom schedules nothing.

---

## Requirements

- macOS or Linux, **bash 3.2+**
- `git`, [`jq`](https://jqlang.github.io/jq/) 1.6+, [`gh`](https://cli.github.com/) (authenticated)
- `shellcheck` for linting
- Optional: the [Orca](https://github.com/) CLI for supervised workers (the
  `orca` executor) and a reachable SSH host for `compute`

No service, daemon, database or language runtime. State is JSON on disk.

---

## Install

```bash
git clone https://github.com/RedKnight13/loom.git
cd loom
bash ops/selftest.sh          # offline proof: throwaway repo, stubbed gh/orca/ssh
shellcheck -x ops/*.sh ops/loom
```

Put `ops/` on your path, or call it by path. The only entry point a harness
needs is `ops/loom`.

## Quickstart

```bash
# 1. Register a consumer repo (where tickets live).
cat > consumers/example.toml <<'EOF'
repo      = "you/your-repo"
checks    = "make check"
worktrees = "~/work/your-repo-workdirs"
limit_min = 45
laws      = ["Workers never push; only the conductor pushes, reviews and merges."]
EOF

# 2. Write a Ticket (the Mandate is immutable; Done means is written first).
bash ops/loom accept --consumer consumers/example.toml \
  --short add-flag --title "Add --json" \
  --scope "cmd/main.go: add a --json flag" --out "everything else" \
  --done "make check exits 0"

# 3. Dispatch it.
LOOM_REPO=~/src/your-repo bash ops/loom dispatch \
  --consumer consumers/example.toml --issue 42

# 4. Start a worker. Local executor:
bash ops/loom launch add-flag.1 -- codex exec -s workspace-write \
  "You are a loom worker. Read WORK.md."
# Orca executor:
bash ops/loom start add-flag.1

# 5. Hold the clock until it settles.
bash ops/loom watch --until add-flag.1

# 6. Re-check in a fresh clone, bring the branch home.
bash ops/loom verify add-flag.1 --baseline   # what was already true
bash ops/loom verify add-flag.1
bash ops/loom collect add-flag.1

# 7. Push, open the PR, merge — conductor only. Then settle it.
bash ops/loom ack add-flag.1 "merged as #43"
```

Full setup, including Orca and a compute host: [docs/setup.md](docs/setup.md).

---

## The call

```bash
$ bash ops/loom status
{"v":"0.6.0","cmd":"status","ok":true,"state":"waiting","fact":"nothing waits for a person","id":null,"ticket":null,"items":[],"actions":[]}
```

Every invocation prints exactly one JSON object. Diagnostics go to stderr.
Exit `0` iff `ok` is true; `2` on a usage error (the object is still printed).

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
compute   = ["build1", "build2"]      # optional SSH hosts, first reachable wins
compute_setup = ". ~/.venvs/checks/bin/activate"   # optional, runs on the host
compute_selector = "--host ssh:<id>"               # optional exact Orca selector
model     = "…"                     # optional: worker-start --model
effort    = "high"                  # optional: requires model
start_timeout_ms = 300000           # optional: worker-start --timeout-ms
```

Unknown or duplicate keys are rejected. Nothing in the config is evaluated at
parse time.

## Execution models

| Mode | Workspace | Who supervises | Why |
| --- | --- | --- | --- |
| `local` | private clone, no remote, own `.git` | `launch.sh` + watchdog | a sandboxed worker can commit; no remote means it cannot push |
| `orca` | Orca-created worktree, optionally on a compute host | Orca | supervised terminals, placement, release, mail |

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
- Tickets are GitHub issues (`gh` is a dependency). A non-GitHub Source is a
  later seam, not a feature.

## Documentation

- [PROTOCOL.md](PROTOCOL.md) — the law: roles, domain, report states
- [templates/MANDATE.md](templates/MANDATE.md) — the Mandate block
- [ops/README.md](ops/README.md) — every script and its guarantee
- [ROADMAP.md](ROADMAP.md) — layers and the certification bar
- [docs/setup.md](docs/setup.md) — install, consumer config, Orca, compute host
- [docs/support.md](docs/support.md) — support matrix and known gaps
- `docs/superpowers/specs/` — the 0.5.0 call contract and the 0.6.0 additions
- [HANDOVER.md](HANDOVER.md) — current state, for whoever picks this up

## Contributing

Small, evidenced changes. A fix lands with a selftest case *and* a mutant, and
`bash ops/selftest.sh`, `shellcheck -x ops/*.sh ops/loom`, and
`bash ops/mutate.sh` must all exit 0. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

The domain model is adapted from DeepSeek's `dsh-superagent` prototype (MIT).
This repository does not yet carry a `LICENSE` file, so no licence is granted
until one is added. MIT is the intended choice; it is the owner's decision, and
the project's own drill D3 is exactly that question.
