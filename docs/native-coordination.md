---
layout: documentation
title: "Native coordination authority"
---

# Native coordination authority

S6 implements the closed protocol 1 run, task and gate operations in
`ops/coordination.sh`. It is safe to source: no options, traps, environment,
working directory or state change until a function is called. It launches no
processes, sends no messages, and registers no shared CLI commands.

Source S1/S2/S3 from their installed module locations, or set the trusted
installation overrides `LOOM_COORDINATION_PROTOCOL_MODULE`,
`LOOM_COORDINATION_STATE_MODULE`, and `LOOM_COORDINATION_POLICY_MODULE` to actual
module files. Their schemas remain beside their original modules; dependencies
are not copied into this slice.

| Entry point | Contract |
| --- | --- |
| `loom_coordination_handle CONTEXT REQUEST` | One closed S1 `loom.coordination` JSON request file, one S1 response. |
| `loom_coordination_serve CONTEXT` | The same API with one bounded request on stdin. |
| `loom_coordination_authorize CONTEXT PLAN` | Internal launch authorization, returning the S4 `{capacity_receipt,launch_receipt}` document. |

Executable forms are `bash ops/coordination.sh handle CONTEXT REQUEST`,
`serve CONTEXT`, and `authorize CONTEXT PLAN`. Handle uses the wire deadline;
authorize has a 30-second deadline. Read/validation refusals return 2, durable
success returns 0, and uncertain storage failures return 1 (authorize also retains
S2/timeout exit codes). Any nonzero mutation outcome requires inspecting/replaying
the same operation before another attempt. Success authorizes a particular
attempt; it does not prove execution, completion, acceptance or capacity release.

## Provisioned authority context

The context is an operator-installed private mode-0600 JSON file, not a wire
argument uploaded by an agent. Canonical absolute paths, safe ancestors, ownership,
links and size bounds use S3 checks. The authority store must already exist and
match `store_id`; S3's global capacity ledger must already be initialized.

```json
{
  "schema": 1,
  "state_root": "/srv/loom/authority",
  "store_id": "consumer-example",
  "actor_id": "owner-example",
  "runs": ["run-example"],
  "create_runs": true,
  "claims": [],
  "proofs": [],
  "config": "/srv/loom/config.json",
  "hosts": "/srv/loom/hosts.json",
  "profiles": "/srv/loom/profiles.json"
}
```

The context fixes the authenticated actor independently of request bodies,
extensions and evidence references. A service must choose this file through its
authenticated transport/session binding. Allowing a caller to choose or rewrite
it grants that caller authority; hashes are drift detection, not signatures.
Same-account hostile code is outside the S2/S3 trust model.

`run.create` uses the nonnull `actor.run_id` as the new run ID; owner must equal
the authenticated actor, epoch must be zero, and parent runs are currently refused.
Task and gate IDs are deterministic opaque hashes of actor/operation/idempotency
key, returned by their create operations. Targets must be all null for wire
coordination operations. Unknown args and extensions never provide an authority
escape hatch. `run.use` only reads/selects context; it cannot claim ownership.

A claim requires an exact operator-provisioned entry in `claims` with
`run_id`, `expected_owner`, `expected_revision`, `epoch`, and `reason`, matching
the request and current run. The claim increments the epoch once, with S2 CAS.
An unresolved preparation or active/unknown attempt refuses takeover because S4
cannot yet prove host fencing. Silence, a crashed owner or disconnected host does
not release ownership or capacity. Competing claims cannot both succeed.

The run aggregate is the graph authority. Task/gate/attempt/assignment entities
are transactionally maintained projections for S7/S8; callers must not mutate
them directly. Every mutation changes the run revision, so snapshot validation
and graph changes are fenced by one atomic S2 CAS. Graphs are bounded to 80 tasks
and 80 gates per run; S2 transaction size/record quotas also apply.

Dependencies must already exist in the same run. Missing, self, cyclic and
cross-run references are refused. Both dependency policies conservatively require
an accepted successful result; this implementation does not treat settled failure
as success. The closed protocol has no graph-edit operation: dependency and spec
fields are immutable, including during execution. Readiness is recomputed after
gate decisions and task acceptance in the same transaction. No background runner
or implicit scheduling exists.

Gate options are explicit `approved`, `rejected`, `cancelled` values; arbitrary
option-to-approval mappings are refused. Only the designated authenticated resolver
or current owner may resolve an open gate at the expected revision, with evidence.
No timer or absence of response approves it. Opening a gate while running changes
the task to waiting and records `stop_requested:true` on the attempt. That flag is
an authority request, not a signal receipt or proof of pause/exit.

## Completion evidence

