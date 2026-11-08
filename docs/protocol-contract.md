# Normative protocol 1.0 resolutions

This appendix freezes the previously unspecified S1 wire shapes. The architect
semantics remain authoritative for lifecycle, policy and durability. The checked-in
2020-12 contracts are authoritative for field spelling, required/nullability rules,
enums and numeric bounds; the wire assertions below also apply. A change to required
fields or meaning requires a new major, not an optional extension. Runtime routing
is pending. This document does not authorize a launch or add coordination effects.

## Resolutions

- All listed core fields are required; only registry cursor fields and inspect operation ID are optional. Explicitly nullable fields must still be present.
- Opaque IDs are nonempty UTF-8 strings of at most 128 bytes. Artifact references are opaque store-relative slash-separated alphanumeric/underscore/hyphen components; dot, traversal and absolute paths are refused.
- Digests use `git-blob-sha1-v1:` plus 40 lowercase hexadecimal digits. Commit SHA fields contain exactly 40 lowercase hexadecimal digits.
- All numbers representing revisions, epochs and counts are safe nonnegative integers. Offered version components are bounded to 65535. Numeric exponents are limited to -308 through 308, and fractional tokens that would round into integers are refused before decoding. List limit is 1–100; call/grace/lease/watch/pump durations have a maximum of 300000 ms. Runtime duration may be a positive safe integer or null.
- Timestamps use the UTC seconds form `YYYY-MM-DDTHH:MM:SSZ`; fractional offsets are not part of 1.0. Text/body and read data are at most 65536 decoded UTF-8 bytes; short reasons/subjects/error messages at most 4096.
- Agent argv contains 1–256 strings, each at most 65536 bytes, and index zero is nonempty. Adapter prefix argv contains 0–256 strings; its executable is a separate canonical absolute path. No string can contain NUL.
- `start_limits` requires `runtime_ms`, `stop_on_timeout`, `allow_kill`, `output_bytes`. Output quota is 1 byte–1 GiB (caller policy normally chooses 64 MiB). A stop-on-timeout policy requires a runtime; KILL authorization requires stop-on-timeout. These fields express policy, not an implementation in S1.
- A capability record is `{name,state,evidence,limits}`. State is supported/unsupported/unknown. Limits requires nullable `max_bytes` and `max_items`; max_bytes caps both encoded request and raw response envelopes for that capability, and max_items caps list/discovery request counts. These intersect with configured and hello global limits. Referenced body content is checked by the later artifact receiver against message_bytes; S1 never reads a body_ref. Capability names are unique and must come from the protocol-specific registry.
- Hello returns `selected_version`, closed provider `{id,version}`, capability records, seven negotiated global limits and `schema_digest`. Only exact version 1.0 currently intersects. Unknown required capability names with valid version-suffixed syntax yield truthful unsupported-capability refusal.
- Native identity contains every field required by the architect, plus explicit `supervisor_pid`. Provider identity uses provider/resource/attempt/host IDs and a binding digest. Unproven identity is null; no fabricated PID or opaque UI handle substitutes for proof.
- A terminal record has nullable captured exit/signal, a captured flag and evidence. Uncaptured exit/signal must be null; captured terminal records require an actual exit code or signal. Identity verification and stopped confirmation are separate booleans; confirmed stop requires verified identity and exited group state. A receipt reporting KILL requires allow_kill in the exact request.
- `resource.state` is owned/retained/released/unknown. Release results do not imply workspace deletion. Observation states are reserved/starting/running/exited/start_failed/stop_requested/unknown; terminal result is null unless exited. A proven pre-exec start failure is start_failed, with no fabricated worker exit.
- Chunk results carry source/generation, literal UTF-8 data, nullable next cursor, EOF/truncation and nullable byte gap. Binary bundles use artifact refs/digests/byte counts, not inline encodings.
- Run states are open/settled/unknown. Task states and explicit transition requests are pending/ready/running/waiting/review/succeeded/failed/cancelled (pending is creation only). Gate states are open/approved/rejected/cancelled. State transitions, evidence acceptance and scheduling are checked by the future core store, never inferred by the validator.
- Dependency records are `{task_id,policy}` with accepted/settled policy; IDs must be unique. Gate options are a nonempty unique ID list and the future core must validate that a decision belongs to it.
- Mail `to` is a nonempty unique array of run/task/attempt addresses, resolved once by the future core. Delivery records expose monotonic facts, authority sync and enumerated next actions; only mail.claim returns claim tokens. Read/ack/retry are mutations. Mail reply is enqueue/creation; optional question acknowledgement needs its explicit token and later core transaction checks.
- Mail claim requires explicit lease_ms; CLI defaults (30000 ms) belong to the future facade. Mail pump uses the run expected revision to fence its batch, with per-delivery CAS in the future core.
- Run use is a context lookup in this wire contract. It does not mutate the run record or schedule work. Execution reconcile is read-only and names the original operation in args.
- Events reference a separately bounded immutable payload artifact rather than accepting untyped core JSON. Coordination receipts expose the minimal records needed by the registry; the durable store may contain more fields than these wire projections.
- Mutations require operation/idempotency IDs; existing-entity mutations also require expected_revision. Creation/enqueue and pure reads require null expected_revision. Pure reads/hello require null operation/idempotency IDs.
- Successful responses have a registered operation-specific result. Error responses have null result, except unsupported_capability which requires `{missing_capability}`. Refusals have no effects. Unknown operation names may appear only in error responses.
- Envelope maximum is 1048576 raw bytes, hello maximum 65536; diagnostics maximum 1048576; depth maximum 64, syntax nodes maximum 50000. Extensions remain bounded optional namespaced data. UTF-8 byte limits are mandatory alongside JSON Schema character-length checks.

