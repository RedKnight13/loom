---
layout: documentation
title: "Native configuration, policy and discovery"
---

# Native configuration, policy and discovery

S3 is an isolated, sourceable policy layer. It requires Bash, jq, Git and existing
system tools; it requires no orchestrator, agent executable or service. Source
`ops/policy.sh`, then `ops/discover.sh`. Sourcing changes no shell options, traps,
working directory, environment or umask. Functions return JSON on stdout and
diagnostics on stderr. Success is exit 0; validation/policy refusal is exit 2;
store read failures retain their exit status. No function launches an agent,
contacts a service, changes operator configuration or selects a fallback.

## Closed configuration and registries

`schemas/config-v2/{config,hosts,profiles}.json` describe the three documents.
`validate.jq` is the runtime validator, including byte bounds, registry uniqueness,
canonical paths and selected-host membership. All fields are required, including
nullable model/effort/mappings. Unknown fields or schema versions are refused.
Inputs must be single UTF-8 JSON objects, at most 1 MiB. Duplicate keys (including
escaped aliases), NUL, fractional/exponent number tokens and multiple documents
are refused before interpretation. IDs are opaque strings, never path fragments.

Inputs are explicit canonical absolute filenames owned by the current user and
not writable by group/other. Links in any path component, hardlinked files and
dot/traversal components are refused. Ancestors must be owned by the user or root
and not writable by others, except root-owned sticky directories. These checks
and before/after content digests detect
mistakes and configuration drift; the trusted same-account execution model still
applies. They are not a sandbox against hostile concurrent same-UID mutation.

The following values are synthetic; real destinations and executable locations
belong in operator-owned configuration, outside tracked examples.

```json
{
  "schema": 2,
  "repo": "example/project",
  "execution": {
    "provider": "native",
    "transport": "ssh",
    "placement": {
      "allowed_hosts": ["compute-primary"],
      "selection": "explicit",
      "selected_host": "compute-primary",
      "allow_local": false,
      "fallback": "deny"
    },
    "agent_profile": "worker",
    "model": "opaque-model",
    "effort": null
  },
  "limits": {"workers": 2, "operation_timeout_ms": 30000},
  "ticket_provider": "github"
}
```

Host registry:

```json
{
  "schema": 2,
  "hosts": [{
    "id": "compute-primary",
    "transport": "ssh",
    "destination": "compute.example.invalid",
    "workspace_root": "/srv/workspaces",
    "identity": "pinned-host-key",
    "helper": {
      "version": "1.0",
      "digest": "git-blob-sha1-v1:1111111111111111111111111111111111111111"
    }
  }]
}
```

Agent and optional command-adapter registry:

```json
{
  "schema": 2,
  "agents": [{
    "id": "worker",
    "executable": "/opt/agent/bin/agent",
    "argv": ["--batch"],
    "prompt_ingress": "stdin",
    "model": {"argv": ["--model"], "values": ["opaque-model"]},
    "effort": null
  }],
  "adapters": [{
    "id": "example-adapter",
    "executable": "/opt/adapter/bin/adapter",
    "argv": ["--json"]
  }]
}
```

Agent executable and argv are separate; resolution constructs an argv array with
the executable at index zero, base arguments, then explicit model and effort
mapping arguments and their exact values. Null means no mapping arguments are
added. The total agent argv cannot exceed S1's 256 entries. Prompt ingress is
`stdin` or `file`; S4 handles prompt transfer and never evaluates text as a shell
command. Adapter executable/prefix are retained separately. There are no command
strings, environment-value fields or credential-file fields.

`model.values` and `effort.values` are operator allowlists, not availability
catalogs. A nonnull selection needs both a mapping and an exact allowlist match;
unknown support is refused without dropping flags. Runtime capability negotiation
must independently prove model/effort selection support before launch. Agent
profile ID also serves as this layer's configured agent ID; it does not invent a
provider-specific runtime agent ID.

Only explicit host selection is implemented. SSH destinations are opaque trusted
registry values, never shell commands; the transport must verify the pinned host
identity and helper digest at execution. Process transport requires an explicit
`allow_local:true` and matching process host entry (`destination:null`). Real-agent
deployment remains remote-only unless separately authorized by the owner. No
environment override weakens that setting, and no provider/SSH failure changes
transport, provider, host, model or effort. Presence of an orchestrator never
changes policy. Local transport is available for explicitly allowed fixtures.

