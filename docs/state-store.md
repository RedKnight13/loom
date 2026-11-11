---
layout: documentation
title: "Native durable state store (schema 2)"
---

# Native durable state store (schema 2)

S2 provides storage, not task scheduling, authorization, provider calls or launch
verification. Source `ops/state.sh` and `ops/events.sh` without changing options,
traps, cwd, umask or environment. Source by absolute path if your caller later
changes cwd. Set `LOOM_STATE` to an explicit absolute private
state directory. Every API runs in a separate bounded subprocess; no locks escape
a call. Nothing is initialized merely by sourcing a file. Legacy CLI/lib routing
is unchanged; integrating capacity fences into those entry points belongs to S8.

## API for S3, S6 and S7

All arguments are separate quoted argv values. Output is one JSON object on stdout;
diagnostics go to stderr. The functions and equivalent `bash ops/state.sh COMMAND`
commands are:

| Function | Command and arguments | Result |
| --- | --- | --- |
| `loom_state_init` | `init STORE_ID` | Immutable `{schema,store_id,created_at}`; same ID is idempotent, another ID refused. |
| `loom_state_transact` | `transact REQUEST_FILE` | Durable outcome below; retries return the original outcome. |
| `loom_state_get` | `get KIND ID` | Entity `{schema,kind,id,revision,run_id,epoch,data}`; missing is a refusal. |
| `loom_state_list` | `list KIND [AFTER_ID [LIMIT]]` | `{items,next_cursor}`, sorted opaque IDs, exclusive cursor; limit 1–100, default 100. |
| `loom_state_operation` | `operation ACTOR OP KEY` | Immutable dedupe entry with `actor_id,op,key,operation_id,digest,outcome`. |
| `loom_state_replay` | `replay` | Rebuild snapshot; return `{schema,store_id,sequence,event_sequence,last_digest}`. |
| `loom_state_legacy_get` | `legacy-get ID` | Explicit `{schema:1,read_only:true,id,origin_provider,identity:"unknown",record}` projection; no migration. |
| `loom_events_read` | `bash ops/events.sh AFTER_SEQUENCE LIMIT` | `{events,next_sequence}`, exclusive sequence cursor; non-consuming. |

Exit 0 means successful storage/read; exit 2 means refused, invalid request, corrupt
store, conflict or missing capability. Exit 1 means storage failure and may have
crossed commit: replay the identical operation before acting. Timeout returns 124
(or 137 if forced termination); any interrupted mutation has an unknown outcome.
Never infer absence of an effect from nonzero exit. Diagnostics include
`revision_conflict`, `owner_fenced`, `idempotency_conflict`, `identity_mismatch`,
`resource_busy`, `quota_exceeded`, `cursor_expired`, `unsupported_capability`,
`unsafe_path`, `corrupt_journal` or `journal_gap`. This is an internal sourceable
storage API, not a protocol 1.0 response envelope; the facade maps these results.

`LOOM_STATE_TIMEOUT_MS` is 1–300000 (default 30000). Lock acquisition waits at most
five seconds within that overall deadline. Calls are one-shot, never pollers.
Requests are at most 1 MiB; transactions 4 MiB; journal 64 MiB / 4096 transactions.
All limits fail closed. No pruning is implemented: dedupe entries and history stay
for the lifetime of the store. Quota exhaustion requires operator-managed retention
or a future migration, never silently forgetting a key and replaying an effect.

## Atomic transaction format

Write the request with `jq -cS ... > request.json`: **exactly canonical sorted,
compact jq JSON plus one newline**. This narrower internal format rejects duplicate
keys, noncanonical/lossy numbers, trailing documents and invalid UTF-8 before
mutation. IDs are opaque UTF-8 strings (1–128 bytes), never filesystem paths.
Revisions/epochs are nonnegative safe JSON integers. Creation uses null expected
revision and produces revision 1; each subsequent replacement increments it.
Null is explicit; all envelope fields below are required and unknown fields fail.

