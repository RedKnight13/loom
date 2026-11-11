# Loom

**Give coding agents a defined task, an isolated workspace, and a checkable result.**

Loom records the scope before work starts, tracks the worker, and verifies its
output against your project's checks. You review the result and decide what gets
pushed or merged.

Version **0.6.0** · MIT · Bash-based · no model or resident service of its own

[Overview](https://redknight13.github.io/loom/) ·
[Setup](https://redknight13.github.io/loom/copy.html) ·
[Coordination patterns](https://redknight13.github.io/loom/patterns.html) ·
[Protocol](https://redknight13.github.io/loom/protocol.html) ·
[Support and known gaps](https://redknight13.github.io/loom/support.html)

## The work loop

1. **Define the task.** A GitHub issue holds a mandate: scope, exclusions, and
   the checks that mean done.
2. **Dispatch a worker.** Loom reserves the ticket and records its workspace,
   executor, and attempt. A second open assignment for the same ticket refuses.
3. **Keep evidence.** The worker ends its turn with `ready`, `blocked`, `failed`,
   or `waiting` in `REPORT.md`, plus one fact. A ready report does not prove the
   checks passed.
4. **Verify the result.** Loom runs your checks in a fresh clone, on a declared
   compute host when configured. A check that could not run is reported separately
   from a failing check.
5. **Review and merge.** Collect the branch, inspect the diff and evidence, then
   push and merge through your normal review process. Loom does not push or merge.

```text
Ticket: Add --json to the CLI
  scope: cmd/main.go, cmd/main_test.go
  out:   everything else
  done:  make check exits 0

Worker: state: ready — added --json and a golden test
Loom:   verify in a fresh clone → capture exit → collect branch
You:    review → push → PR → merge
```

A mandate is an instruction the agent must follow. Workspace separation and
captured evidence help you assess its work; they are not a security sandbox or
proof that an agent obeyed every instruction.

## Start here

Copy the [bootstrap prompt](https://redknight13.github.io/loom/copy.html) into an
agent session that can work in your repository. It checks existing choices,
updates a clean Loom installation, and configures only within your authorization.
It stops for unresolved decisions. A chat without shell execution cannot verify
installation or run workers.

For a manual installation, use Bash 3.2+, Git, jq, GitHub CLI and ShellCheck:

```bash
# macOS; on Linux use your package manager for jq, gh and shellcheck.
brew install jq gh shellcheck
gh auth login

git clone https://github.com/RedKnight13/loom.git ~/loom
cd ~/loom
bash ops/loom version
bash ops/selftest.sh
shellcheck -x ops/*.sh ops/loom
```

Call `~/loom/ops/loom` by path, or add `~/loom/ops` to your `PATH`.
The longer mutation suite is a **contributor gate**, not a routine installation
step. Setup writes configuration and workspace files within your authorization;
private runtime records default to `~/.loom` (`LOOM_STATE` overrides it).

Follow [the setup guide](docs/setup.md) to create your consumer config and install
the [session checklist](templates/LOOM_SESSION.md) in the project's supported
instruction file. Calibration records a fixed offline drill and checks for wiring
drift at session entry and before delegation:

```bash
export LOOM_REPO=~/src/your-repo
loom calibrate --consumer /path/to/consumer.toml
loom calibrate --consumer /path/to/consumer.toml --check
```

Read the complete response. Ready calibration means the recorded wiring and
offline drill match; **live project acceptance remains `not_run`**. Review drift
before explicitly recording a new baseline. The session agent must invoke these
checks: there is no background recalibration or automatic launch guard.

## Choose an execution path

| Path | What it provides | Requirements and limits |
| --- | --- | --- |
| Standard `local` | Private clone without a remote, local process-group supervision, report harvesting and verification | Works without Orca. The worker command runs on the launching host. macOS and Linux. |
| Standard `orca` | Orca-managed workspace, worker supervision, placement and Orca mail | Requires a compatible running [Orca](https://github.com/stablyai/orca) runtime; documented baseline is 1.4.246+. |
| Opt-in native workflow | Loom-owned execution, coordination and mail APIs over provisioned process or SSH contexts | Linux execution runtime; explicit authority, registries and host provisioning. Separate acceptance requirements; not the default bootstrap path. |

`executor = "auto"` chooses ready Orca at dispatch, otherwise the standard local
launcher. Set `local` or `orca` explicitly when that choice must not change.
Required Orca refuses an unavailable runtime. An existing local assignment stays
local even if Orca appears later.

In the standard workflow, `compute` places **verification** on a named SSH host
and **Orca workers** on a connected host. It does not remotely place a standard
local launch. A declared but unavailable verification host refuses; there is no
silent fallback to the conductor's machine.

The [native workflow guide](docs/native-workflow.md) documents provisioning and
remaining acceptance gaps. Its mail requires startup or cooperative boundaries
and explicit transport pumping. It does not push a new turn into every idle
agent. Arbitrary orchestrators are not automatically supported; the shipped Orca
adapter and native contracts are distinct integration paths.

## A standard ticket

Start from [consumers/example.toml](consumers/example.toml), set your repository
and existing checks command, and choose the executor and worker cap. Private
consumer files are gitignored; do not put credentials in them.

```bash
loom accept --consumer /path/to/consumer.toml --short add-json \
  --title "Add --json" --scope "cmd/main.go, cmd/main_test.go" \
  --out "everything else" --done "make check exits 0"

# Use the issue number returned above.
LOOM_REPO=~/src/your-repo loom dispatch --consumer /path/to/consumer.toml --issue 42
loom verify add-json.1 --baseline

# For an Orca assignment:
loom start add-json.1
# For a local assignment instead, supply your authorized worker command:
# loom launch add-json.1 -- codex exec "Read WORK.md and follow its mandate."

loom watch --until add-json.1
# Orca: harvest the completed turn before verification.
loom harvest add-json.1
loom verify add-json.1
loom collect add-json.1

# After review, push and merge through your usual Git workflow.
loom ack add-json.1 "merged as #43"
```

The local launcher harvests after confirmed group settlement; skip the explicit
Orca harvest command for that path. Commands return one JSON object with `ok`,
`state`, `fact`, and captured evidence in `items`. Check the exit code and response
before continuing. See [operations](ops/README.md) for the full lifecycle.

## Reliability and limits

- **Worker exit is not enough.** Local harvest requires positive process-group
  settlement. A watchdog kill remains pending until settlement is observed;
  uncertain process identity cannot justify collection or a replacement worker.
- **Orca retains supervision.** Loom surfaces stale Orca work for an owner
  decision; it does not signal those workers itself.
- **Collection protects existing work.** A conflicting or conductor-changed
  destination refuses. Collection must not move a branch checked out in another
  consumer worktree.
- **Mail and recovery retain evidence.** Native retries use durable operation
  identities; delivery, reading and acknowledgment are separate states. Unknown
  outcomes require reconciliation, not an invented success.
- **Checks prove only what ran.** Offline fixtures do not establish real model
  access, fresh-session instruction loading or acceptance on your project.
- **Host and harness permissions still matter.** No remote on a clone is not a
  network or credential restriction. Keep worker permissions appropriate to its
  task, and review its output.

The standard flow uses GitHub tickets and one conductor's private state. There is
no daemon, automatic scheduling, universal orchestrator adapter, or automatic
push/PR/merge. Native Windows is unsupported; see the
[support matrix](docs/support.md) for platform and runtime-specific gaps.

## Documentation and contributing

- [Protocol](PROTOCOL.md): roles, mandates and report states.
- [Operations](ops/README.md): commands and evidence boundaries.
- [Coordination patterns](docs/patterns.md): catalog, selection and attribution.
- [Setup](docs/setup.md) and [bootstrap](docs/bootstrap.md): getting a project wired.
- [Native workflow](docs/native-workflow.md): the opt-in runtime and its limits.
- [Roadmap](ROADMAP.md): planned work and acceptance criteria.

A runtime fix needs a regression and a mutant that demonstrates the regression
catches the defect. Contributors run `bash ops/selftest.sh`,
`shellcheck -x ops/*.sh ops/loom`, and `bash ops/mutate.sh`, plus the relevant
runtime suites. See [CONTRIBUTING.md](CONTRIBUTING.md). Report captured exits;
mark checks that were not run.

## License

MIT. See [LICENSE](LICENSE). Loom's domain model is adapted from DeepSeek's
`dsh-superagent` prototype (MIT), with its service layer removed.
