# Calibration Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. The coordinator has already assigned runtime and bootstrap developers; do not spawn additional workers. Leave changes uncommitted for Loom harvest.

**Goal:** Give every executable agent session an honest, repeatable bootstrap check that detects drift without running arbitrary consumer code.

**Architecture:** Add a calibration helper behind the existing JSON facade, with explicit recording and a read-only comparison mode. Keep installation, instruction loading, executor connectivity, a synthetic offline drill and real acceptance distinct. Persistent instruction bridges tell sessions when to compare; existing commands retain their behavior.

**Tech Stack:** Bash 3.2+, existing git, jq 1.6+, and standard utilities only.

**Spec:** `docs/superpowers/specs/2026-11-08-calibration-design.md` is the normative schema and behavior contract.

## Global constraints

- Bash 3.2+, existing git, jq 1.6+, and standard utilities only.
- No additional consumer TOML keys are required.
- Exit 0 iff `ok:true`; exit 1 for incomplete, unwired, drifted, or failed observation; exit 2 for usage errors.
- Acceptance remains `not_run` in calibration.
- Comparison cannot create even an empty state directory or update access-independent metadata such as a last-checked field.
- No root privileges, global hooks, Git commits, remotes, or working-tree edits.
- No daemon, automatic checks/installers, new services, provider requests, or guaranteed persistent memory.
- No worker pushes, merges, commits, or extra workers; logs and captured exit codes belong under `.loom/`.

## Review focus

- Consumer/bridge strings containing shell syntax must stay data, with no execution (task 1 and task 2).
- Relocated checkouts and changed executables must invalidate evidence without disclosing identities (task 1).
- Interruptions and simultaneous recorders must preserve a complete baseline (task 2).
- A nonCLI session with shell tools works; a chat-only session must report unwired (task 3).
- A changed runtime after calibration blocks delegation through the entry protocol, with no claim that legacy dispatch is guarded (task 3 and task 4).

## Ownership and interfaces

Runtime developer owns `ops/calibrate.sh` (new), `ops/loom` command integration, and new tests in `ops/selftest.sh`. Keep calibration-specific helpers in `ops/calibrate.sh`; use existing `loom_config` and executor policy helpers without weakening their validation. Bootstrap developer owns `docs/bootstrap.md`, `docs/bootstrap.txt`, `docs/setup.md`, and `ops/README.md` integration. These are downstream implementation targets, not edits made by this architecture assignment. Coordinate shared-file changes before editing; the runtime developer owns all executable integration.

`bash ops/calibrate.sh --consumer FILE [--check]` emits one schema-1 item object on stdout and exits 0 for ready, 1 for failed/blocked, 2 for usage. It never emits an envelope. The `ops/loom` branch captures output and status without `run_out` (which discards structured failure payloads), validates the item, maps readiness/failure to the spec's envelope state, adds fixed `fact/actions`, and calls `emit` exactly once. To distinguish operational failure from incomplete prerequisites, helper failure output includes an internal top-level `failure` field (`null|usage|invalid_evidence|unsafe_path|internal`); the facade consumes and removes it before exposing the item. Internal diagnostics are static reason codes only. Unknown/malformed helper output maps to failed/incomplete. The final item schema remains exact.

Use private functions prefixed `loom_cal_` rather than exporting shared mutable variables or expanding `loom_init`. Proposed internal boundaries: `loom_cal_observe CONSUMER` returns the fingerprint and stage observations; `loom_cal_compare CURRENT RECORD` returns validated equality/drift data; `loom_cal_drill` returns a captured status; `loom_cal_record KEY ITEM` performs the atomic write. Their wire contract is JSON through stdout, errors are captured statuses, and they never call `emit`. Runtime developer may organize internals differently while preserving the public contract.

### Task 1: Observe and compare without mutation (runtime developer)

**Files:** create `ops/calibrate.sh`; modify `ops/loom`, `ops/selftest.sh`.

- [ ] Add tests `calibrate_usage`, `calibrate_missing_record_readonly`, `calibrate_invalid_config`, `calibrate_corrupt_record`, `calibrate_unknown_schema`, and `calibrate_missing_tool`. Assert one JSON envelope, exact exit mapping and no state-directory creation. Stub required tools in isolated PATH; missing jq expects the fixed literal failure envelope.
- [ ] Run `bash ops/selftest.sh` and capture the expected new-test failure under `.loom/`; distinguish preexisting failures.
- [ ] Implement strict argument parsing and the calibration-only state resolver. Validate input file types, exact JSON schema, 64 KiB bound, the specified simple compute-host grammar and static diagnostics before any optional probe. Do not use `run_out` for structured calibration failures or `loom_init` during check.
- [ ] Implement deterministic fingerprint inputs exactly as specified: code manifest, exact config bytes, checkout identity, both bridge files, executable resolution/bytes and actual executor selection. Use hash-object without object writes in explicit SHA-1 context; preserve privacy by exposing only digests and logical names.
- [ ] Add `calibrate_drift_matrix`, `calibrate_relocated_checkout`, `calibrate_dirty_code`, `calibrate_tool_changed`, `calibrate_orca_timeout`, `calibrate_config_is_data` and `calibrate_privacy`. Independently mutate each field, confirm sorted drift names, ensure no raw fixture path/identity/secret canary reaches either stream, and assert forbidden commands were never called.
- [ ] Implement read-only comparison with fingerprint stability checks. Valid matching recorded drill can pass; missing/invalid evidence cannot. No comparison timestamp write, no drill rerun and no baseline repair.
- [ ] Run the selftest and shellcheck; record actual exit codes. Deliver the externally callable check contract before bootstrap integration.

