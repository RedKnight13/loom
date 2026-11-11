---
layout: documentation
title: "Protocol 1.0 adapter boundary"
---

# Protocol 1.0 adapter boundary

Runtime routing is pending. `ops/loom`, dispatch, native execution, coordination,
mail transport, collection and existing compatibility routes do not use this
module yet. This slice provides wire validation, negotiation and a bounded
command-adapter boundary. The offline fixtures use Agni fake adapters only;
real-provider compatibility and real-agent smoke are **not run**.

The normative structural contracts are
[`execution-v1/contract.json`](https://github.com/RedKnight13/loom/blob/main/schemas/execution-v1/contract.json) and
[`coordination-v1/contract.json`](https://github.com/RedKnight13/loom/blob/main/schemas/coordination-v1/contract.json).
`request.json` and `response.json` are standard 2020-12 entry points. The
[contract appendix](protocol-contract.html) resolves the architect's previously
unspecified nested records, enums and capability names. Protocol version, state
schema and provider release version remain separate.

## Sourceable and CLI interfaces

Sourcing `ops/protocol.sh` defines functions only. It does not run a main, source
`lib.sh`, change options, install traps, set environment variables or touch state.
Public functions use subshells for temporary files, private umasks and cleanup.
No function writes a Loom authority or assignment record.

| Interface | Input | Output and return |
| --- | --- | --- |
| `loom_protocol_validate request FILE` | A newline-terminated request file | Silent; 0 valid, 2 invalid. |
| `loom_protocol_validate response FILE [REQUEST_FILE]` | Response, optionally the exact request | Silent; 0 valid, 2 invalid. With the request, verifies correlation and operation-specific limits/IDs. |
| `loom_protocol_validate adapter_config FILE` | Closed, pinned adapter configuration | Silent; 0 valid, 2 invalid. Does not launch a command. |
| `loom_protocol_digest FILE` | Exact file bytes | `git-blob-sha1-v1:<40 lowercase hex>`; a drift digest, not an authenticity signature. |
| `loom_protocol_serve` | One request on stdin | One response on stdout; hello negotiation or an effect-free unsupported-operation refusal. |
| `loom_protocol_invoke CONFIG CONFIG_DIGEST` | One execution request on stdin | Negotiates, then calls only the configured adapter; one normalized response on stdout. |

CLI equivalents are `bash ops/protocol.sh [serve]`,
`bash ops/protocol.sh validate KIND FILE [REQUEST_FILE]`, and
`bash ops/protocol.sh invoke CONFIG CONFIG_DIGEST`. `serve` is the default.
`_call` is a private subprocess helper, not a public adapter or worker API.

```bash
source ops/protocol.sh
loom_protocol_validate request request.json
loom_protocol_validate adapter_config adapter.json
# Invoke only after the caller has authorized the exact configured operation.
config_digest=$(loom_protocol_digest adapter.json)
loom_protocol_invoke adapter.json "$config_digest" < request.json
```

Transport returns 0 for a valid `ok:true` completed/accepted/pending result, 2 for
a refusal and 1 for failed/unknown. `validate` is a silent predicate, not a wire
endpoint. Every wire endpoint returns JSON for invalid requests. If input cannot
be safely parsed, correlation uses `invalid-request`, `invalid`, null operation
and null target. An unsupported wire version receives a 1.0 refusal; it is not
silently accepted as 1.0. Unknown operation names are echoed in an error response;
only success responses require an operation-specific registered result.

## Configuration and invocation

`$defs.adapter_config` in the execution contract is the configuration schema:
`schema:1`, canonical absolute `executable`, `executable_digest`, string-array
`argv` prefix, capability records, and all seven `limits` fields. Config bytes
must end with newline. Pin the digest of the exact file, not a reserialized copy.
The invoker snapshots the config, verifies that digest and checks the executable
digest before and after every call. Symlink/noncanonical/nonexecutable targets,
command strings and unknown config fields are refused. Transitive interpreter,
library and helper dependencies remain part of the trusted installation; this
is not an authenticity or hostile same-account sandbox.

The adapter receives exactly the request on stdin and is executed as one
executable plus an argv array. Empty arguments, spaces, newlines, quotes,
backticks and dollar signs stay literal. There is no shell command-string,
selector splitting, model/host substitution or executor fallback. All processes
in the fixture runner are fake adapters, not model workers.

The environment allowlist is fixed: `PATH=/usr/bin:/bin`, `LC_ALL=C.UTF-8`,
`LANG=C.UTF-8`, and `HOME`/`TMPDIR` pointing to a fresh private operation directory.
No ambient credentials, SSH agent sockets, model settings, exported shell
functions or shell startup hooks are passed. Raw adapter stderr is drained and
bounded but withheld from the caller; only a fixed diagnostic label is emitted.
The module neither reads credential stores nor publishes trace exports.

An effectful call requires supported capabilities in both the pinned config and
the validated hello result. Missing/unknown is never supported. Hello offers
exact version pairs; 1.0 is currently the only supported pair, so intersection
selects 1.0 or refuses. Config and negotiated numeric limits intersect using
minimums. Model/effort selection requires the corresponding capabilities even
when the provider supports start. Live/boundary prompt selection is explicit.
Coordination requests are refused before calling any command adapter.

The command subprocess uses GNU `timeout` as the owned process-group leader;
the private helper remains alive after TERM until timeout performs its bounded group KILL, and verifies/captures that group's PID, PGID, SID, start ticks
and boot ID before starting the adapter. Timeout signals its own group while it
is the identity anchor, with a 100 ms KILL cleanup allowance. Negotiation and invocation share the request deadline; bounded validation and receipt formatting also take time. The caller never
issues an external kill to a remembered PGID. Bounded writers continue draining;
the helper waits for the writers as well as the adapter, so descendants holding
pipes open remain inside the deadline. This mechanism controls the short adapter
command only. Durable worker/process lifecycle, escape containment and SSH
transport are future slices; it must not be reused as proof that a worker stopped.

The `loom.transport` response extension records captured transport exit,
nullable captured adapter wait exit, config/executable/request/invocation and
capability digests, group identity, overflow flags and a fixed reason. A final validation pass checks every normalized response, including extension counts and depth; a normalization failure after a possible effect becomes bounded unknown. An adapter
exit is never an agent/check exit. A valid provider failure retains its error and
effects. Missing/mixed/partial output, wrong IDs, exit disagreement, timeout or
overflow after possible mutation produces `unknown`, `after_reconcile`, and an
unknown effect. No automatic retry follows. A preflight refusal has no effects;
a failed hello is preserved under `loom.negotiation` and the requested operation
is not invoked. Ephemeral raw streams are removed on return; the caller must
persist the returned receipt and digests before making a durable claim.

## Validation and integration

The runtime uses the checked-in schema definitions through the restricted jq
interpreter in `schemas/execution-v1/validate.jq`. It also checks wire constraints
that JSON Schema does not express: duplicate decoded keys, UTF-8, a single
newline-terminated object, safe finite numbers, decoded byte counts, depth/node
bounds, exact request/response IDs and cross-field identity. `x-loom-*` describes
these mandatory wire constraints; ordinary JSON Schema validation alone is not
sufficient conformance. All nested core records are closed. Namespaced extension
values are optional data and remain subject to wire size/depth/NUL constraints.

Run `bash tests/contract/run.sh` for the reusable offline conformance suite. It
uses `tests/contract/fixtures/operations.json` and the fake adapter. The reusable `bash tests/contract/conformance.sh CONFIG CONFIG_DIGEST CASES_JSON` runner takes a config pinning the executable, capability fixture and argv transport selector, plus cases containing request, exit, status and error_code. It does not select or fall back to an adapter. The normal
repository gate remains `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`;
this slice does not insert a shared selftest hook. Runtime requires the current
Linux Bash, Git, jq, awk, iconv, coreutils (including GNU timeout), procps and
`/proc` toolchain; no package/runtime JSON Schema library is added.

S2 must persist canonical operations, capability snapshots, invocation digests
and receipts before acknowledging effects. S3 must supply approved immutable
config/host/profile bindings and validate policy before invocation. S4/S5 own
real process/SSH identity, gated launch, durable wait evidence and stop/reconcile;
the contract helper provides none of those worker lifecycle guarantees. S6/S7
own store resolution, actor/epoch authority, revision CAS, DAG/gates and mail
leases. S8 owns facade routing. These callers must still check entity existence,
authority and durable state; shape validation does not grant them. The conductor
owns the serialized selftest/CLI hooks and architect review of this frozen wire
contract before later slices depend on it.
