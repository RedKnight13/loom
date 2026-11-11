# Native SSH transport

S5 is a source-safe transport around the S4 host API. It does not register shared
CLI commands, choose placement, reserve global capacity or authorize work.
Install S1 `protocol.sh`/schemas, S2 `state.sh`/schemas, S3 `policy.sh`/schemas and
S4 `native.sh`, `native-supervisor.sh`, `output.sh` in one private runtime tree.
No copies of those modules are part of this slice. The S3 selected host must pin
helper version `1` and the Git blob digest of the installed `remote-helper.sh`;
the client additionally pins the full helper/runtime/configuration SHA-256 digest.

Source `ops/transport-ssh.sh` and use:

| API | Result |
| --- | --- |
| `loom_ssh_handle CONFIG REQUEST` | One validated S1 response; exits 0/1/2 per S1. |
| `loom_ssh_serve CONFIG` | Same, with one S1 request on stdin. |
| `loom_ssh_preflight CONFIG` | Small control receipt verifying all pinned identities. |
| `loom_ssh_upload CONFIG BUNDLE DIGEST` | Separate raw bundle stream with byte quota and S1 Git blob digest. |

Executable forms use `handle`, `serve`, `preflight`, `upload` with the same
arguments. `workspace.prepare` is handled by S5; lifecycle requests delegate to
`loom_native_handle CONTEXT REQUEST`. The client sends no user data in the SSH
command. The one remote command is an installed absolute helper path restricted
to safe shell characters. Destination is one validated SSH argument. Batch mode,
strict pinned known-host verification, no PTY, no forwarding, no local command,
no connection sharing and connect/call deadlines are fixed options. There is no
alternate host, provider or local process fallback.

## Explicit installation and update

On the approved execution host, prepare the private S4 context, binding, prompt,
policy files and copied authoritative capacity/launch receipts as specified in
`docs/native-process.md`. Initialize its separate execution spool using S2.
The authority has already checked ownership, gates and capacity before issuing
these receipts. The helper does not accept context files or receipts uploaded in
ordinary requests; only an operator-installed routing table can select them.
Provision the runtime, contexts and installation config as owner-only regular
files below private directories, with no symlink components. No credentials are
included in the runtime or transferred workspace.

Run `bash ops/remote-helper.sh install INSTALL_CONFIG NEW_DIRECTORY` explicitly
on that host. It installs a fixed executable `NEW_DIRECTORY/remote-helper.sh` and
refuses to overwrite an existing installation. Updates use a new versioned
private directory, explicit review and new client pins. Start/preflight never
installs, downloads or upgrades code. Retain old installation/context snapshots
for unresolved attempts; a changed helper or context cannot silently acquire an
old attempt. `identity DIRECTORY CONTEXT_ID` prints the tuple for explicit
operator pinning; it is not authentication by itself. SSH host-key verification
must authenticate the selected destination.

Installation config has exactly this shape (synthetic paths):

```json
{
  "schema": 1,
  "runtime": "/srv/loom/runtime-v1",
  "bundle_bytes": 67108864,
  "contexts": {
    "attempt-example": {
      "context": "/srv/loom/attempt-example/context.json",
      "prepare": null
    }
  }
}
```

For a provisioned workspace, replace `prepare:null` with
`{args,max_files,max_worktree_bytes,manifest,work}`. `args` is the exact S1
`workspace.prepare` arguments object: workspace ID, exact base SHA, opaque bundle
reference, Git blob bundle digest, branch and manifest digest. `manifest` and
`work` are private, absolute files installed by the authority; the manifest digest
must match the S4 binding. The workspace path comes only from that binding and
must be an immediate child of the pinned workspace root. The helper writes
`WORK.md` and `.loom/binding.json`, excludes Loom evidence, and removes origin.
No setup script or network fetch is performed. Setup execution is not supported.

Client config contains exactly these keys:

```json
{
  "schema": 1,
  "destination": "compute-example",
  "port": 22,
  "helper_command": "/srv/loom/helper-v1/remote-helper.sh",
  "known_hosts": "/srv/loom/client/known_hosts",
  "identity_file": null,
  "context_id": "attempt-example",
  "identity": {
    "installation_id": "installation-example",
    "transport_identity": "verified-transport-example",
    "boot_id": "operator-observed-boot",
    "helper_digest": "sha256:operator-observed-helper-digest",
    "context_digest": "sha256:operator-observed-context-digest"
  },
  "connect_timeout_s": 5,
  "timeout_ms": 30000,
  "bundle_bytes": 67108864
}
```

Client config, known-hosts and optional identity file must be private files with
safe ancestors. `identity_file:null` uses the operator's existing SSH identities.
The trusted `LOOM_SSH_PROTOCOL_MODULE` can select a separately installed S1 module;
`LOOM_SSH_EXECUTABLE` is a trusted fixture/installation hook, never a request field.
Do not set the latter from untrusted input.

## Bounds, replay and authority

Wire requests contain a small routing/identity wrapper around one S1 JSON request.
Bundles use a one-line JSON header followed by exact raw bytes, not JSON/base64.
Input, response and diagnostic streams are bounded; S1 request/response bounds
remain 1 MiB, metadata 64 KiB, read chunks 64 KiB. Bundle quota is enforced at both
ends; upload verifies the exact bytes and provisioned digest before publication.
One content-pinned bundle is retained per context, with no arbitrary artifact IDs
or filesystem paths. Receive scratch can temporarily retain the wire and extracted
bundle plus the committed copy. This is a bounded transfer, not an OS disk quota.

Workspace preparation imports only a verified Git bundle, verifies the exact base,
checks tree file count/bytes before checkout and rejects symlinks, submodules and
reserved `.loom` paths. Git hooks and external configuration are disabled for its
commands. File-byte limits bound the checked-out tree; Git pack/history storage
and decompression resources are not a filesystem or CPU sandbox. Trusted host and
same-account process-management assumptions remain those of S4. Preparation is
locked, receipts are flushed, exact replay returns existing, and a directory
without a durable receipt is unknown rather than overwritten.

All calls compare installation, transport, boot, helper/runtime and context
identity before S4 can act. Mismatch, timeout, reply loss, oversized or malformed
JSON, response correlation errors and SSH/response exit mismatch become unknown.
`extensions["loom.ssh.transport"].exit_code` is captured transport status; it never
supplies an agent exit. S4 retains the permanent same-operation launch fence,
capacity/launch receipts and remote spool facts. Retry the same operation or use
`execution.reconcile` with its original operation ID; never allocate a fresh
attempt merely because a reply was lost. A boot/helper replacement requires owner
resolution, not automatic repinning. Read/inspect cannot grant ownership, approve
gates, launch, signal, release capacity or infer completion from silence.

## Validation

Run `LOOM_SSH_FIXTURES_APPROVED=1 bash tests/ssh/run.sh` only on explicitly approved
compute. Add `LOOM_SSH_REAL_FIXTURE=1` for an isolated unprivileged loopback sshd
with fixture-only host/client keys, a private known-hosts file and cleanup. It
requires existing OpenSSH server/client tools; it changes no global SSH settings.
A split-slice checkout can point `LOOM_SSH_TEST_RUNTIME` to a private staged tree of
the actual S1-S4 files. The fake transport invokes the same installed S4 helper,
not a mock lifecycle implementation. No real agents are started.

Normal preflight/inspect/read round trips are sampled separately from fault tests
with SSH multiplexing disabled; samples include client and server validation.
Captured logs, exit codes, runtime source digests, environment and latency samples
belong in `.loom/validation.md` and adjacent evidence. Production network SSH,
real-agent readiness and complete S6-S8 workflow acceptance are separate claims.
On the validation host, fixture key authentication succeeded but the remote
shell failed with `Permission denied` (captured SSH exit 1). SELinux was enforcing
and sshd logged an execution-context setup; SELinux causation is suspected, not
confirmed by audit evidence. No global SSH or host security policy was changed.
Actual SSH end-to-end acceptance and SSH round-trip latency remain blocked by
that execution failure. Fake-path S4 integration and its explicitly labeled
samples do not establish network transport acceptance. Rerun the real fixture on
an approved deployment whose existing policy permits its SSH execution path.

The existing gate remains `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`.
