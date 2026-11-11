---
layout: documentation
title: "Native mail integration API"
---

# Native mail integration API

S7 owns `ops/mail.sh` and `ops/worker-bridge.sh`. Shared CLI and supervisor
registration belong to the integration owner. Modules are source-safe; calling an
API is explicit work, never a background poller.

The authority interface is `loom_mail_handle CONTEXT REQUEST` or
`loom_mail_serve CONTEXT`. Requests and responses use closed S1
`loom.coordination` mail operations. Installation overrides are
`LOOM_MAIL_PROTOCOL_MODULE`, `LOOM_MAIL_STATE_MODULE`, `LOOM_MAIL_POLICY_MODULE`,
and `LOOM_MAIL_SSH_MODULE`, pointing to actual dependency modules and their
adjacent schemas. Existing public CLI envelopes remain the facade's responsibility.

The bridge interface is `loom_worker_bridge_handle CONTEXT REQUEST` for worker
mail commands and `loom_worker_bridge_boundary CONTEXT LIMIT` at startup or a
cooperative turn boundary. Presentation is JSON-escaped external message data;
it never evaluates message content, approves a gate, or completes a task.

The S5 helper integration entry point is
`loom_worker_bridge_exchange NATIVE_CONTEXT REQUEST`. After authenticating its
pinned installation/context tuple, the helper routes `loom.coordination`
`mail.pump` here. The request uses the namespaced `loom.mail.exchange` extension;
closed S1 args remain `{run_id,deadline_ms}`. The helper must verify private
`mail.sh` and `worker-bridge.sh` files and include them in its runtime digest.
There is no reverse connection, credential transfer, resident daemon, keystroke
injection, or automatic continuation. Actual network acceptance is separate from
deterministic transport tests against the installed helper.

## Provisioned authority context

Install a private mode-0600 context through the trusted launcher/conductor, never
from message text or a wire argument. S3 checks paths and S2 verifies store identity.

```json
{
  "schema": 1,
  "state_root": "/srv/loom/authority",
  "store_id": "consumer-example",
  "actor": {"id":"owner-example","run_id":"run-example","epoch":0},
  "role": "owner",
  "binding": null,
  "commands": ["mail.send","mail.reply","mail.poll","mail.status","mail.claim",
               "mail.read","mail.ack","mail.retry","mail.pump"],
  "routes": []
}
```

Worker contexts use `role:"worker"`, an absolute `binding` file path containing
the exact S6-authorized S4 binding, and a restricted command list. Actor and target
come from that binding. S6 currently binds execution to the launch actor; S7 also
checks the worker role and exact assignment/attempt/host, so knowledge of the
actor ID alone grants no mailbox access. The context is trusted provisioning,
not a cryptographic credential against hostile code under the same OS account.
Every authority write checks the current S6 run revision and epoch in the same
S2 transaction. Mail never changes S6 graph projections.

An owner route is `{ "attempt_id":"attempt-example",
"config":"/srv/loom/client/attempt-example.json" }`, pointing to the actual S5
private client config. Its context ID must equal the attempt ID; transport identity
must equal the S6 policy pin. Pin changes require explicit operator resolution.
Remote worker APIs receive the existing native context from `native-process.md`;
they use its separate S2 host spool and verified capacity/launch receipts.

## Observable semantics

Sending atomically creates one immutable message plus a delivery for each concrete
recipient. A failed recipient validation refuses the entire group. This initial
transaction supports at most 98 recipients, reserving S2 changes for the message
and explicit reply acknowledgement. Same ID/content replays; changed content or
sender binding conflicts. `from` must match the bound actor. Replies target the
recorded sender's return address, which is the run owner inbox or exact originating
attempt. A reply cannot choose a new recipient. Its optional ack token acknowledges
only the matching question delivery; otherwise reply and ack are independent.

Poll is passive and hides claim tokens. Its exclusive cursor advances over the
store, including filtered records; clients must follow `next_cursor` to finish a
scan. Claim requires the observed delivery revision, creates a random token and
sets a millisecond lease (maximum 300 seconds). Renewal uses the current token and
revision. Expiry permits redelivery; it does not erase earlier read facts. Read and
ack are separate durable writes; retrying the original operation recovers a lost
reply. Ack never means approval, task completion, or successful checks.

Task claims select the latest authorized attempt under S2 CAS. Exact attempt mail
never redirects. A remote intent remains pinned to its original attempt until
explicit resolution; lease expiry on the host allows another reader of that same
attempt, not reassignment to another host. This conservative fence preserves
uncertain delivery instead of duplicating work across replacements.

Pump calls are bounded by their request deadline, at most 20 configured routes,
one message per host exchange and 100 scanned authority records. A durable scan
cursor prevents old history from permanently hiding newer messages. Intents are
committed before transfer. Lost replies retain the original message/delivery/digest;
remote read/ack facts import monotonically. Remote ack remains `ack_pending_sync`
until a subsequent successful pump confirms authority import. Remote sends remain
`queued_for_authority` until accepted; unknown recipients remain unresolved in the
outbox. No background retry exists. Failed transfers plan delays of 1/2/4/8/16
seconds and reach a visible dead letter after five attempts. Owner `mail.retry`
resets the retry budget; it does not extend a message's immutable deadline.

The host aggregate is bounded to 512 KiB and 100 retained deliveries/outbox entries;
quota refusal preserves history and requires operator-managed retention. This
initial implementation does not prune acknowledgements or dedupe records. Message
bodies retain S1's 64 KiB bound. Presentation uses escaped JSON; quoted content
cannot grant commands, change identity, or trigger policy transitions.

The supervisor integration must explicitly call the boundary API before releasing
the startup gate, and the cooperative agent integration must call it between
turns. The API returns a bounded batch with claim tokens and read receipts; it does
not ack automatically. Merely installing instructions or running the detached
supervisor does not prove a boundary occurred. Busy/noncooperative agents expose
`delivery_mode:"next_boundary"` and `wake:"unsupported"`; no hidden relaunch occurs.

## Validation

Focused commands are `bash tests/mail/run.sh`, `bash tests/mail/continuation.sh`,
`bash tests/mail/cooperative.sh`, `bash tests/mail/ssh.sh`, and
`bash tests/mail/retry.sh`; `bash tests/mail/helper.sh` checks the narrow helper dispatch. For a split checkout set
`LOOM_MAIL_TEST_DEPENDENCIES` to an installation of the actual S1–S6 modules.
Remote integration requires the patched S5 helper and S7 files installed in that
private runtime; test staging belongs under ignored `.loom/`, never in commits.
The cooperative test launches only a synthetic two-step shell workload through
real S6 authorization and S4. The SSH tests invoke the actual installed helper
through deterministic transport, including reply loss and source pinning.

The existing regression gate remains
`bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`, plus the existing
`LOOM_SSH_FIXTURES_APPROVED=1 bash tests/ssh/run.sh` on approved compute. No model
clients or production credentials are used. Actual network SSH remains an explicit
acceptance limitation inherited from S5; passing deterministic tests does not
clear that blocker. Source hashes and captured exits are recorded privately in
`.loom/validation.md`.

Authority poll/status responses expose `loom.mail.observations` in the namespaced
extensions: message age, immutable expiry, scheduled next attempt, failed-attempt
count, and claim expiry. These are observations or plans, never evidence that a
runner is active. Claim tokens remain available only in the claimant's receipt.