```json
{
  "schema": 2,
  "store_id": "consumer-example",
  "operation_id": "reserve-example",
  "idempotency_key": "reserve-example",
  "op": "capacity.reserve",
  "actor": {"id": "conductor-example", "run_id": "run-example", "epoch": 0},
  "target": {"host_id": "compute-primary"},
  "checks": [{"kind": "run", "id": "run-example", "revision": 1}],
  "changes": [{
    "kind": "attempt", "id": "attempt-example", "expected_revision": null,
    "run_id": "run-example", "epoch": 0,
    "data": {"execution_state": "reserved", "host_id": "compute-primary"}
  }, {
    "kind": "run", "id": "run-example", "expected_revision": 1,
    "run_id": "run-example", "epoch": 0,
    "data": {"owner_id": "conductor-example", "occupied_slots": 1}
  }],
  "events": [{
    "type": "attempt.reserved", "entity_ids": ["attempt-example"],
    "payload": {"host_id": "compute-primary"}, "observed_at": null
  }],
  "result": {"attempt_id": "attempt-example"}
}
```

The display example must be canonicalized before use. It illustrates storage CAS,
not a complete S6 run or execution manifest. `data`, `target`, `payload` and `result`
are JSON objects owned and validated by the calling domain layer; the storage
schema closes the envelope, not future domain payloads. Do not pass unvalidated
wire input straight through. Domain validators enforce the required run/task/
assignment/attempt/message/delivery/gate/operation fields in the architecture,
closed protocol records, transitions, dependencies, resolver authorization,
immutable spec/placement and evidence. Storage alone cannot approve work.

Kinds are `run`, `task`, `assignment`, `attempt`, `message`, `delivery`, `gate`,
`operation`, `config`, `host`, `profile`. No physical deletion API exists; use
revisioned domain tombstones. Every change fully replaces `data`; preserve fields
when updating. Up to 100 unique kind/ID changes, 100 unique checks and 1–100 events
are accepted. `checks` validate existing revisions without changing those entities.
Each change also performs CAS against its expected revision, atomically with all
other changes. Missing/stale records return `revision_conflict`, with no journal
transaction and no changed entities.

Scoped mutations carry the current run ID and epoch; the journal rechecks the run
under lock. A new run requires epoch 0, `run_id == id`, and `data.owner_id` equal
to the actor ID. Every changed/checked record must be in the actor's run. Run epoch
can remain unchanged or increase by exactly one; changing `data.owner_id` requires
the increment. The domain layer must authorize takeover/release and require a
reason before submitting that change. Epoch checks fence stale callers but do not
authorize a caller just because it knows the epoch. Workers may use their own actor
IDs only after S6/S7 validates their exact assignment/attempt binding.

Store-level `config`, `host` and `profile` records use `actor.run_id:null`, epoch 0
and null record run IDs. This is the S3 seam for a **shared capacity ledger**:
read one host/config ledger, compute occupancy including unknown attempts, then
CAS its revision when reserving/releasing a slot. Competing writers with the same
revision cannot both reserve. A run-scoped batch cannot update a global ledger;
use the global ledger as the authoritative reservation record (pin run/attempt IDs
in its data), then reconcile a separate run record via an explicit storage
operation. Never count a list and blindly create different records: that is not
an atomic capacity check. Run-local capacity uses a changed run revision in the
same batch as the attempt, as in the example.

Dedupe scope is `(store_id, actor.id, op, idempotency_key)`. The digest covers the
**entire canonical request**, including operation ID, checks, changes and result.
An exact retry returns the original outcome even if current revisions/epoch have
advanced. Changing anything with that key is `idempotency_conflict`; reusing an
operation ID for another request is also refused. Resolve uncertain outcomes via
this lookup/retry, never by allocating a fresh launch operation.

A successful outcome is:

```json
{"schema":2,"store_id":"consumer-example","sequence":2,"transaction_id":"opaque-transaction","operation_id":"reserve-example","durable":true,"revisions":[{"kind":"attempt","id":"attempt-example","revision":1},{"kind":"run","id":"run-example","revision":2}],"result":{"attempt_id":"attempt-example"}}
```

