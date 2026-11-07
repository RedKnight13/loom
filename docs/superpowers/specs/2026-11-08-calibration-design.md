# Calibration and drift-aware bootstrap contract

Status: implementation contract, schema 1. Applies equally to CLI agents and tool-enabled sessions. Bash 3.2+, existing git, jq 1.6+, and standard utilities only.

## Initial contract for developers

- `loom calibrate --consumer FILE` explicitly records a local observation and runs only a fixed, offline, isolated workflow drill. `loom calibrate --consumer FILE --check` compares current observations to that record without writes, locks, drill execution, consumer checks, installation, or worker launch.
- Preserve the existing JSON envelope (`v,cmd,ok,state,fact,id,ticket,items,actions`). Exit 0 iff `ok:true`; exit 1 for incomplete, unwired, drifted, or failed observation; exit 2 for usage errors. `state:ready` means bootstrap prerequisites and the offline drill are current, never real project acceptance.
- One schema-1 object in `items` carries `mode`, `readiness`, `fingerprint`, `stages`, `drift`, and `acceptance`. Readiness is `ready|incomplete|unwired|drifted`; envelope state is `ready|blocked|failed`. Acceptance remains `not_run` in calibration.
- Fingerprint Loom version and executable source bytes, consumer file bytes, checkout identity, persistent instruction bridge bytes, selected executor, and tool availability. Every new session and every delegation must run `--check`; failure stops delegation. Explicit recording is required after reviewed drift; comparison never refreshes the baseline.
- Store only sanitized observations under `${LOOM_STATE:-$HOME/.loom}/calibration/<key>.json`, with private permissions, symlink refusal and same-directory atomic replacement. Never store raw paths, repository identities, hostnames, tokens, tool output, prompts, or environment dumps.
- No brand inference, daemon, silent install, automatic consumer checks, background monitoring, or claim of persistent model memory. A session unable to invoke shell execution reports `unwired` and cannot claim command evidence.

## Stages and capability boundary

| Stage | Observation | What it does not prove |
|---|---|---|
| installation | Required executable resolution; supported Bash and jq; readable Loom sources | Successful installation, authentication, or tool trust |
| configuration | Existing `loom_config` validation plus nonempty string `checks`; valid local checkout matching configured repo using existing dispatch normalization | Consumer checks pass |
| connectivity | `local`: Bash launch mechanism present; `orca`: existing read-only runtime status says reachable and ready; `auto`: existing selection rules, fingerprint the actual selection | A model is authenticated or a worker will succeed |
| instructions | Persistent bridge exists and contains the exact marker `loom-calibration:v1` | Harness loaded or obeyed it |
| drill | Fixed isolated offline fixture exercises report and envelope interpretation | Network, real worker, provider, remote compute, or project acceptance |
| acceptance | `not_run`, always, in this command | Anything about an earlier or future verification run |

A successful invocation through the current session's tool is evidence of a working shell route at that instant. The agent must separately confirm it read the bridge; calibration cannot introspect a chat platform's tool inventory or instruction loading. Claude CLI, Codex CLI, and nonCLI sessions with equivalent tools use the same protocol. Plain chat emits a clearly labeled explanation (`unwired; calibration not run`), never a fabricated command result. A shell route without permission to launch agents is not authority to delegate. Local connectivity means only the existing explicit local launch route is available; it is not automatic model discovery.

No additional consumer TOML keys are required. This preserves strict parsing and old configs. If `checks` is missing or not a nonempty string, calibration is incomplete even if the legacy parser accepts it. Calibration never evaluates `checks`, `compute_setup`, law strings, config fragments, or bridge text. Calibration additionally rejects each declared compute host unless it matches `^[A-Za-z0-9][A-Za-z0-9._-]*$`; schema 1 accepts simple host aliases only, never option-like names, whitespace, shell syntax or user/port syntax. This calibration-only tightening does not change existing command parsing. Remote compute and provider authentication are untested until separately authorized real verification.

## Exact data and states

The single `items` entry has this shape; tokens in angle brackets stand for computed values:

```json
{
  "schema": 1,
  "mode": "check",
  "readiness": "ready",
  "fingerprint": {
    "algorithm": "git-blob-sha1-v1",
    "loom_version": "<version>",
    "loom_code": "<digest>",
    "consumer": "<digest>",
    "checkout": "<digest>",
    "bridge": "<digest>",
    "tools": "<digest>",
    "executor": "local"
  },
  "stages": {
    "installation": "passed",
    "configuration": "passed",
    "connectivity": "passed",
    "instructions": "passed",
    "drill": "passed"
  },
  "drift": [],
  "acceptance": "not_run"
}
```

`mode` is `record|check`. Each stage is `passed|failed|not_run`; passed drill on check means valid recorded drill, not a newly run drill. `drift` is a sorted unique array of changed fingerprint field names, never values or raw diffs. Before a complete fingerprint exists, `fingerprint` is null; failed observations must not invent digests. `actions` is an array of fixed human-readable next steps, not executable commands. `id` and `ticket` are null. `fact` uses fixed sanitized reason text, never subprocess stderr. Envelope `v` remains Loom's version; `schema` versions the evidence format independently.

