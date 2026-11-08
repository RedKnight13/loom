---
layout: setup
title: Setup
---
<section class="setup-hero" aria-labelledby="setup">
  <div>
    <p class="intro">Setup · Start with your project</p>
    <h1 id="setup">Set up Loom.<br>Keep your context.</h1>
    <p class="lead">Give your coding agent the bootstrap prompt. It inspects your project, reuses existing choices, and guides you through configuration and offline checks.</p>
    <div class="actions"><button class="button primary" data-copy-bootstrap hidden>Copy bootstrap prompt</button><a class="button secondary" href="copy.html">Read the prompt</a></div>
    <p class="copy-status" role="status" aria-live="polite" data-copy-status></p>
    <p class="fine"><a href="bootstrap.txt">Open raw prompt</a> to select and copy manually. Prefer hands-on setup? <a href="#manual-reference">Jump to the manual reference.</a></p>
    <noscript><p>JavaScript is off. Open the raw prompt, select all its text, and copy it into your coding agent.</p></noscript>
  </div>
  <aside class="setup-prerequisites" aria-labelledby="bring-title">
    <p class="intro">Before you paste</p>
    <h2 id="bring-title">A project. Trusted checks.<br>A capable session.</h2>
    <p>Use a CLI agent or chat with project read/write access and shell execution. Bring the repository you want to delegate work in and the checks you trust.</p>
    <p>Bash 3.2+, Git, jq 1.6+, authenticated GitHub CLI and ShellCheck. Orca is optional. <a href="#1-requirements">Full requirements</a> · <a href="support.html">Platform support</a></p>
    <p class="fine">Plain chat without those capabilities stays unwired: nothing is installed or persisted. A session without shell execution reports calibration and command checks as not run.</p>
  </aside>
</section>

<section class="setup-expectations" aria-labelledby="setup-outcome">
  <div>
    <h2 id="setup-outcome">Know what setup proves.</h2>
    <p>The prompt reuses permissions already granted and asks only for unresolved choices or missing permission. It preserves existing configuration and project instructions, reusing a marked session-entry section where supported.</p>
    <p>Opening an issue or launching a worker needs task-specific authorization; reuse it when already granted. Setup itself does not grant it.</p>
  </div>
  <ol class="setup-results">
    <li><strong>Structural wiring</strong><span>Configuration and entry files inspected. Confirm actual loading in a fresh session before claiming continuity.</span></li>
    <li><strong>Offline evidence</strong><span>Selftest, ShellCheck and calibration reported separately. Check existing evidence before reviewing and recording a new baseline.</span></li>
    <li><strong>Live workflow proof</strong><span>Only an authorized real ticket, worker, harvest and verification sequence counts. Otherwise: not run. Human review still follows.</span></li>
  </ol>
</section>

<div class="manual-heading">
  <p class="intro">At your own pace</p>
  <h2 id="manual-reference">Manual reference</h2>
  <p>Start at requirements for a new setup, or jump to the part you need. Commands below use the trusted Loom checkout directly; no installed <code>loom</code> alias is assumed.</p>
</div>
<div class="setup-reference">
<aside class="setup-toc" aria-label="Reference navigation">
  <nav aria-label="Setup sections">
    <p>Prepare</p>
    <a href="#1-requirements">1. Requirements</a>
    <a href="#2-get-the-tools">2. Get the tools</a>
    <a href="#3-state">3. State</a>
    <a href="#4-register-a-consumer">4. Register a consumer</a>
    <p>Choose your executor</p>
    <a href="#5-local-executor">5. Local executor</a>
    <a href="#6-orca-executor">6. Orca executor</a>
    <a href="#7-compute-host">7. Compute host</a>
    <p>Check and maintain</p>
    <a href="#8-first-ticket-checklist">8. First ticket checklist</a>
    <a href="#calibration-and-session-entry-schema-1">Calibration &amp; session entry</a>
    <a href="#9-troubleshooting">9. Troubleshooting</a>
    <a href="#10-uninstall">10. Uninstall</a>
  </nav>