## Operation registry

Creation, mutation and read classes below define the common envelope invariants.
All fields in each args/result object are required unless marked `?` or explicitly nullable in the schema.

| Operation | Class | Required capability | Args | Result fields |
| --- | --- | --- | --- | --- |
| `hello` | read | `none` | versions, required_capabilities | selected_version, provider, capabilities, limits, schema_digest |
| `hosts.list` | read | `hosts.list.v1` | cursor?, limit | items, next_cursor |
| `agents.discover` | read | `agents.discover.v1` | host_id, profile_ids | profiles |
| `workspace.prepare` | create | `workspace.prepare.v1` | workspace_id, base_sha, bundle_ref, bundle_digest, branch, manifest_digest | workspace_id, host_id, base_sha, manifest_digest, disposition |
| `execution.start` | create | `execution.start.v1` | workspace_id, profile_id, profile_digest, argv, prompt_ref, model, effort, limits, manifest_digest | binding, identity, start_evidence, prompt_acceptance, resources |
| `execution.inspect` | read | `execution.inspect.v1` | operation_id? | binding, state, identity, identity_verified, terminal, source, observed_at, resources |
| `execution.list` | read | `execution.list.v1` | run_id, cursor?, limit | items, next_cursor |
| `execution.read` | read | `execution.read.v1` | source, cursor?, limit_bytes | source, generation, data, next_cursor, eof, truncated, gap |
| `execution.stop` | mutate | `execution.stop.group.v1` | reason, grace_ms, allow_kill | binding, requested_signals, identity_verified, group_state, confirmed_stopped, terminal |
| `execution.release` | mutate | `execution.release.v1` | retention_policy | binding, resources |
| `execution.reconcile` | read | `execution.reconcile.v1` | operation_id | operation_id, observation |
| `execution.prompt` | mutate | `prompt.live.v1 / prompt.boundary.v1` | message_id, delivery_id, body_ref, mode | binding, message_id, delivery_id, acceptance |
| `execution.fence` | mutate | `execution.fence.v1` | reason, new_epoch | binding, epoch, fenced |
| `workspace.read` | read | `workspace.read.v1` | artifact, cursor?, limit_bytes | source, generation, data, next_cursor, eof, truncated, gap |
| `workspace.export` | read | `workspace.export.v1` | sha, kind, limit_bytes | artifact, digest, bytes, sha |
| `run.create` | create | `run.create.v1` | objective, owner_id, parent_run_id | run_id, objective, owner_id, epoch, state, revision, parent_run_id |
| `run.use` | read | `run.use.v1` | run_id | run_id, objective, owner_id, epoch, state, revision, parent_run_id |
| `run.show` | read | `run.show.v1` | run_id | run_id, objective, owner_id, epoch, state, revision, parent_run_id |
| `run.list` | read | `run.list.v1` | cursor?, limit | items, next_cursor |
| `run.claim` | mutate | `run.claim.v1` | run_id, expected_owner, reason | run_id, objective, owner_id, epoch, state, revision, parent_run_id |
| `task.create` | create | `task.create.v1` | run_id, spec_ref, spec_digest, deps, gates | task_id, run_id, spec_ref, spec_digest, deps, gates, state, revision, attempt_ids, accepted_result |
| `task.update` | mutate | `task.update.v1` | task_id, transition, evidence_refs | task_id, run_id, spec_ref, spec_digest, deps, gates, state, revision, attempt_ids, accepted_result |
| `task.show` | read | `task.show.v1` | task_id | task_id, run_id, spec_ref, spec_digest, deps, gates, state, revision, attempt_ids, accepted_result |
| `task.list` | read | `task.list.v1` | run_id, cursor?, limit | items, next_cursor |
| `task.continue` | mutate | `task.continue.v1` | task_id, parent_attempt_id, placement_digest, message_ids, reason | task_id, parent_attempt_id, attempt_id, revision |
| `gate.create` | create | `gate.create.v1` | task_id, question, resolver_id, options | gate_id, task_id, question, resolver_id, options, state, revision, decision, evidence_ref |
| `gate.resolve` | mutate | `gate.resolve.v1` | gate_id, decision, evidence_ref | gate, ready_task_ids |
| `gate.list` | read | `gate.list.v1` | run_id, cursor?, limit | items, next_cursor |
| `mail.send` | create | `mail.send.v1` | message_id, from, to, kind, subject, body, thread_id, in_reply_to, expires_at | message_id, deliveries |
| `mail.poll` | read | `mail.poll.v1` | mailbox, after_cursor, limit | items, next_cursor |
| `mail.claim` | mutate | `mail.claim.v1` | mailbox, delivery_id, lease_ms, claim_token | delivery, claim_token, expires_at |
| `mail.read` | mutate | `mail.read.v1` | delivery_id, claim_token | delivery, message |
| `mail.ack` | mutate | `mail.ack.v1` | delivery_id, claim_token, message_digest | delivery_id, message_id, message_digest, recipient, attempt_id, revision, state, authority_sync, next_action, reason |
| `mail.reply` | create | `mail.reply.v1` | question_id, message_id, body, ack_claim_token | message_id, deliveries |
| `mail.status` | read | `mail.status.v1` | message_id | message_id, deliveries |
| `mail.retry` | mutate | `mail.retry.v1` | delivery_id | delivery_id, message_id, message_digest, recipient, attempt_id, revision, state, authority_sync, next_action, reason |
| `mail.pump` | mutate | `mail.pump.v1` | run_id, deadline_ms | deliveries, next_cursor, deadline_reached |
| `events.read` | read | `events.read.v1` | after_sequence, limit | events, next_sequence |
| `watch` | read | `watch.v1` | run_id, every_ms, deadline_ms | observations, next_cursor, state |

## Optional execution capabilities

`prompt.live.v1`, `prompt.boundary.v1`, `events.push.v1`, `ui.keep_open.v1`,
`model.select.v1`, `effort.select.v1`, `resume.session.v1` and `owner.fence.v1`
are explicit optional names. They do not imply core support. `execution.prompt`
requires the capability for the chosen mode. Start additionally requires model/effort
capabilities when the corresponding request field is nonnull. No optional UI capability
is required for native core coordination. Coordination capabilities use their exact
operation name plus `.v1` and are never sent to a command executor.

The core execution minimum consists of the registry capabilities for hosts.list,
agents.discover, workspace prepare/read/export and execution start/inspect/list/read/
reconcile/stop/release/fence. Partial adapters may advertise unsupported or unknown;
the future policy layer decides whether their gaps satisfy a workflow.

Every nested record is specified under `$defs` in its protocol contract. The
fixture corpus provides one complete request/result pair for every registry operation.
Use those concrete fields instead of reconstructing wire records from prose.