Each storage operation is immutable. For S3/S6 execution intents or S7 delivery
stages, create a revisioned `operation` entity with pinned target, canonical wire
request digest, actor/epoch, stage, receipts and effects. Commit intent with one
storage operation ID, release the lock, invoke the provider, and commit a separate
idempotent reconciliation with entity revision/run epoch checks. Record stale
responses as domain evidence; do not overwrite newer state. Provider and wire
operation IDs remain the original pinned IDs, not the new storage mutation ID.

## Journal, recovery and locking

Only `$LOOM_STATE/v2/` is written. `store.json` pins the installation ID.
`journal/0000000000000001.json` onward are immutable transactions containing the
canonical request, digest, events and operation outcome; each names the prior
transaction digest. The digest is `git-blob-sha1-v1:` plus `git hash-object` output,
a drift detector, not an authenticity signature. Event sequences are monotonic
across transactions; each event includes actor/epoch, entity IDs, previous
revisions, type, payload, recorded/observed times, transaction and event IDs.

Under a short lock, validate requests/revisions, allocate a sequence, write an
unpredictable same-directory temporary file, `sync -f` the file, rename, then
`sync -f` the directory. Only then can stdout contain `durable:true`. Snapshot
publication is another atomic replace, but snapshot failure cannot revoke a
committed journal transaction. Every read rebuilds from the journal and verifies
the sequence, canonical bytes, digest chain, CAS/epoch rules and derived events/
outcomes; no stale snapshot can supply authority. A recognizable snapshot ahead
of the journal blocks as evidence of missing committed history. Removing a damaged
projection is an explicit operator recovery action, not an automatic truncation
repair; without a retained watermark, deletion of an entire journal suffix cannot
be detected from the remaining hash chain alone. Recovery flushes the journal
filesystem before returning any recovered durable outcome. Partial `.tmp.*` files
are ignored; committed malformed/gapped/conflicting files are never skipped.

`guard` is a permanent flock inode, never removed. `lock.json` records host digest,
boot ID, PID namespace, PID/start ticks and random nonce. Metadata replacement and
nonce comparison occur while holding that same kernel guard. Dead/reused local
PID owners may be reclaimed; exact live owners and foreign/boot/namespace-ambiguous
owners block. There is no unsafe lock-breaking command. Unlock compares the nonce;
a concurrent reclaimer cannot unlink a replacement owner's lock. Locks never span
remote calls, provider invocations or agent waits. Crash residue is private and
may be inspected; no automated history deletion or remote signaling occurs.

Linux `/proc`, `setsid`, util-linux `flock` and GNU `sync -f` are probed; missing
primitives return `unsupported_capability`. Existing Bash/Git/jq/system tools are
the only runtime dependencies. Unsupported platforms fail closed. This does not
claim power-loss guarantees on untested network filesystems. Tests inject process
crashes and barrier failures on the test host; they do not emulate hardware caches.

State directories/files must be owned by the effective user and inaccessible to
group/other; symlinked roots, ancestors, nested records, hardlinked files and
special files are refused. Shared ancestors must be safe root-owned sticky
directories or non-writable by others. The trusted same-account model remains:
this is not protection against an adversarial process racing filesystem changes
under the same UID. Paths are never derived from opaque entity IDs.

Legacy projections require an explicit legacy ID, validate a bounded assignment
shape and report identity as unknown. They work without initializing v2, preserve
the original executor route, and never write or import the record. Root `*.json`
iteration still sees only legacy records. No dual authoritative writes are made.
Old dispatchers themselves are unchanged in this slice; they must gain the S8
active-v2 capacity/ownership fence before new v2 execution is enabled.

## Validation and fault injection

Run `bash tests/state/run.sh`, followed by
`bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`.
`LOOM_STATE_TESTING=1` enables explicit test-only faults:
`LOOM_STATE_TEST_CRASH=journal.after_rename` kills the storage subprocess;
`LOOM_STATE_TEST_FAIL=journal.after_write` simulates a storage failure.
Labels are `metadata`, `lock`, `journal`, `snapshot`; boundaries are `before_write`,
`after_write`, `after_file_flush`, `after_rename`, `after_directory_flush`.
These controls never fabricate an acknowledgement and are unused by default.