</aside>
<div class="setup-doc" markdown="1">

## 1. Requirements
{: id="1-requirements"}

Loom is Bash scripts plus the tools below. There is nothing to build and no
persistent service to run. Use a project checkout and trusted check command.

<div class="table-region" role="region" tabindex="0" aria-label="Requirements table; scroll horizontally if needed" markdown="1">

| Tool | Version | Needed for |
| --- | --- | --- |
| bash | 3.2+ | everything |
| git | any recent | dispatch, harvest, collect, verify |
| jq | 1.6+ | every record and config read |
| gh | any recent, authenticated | tickets, issues, labels |
| shellcheck | any recent | `shellcheck -x ops/*.sh ops/loom` |
| [Orca](https://github.com/stablyai/orca) | 1.4.246+ (MIT), optional | the `orca` executor, placement, worker mail; app must be running |
| ssh | optional | `compute` host for checks and placement |

</div>

Check:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash --version | head -1
jq --version
gh auth status
```

</div>

## 2. Get the tools
{: id="2-get-the-tools"}

Reuse an existing approved Loom checkout. If none exists, clone into an
unused directory you are authorized to use:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
git clone https://github.com/RedKnight13/loom.git
cd loom
export LOOM_TOOLS="$(pwd -P)"
bash ops/selftest.sh
selftest_exit=$?
printf 'SELFTEST=%s\n' "$selftest_exit"
# Continue only if SELFTEST is 0.
shellcheck -x ops/*.sh ops/loom
lint_exit=$?
printf 'LINT=%s\n' "$lint_exit"
```

</div>

`LOOM_TOOLS` is a shell variable used by this guide, pointing to that trusted
checkout. If reusing an installation, enter its directory and set
`export LOOM_TOOLS="$(pwd -P)"` there. Run the two gates above from that directory.
Keep this variable available in each terminal used below.
If a tool starts a fresh shell for each call, bind the variables in the same
invocation as the command or explicitly source an approved private setup file.
This also applies to `LOOM_REPO` and `FILE` below; past tool calls or chats do
not establish the current shell's environment.

`ops/selftest.sh` needs no network, signals no real worker, and uses stubs for
`gh`, `orca`, `ssh` and `ps`. If it fails, stop dependent setup work and retain the captured exit code.
Capture the selftest and lint exits separately; both must be 0.
These offline gates do not prove live consumer operation. `ops/mutate.sh` is
the longer portable contributor/CI gate, not a setup requirement. It can run
locally or on a compute host with `bash ops/mutate.sh --on HOST`.

## 3. State
{: id="3-state"}

Loom keeps one JSON record per assignment in `$LOOM_STATE` (default `~/.loom`).
It is conductor-only; workers never write it.

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
export LOOM_STATE="$HOME/.loom"     # optional; this is the default
```

</div>

Records are validated on every read. A corrupt record stops the scripts rather
than reading as healthy.

<div class="table-region" role="region" tabindex="0" aria-label="Environment variables table; scroll horizontally if needed" markdown="1">

| Variable | Meaning |
| --- | --- |
| `LOOM_STATE` | state directory (default `~/.loom`) |
| `LOOM_REPO` | consumer checkout for `dispatch`/`collect` (default: cwd) |
| `LOOM_LOCK_WAIT` | seconds to wait for a live lock (default 10) |
| `LOOM_ORCA` | Orca binary (tests stub it) |
| `LOOM_SSH` | ssh binary used for compute hosts (tests stub it) |
| `LOOM_ALLOW_LOCAL` | `1` lets `launch` start a local worker while Orca is ready |
| `LOOM_CALLER_UMASK` | umask handed to workers and checks |

</div>

## 4. Register a consumer
{: id="4-register-a-consumer"}

A consumer is any repo that owns tickets. Reuse its approved TOML file;
otherwise create `consumers/project.toml` in the Loom checkout with values you
have resolved for this project. The following is TOML file content, not a shell
command. Replace the example repository, check command and workspace root.

<div class="code-region" role="region" tabindex="0" aria-label="Consumer TOML configuration" markdown="1">

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

</div>

Bind the project and configuration explicitly in your shell. These are example
locations; use your actual consumer checkout and approved config file:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
export LOOM_REPO="$HOME/src/your-repo"
export FILE="$LOOM_TOOLS/consumers/project.toml"
```

</div>

`LOOM_REPO` is the project receiving work, **not** the Loom tools checkout.
Without it, dispatch and calibration use the current directory.

A tracked config must be committed by its authorized conductor before calibration
or dispatch; the assignment record pins that commit. Ignored, untracked private configs in Loom’s `consumers/` do not need
a commit. Preserve existing configuration; bootstrap does not commit it.

### Worker cap

`workers` is the maximum number of open assignments for this consumer. `dispatch`
counts records that are live or dispatched-but-unsettled and refuses past the
cap with the ids that hold the slots. Omit the key for no cap.

`bash "$LOOM_TOOLS/ops/loom" capacity` reports what Orca can carry right now — runtime ready, connected
hosts — and suggests a number (one per connected host, minimum one). The
bootstrap prompt reuses an existing cap or offers this suggestion when the
choice is unresolved. A capacity suggestion is not authorization to launch.

Declaring `executor = "local"` selects local dispatch. If Orca is installed
and ready, `launch` still requires `LOOM_ALLOW_LOCAL=1`; the config alone
does not bypass that guard.

## 5. Local executor
{: id="5-local-executor"}

Set `executor = "local"` in the consumer TOML. Complete the
[first ticket checklist](#8-first-ticket-checklist), including calibration,
before launching a real task. The commands below show an already authorized
issue; replace `42`, the returned assignment ID and `my-agent` with your values.
Run each step separately, capture its exit and inspect its JSON response before
continuing. Recheck calibration immediately before dispatch and again before
launch; a successful dispatch does not start a worker.
Use an approved noninteractive worker command: local launch supplies no stdin
and runs it inside the assignment workspace. `my-agent` is a placeholder, not
an installed Loom command.

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/loom" dispatch --consumer "$FILE" --issue 42
# Read the returned id; add-flag.1 below is an example.

bash "$LOOM_TOOLS/ops/loom" launch add-flag.1 -- bash -c 'my-agent "Read WORK.md"'
```

</div>

`launch` waits for the worker. In a second conductor terminal with the same
`LOOM_TOOLS` and state settings, run the watch loop while it works:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/loom" watch --until add-flag.1
```

</div>

After a ready report, verify and collect the result:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/loom" verify add-flag.1
bash "$LOOM_TOOLS/ops/loom" collect add-flag.1
```

</div>

`launch` harvests when the local process exits; inspect the report, not just the
command exit. Continue to collect only after verification succeeds. Collect
fetches the branch; it does not enforce verification or perform review, push or
merge. After changing or rebasing the collected branch, verify its new revision.

`dispatch` creates a **private clone** with its own `.git` and **no remote**.
The worker reads `WORK.md`, leaves files in the working tree, and appends one
line to `REPORT.md`:

<div class="code-region" role="region" tabindex="0" aria-label="Worker report" markdown="1">

```
state: ready — added the flag and a test
```

</div>

The worker must not stage, commit or push. Loom commits what it left, on
branch `<short>`, when the turn is harvested. `WORK.md`, `REPORT.md` and `.loom/` are excluded from that commit;
`.loom/` is copied to `$LOOM_STATE/<id>.evidence/` instead.

## 6. Orca executor
{: id="6-orca-executor"}

Orca (<https://github.com/stablyai/orca>, MIT, **1.4.246+**) supervises
workers and, when a `compute` host is declared, places them there. Its desktop
app must be running: `orca status` reports whether the runtime is ready.

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
orca --version                    # must be 1.4.246 or newer
orca status                       # runtime reachable and ready
orca repo add --path "$LOOM_REPO"
orca host list                    # connect the target in the Orca app first
```

</div>

Set the executor in the consumer TOML:

<div class="code-region" role="region" tabindex="0" aria-label="Consumer TOML configuration" markdown="1">

```toml
executor = "orca"                 # in the consumer config
compute  = ["build1", "build2"]   # optional; first connected Orca host wins
```

</div>

Complete the [first ticket checklist](#8-first-ticket-checklist) before an
authorized real task. With compute placement, the consumer project must also
have a ready setup on the selected Orca host; the pinned base commit must be
available there. Use your issue number and the assignment ID returned by dispatch.
Run each step separately, capture its exit and inspect its JSON response before
continuing. Check calibration immediately before dispatch and again before
start. After harvest, inspect the report and verify a ready result before collect;
blocked or failed work needs resolution first.

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/loom" dispatch --consumer "$FILE" --issue 42
bash "$LOOM_TOOLS/ops/loom" start add-flag.1                    # declared compute: first connected host, or refuse
# Orca wakes the conductor when the worker is done:
bash "$LOOM_TOOLS/ops/loom" harvest add-flag.1
bash "$LOOM_TOOLS/ops/loom" verify add-flag.1
bash "$LOOM_TOOLS/ops/loom" collect add-flag.1
bash "$LOOM_TOOLS/ops/loom" release add-flag.1                  # after collect
```

</div>

`start` defaults to the `codex` agent; use `start add-flag.1 --agent NAME` for an
approved alternative available in Orca. `collect` fetches the branch and `release`
releases the settled worker; neither proves project acceptance. Review, push and
merge remain the authorized conductor's actions. Reverify after any change to
the collected revision.

Rules Loom keeps for Orca:

- Orca creates the workspace. Loom adopts it.
- Loom never signals an Orca worker. A silent one is shown as `stale`; you decide.
- `stop` records a stop only when Orca confirms one; `stop_unknown` changes nothing.
- `abandon` fences and records `failed / owner_fenced`; it never claims a stop.
- A failed `worker-start` is recorded and never retried.
- `check` is only ever called with `--peek`; `inbox` is the other read path.

## 7. Compute host
{: id="7-compute-host"}

`compute` moves the checks (and Orca workers) off the conductor's machine.

<div class="code-region" role="region" tabindex="0" aria-label="Consumer TOML configuration" markdown="1">

```toml
compute       = ["build1", "build2"]                  # first reachable wins
compute_setup = ". ~/.venvs/checks/bin/activate"    # run before each check
```

</div>

Requirements on the host:

- SSH key auth works non-interactively (`ssh -o BatchMode=yes host true`)
- `git` and the runtime your `checks` need
- whatever `compute_setup` expects (a venv, a toolchain)

`verify` ships the exact commit as a git bundle over SSH, builds a fresh tree in
an isolated directory under `$HOME/.loom-remote/`, runs setup then checks,
returns the log, records the host, and deletes its folder. If no declared host
is reachable, verification refuses; Loom never
falls back to the conductor's machine. A failing `compute_setup` is reported as
**could not run** (exit 126), never as a test failure.

## 8. First ticket checklist
{: id="8-first-ticket-checklist"}

- [ ] `bash ops/selftest.sh` exits 0
- [ ] `shellcheck -x ops/*.sh ops/loom` exits 0
- [ ] any tracked consumer config is committed by its authorized conductor
- [ ] `LOOM_TOOLS`, `LOOM_REPO` and `FILE` point to the intended checkout/configuration
- [ ] `gh auth status` shows the account that owns the repo
- [ ] the checkout's git identity is the one you want in commits
  (Loom copies `user.name`/`user.email` into a local clone)
- [ ] if `compute` is declared: `bash "$LOOM_TOOLS/ops/loom" compute --consumer "$FILE"` names a host
- [ ] if `executor = "orca"`: `orca status` is ready; any declared compute host is connected
- [ ] session entry is inspected and calibration `--check` is current (below)
- [ ] opening the ticket or launching a worker is authorized for this task

### Render, then accept a ticket

After configuring the paths above, replace the scope and done condition with
the proposed task. Rendering validates the Mandate format without creating an
issue or worker:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/ticket.sh" "$FILE" \
  --short first-check --title "First check" \
  --scope "<authorized area>" --out "everything else" \
  --done "<trusted checks> exits 0" --dry-run
```

</div>

Inspect the rendered Mandate and capture the exit. Only when opening this
ticket is authorized, run the following with the same reviewed values. Reuse
authorization already granted; ask only for an unresolved owner decision.

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/loom" accept --consumer "$FILE" \
  --short first-check --title "First check" \
  --scope "<authorized area>" --out "everything else" \
  --done "<trusted checks> exits 0"
```

</div>

`accept` opens a GitHub issue; its `accepted` state is not project acceptance.
Use the returned `ticket` for authorized `dispatch`, then the returned `id` for
`start` (Orca) or `launch` (local), as shown in the executor sections. An existing
reviewed ticket can be dispatched without opening another. These are separate
actions; rendering or accepting a ticket does not authorize a worker.

### Calibration and session entry (schema 1)

The schema-1 command ships in `ops/loom`. Confirm availability in the installed
checkout; older installations may lack it. If absent, report calibration not
run and stop dependent delegation until an approved implementation is available.
The selftest composes the shipped session bridge with record/check fixtures;
actual harness loading and real worker acceptance still need separate evidence.

Install the [session bridge](https://github.com/RedKnight13/loom/blob/main/templates/LOOM_SESSION.md) only after inspecting
the agent's project loading convention and existing content. Schema 1 requires
literal `loom-calibration:v1` in root `AGENTS.md` or `CLAUDE.md`; every present
root entry file must be regular, readable and non-symlink, and both are
fingerprinted if present. Preserve existing
content and user customizations; reuse one `loom-session:start` / `loom-session:end`
section rather than appending another. Reconcile duplicate or malformed markers
before editing. Do not create competing entry files or overwrite global instructions.
Unsupported entry conventions remain unwired. No new consumer TOML keys are required.
Install or reuse the checklist in the consumer checkout and make the bridge's
project-relative link resolve to it. A link into a nonexistent consumer
`templates/` directory does not carry the checklist into the next session.

With `LOOM_REPO` bound to the intended consumer checkout (otherwise cwd), use
the trusted Loom installation and the resolved consumer `FILE`.
First compare, including on a setup rerun:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/loom" calibrate --consumer "$FILE" --check
calibration_exit=$?
printf 'CALIBRATION_CHECK=%s\n' "$calibration_exit"
```

</div>

Reuse a current successful baseline. If evidence is missing or drifted, stop
dependent delegation and review the reported fields and intended changes.
**Only after that review**, explicitly record if needed:

<div class="code-region" role="region" tabindex="0" aria-label="Shell commands" markdown="1">

```bash
bash "$LOOM_TOOLS/ops/loom" calibrate --consumer "$FILE"
record_exit=$?
printf 'CALIBRATION_RECORD=%s\n' "$record_exit"
```

</div>

After successful recording, run the first `--check` command again and capture
its exit. Rerunning setup must not silently replace the baseline. At every new
session and immediately before delegation, check again through a shell tool.
Inspect the complete JSON envelope, not only the exit code: require `ok:true`,
`state:ready`, `items[0].schema:1` and `items[0].readiness:ready`;
`items[0].acceptance` remains `not_run`.

<details class="setup-details" markdown="1">
<summary>Calibration evidence, storage and limits</summary>


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
`${LOOM_STATE:-$HOME/.loom}/calibration/<key>.json`. Relative `LOOM_STATE`
resolves against invocation cwd; spaces are allowed, control characters and
`.`/`..` path components are refused. Existing state/calibration directories
require owner-only mode 0700 and proof files mode 0600. Missing baseline blocks;
corrupt/unknown schema, unsafe state or symlinks fail closed. Do not delete
locks or change permissions as an automatic repair. Failed recording preserves
the prior baseline. Keep separately redacted setup evidence under `.loom/`
only where private; do not publish paths, identities, hosts or credentials.

Every new session and immediately before delegation, invoke `--check`, including
after context loss, tool reconnect or dependency changes. Read the bridge
explicitly if loading is uncertain and confirm it was read. Review drift before
explicit recording; comparison never accepts changes. Fingerprints cover Loom
source/version, consumer and bridge bytes, checkout identity, tools and executor.
They do not cover linked checklist contents, project check implementations,
credentials or session permissions. The `connectivity` stage reflects local
executor selection (and Orca status when probed), not GitHub authentication,
SSH access or remote project readiness. Read the linked checklist and review
current authorization at session entry; repeat relevant authorized observations
after changes even when calibration returns ready. Do not refresh a baseline
as a substitute for checking facts outside its fingerprint.
Recording reobserves inputs after the drill, and checking reobserves before
success; observable concurrent changes fail without replacing evidence. These
checks do not prevent adversarial filesystem races. SHA-1 fingerprints are
independent of the caller repository object format. A new checkout/config
location needs a new baseline; branch/HEAD changes alone
do not imply bootstrap drift or project acceptance.

Tool-enabled sessions with shell execution follow the same protocol as CLI
agents. Without execution, say **unwired; calibration not run** and resume in a
capable session. A shell route does not grant delegation permission. Marker
presence proves structure only; confirm actual loading in a fresh session before
claiming continuity. Schema 1 relies on the agent: existing dispatch/start/launch
commands are not automatically gated, and a comparison-to-delegation gap remains.
No background monitor, persistent model memory or unattended repair is installed.

</details>

## 9. Troubleshooting
{: id="9-troubleshooting"}

<div class="table-region" role="region" tabindex="0" aria-label="Troubleshooting table; scroll horizontally if needed" markdown="1">

| Symptom | Cause | Fix |
| --- | --- | --- |
| `consumer config has uncommitted changes` | config under git, edited | have the authorized conductor review and commit it; the record pins the config commit |
| `ticket already has a live assignment` | one-ticket-one-worker rule | wait, `stop`, or dispatch a new attempt after it settles |
| `executor orca required but ... not ready` | Orca runtime down | start Orca; Loom never silently falls back |
| `no compute host is connected in Orca` | none of `compute` is connected | connect one in Orca; Loom does not connect hosts |
| `no compute host reachable ... refusing` | SSH/setup | fix SSH or the host; do not expect a local run |
| `checks could not run (exit 126/127/255)` | setup, ssh, missing runtime | read `$LOOM_STATE/<id>.checks-<kind>.log`; it is not a test failure |
| `worker_exit_no_report` | worker exited without a `state:` line | read the log, re-dispatch with clearer instructions |
| `watchdog_kill` | no report within `limit_min` | autopsy the workdir; the ticket stays open |
| `orca could not confirm the stop` | `stop_unknown` | inspect with `worker-show`; `abandon` is fencing, not a stop |
| `agent_readiness` timeout on a remote host | agent startup slower than Orca's wait | raise `start_timeout_ms` (for example `300000`) |
| `git staging exits 128 ... .git is read-only` | old executor sandbox | workers leave changes unstaged; harvest commits. Re-dispatch on 0.6.0 |

</div>

## 10. Uninstall
{: id="10-uninstall"}

Inspect active assignments before removing their state. Remove only the Loom
checkout/state and project bridge you intend to uninstall; preserve surrounding
project instructions and user files. Bootstrap may have installed authorized
prerequisites or a project checklist, so review its change report separately.
Loom does not install a persistent background service.

</div>
</div>
