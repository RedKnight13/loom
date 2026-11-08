# Bootstrap prompt

Copy [bootstrap.txt](bootstrap.txt) into the agent session for your project.
It discovers existing choices, configures within granted authorization and
reports evidence with explicit limits. It does not make an agent fully
dependable merely by being pasted.

## Capability paths

| Session capability | What the prompt can establish |
| --- | --- |
| Shell/CLI, including shell tools in chat | Inspect, configure and run available Loom checks with captured exit codes |
| File/repository tools without command execution | Inspect and make authorized edits; execution checks remain not run |
| Plain chat without project tools | Unwired; reopen in a capable project session |

Setup runs `bash ops/selftest.sh` and `shellcheck -x ops/*.sh ops/loom`.
`ops/mutate.sh` is the longer contributor/CI gate, not a setup requirement.
It can run locally or on a compute host with `bash ops/mutate.sh --on HOST`.
Missing tools are installed only within granted authorization. Existing files,
consumer choices and global instructions are preserved. Only consequential
unresolved choices require questions.

## Session continuity

The prompt uses [LOOM_SESSION.md](https://github.com/RedKnight13/loom/blob/main/templates/LOOM_SESSION.md) to add a small,
marked bridge to root `AGENTS.md` or `CLAUDE.md`, only where the current agent
actually supports that convention. Schema 1 requires literal
`loom-calibration:v1` in at least one regular, readable, non-symlink root file;
both are hashed when present. No additional TOML keys are needed.
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
have its result harvested and verified. The confirmed schema-1 interface is:

```sh
loom calibrate --consumer FILE          # explicit baseline + fixed offline drill
loom calibrate --consumer FILE --check  # read-only comparison; no drill rerun
```

On a setup rerun, check first and reuse a current baseline; never record
unconditionally to clear drift. Bind `LOOM_REPO` to the intended checkout or
run from it. Capture the exit and
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

The prompt renders a Mandate without opening an issue. Opening a ticket or
starting workers requires task-specific authorization; existing authorization
is retained. See [setup.md](setup.md) for commands and [support.md](support.md)
for residual gaps. Private consumer configs stay untracked; tracked configs
need an authorized conductor's commit before dispatch.