Precedence: unsafe path, invalid JSON/schema, invalid arguments or internal failure => `state:failed`, `readiness:incomplete`; required executable/selected executor unavailable => `state:blocked`, `readiness:unwired`; invalid consumer/checkout/bridge or no baseline => blocked/incomplete; valid observations unequal to baseline => blocked/drifted; otherwise passed prerequisites and passed drill => ready/ready. An unknown record schema fails closed. Unsupported flags, duplicate flags, missing/empty consumer and positional arguments are usage failures (exit 2); all other failures exit 1. Usage failures may have empty `items`. Missing jq permits a fixed literal failure envelope with `v:"unknown"`, no interpolated values, and exit 1.

Recording does not make failures ready: it reruns current observations and the fixed drill, and replaces the baseline only on complete success. Failed recording leaves the old baseline intact and returns failure. Thus explicit recording after review can establish a new fingerprint, but no command silently repairs config, modifies instructions, accepts terms, or runs an installer. Comparison cannot create even an empty state directory or update access-independent metadata such as a last-checked field.

## Fingerprint algorithm

Use the already-required `git hash-object --stdin` without `-w`, explicitly SHA-1 object format in a sanitized non-repository environment. It hashes bytes without writing objects; do not depend on the caller repository's SHA-256 setting. This is an accidental-change detector, not a cryptographic attestation or security signature. Digests of physical paths and origins are pseudonymous and may be guessable; they are not anonymization and should remain private local evidence. `LC_ALL=C` ordering and `jq -Sc` canonical JSON (one trailing newline) make composite inputs deterministic.

- `loom_code`: hash a canonical JSON array of `[relative_name, content_digest]` for `VERSION`, `ops/loom`, and every regular `ops/*.sh`, sorted by relative name. Include newly added files and deletions; refuse symlink code inputs. No unrelated documentation or Git HEAD dependency.
- `consumer`: hash exact file bytes, including comments, so all policy edits require review. Read as data through the existing parser; never source it.
- `checkout`: hash canonical JSON containing physical checkout root, resolved physical Git common directory and normalized origin identity. Bind to `LOOM_REPO` when set, otherwise cwd, consistent with dispatch. Never emit these raw inputs. Distinct clones or moved checkouts do not inherit calibration. Branch and HEAD changes alone are not bootstrap drift; real acceptance is bound to the exact verified commit independently.
- `bridge`: hash a sorted array of relative filename/content digest pairs for root `AGENTS.md` and `CLAUDE.md`, including a null marker for a missing file. At least one must be regular, readable, non-symlink and contain the literal marker `loom-calibration:v1`. Hash both if present so switching harnesses cannot bypass changed instructions. Mere marker presence is structural evidence, not proof that the instruction text is sufficient.
- `tools`: hash a canonical array of logical name, availability, digest of resolved executable path, and digest of executable bytes for Bash, git, jq, gh, and the selected Orca binary (only if selected). A missing optional Orca entry is represented explicitly. Do not record raw paths or version output. Recompute binary hashes on check. Installation requires bash, git, jq, gh; Orca only when selected. The resolved `LOOM_ORCA` override participates exactly like PATH resolution.
- `executor`: `local|orca`, chosen with existing `auto|local|orca` policy and read-only Orca status. Include availability of Orca in the tools digest even for local selection, so a newly available runtime cannot silently change the baseline. Do not store runtime IDs, host listings, or process identities.

Record key: hash canonical JSON `[physical_consumer_filename,physical_checkout_root]`; only lowercase 40-hex keys are accepted as filenames. Config or bridge edits hit the existing key and report drift, while a different consumer location/checkout reports missing evidence. Raw key inputs never leave memory. Before publishing a record, recompute fingerprint and reject changes during the drill; do the same around a check's comparison. This detects observable concurrent changes, not adversarial filesystem races.

## State and execution safety

The record is `{schema:1, fingerprint:<object>, stages:<all passed>, acceptance:"not_run", recorded_at:<UTC timestamp>}`. No free-text command output or arbitrary imported proof. Treat record content as untrusted JSON, validate exact keys, enum types, digest lengths, stage values and schema before use. Bound record reads to 64 KiB. Future real acceptance evidence belongs to existing assignment verification records (`checks_runs` and verified revision), not this baseline, and never gets promoted by calibration.

Use a dedicated calibration path resolver; do not call `loom_init` from comparison because it creates directories. Default state remains consistent with Loom; relative `LOOM_STATE` resolves against invocation cwd. Refuse symlinks in existing state ancestors, calibration directory, target record, consumer and bridge inputs; refuse non-directory state components and nonregular record/config files. Permit spaces, reject newline/control characters in input paths, and keep any filename derived from config out of the state path. Existing state must be owned by the current user and not writable by group/other; fail with a sanitized repair instruction, never chmod someone else's directory. A caller-selected hostile parent directory is outside the trust boundary; shell checks cannot eliminate TOCTOU attacks by a same-user adversary.

