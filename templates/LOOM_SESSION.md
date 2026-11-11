# Loom session entry

This checklist installs no hook and grants no execution permission. The root
session bridge is the per-repo permission to use catalog patterns; a repo without
it follows the base Loom turn without a catalog pattern. Schema 1 recognizes
root `AGENTS.md` and `CLAUDE.md`; at least one must contain `loom-calibration:v1`.
Every present root entry file must be readable, regular and non-symlink. Both
are fingerprinted when present. Inspect the agent's actual loading convention
before editing either.
If neither is supported, report **unwired** and offer manual session entry.
Do not create competing entry files or modify global instructions.

Merge the following section into the supported project file, replacing the
checklist link with its actual project-relative location. Install or reuse this
checklist in the consumer and verify the link resolves from the entry file.
Resolve the approved consumer config and trusted Loom invocation from private
project state and existing instructions; do not publish private paths or add TOML keys. Reuse the
marked section on subsequent setup, preserving surrounding text and user
customizations. Reconcile duplicate/malformed markers instead of appending.

<!-- loom-session:start -->
## Loom entry — loom-calibration:v1

Read this project's consumer config, laws and [session checklist](templates/LOOM_SESSION.md).
Set `LOOM_TOOLS` to the absolute trusted Loom checkout path. Export `LOOM_REPO`
as the intended consumer checkout path. Set `FILE` to the absolute approved
consumer config path before using the commands below. If the shell tool starts
a fresh shell per call, bind these variables in the same invocation or explicitly
source an approved private setup file. Do not assume bindings persist across
tool calls or sessions.

At every session entry and immediately before every delegation, run through an
available shell execution tool:

```sh
bash "$LOOM_TOOLS/ops/loom" calibrate --consumer "$FILE" --check
```

Capture the exit code and inspect the complete JSON response. Require exit 0,
`ok:true`, `state:ready`, schema 1 and `items[0].readiness:ready`; calibration's
`acceptance` remains `not_run`. Nonzero, missing or malformed evidence stops
delegation. Repeat after context loss, tool reconnect, config/bridge edits,
checkout changes, installation updates or changed dependencies. Read the linked
checklist and review current task authorization, tools and permissions too:
calibration does not observe those permissions, credentials, linked checklist
contents, project check implementations or remote host reachability. Repeat
relevant authorized observations after changes even if calibration is ready.

Review missing evidence or named drift fields and resolve only within existing
authorization. After reviewing an intended baseline change, explicitly record:

```sh
bash "$LOOM_TOOLS/ops/loom" calibrate --consumer "$FILE"
```

Then check again before delegation. Never record automatically to clear drift.
If the command is unavailable, report **calibration not run** and stop dependent
delegation. If shell execution is unavailable, report **unwired; calibration
not run** and move to a capable project session. Confirm you read this bridge;
if loading is uncertain, open it explicitly rather than assuming persistence.

Read the approved coordination choice below if present. Reuse it only while
its task fit, capabilities, budget and authorization still hold, and say its
name. Preserve the approved text until explicitly replaced; changed advice is
a proposal until the person accepts it or asks the session to pick. Stop work
that depends on an infeasible choice.

Select only complete `catalog/<id>/PATTERN.md` entries in the trusted Loom
checkout. Missing fields or attribution make an entry ineligible. A named
pattern wins: list matches without picking if ambiguous; report an unknown or
incomplete name without substituting. Manual choice lists every complete entry
with attribution. If the person explicitly has no opinion, say "Let me propose
an ideal flow for us," then pick one using the selection criteria in the
trusted Loom checkout `docs/patterns.md` (Choose a pattern):
eligibility, task shape, evidence, bounded cost, safety and reversibility, then
the simplest option with fewest workers closest to solo as the tie-break.
Unknown capability is ineligible; unsupported estimates stay unknown. State the
reasoning and any tie-break. If none is eligible, say so and offer the solo
baseline with human review without relaxing constraints.

Before following steps in this same session, announce the name, author,
upstream and license, the task-grounded cost, effectiveness and intelligence
estimate, and **using this pattern**. Silence is not no opinion: ask once, then
continue the authorized base turn without a pattern and record no choice if
there is still no answer. Selection never launches workers. Pattern steps remain
subordinate to the protocol, consumer laws, trusted checks and owner-only finish.
New entries arrive with the normal Loom checkout update; contribution and owner
PR review follow `catalog/README.md` in that checkout.

Model-role recommendations are advice, not applied settings. Inspect current
inventory for available local/custom harnesses or the optional Orca adapter on
the authorized execution host and respect pinned consumer settings;
unknown access/quota stays unknown. Missing discovery can use user-supplied
observed inventory and does not block advice. Loom Orca start exposes only `--agent`, with
consumer model/effort pinned at dispatch. Never silently override them or use
invented per-role flags. Local launch uses its authorized command/harness settings.
Selection grants no installation, model/cap/placement
change or launch permission. Before separately authorized execution, confirm
context isolation and effective model/effort/host fields; report unknowns.

Real acceptance requires separately authorized verification of the actual
revision with captured exits. Installation, configuration, offline drill and
prior acceptance do not substitute for that verification or authorize a worker.
<!-- loom-session:end -->

## Optional approved coordination choice

After explicit user selection or an explicit no-opinion request to pick, save
ONE section with the following fields
inside the root bridge above. This example is a fill-in guide, not a selection;
do not copy unfilled placeholders as approved instructions. Check both root
entry files for duplicate/conflicting sections, reconcile first, and preserve
surrounding instructions and user customizations. Do not add a second section
on reruns. A changed recommendation remains a proposal until accepted.

```markdown
<!-- loom-pattern:start -->
### Approved coordination choice
- Recipe and catalog reference: <chosen name; trusted catalog/<id>/PATTERN.md>
- Task/fit: <scope and reason; when to reconsider>
- Roles and context: <responsibilities; permitted input per role; isolation>
- Bounds: <worker total and peak concurrency; review/retry rounds; time/token budget>
- Stop: <checks/acceptance, exhausted bounds, drift, missing capability, owner decision>
- Model-role advice: <each role's observed agent/provider/model or unknown;
  effort if supported; private authorized-host reference; rationale;
  installed/configured/launch-verified evidence; cost basis and confidence>
- Applied configuration: <existing approved consumer settings or unknown;
  advice not applied; no per-role routing implied>
- Approval scope: <explicit selection or no-opinion request to pick; constraints; no new permissions>
<!-- loom-pattern:end -->
```

Keep private paths, host names, identities and account details out of shared
instructions; resolve private references at entry. Save the operative choice in
this root section. Schema 1 fingerprints root entry bytes, including the choice,
but not linked checklist or separate pattern artifact bytes. Review linked
content separately. On an approved edit, run `--check`, review the named drift,
explicitly record if appropriate, then check again before delegation. Do not
refresh the baseline merely to accept new advice. If this recording flow is
unavailable, keep the choice session-only and say it was not persisted; dependent
delegation still requires a successful check. The markers add no parser,
TOML keys, model calls, scheduler, telemetry or automatic enforcement.

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

The agent must perform entry/delegation checks; schema 1 does not retroactively guard
existing dispatch/start/launch commands. A gap remains between comparison and
delegation. Marker presence proves only structure, not harness loading or
obedience. Confirm actual loading in a fresh session before claiming observed
continuity. There is no daemon, automatic repair, persistent model memory or
universal security guarantee. Setup selftest/lint remain separate offline gates;
mutation testing belongs to contributor/CI work, not routine session entry.
