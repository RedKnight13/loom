# Bootstrap prompt

Copy [bootstrap.txt](bootstrap.txt) into the agent session for your project.
It discovers existing choices, configures within granted authorization and
reports evidence with explicit limits. It does not make an agent fully
dependable merely by being pasted.

Before the gates, it updates the Loom tools checkout: fetch `origin`, stop on a
dirty tree, a non-main `HEAD` or any commit ahead of `origin/main`, and
fast-forward only when cleanly behind. The prompt is written for the latest
`main`, so a checkout that cannot move safely stops setup instead of testing
stale code.

## Capability paths

| Session capability | What the prompt can establish |
| --- | --- |
| Shell/CLI, including shell tools in chat | Inspect, configure and run available Loom checks with captured exit codes |
| File/repository tools without command execution | Inspect and make authorized edits; execution checks remain not run |
| Plain chat without project tools | Unwired; reopen in a capable project session |

Setup runs `bash ops/selftest.sh` and `shellcheck -x ops/*.sh ops/loom`.
Worker count and the Orca worker agent are asked only when unresolved: `loom
capacity` reports readiness, connected hosts and a suggested count, `loom hosts`
names them, and `orca account list --json` shows agents the runtime can launch.
A ready Orca environment is reused, not reconfigured.
`ops/mutate.sh` is the longer contributor/CI gate, not a setup requirement.
It can run locally or on a compute host with `bash ops/mutate.sh --on HOST`.
Missing tools are installed only within granted authorization. Existing files,
consumer choices and global instructions are preserved. Only consequential
unresolved choices require questions.

## Three choices, grounded in this project

After inspecting the task, checks and capacity, bootstrap offers exactly three
coordination candidates, marks one recommended and compares each with a single
scoped worker baseline. Compare cost assumptions, elapsed time, accepted work
per human hour and defects/rework separately; no measured gains are promised.
Each candidate also gets role-by-role agent/model advice from the authorized
host's observed inventory. Local/custom harnesses work without Orca; if discovery
is unavailable, use user-supplied observed inventory or explicit unknowns without
blocking advice. Unknown access, rates or quota stay unknown.

Choose a candidate, keep the simple baseline, defer, or request the
[full maintained pattern catalog](patterns.html#catalog). Manual choice lists
all maintained families with capability limits; it does not claim to enumerate
all possible patterns. Unavailable recipes remain informational. Selection
never installs a plugin, changes models, raises caps, moves work or launches it.
Loom capacity counts hosts, not model availability or safe concurrency.

An approved choice is reused. Changed advice is a proposal until explicitly
accepted; silence never selects anything. Existing authorized work without a
choice can continue safely without adding workers. The reviewed choice lives
in one marked section of the supported root session-entry file, so existing
schema-1 calibration detects edits. Linked artifacts are not fingerprinted.
Advice is not runtime routing: Loom Orca start exposes only `--agent`; consumer
model/effort are pinned at dispatch. See [model-role matching](patterns.html#models)
for inventory evidence and configuration limits.

## Session continuity

The prompt uses [LOOM_SESSION.md](https://github.com/RedKnight13/loom/blob/main/templates/LOOM_SESSION.md) to add a small,
marked bridge to root `AGENTS.md` or `CLAUDE.md`, only where the current agent
actually supports that convention. Schema 1 requires literal
`loom-calibration:v1` in at least one root file; every present root entry file
must be regular, readable and non-symlink, and both are hashed when present.
Install or reuse the checklist in the consumer and verify the bridge's relative
link resolves. No additional TOML keys are needed.
It inspects existing conventions first and preserves surrounding content.
Repeating setup updates that section without duplicating it. No universal
instruction filename or automatic loader is assumed.

A bridge on disk is structural wiring. Loading must be observed in a fresh
session before claiming continuity works. Unsupported sessions remain unwired
and must open the checklist manually. Recheck at new session entry, before
delegation and after changed dependencies; missing/stale evidence blocks the
dependent work. The checklist itself is not a daemon or enforcement boundary.

## Evidence and next steps

Report structural wiring, offline drills and live workflow proof separately.
Selftest/lint and ticket rendering do not prove a real worker can finish and
have its result harvested and verified. Use the absolute `LOOM_TOOLS`,
`LOOM_REPO` and `FILE` paths resolved by the prompt or
[manual setup](setup.md#4-register-a-consumer); no installed alias is assumed.
For fresh setup and existing installations, compare first:

```sh
bash "$LOOM_TOOLS/ops/loom" calibrate --consumer "$FILE" --check
```

On a setup rerun, check first and reuse a current baseline; never record
unconditionally to clear drift. For missing or drifted evidence, review it before
explicitly recording with `bash "$LOOM_TOOLS/ops/loom" calibrate --consumer "$FILE"`,
then run `--check` again. Bind `LOOM_REPO` to the intended checkout or run from it.
Capture the exit and
inspect the complete envelope: exit 0 means ready prerequisites/offline drill,
1 means blocked/failed, 2 means usage error. Calibration acceptance is always
`not_run`. Review drift before explicitly recording again; checking never
refreshes a baseline. Records are private, sanitized data under
`${LOOM_STATE:-$HOME/.loom}/calibration/<key>.json`. Relative `LOOM_STATE`
is resolved against invocation cwd. Existing state directories require mode
0700 and proof files mode 0600; calibration never repairs permissions.

The command ships in `ops/loom`. Verify the installed checkout supports it;
an older installation may lack it. An unavailable command blocks calibration
and delegation. The hermetic selftest records and checks the shipped bridge
with fixture data; it does not prove fresh-session loading by a real harness.

The bridge instructs execution at every session entry and immediately before
delegation, including after context loss or a tool reconnect. Schema 1 does not
automatically gate legacy dispatch/start/launch commands; the agent must enforce
this protocol, and a gap remains between comparison and delegation.
Calibration does not fingerprint linked checklists or project check implementations,
inspect credentials or session permissions, or prove remote host reachability.
Read the checklist and review current authorization separately; repeat relevant
authorized observations after changes even if calibration is ready.

The prompt renders a Mandate without opening an issue. Opening a ticket or
starting workers requires task-specific authorization; existing authorization
is retained. `accept` opens the reviewed ticket; it does not launch a worker or
certify project acceptance. Authorized `dispatch` and `start`/`launch` are separate
steps. See [setup.md](setup.md) for commands and [support.md](support.md)
for residual gaps. Private consumer configs stay untracked; tracked configs
need an authorized conductor's commit before calibration or dispatch.
