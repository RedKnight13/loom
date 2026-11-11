---
layout: documentation
title: "Pinned native artifact and check interface"
---

# Pinned native artifact and check interface

Status: implemented S8 extension under fixture validation and independent review.
This adds host facts only. The authority still owns task/gate decisions and
acceptance. No remote response may approve a task, settle authority capacity or
create a new attempt. No real agent or real network SSH acceptance is implied.

## Protocol and compatibility

Retain protocol 1.0 and every existing operation's closed args/results. Add two
optional operations/capabilities, `workspace.seal` / `workspace.seal.v1` and
`workspace.check` / `workspace.check.v1`. They require concrete assignment,
attempt and host bindings, operation/idempotency IDs and expected revision 1
(the single immutable bound workspace generation). No request fields contain
paths, shell snippets, argv, environment overrides, executable selections or body
text. Older runtimes refuse unknown operations/capabilities before any effect.

Existing hello callers receive the unchanged existing capability set. A provisioned
host advertises the new capabilities only when explicitly requested in
`required_capabilities`; callers must negotiate them before using the workflow.
This avoids adding unknown capability enum values to responses consumed by old
closed-schema clients. Existing `workspace.export` and `workspace.read` keep their
exact protocol shapes and gain concrete implementations over immutable artifacts.
`workspace.export` remains observational: bundle creation belongs to seal, and
export only returns a previously sealed descriptor. No minor-version relaxation
or extra args on existing operations is used.

## Trusted installation

Only an installation with explicit `workflow_access:"owner"` may load the
workflow descriptor or expose seal/check capabilities. A default worker helper
with the same binding refuses them; the authenticated installed route is the
authority boundary, not the caller-supplied actor tuple.

An optional operator-installed sibling `NATIVE_CONTEXT.workflow` fixes a workflow
manifest path/digest, check script and `/usr/bin/bash` digests, check deadline, artifact/file/byte
quotas and Git author identity. It is not uploaded by a request. Its exact bytes,
referenced manifest/check bytes, startup mail descriptor/context/bridge bytes and
workflow implementation code enter the helper's context/runtime digests. Existing
contexts without this descriptor retain existing lifecycle behavior and refuse
artifact/check capabilities. Retain S7 mail dispatch and runtime digests.

The manifest binds base SHA, consumed report line offset and check digest to the
already-authorized S4 binding's manifest digest. Changes invalidate the SSH pin;
there is no automatic repinning. Check execution remains on the selected host.
All operations validate actor/epoch/target against the installed binding and verify
actual S4 identity/group completion with captured worker exit before reading or
mutating result state. Same-account trusted-host assumptions still apply.

## Operations

| Operation | Closed arguments | Result / effect |
| --- | --- | --- |
| `workspace.seal` | `workspace_id, base_sha, manifest_digest` | Captured execution observation, current report state/digest, exact sealed SHA, pinned policy/manifest and source identity; creates immutable report and Git bundle artifacts. A nonzero worker exit remains nonzero and cannot become acceptance. |
| `workspace.check` | `sha, manifest_digest` | Captured check exit for exactly the previously sealed SHA, check-script digest, report digest and runtime/context pins. Runs only the installed approved check script in a fresh private clone. |
| `workspace.export` | Existing `sha, kind, limit_bytes` | Previously sealed `git_bundle` or bounded JSON `evidence` descriptor, digest and bytes. Never seals, executes checks or substitutes HEAD for SHA. |
| `workspace.read` | Existing `artifact, cursor?, limit_bytes` | Base64 chunks of an immutable known artifact. Artifact IDs are opaque allowlisted spool names, never filesystem paths; cursor binds artifact digest and byte offset. |

Check results distinguish captured check exit from transport/setup failure. A
nonzero check can produce a successful observation receipt containing that exact
exit; the authority refuses acceptance. Deadline or setup uncertainty is never
check success. Source/report/HEAD/worktree changes invalidate further check/export
and acceptance. Requests cannot read arbitrary workspace files or credentials.
Artifacts reject links and special paths, enforce file/total-byte/bundle quotas,
and transfer in bounded base64 chunks; clients verify exact byte count and whole
artifact digest before Git import. No archive extraction is required.