Recording uses umask 077, private directories (0700), files (0600), a calibration-specific mkdir lock, a unique same-directory temporary file, full JSON validation, and rename to replace the record. Lock contention fails promptly with a retry action; no automatic stale-lock deletion. Traps remove only owned temporary files and the owned lock. Interruptions preserve the previous complete record. Comparison needs no lock and sees a complete old or new record; it never rewrites either. No root privileges, global hooks, Git commits, remotes, or working-tree edits.

Probes are a fixed allowlist: executable discovery, local byte reads/hashes, Git metadata reads with optional locks disabled, supported version checks, and the existing Orca status query. No `gh auth`, network calls, provider/model requests, compute probes, plugin enumeration, or automatic executable installation. Cap runtime status waits at five seconds; on timeout mark connectivity failed/unwired. A Bash child watchdog may terminate only the exact probe it launched and reap it; no daemon or broad process matching. The `--check` path writes no temporary files; capture probe output in memory and discard it after parsing. Execution of resolved tools assumes the user's installed toolchain is trusted; hashing cannot establish that trust.

The recording drill creates a private disposable directory, isolates HOME/LOOM_STATE/LOOM_REPO/PATH and Git config, and exercises only packaged fixed fixture logic. It must use local fixture inputs, a stub executor, a synthetic worker report (`state: ready`), and interpretation through the same report parser/JSON envelope path used by Loom. The fixture may create a private clone with no origin, harvest a synthetic report, and verify a fresh fixture clone using the fixed literal command `true` from fixture-owned configuration. This is never the real consumer configuration. Assert that blocked and missing reports fail closed as well. Never call the consumer's commands, full selftest suite, real dispatch, real model, or real Orca mutation. Capture the drill's real exit code; timeout/failure is not passed. Clean up only the owned fixture directory. Fixture evidence is explicitly synthetic and never a real task completion. This narrowly scoped drill is preferable to invoking the current full selftest suite from bootstrap.

## Persistent entry and delegation contract

Bootstrap installs or offers a reviewed instruction block in the consumer's actual persistent instruction file; calibration itself never writes it. The marker names this protocol, not a universal hook. Required block semantics:

1. Read the consumer config and this project's laws; resolve the trusted Loom installation and intended checkout.
2. At every session entry, invoke `loom calibrate --consumer FILE --check` through an available execution tool, inspect exit code and the complete JSON response.
3. Repeat immediately before delegation, including after context loss, a tool reconnect, config edit, checkout change or installation update. On failure, stop delegation, explain the reason, and review drift before explicit recording.
4. If shell execution is unavailable, report unwired and do not claim installation, calibration or checks ran. If bridge loading is uncertain, explicitly read it in the current session.
5. Real acceptance requires separately authorized verification of the actual revision with captured exit codes. Installation, configuration, offline drill and prior acceptance are not substitutes.

Review of drift and permission to rebaseline are agent/user protocol, not CLI-authenticated consent. The bootstrap/session agent enforces this protocol; schema 1 does not retroactively gate every existing dispatch/start/launch command. State this limit plainly. A future runtime dispatch guard can enforce comparison inside delegation, but is not silently added to legacy commands here. No polling, background monitor, memory persistence guarantee, or universal security claim. A gap between comparison and delegation still exists.

## Acceptance cases and compatibility

Developers must test these with isolated fixtures and captured exit codes:

1. Record valid local fixture: one envelope, exit 0, ready, acceptance not_run, private complete record. Check unchanged fixture: same result, no baseline or filesystem writes, no drill rerun.
2. Missing baseline: blocked/incomplete, exit 1, state directory remains absent. Corrupt/oversized/unknown-schema baseline: failed/incomplete without overwrite.
3. Independently change version, source (including dirty source), consumer bytes, checkout identity, bridge bytes, binary resolution/bytes, selected executor: check blocks and names only changed fields. Consumer path/checkout relocation yields missing evidence. Restoring exact inputs restores validity.
4. Read-only check after drift never blesses it. Explicit successful record refreshes evidence; failed record or interrupted write preserves prior evidence. Concurrent record fails lock safely.
5. Missing tools, disconnected/timeout Orca with explicit Orca policy, and plain chat are unwired; local capability does not pretend a model was contacted. Auto fallback changes are detected.
6. Bridge missing => incomplete; marker in a regular bridge permits structural instruction stage; symlink bridge refused. Tool-enabled nonCLI session follows identical entry/check behavior.
7. Put shell substitution and command delimiters in config strings; calibration runs none. Stub forbidden installer, network, model and consumer check commands and assert zero calls. Fixture drill uses no production state, consumer hooks or real executor.
8. Unsafe state ancestors/record symlinks, path traversal attempts, whitespace/control characters, unknown/duplicate flags, invalid TOML and incompatible record types fail closed with valid sanitized envelopes.
9. No stdout, stderr, JSON record, or action contains raw local paths, repository identities, hosts, credential strings or captured tool errors. Probe failure reasons are static.
10. Existing commands and old consumer configs retain their schemas and behavior. Bootstrap readiness never changes acceptance records or claims a check passed. Existing selftest and shellcheck pass.

Implementation defaults above are architect choices within the authorized scope. No owner decision is pending. Existing explicit execution permissions and consumer laws still govern all actual delegation and verification.
