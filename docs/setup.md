# Setup

Loom is plain bash plus `git`, `jq`, `gh`, and optionally [Orca](https://github.com/stablyai/orca)
(MIT) and an SSH host.
There is nothing to build and no service to run.

For agent-assisted setup, paste [bootstrap.txt](bootstrap.txt). It discovers
existing choices before asking and preserves user files. See
[the session-entry checklist](../templates/LOOM_SESSION.md) for continuity.

## 1. Requirements

| Tool | Version | Needed for |
| --- | --- | --- |
| bash | 3.2+ | everything |
| git | any recent | dispatch, harvest, collect, verify |
| jq | 1.6+ | every record and config read |
| gh | any recent, authenticated | tickets, issues, labels |
| shellcheck | any recent | `shellcheck -x ops/*.sh ops/loom` |
| [Orca](https://github.com/stablyai/orca) | 1.4.246+ (MIT), optional | the `orca` executor, placement, worker mail; app must be running |
| ssh | optional | `compute` host for checks and placement |

Check:

```bash
bash --version | head -1
jq --version
gh auth status
```

## 2. Get the tools

```bash
git clone https://github.com/RedKnight13/loom.git
cd loom
bash ops/selftest.sh                          # offline, hermetic, ~1 min
shellcheck -x ops/*.sh ops/loom
```

`ops/selftest.sh` needs no network, signals no real worker, and uses stubs for
`gh`, `orca`, `ssh` and `ps`. If it fails, stop dependent setup work and retain the captured exit code.
Capture the selftest and lint exits separately; both must be 0.
These offline gates do not prove live consumer operation. `ops/mutate.sh` is
the long macOS contributor/CI gate, not a setup requirement.

## 3. State

Loom keeps one JSON record per assignment in `$LOOM_STATE` (default `~/.loom`).
It is conductor-only; workers never write it.

```bash
export LOOM_STATE="$HOME/.loom"     # optional; this is the default
```

Records are validated on every read. A corrupt record stops the scripts rather
than reading as healthy.

| Variable | Meaning |
| --- | --- |
| `LOOM_STATE` | state directory (default `~/.loom`) |
| `LOOM_REPO` | consumer checkout for `dispatch`/`collect` (default: cwd) |
| `LOOM_LOCK_WAIT` | seconds to wait for a live lock (default 10) |
| `LOOM_ORCA` | Orca binary (tests stub it) |
| `LOOM_SSH` | ssh binary used for compute hosts (tests stub it) |
| `LOOM_ALLOW_LOCAL` | `1` lets `launch` start a local worker while Orca is ready |
| `LOOM_CALLER_UMASK` | umask handed to workers and checks |

## 4. Register a consumer

A consumer is any repo that owns tickets. One TOML file per consumer in
`consumers/`, or anywhere you like.

```toml
repo      = "you/your-repo"          # where issues live
checks    = "make check"             # run by verify.sh in a fresh clone
worktrees = "~/work/your-workdirs"   # local executor workspace root
laws      = [                        # copied verbatim into every WORK.md
  "Workers never push; only the conductor pushes, reviews and merges.",
  "Captured exit codes only; a check that was not run is reported as not run.",
]
limit_min = 45                       # optional; default 30
executor  = "auto"                   # auto | local | orca
workers   = 3                        # optional: max open assignments; omit = unlimited
```

A tracked config must be committed before dispatch; the record pins that
commit. Ignored, untracked private configs in Loom’s `consumers/` do not need
a commit. Preserve existing configuration; bootstrap does not commit it.

### Worker cap

`workers` is the maximum number of open assignments for this consumer. `dispatch`
counts records that are live or dispatched-but-unsettled and refuses past the
cap with the ids that hold the slots. Omit the key for no cap.

`loom capacity` reports what Orca can carry right now — runtime ready, connected
hosts — and suggests a number (one per connected host, minimum one). The
bootstrap prompt reuses an existing cap or offers this suggestion when the
choice is unresolved. A capacity suggestion is not authorization to launch.

Declaring `executor = "local"` selects local dispatch. If Orca is installed
and ready, `launch` still requires `LOOM_ALLOW_LOCAL=1`; the config alone
does not bypass that guard.

## 5. Local executor

```bash
bash ops/loom dispatch --consumer consumers/example.toml --issue 42
# → {"id":"add-flag.1","fact":"/home/you/work/your-workdirs/add-flag.1", ...}

bash ops/loom launch add-flag.1 -- bash -c 'my-agent "Read WORK.md"'
bash ops/loom watch --until add-flag.1
```

`dispatch` creates a **private clone** with its own `.git` and **no remote**.
The worker reads `WORK.md`, leaves files in the working tree, and appends one
line to `REPORT.md`:

```
state: ready — added the flag and a test
```

It never runs git. Loom commits what it left, on branch `<short>`, when the turn
is harvested. `WORK.md`, `REPORT.md` and `.loom/` are excluded from that commit;
`.loom/` is copied to `$LOOM_STATE/<id>.evidence/` instead.

## 6. Orca executor

Orca (<https://github.com/stablyai/orca>, MIT, **1.4.246+**) supervises
workers and, when a `compute` host is declared, places them there. Its desktop
app must be running: `orca status` reports whether the runtime is ready.

```bash
orca --version                    # must be 1.4.246 or newer
orca status                       # runtime reachable and ready
orca repo add --path ~/src/your-repo
orca host list                    # connect the target in the Orca app first

executor = "orca"                 # in the consumer config
compute  = ["build1", "build2"]   # optional; first connected Orca host wins

bash ops/loom dispatch --consumer consumers/example.toml --issue 42
bash ops/loom start add-flag.1                    # first connected host; refuses if none
# Orca wakes the conductor when the worker is done:
bash ops/loom harvest add-flag.1
bash ops/loom verify add-flag.1
bash ops/loom collect add-flag.1
bash ops/loom release add-flag.1                  # after collect
```

Rules Loom keeps for Orca:

- Orca creates the workspace. Loom adopts it.
- Loom never signals an Orca worker. A silent one is shown as `stale`; you decide.
- `stop` records a stop only when Orca confirms one; `stop_unknown` changes nothing.
- `abandon` fences and records `failed / owner_fenced`; it never claims a stop.
- A failed `worker-start` is recorded and never retried.
- `check` is only ever called with `--peek`; `inbox` is the other read path.

## 7. Compute host

`compute` moves the checks (and Orca workers) off the conductor's machine.

```toml
compute       = ["build1", "build2"]                  # first reachable wins
compute_setup = ". ~/.venvs/checks/bin/activate"    # run before each check
```

Requirements on the host:

- SSH key auth works non-interactively (`ssh -o BatchMode=yes host true`)
- `git` and the runtime your `checks` need
- whatever `compute_setup` expects (a venv, a toolchain)

`verify` ships the exact commit as a git bundle over SSH, builds a fresh tree in
`$HOME/.loom-remote/<id>`, runs setup then checks, streams the log back, records
the host, and deletes its folder. A host that is unreachable refuses; Loom never
falls back to the conductor's machine. A failing `compute_setup` is reported as
**could not run** (exit 126), never as a test failure.

## 8. First ticket checklist

- [ ] `bash ops/selftest.sh` exits 0
- [ ] `shellcheck -x ops/*.sh ops/loom` exits 0
- [ ] any tracked consumer config is committed by its authorized conductor
- [ ] `gh auth status` shows the account that owns the repo
- [ ] the checkout's git identity is the one you want in commits
  (Loom copies `user.name`/`user.email` into a local clone)
- [ ] if `compute` is declared: `bash ops/loom compute --consumer FILE` names a host
- [ ] if `executor = "orca"`: `orca status` is ready and the host is connected

### Calibration and session entry (schema 1)

Runtime integration is in progress for this documentation revision; runtime
calibration tests are **not run** here. Confirm command availability in the
installed checkout first. If absent, report calibration not run and stop
dependent delegation until an approved implementation is available.

Install the [session bridge](../templates/LOOM_SESSION.md) only after inspecting
the agent's project loading convention and existing content. Schema 1 requires
literal `loom-calibration:v1` in root `AGENTS.md` or `CLAUDE.md` (regular,
readable, non-symlink); both are fingerprinted if present. Preserve existing
content and user customizations; reuse one marked section. Unsupported entry
conventions remain unwired. No new consumer TOML keys are required.

With `LOOM_REPO` bound to the intended consumer checkout (otherwise cwd), use
the trusted Loom installation and the resolved consumer `FILE`:

```sh
loom calibrate --consumer FILE
loom calibrate --consumer FILE --check
```

For an existing setup, run `--check` first and reuse a current baseline. Review
missing evidence or drift before recording; rerunning setup must not silently
replace the baseline.

Recording runs a fixed isolated offline report/envelope drill and records only
complete success. Comparison writes nothing, acquires no locks and reruns no
drill. Neither invokes consumer checks, `compute_setup`, authentication probes,
installers or real workers. The earlier `gh`/compute setup checks are separate,
authorized observations. Compute aliases in calibration must match
`^[A-Za-z0-9][A-Za-z0-9._-]*$`; user/port syntax and shell fragments are rejected.

Capture exits and inspect the complete JSON envelope. Exit 0 requires `ok:true`
and `state:ready`; schema-1 `items[0]` reports readiness, fingerprint, stages,
sorted drift field names and `acceptance:not_run`. Exit 1 blocks dependent
work; exit 2 reports usage errors. A passed drill in check mode is recorded
proof, not a new execution. `ready` never means project acceptance.

Private sanitized records live at
`${LOOM_STATE:-$HOME/.loom}/calibration/<key>.json`. Missing baseline blocks;
corrupt/unknown schema, unsafe state or symlinks fail closed. Do not delete
locks or change permissions as an automatic repair. Failed recording preserves
the prior baseline. Keep separately redacted setup evidence under `.loom/`
only where private; do not publish paths, identities, hosts or credentials.

Every new session and immediately before delegation, invoke `--check`, including
after context loss, tool reconnect or dependency changes. Read the bridge
explicitly if loading is uncertain and confirm it was read. Review drift before
explicit recording; comparison never accepts changes. Fingerprints cover Loom
source/version, consumer and bridge bytes, checkout identity, tools and executor.
A new checkout/config location needs a new baseline; branch/HEAD changes alone
do not imply bootstrap drift or project acceptance.

Tool-enabled sessions with shell execution follow the same protocol as CLI
agents. Without execution, say **unwired; calibration not run** and resume in a
capable session. A shell route does not grant delegation permission. Marker
presence proves structure only; confirm actual loading in a fresh session before
claiming continuity. Schema 1 relies on the agent: existing dispatch/start/launch
commands are not automatically gated, and a comparison-to-delegation gap remains.
No background monitor, persistent model memory or unattended repair is installed.

## 9. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `consumer config has uncommitted changes` | config under git, edited | commit it; the record pins the config commit |
| `ticket already has a live assignment` | one-ticket-one-worker rule | wait, `stop`, or dispatch a new attempt after it settles |
| `executor orca required but ... not ready` | Orca runtime down | start Orca; Loom never silently falls back |
| `no compute host is connected in Orca` | none of `compute` is connected | connect one in Orca; Loom does not connect hosts |
| `no compute host reachable ... refusing` | SSH/setup | fix SSH or the host; do not expect a local run |
| `checks could not run (exit 126/127/255)` | setup, ssh, missing runtime | read `$LOOM_STATE/<id>.checks-<kind>.log`; it is not a test failure |
| `worker_exit_no_report` | worker exited without a `state:` line | read the log, re-dispatch with clearer instructions |
| `watchdog_kill` | no report within `limit_min` | autopsy the workdir; the ticket stays open |
| `orca could not confirm the stop` | `stop_unknown` | inspect with `worker-show`; `abandon` is fencing, not a stop |
| `agent_readiness` timeout on a remote host | agent startup slower than Orca's wait | raise `start_timeout_ms` (for example `300000`) |
| `git staging exits 128 ... .git is read-only` | old executor sandbox | workers never run git; harvest commits. Re-dispatch on 0.6.0 |

## 10. Uninstall

Inspect active assignments before removing their state. Remove only the Loom
checkout/state and project bridge you intend to uninstall; preserve surrounding
project instructions and user files. Bootstrap may have installed authorized
prerequisites or a project checklist, so review its change report separately.
Loom does not install a persistent background service.