`task.update` cannot directly enter running; only authorization can reserve an
execution attempt. Ready means prerequisites satisfied. Mail/ack/UI/report text
cannot enter review, fail a task, or accept a result. Trusted workflow integration
must verify evidence first, then provision an exact proof in `proofs`. All proofs
bind `kind`, `run_id`, `task_id`, current task `revision`, `epoch`, latest
`attempt_id`, and `evidence_ref` included in the request's `evidence_refs`.

* `harvest` additionally requires `confirmed_stopped:true`, `quiescent:true`,
  `current_report:true`, `report_state:"ready"`, a `report_digest`, and `exit_code:0`.
  It moves the task to review and marks the attempt exited.
* `settlement` requires `confirmed_stopped:true`, `quiescent:true` to record failure.
* `accept` requires review state, `reviewed:true`, `check_exit:0`, identical
  `checked_sha`, `collected_sha`, and `current_sha`, and `config_digest` equal to
  the attempt's policy pin plus `manifest_digest` equal to the bound execution
  manifest. Only this sets the accepted result and readies dependents.

The exact verified completion proof is retained in the durable event; launch
proofs are retained with the preparation operation. These normalized proofs must come from a verified importer of captured process,
report, check and review evidence. This slice does not implement harvest/check
execution or validate external provider artifacts. The wire caller cannot supply
proofs. Cancelling/waiting does not settle an attempt or free capacity.

`task.continue` requires explicit reason, exact latest settled parent attempt,
expected task revision and unchanged placement digest. It reserves a new attempt
ID and retains the parent/history. Nonempty `message_ids` are refused pending S7's
verified binding integration. The new attempt still needs the launch handoff;
continuation never calls an executor or releases a parent slot.

## Durable S4 launch handoff

PLAN is a closed internal data object:

```json
{
  "schema": 1,
  "actor": {"id":"owner-example","run_id":"run-example","epoch":0},
  "task_id": "task-example",
  "expected_revision": 1,
  "operation_id": "start-example",
  "idempotency_key": "start-example",
  "placement_digest": "git-blob-sha1-v1:1111111111111111111111111111111111111111",
  "binding": {}
}
```

Replace `binding` with the complete S4 binding from `docs/native-process.md`,
including `prompt_digest`, target, workspace, executable digest and limits. The
actor must match PLAN; selected host/profile must match actual S3 resolution.
`placement_digest` is `loom_policy_scope` of the complete policy pin.

A trusted `launch` proof must match run, task, expected task `revision`, `epoch`,
`binding_digest`, `placement_digest`, and `stop_authorized`. It must carry
`calibration_verified:true`, `capabilities_verified:true`, and
`workspace_verified:true`. The digest removes only `stop_authorized` and
`release_authorized` from binding, then uses `loom_policy_scope`, exactly as S4
requires. Release authorization is always false at this initial handoff. The
provisioner must validate calibration, capabilities, workspace/base/manifest and
prompt/executable identities before installing this proof. Changing PLAN or an
evidence reference does not grant authority.

Authorization durably stores a preparation operation containing the exact S3
capacity transaction, and exclusively claims the task's preparation slot under
run CAS. This is only a preparation intent. It then commits the S3 global capacity
reservation, rechecks current owner/epoch, task revision, dependencies, gates and
policy, and atomically creates the bound attempt/assignment with the launch
receipt. Until that final transaction succeeds there is no execution authority.
The preparation slot prevents two keys from launching the same ready task.

A crash or refusal after capacity reservation retains the slot and preparation.
The exact capacity transaction survives in S2; retry replays its original bytes.
CAS conflicts never silently regenerate a request or allocate another slot.
Unknown/crashed preparations require explicit reconciliation; they are not expired
or automatically compensated. S3 capacity settlement is separate and must use
verified exact process/group settlement, never a task cancellation or timeout.

The returned `capacity_receipt` is the actual S3/S2 outcome. `launch_receipt` is
the actual S2 outcome with result exactly `{actor,target,binding_digest}`. Supply
these through S4's authenticated binding installation path, never as user-uploaded
proofs. S4 separately rechecks policy and the exact binding before execution.
Identical retries return the same durable authorization and cannot issue a second
launch. Wire retries also reconcile a concurrent identical caller's committed
result, even when that caller won between the initial lookup and CAS. Old-epoch requests are fenced even when a historical receipt exists.

## Validation boundary

Run `bash tests/coordination/run.sh` with actual S1/S2/S3 module overrides when
using independent sibling slices. Then run the repository gate:
`bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`.
Fixtures use synthetic configuration and fake workloads only. Shared CLI routing,
mail, provider evidence import, real agents and remote host fencing are not
implemented here. Explicit test-only crash/failure hooks (`LOOM_COORDINATION_TESTING=1` plus
`LOOM_COORDINATION_TEST_CRASH` or `LOOM_COORDINATION_TEST_FAIL`) cover
`after_prepare`, `after_capacity`, and `after_authorize`; they are never request
fields. Exact captured exits and dependency hashes belong in
`.loom/validation.md`, not in public environment-specific paths or logs.