## Frozen sourceable API

| Function | Output / behavior |
| --- | --- |
| `loom_policy_validate KIND FILE` | Validate `config`, `hosts`, `profiles`, `context`, `ledger`, `observation` or `discovery-evidence`; no stdout on success. |
| `loom_policy_resolve CONFIG HOSTS PROFILES` | Complete selection pin as JSON; no writes. |
| `loom_policy_check PIN CONFIG HOSTS PROFILES` | Re-resolve and compare the complete pin; any binding or input-byte change refuses. |
| `loom_policy_scope` | Read JSON stdin, hash sorted compact JSON plus newline; print the S1 digest spelling. |
| `loom_discover CONFIG HOSTS PROFILES [EVIDENCE]` | Passive discovery projection described below. |
| `loom_policy_capacity_init_request STORE_ID ACTOR_ID` | Canonical S2 ledger-creation transaction; creation is a separate explicit operation. |
| `loom_policy_reserve_request CONFIG HOSTS PROFILES CONTEXT` | Read authoritative ledger; emit a canonical S2 reservation CAS transaction. |
| `loom_policy_observe_request CONTEXT OBSERVATION` | Emit a canonical S2 CAS transaction updating one exact-scope reservation. |
| `loom_policy_capacity CONFIG HOSTS PROFILES` | Current configured limit, occupied/reserved/live/unknown/available counts, ledger revision and observation time. |

Pins retain the complete validated selected host/profile/adapter, placement,
provider, transport, exact model/effort including null, argv, limits, repo and
ticket provider. `config_digest`, `hosts_digest`, `profiles_digest` hash exact
input bytes. `profile_digest` and nullable `adapter_digest` hash canonical selected
objects. All use S1 `git-blob-sha1-v1:` spelling. The canonical complete pin digest
is the discovery/reservation scope; any input revision invalidates old evidence.
These hashes detect drift, not authenticity.

The caller persists this pin before launch and binds it to the run, assignment,
source/base SHA, setup/check policy, capability snapshot and execution intent.
Those workflow fields are owned by S6/S4, not guessed by config resolution.
`loom_policy_check` detects edits before a new start or retry; reconciliation of
an existing attempt still targets its persisted original binding. A new config
cannot retarget existing work or authorize a second attempt while its slot is
unresolved. The caller must recheck the pin at its launch boundary.

## Discovery evidence

This slice performs **no active probes**. It does not inspect PATH for agents,
run version/list commands, open SSH, inspect authentication, read credential files
or environment credential values, or query an orchestrator. With only config,
`configured.value` is true and installed/reachable/launch-verified are null.
Provider capabilities and authentication remain unknown. This permits offline
inspection even when every execution service is unavailable.

The optional evidence file is a normalized, caller-verified record, not raw
provider output. The caller must validate underlying receipts/artifacts before
passing it here. It is not a user-supplied proof of authorization.

```json
{
  "schema": 2,
  "scope_digest": "git-blob-sha1-v1:2222222222222222222222222222222222222222",
  "observations": [{
    "dimension": "installed",
    "value": true,
    "source": "bounded_version_probe",
    "observed_at": "2026-01-01T00:00:00Z",
    "evidence_ref": "evidence/version",
    "attempt_id": null
  }]
}
```

Each dimension appears at most once. Nonnull observations require a bounded
artifact reference. `installed:true` requires `bounded_version_probe` on the
exact target host; false requires `missing_executable`. `reachable` uses
`transport_probe`. `launch_verified` requires `authorized_attempt`, a concrete
attempt ID and evidence of expected startup/prompt acceptance. A null observation
uses `unavailable`. Missing, differently scoped, future or older-than-300-second
observations become null with an explicit source reason. No dimension is inferred
from another: an installed CLI never proves model access or authentication.

Output is a local schema-2 projection with `provider`, `host`, `authentication`,
`scope_digest` and `profiles`. Each profile uses S1 discovery field names and
dimension shapes (`value`, `source`, `observed_at`, `scope_digest`). Reachability
belongs to the separate host inventory because S1's closed profile shape does
not contain it. The facade can use `{profiles: result.profiles}` for
`agents.discover`; it must not put extra local fields into a closed S1 response.
Active version/transport/model probes remain the execution adapter's integration
responsibility; they require bounded safe commands and explicit permission for
service contact. No active probing or real launch is claimed by this module.