## Durability and recovery

Under a short per-context operation lock, write and flush an immutable semantic
request intent before seal/check effects; then atomically flush/publish artifacts
and an immutable response. Identical keys recover the same result without another
commit or check execution. Changed payload/key conflicts cannot replace history.
An intent without a terminal receipt is unknown, including after timeout or helper
death; there is no automatic rerun of a possibly executed check. Lost replies
return unknown at transport; exact replay recovers an already committed receipt.
Report/tree/runtime drift is rejected even on replay rather than returning a
stale success. Git sealing uses a private index and CAS update of the pinned base
branch, with no hooks, pushes, merges, remote fetching or worker commits.

The authority facade imports these authenticated facts into its existing S6 proof
flow. Collection verifies the complete bounded Git bundle and exact SHA before
fetching into a dedicated local reference; this is artifact movement, not local
execution. Only explicit owner review plus matching current remote evidence,
check result and collected SHA can authorize task acceptance.

## Required evidence

Keep existing contract/SSH/mail regressions. Add full fake-transport CLI workflow
using actual helper processes and S6 authorization; replay after lost seal/check
reply; fresh process restart; report/base/SHA/manifest/check/source drift; wrong
actor/attempt; unknown/traversal/control artifact IDs and malformed cursors;
oversized/link artifacts; arbitrary argv/script/body injection refusal; check
nonzero/timeout and journal intent without receipt. Check code must execute once
per operation. Record normal round trips separately from injected faults. Real
network SSH remains separately blocked/not run until its deployment permits it.

## Independent integration acceptance blockers

Architect review of the frozen S1–S7 runtime reports stale-owner historical success
after epoch takeover, stop/release retry failure after cache loss despite committed
journal intent, and inability to import settlement after task cancellation.
Independent reproductions are retained in the review evidence. This artifact slice does not guess
repairs to those modules or claim lifecycle/release acceptance. Preparation-only bootstrap addresses the preauthorization cycle in this slice;
mail delivery/route fairness, exclusive-lock journal replay cost, host-wide keeper
scanning, output scanning and sparse-output throughput remain separate blockers. These blockers survive
any passing artifact or fixture tests until separately resolved and reviewed.

## Architect dispositions

- Compatibility: add frozen old-client/new-helper hello response validation and
  new-client/old-helper unsupported-capability refusal. Negotiate all four
  seal/check/export/read capabilities explicitly.
- Duplicate effects: the host fence is per bound workspace generation and
  operation kind, not merely per caller key. A different key cannot escape an
  uncertain seal/check intent. Receipts bind exact attempt/manifest, SHA,
  runtime/context identity, config, report and check-script digest.
- Checks: installation explicitly sets `check_authorized:true`, `allow_kill:true`,
  finite deadline and output quota. A bounded session keeper retains group
  identity through descendant exit; leader exit alone cannot prove completion.
  Timeout/escaped group/lost receipt remains unknown with the original fence.
  Setup execution remains unsupported; no request can supply a script or argv.
- Historical reads: `workspace.read` continues serving an existing immutable
  artifact after live worktree/report drift. Seal/check/export and promotion
  still refuse drift; the old bytes never become new success evidence.
- Bootstrap: when the native launch authorization file does not yet exist, an
  explicit private `NATIVE_CONTEXT.prepare` authorizes only hello/prepare. Its
  exact closed fields are `schema:1, actor, target, base_sha, manifest_digest`,
  matching the provisioned binding and preparation plan. It cannot execute,
  check, signal, release, receive mail or approve authority state. Install the
  actual S6 authorization only after capability/workspace verification, then
  explicitly install/re-pin the execution helper context. No automatic upgrade
  from preparation-only to execution authority occurs.
- Inherited lifecycle findings remain separate integration acceptance blockers;
  no successful artifact test clears them.

## Installed workflow descriptor

The private `NATIVE_CONTEXT.workflow` object has exactly these fields:

```json
{
  "schema": 1,
  "manifest": "/srv/loom/manifest.json",
  "check_script": "/srv/loom/check.sh",
  "check_digest": "GIT_BLOB_DIGEST_OF_SCRIPT",
  "interpreter_digest": "GIT_BLOB_DIGEST_OF_USR_BIN_BASH",
  "seal_authorized": true,
  "check_authorized": true,
  "allow_kill": true,
  "check_timeout_ms": 5000,
  "output_bytes": 65536,
  "artifact_bytes": 1048576,
  "max_files": 100,
  "max_worktree_bytes": 1048576,
  "author_name": "Loom",
  "author_email": "loom@example.invalid"
}
```

The installed script runs with a clean fixed PATH/locale and checkout HOME, no
stdin, and no request-controlled environment. Output is continuously drained
through the existing bounded binary drainer; the terminal check proof includes
captured exit, anchored keeper identity, group emptiness, output EOF and retained
byte counters. Deadline expiry records uncertainty and kills only the keeper's
verified group; alternate keys cannot re-execute that attempt's check. Process
observations use the existing cooperative trusted-process model, not sandbox
containment against hostile process/session escape.

`workspace.export.limit_bytes` limits the whole artifact. In `workspace.read`,
`limit_bytes` bounds each base64-encoded chunk; values below four refuse, and
cursors bind the artifact digest and raw byte offset. The client download helper
`loom_ssh_download CONFIG EXPORT_REQUEST EXPORT_RESPONSE DESTINATION` verifies
the fixed artifact, total size and whole digest before publishing a new private
local file. Historical reads survive live workspace drift while the original
installation and source pins still match; changes to those pins require explicit
operator inspection and cannot silently authenticate old evidence.

Artifact byte quotas are upper safety bounds, not a throughput guarantee. The
whole download also has the client context's finite deadline; sufficiently large
bundles can exceed it even while each chunk is valid. Such a transfer remains
incomplete and cannot be imported or accepted. This slice does not raise the
existing deadline or bypass identity/durability checks to hide resource findings.

## Repository Git boundary

Repository-local configuration does not confer check authority. Before any
repository Git command, the helper reads config keys outside that repository
with includes disabled and accepts only basic repository settings, local author
identity, the origin URL/fetch mapping and branch remote/merge metadata. Other
keys, includes, filters, filesystem monitors, upload hooks, alternates, grafts,
worktree config and unsupported layouts refuse. Git runs with hooks and fsmonitor
disabled, replacement objects disabled, no system/global config or attributes,
and only explicit local file transport. Filter and working-tree-encoding
attributes refuse; ordinary text/eol attributes remain supported. This is a
conservative opt-in boundary, not a claim that arbitrary repository config is
safe. Existing legacy commands retain their separate behavior.

The same boundary covers seal, check, export and read validation and facade Git
collection. An otherwise historical artifact read also refuses when the live
repository gains unsupported executable configuration. Positive immutable-object
and hostile clean-filter/fsmonitor/include/clone-hook cases are in
`tests/conformance/git-boundary.sh`; the actual helper workflow exercises hostile
config across all four artifact operations.

Target-tree attributes are checked through an isolated non-materializing index
before checkout, read-tree or reset. This also applies to fresh empty check clones
and preparation workspaces; the absence of live attributes is not evidence about
the target commit. CRLF expansion, custom encodings and filters refuse before
materialization. Even otherwise harmless unsupported config such as
`commit.gpgsign=false` currently refuses; it is not silently ignored.

Collection and acceptance read the exact immutable host check artifact and
validate the complete saved receipt against both that durable result and the
original pinned request. Nested SHA, check/manifest/report/config/runtime identity,
attempt target, captured process exit, status and summary fields must agree.
Promotion also rechecks the current authority owner, epoch and task attempt;
a cached success summary cannot substitute for these facts.

A successful check publishes `workflow-check`, a bounded immutable JSON artifact
containing its original request and normalized receipt. `workspace.read` serves
it only while the original host intent and terminal receipt still exist and
agree with the artifact. Promotion uses this read-only operation, never
`workspace.check`: absent/invalid local proof, missing host intent or complete
check-cache loss cannot initiate a fresh check. An explicitly requested verify
still uses the original create-or-replay operation and its generation fence.