### Task 2: Record only genuine synthetic evidence (runtime developer)

**Files:** modify `ops/calibrate.sh`, `ops/selftest.sh`; create `ops/calibration-drill.sh` only if the fixed fixture benefits from a separate file.

- [ ] Add `calibrate_record_roundtrip`, `calibrate_drill_failed`, `calibrate_failed_record_preserves_old`, `calibrate_interrupted_write`, `calibrate_concurrent_record`, `calibrate_unsafe_state`, and `calibrate_drift_during_record`. Assert private modes, atomic complete JSON, baseline preservation, prompt lock failure and no unrelated path removal.
- [ ] Run tests to observe failures before implementing writes.
- [ ] Implement the fixed private offline fixture: isolate HOME/state/repo/PATH/Git configuration, synthesize ready/blocked/missing worker reports, and exercise the existing report interpretation path plus envelope assertions using only stubs. Capture exits; never infer a pass from expected text alone.
- [ ] Implement recording with umask 077, dedicated mkdir lock, owned-temp cleanup, same-directory validation/rename and prepublication fingerprint comparison. Successful recording always sets acceptance to not_run. Failed or interrupted recording leaves any old record intact.
- [ ] Add `calibrate_check_does_not_write` using before/after directory inventories, record bytes/mtime and stubs that reject mutations; add `calibrate_no_forbidden_calls` with consumer hooks, installers, provider/network commands and production state as tripwires. Do not treat filesystem access-time changes as command writes.
- [ ] Run required checks and report exact command/exit evidence under `.loom/`. No production calibration is needed to test the implementation.

### Task 3: Make session entry persistent and honest (bootstrap developer)

**Files:** modify `docs/bootstrap.md`, `docs/bootstrap.txt`, `docs/setup.md`, `ops/README.md`.

- [ ] Read the finalized schema and runtime command behavior from tasks 1–2; keep all examples aligned with `--consumer FILE [--check]` and existing TOML keys.
- [ ] Separate bootstrap into installation, consumer configuration, executor connectivity, reviewed bridge installation, explicit calibration recording, and session entry comparison. Existing trusted installers require their existing authorization; calibration does not invoke them.
- [ ] Provide one persistent block marked `loom-calibration:v1` for the consumer's applicable root instruction file, preserving existing instructions. Include exact session-entry and predelegation `--check` semantics, failure stop/review behavior, explicit read of bridge if loading is uncertain, and real verification as separate evidence.
- [ ] Explain CLI and nonCLI capability routing without brand detection: tool-enabled sessions invoke the same Bash command; plain chat reports unwired/calibration not run. Local launcher availability does not prove a model session or launch authorization.
- [ ] Provide a drift example: change consumer configuration, comparison blocks, agent explains changed field, reviews intended configuration, explicitly records and then compares again. Never advise automatically running record when check fails.
- [ ] Review examples for privacy, no secret-bearing copied outputs, no daemon/background-monitor claim, no persistent-memory guarantee, and no claim that schema 1 enforces checks inside all legacy commands. Keep offline readiness and real acceptance visibly separate.
- [ ] Run required checks and record actual statuses; manually review both bootstrap variants for semantic parity. Do not claim those checks validate provider connectivity.

### Task 4: Integrate and verify the contract (coordinator with existing developers)

**Files:** integration across the above files; evidence only under `.loom/`.

- [ ] Review all ten acceptance cases in the design against named runtime tests or explicit instruction walkthroughs; missing cases return to the owning developer.
- [ ] Exercise stubbed local, connected Orca, disconnected Orca, auto-fallback and runtime-change cases. Revalidate before the simulated delegation; assert that the prescribed caller stops on any nonzero result. Do not launch a real agent to prove an offline drill.
- [ ] Walk through a new tool-enabled nonCLI session that explicitly reads the bridge and invokes check. Separately review the plain-chat path; label any unavailable live session test as not run.
- [ ] Run exactly `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom` in a fresh integrated checkout, capturing exit codes and logs. Do not claim actual Bash 3.2 execution unless run with that interpreter; compatibility review alone is labeled as such.
- [ ] Review existing command envelopes and old consumer configs for regressions. Confirm no acceptance record is changed by calibration and that real verification still binds to its own revision/evidence.
- [ ] Report remaining limitations: cooperative bridge enforcement, local tool trust, possible drift after a check, untested real worker/provider/remote compute and absence of background monitoring. Hand off a reviewable result without committing or pushing.

## Design self-review

The stage table maps to tasks 1–3; fingerprint, envelope and path contracts map to tasks 1–2; entry/delegation and backwards compatibility map to tasks 3–4. All review-focus cases have named tests or explicit session walkthroughs. No unresolved owner decision is required; implementation organization is flexible only inside the fixed public contract.
