# Loom session entry

This checklist neither installs a hook nor grants permission. Schema 1 recognizes
root `AGENTS.md` and `CLAUDE.md`; at least one must be readable, regular,
non-symlink and contain `loom-calibration:v1`. Both files are fingerprinted when
present. Inspect the agent's actual loading convention before editing either.
If neither is supported, report **unwired** and offer manual session entry.
Do not create competing entry files or modify global instructions.

Merge the following section into the supported project file, replacing the
checklist link with its actual project-relative location. Resolve the approved
consumer config and trusted Loom invocation from private project state and
existing instructions; do not publish private paths or add TOML keys. Reuse the
marked section on subsequent setup, preserving surrounding text and user
customizations. Reconcile duplicate/malformed markers instead of appending.

<!-- loom-session:start -->
## Loom entry — loom-calibration:v1

Read this project's consumer config, laws and [session checklist](templates/LOOM_SESSION.md).
Resolve the trusted Loom installation and intended consumer checkout; bind
`LOOM_REPO` to that checkout, or run from it. Resolve `FILE` to the approved
consumer config before using the commands below.

At every session entry and immediately before every delegation, run through an
available shell execution tool:

```sh
loom calibrate --consumer FILE --check
```

Use `bash <trusted-loom-checkout>/ops/loom` if that is the approved invocation.
Capture the exit code and inspect the complete JSON response. Require exit 0,
`ok:true`, `state:ready`, schema 1 and `items[0].readiness:ready`; calibration's
`acceptance` remains `not_run`. Nonzero, missing or malformed evidence stops
delegation. Repeat after context loss, tool reconnect, config/bridge edits,
checkout changes, installation updates or changed dependencies.

Review missing evidence or named drift fields and resolve only within existing
authorization. After reviewing an intended baseline change, explicitly record:

```sh
loom calibrate --consumer FILE
```

Then check again before delegation. Never record automatically to clear drift.
If the command is unavailable, report **calibration not run** and stop dependent
delegation. If shell execution is unavailable, report **unwired; calibration
not run** and move to a capable project session. Confirm you read this bridge;
if loading is uncertain, open it explicitly rather than assuming persistence.

Real acceptance requires separately authorized verification of the actual
revision with captured exits. Installation, configuration, offline drill and
prior acceptance do not substitute for that verification or authorize a worker.
<!-- loom-session:end -->

## Evidence and limits

`--check` compares without writes, locks or drill execution. Exit 1 means
blocked/failed observation; exit 2 means invalid usage. A successful record
runs only the fixed isolated offline drill and stores sanitized schema-1 data
under `${LOOM_STATE:-$HOME/.loom}/calibration/<key>.json`; a failed record keeps
the previous baseline. Do not delete locks, chmod state or repair unrelated
configuration simply to make a check pass. Separate redacted setup evidence
may live under project `.loom/`, subject to its privacy conventions.

New clone/config locations need their own baseline. Changed source, consumer,
bridge, executable bytes/resolution or selected executor require review;
restoring exact inputs can restore validity without recording. Branch and HEAD
changes alone are not bootstrap drift; real verification is revision-specific.

The agent enforces entry/delegation checks; schema 1 does not retroactively guard
existing dispatch/start/launch commands. A gap remains between comparison and
delegation. Marker presence proves only structure, not harness loading or
obedience. Confirm actual loading in a fresh session before claiming observed
continuity. There is no daemon, automatic repair, persistent model memory or
universal security guarantee. Setup selftest/lint remain separate offline gates;
mutation testing belongs to contributor/CI work, not routine session entry.