## Durable capacity integration

Source the S2 `ops/state.sh` API and set explicit `LOOM_STATE`; initialize the
authority store with `loom_state_init STORE_ID`. S3 never silently initializes or
falls back to legacy state. It reads only S2's global config entity
`loom.policy.capacity`, using `loom_state_get`. Missing/corrupt/unavailable stores
fail closed. Query results describe declared concurrency and authoritative
reservations, not hardware or model capacity; `observed_constraints` is empty
until an integration supplies actual observations.

The initialization request creates ledger data `{schema:2,slots:[]}`. Every
reservation changes this same revision with S2 CAS, even across different runs or
hosts. Each slot contains `attempt_id`, `run_id`, `scope_digest` and `state`.
`reserved`, `running` and `unknown` all count; only `settled` does not. Unknown
ownership, connection loss, abandoned work and retained resources never implicitly
free a slot. Existing slots are not pruned or reused; storage quotas fail closed.

Caller context is closed JSON:

```json
{
  "schema": 2,
  "store_id": "consumer-example",
  "actor_id": "conductor-example",
  "operation_id": "reserve-example",
  "idempotency_key": "reserve-example",
  "run_id": "run-example",
  "attempt_id": "attempt-example"
}
```

The global ledger uses store-level actor `{id:actor_id,run_id:null,epoch:0}`. Its
reservation is authoritative for capacity; S2 deliberately cannot atomically
change a global ledger and a run-scoped entity. Commit the reservation first,
then create the separately epoch-fenced run/attempt intent, then launch. A crash
between these steps retains capacity and requires reconciliation. A reservation
alone does **not** prove current run ownership or authorize execution.

For each generated transaction, retain the **exact** canonical stdout bytes in a
private request file before calling `loom_state_transact REQUEST_FILE`. Generation
has no effects. Only S2's durable success acknowledges reservation. The result
includes the complete `policy_pin` and `scope_digest`, persisted in the journal.
Never launch on failure, timeout or absent acknowledgement. Resolve uncertainty
with `loom_state_operation ACTOR_ID OP KEY` or replay the identical transaction;
do not regenerate it from a newer ledger or allocate another operation ID.
S2's immutable whole-request dedupe supplies idempotency. A confirmed stale-CAS
refusal permits re-reading capacity and building a new authorized transaction;
an uncertain commit does not. No locks span provider calls.

Observation input is closed `{schema:2,scope_digest,state,evidence_ref,
confirmed_stopped}`. State is `running`, `unknown` or `settled`. The current slot
must match both run/attempt and scope and must not already be settled.
`settled` requires `confirmed_stopped:true`; other observations require false.
Only the authorized core may produce that normalized confirmation after validating
exact identity/group exit or proven pre-exec failure. Successful stop-command exit,
silence or an arbitrary provider boolean are insufficient. S3 validates the
normalized structure and CAS, not external evidence authenticity. Evidence remains
in the S2 event. Settlement is a distinct operation with a distinct key.

## Validation and integration limits

Run `bash tests/policy/run.sh` for deterministic synthetic CAS checks. This fake
uses no durable journal and proves no persistence behavior. Run
`bash tests/policy/run.sh --state-api /absolute/path/to/ops/state.sh` against S2 for
actual store reservation contention, exact replay, unknown occupancy and settlement.
The latter exercises S2 directly without copying its modules. Captured exits and
the tested S2 file hashes belong in `.loom/validation.md` and `.loom/` evidence.

The focused suite also checks denied local/host/model/provider changes, config and
registry mutation, duplicate/traversal/link rejection, no fallback or implicit
probe, unavailable/stale evidence and no credential-path expansion. Run the
existing `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom` separately.

Legacy TOML parsing, legacy explicit-Orca selection, CLI dispatch and all existing
entry points are untouched. S3 does not pretend v1 is v2. Shared hooks, the active-v2
fence for old dispatchers, full S1 response envelopes, active safe probes, workflow
authorization and launch-boundary verification remain serialized conductor
integration work. Real-store tests cover this seam, not those pending hooks or
real agents, hardware failure, model availability or remote process persistence.
