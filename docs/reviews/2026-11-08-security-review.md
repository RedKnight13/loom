# Loom security and calibration review — 2026-11-08

Reviewed revision: `e38a325acd9bdcb2fc80d291e1e138171b6fa2cf`.
Scope: ops, bootstrap, and prospective calibration boundaries. No product code was changed.

Loom coordinates trusted tools; it does not establish a security sandbox. The most urgent gaps are SSH option acceptance, execution of candidate code with conductor privileges, and collection without binding to successful verification. Severity below is conditional on the stated attacker access, not a claim of remote unauthenticated exploitation. A malicious same-account process already has substantial authority; filesystem hardening cannot turn shared credentials into isolated roles.

## Evidence and method

Run from the checkout root: `bash .loom/security/reproduce.sh`. The script uses disposable fixtures under `.loom/security`, clones existing history without creating commits, stubs SSH for argument capture, and uses `ssh -G` to inspect parsing without connecting or executing a proxy. All temporary files are removed. The environment test uses a synthetic value only. The report-harvest probe stubs workspace operations so it cannot stage or commit. Evidence is assignment-local and intentionally excluded from the product commit:

- `.loom/security/reproduce.sh`: reproducible probes S1–S10.
- `.loom/security/reproduction.log`: observed probe assertions and captured script exit.
- `.loom/security/consumer-checks.log`: required consumer gate output and captured combined exit.

The fixtures verify specific behaviors, not exploit completeness. No external scanning, credential reads, live worker termination, pushes, or remote execution were performed by the probes. The required repository selftest separately uses its own disposable fake workers and fixture commits.

## Findings

### F1 — High: compute host values can become SSH options

**References:** `ops/lib.sh:255`, `ops/lib.sh:307–315`, `ops/verify.sh:45–51`; compare the stricter explicit `--on` validation at `ops/verify.sh:24`. `ops/orca.sh:127–132,175–179` also splits a configurable selector into arbitrary CLI arguments.

**Prerequisite and impact:** Someone can edit an accepted consumer config, or the assignment record. The config parser accepts any nonempty compute string. `loom_compute_pick` passes it before a destination without an option terminator; a value such as `-oProxyCommand=fixture-command` is an SSH option, not a host. On the reachability check, `true` becomes the destination. A crafted proxy command can therefore execute locally even when the intended policy is remote-only checks. Config authors already control executable `checks` and `compute_setup`, so this is not escalation beyond a fully trusted config author; it breaks any assumption that host-only edits are inert. `compute_selector` similarly exceeds placement-only authority; actual Orca duplicate-option behavior was not tested.

**Reproduction:** S3–S5 accept that value, capture the exact argument at a fake SSH binary, and confirm real SSH configuration output contains its ProxyCommand using `-G`. No proxy was executed.

**Bounded fix:** Apply one host validator to config, records, and overrides; reject leading dashes, whitespace, control characters and unsupported syntax before SSH. Quote argv and terminate options where supported. Replace free-form placement selectors with an allowlisted structured selector. Explicitly classify checks/setup as executable trusted configuration.

**Regression:** Reject option-shaped hosts, embedded whitespace/newlines and selector arguments that change repo/spec/agent. Use an SSH stub to assert the exact argv and that invalid inputs never reach it; preserve valid user-at-host forms and supported host IDs. Keep Bash 3.2 compatibility.

### F2 — High: verification executes candidate code with conductor authority

**References:** `ops/verify.sh:54–75,77–88`; `ops/lib.sh:216–224`; `ops/launch.sh:34–36`.

**Prerequisite and impact:** A worker can edit code invoked by the approved checks, such as a test script or Makefile. A fresh clone binds files to a commit but does not isolate execution. Local checks inherit the conductor environment and user filesystem access; remote checks run as the SSH account after executable setup. No explicit environment allowlist, network boundary or credential isolation appears here. Harvest also deliberately executes commit hooks from worker-controlled repository metadata in the local clone; global hooks may be inherited. Logs can retain anything checks, workers or hooks print. This is intentional execution functionality with an undocumented trust prerequisite, not shell interpolation in the checks string.

**Reproduction:** S9 runs actual `verify.sh` against a disposable clone with an approved fixture check that tests a synthetic inherited environment value; exit 0 proves inheritance. It does not read a credential, execute a hostile hook, or establish the behavior of an external sandbox.

**Bounded fix:** State that candidate checks are arbitrary code. Require an explicitly configured isolated runner for untrusted workers, with a minimal environment, no conductor credentials and narrowly scoped filesystem/network permissions. Fail closed when that required runner is absent. Pin hook policy outside worker-writable metadata. Isolation policy belongs to the owner; this review does not silently choose a new backend.

**Regression:** A fake runner must observe only allowlisted environment variables; fixture code attempting to read a synthetic conductor-only file must fail under the configured runtime. Test local and remote paths, hook policy, and runner-unavailable refusal. Log redaction is useful but cannot replace isolation.

### F3 — High for release assurance: collected code is not bound to verification

**References:** `ops/verify.sh:60–69,101–112`, `ops/collect.sh:15–39`, `ops/orca.sh:521–530`.

**Prerequisite and impact:** A caller collects without verifying, or a branch changes between verification and collection. Collection reads the latest report only for display, accepts failed reports, fetches the current branch tip and stores its SHA without consulting `checks_runs`. Release only requires a syntactically valid collected SHA. Thus a successful verification of A can be followed by collection of B. These commands do not themselves merge or push; the protocol's manual review remains a separate policy safeguard.

**Reproduction:** S6 invokes actual collection with a failed latest report and an empty run list: exit 0. S10 sets a fixture successful run to a different SHA and again observes exit 0 with a mismatch. This isolates the missing equality gate; a live branch race was not attempted.

**Bounded fix:** When collection is intended as verified promotion, require a successful branch run for the exact fetched commit, associated with the checks/config identity and assignment attempt. Fetch into a temporary ref, compare before updating the consumer branch, and record that immutable SHA. Release should confirm the same collected object remains available. If unverified collection is intentionally allowed for inspection, make it explicit and label it unverified; do not treat it as release evidence.

**Regression:** Cover no run, failed run, stale successful SHA, changed config/checks, and branch advancement during fetch. Only a matching approved run should receive verified status. A worker report must never substitute for a check record.

### F4 — Medium: state directory trust and temporary-file symlinks

**References:** `ops/lib.sh:16–19,27–44,51–54,96–101`; `ops/dispatch.sh:75–76,143–144`; `ops/status.sh:11–12`.

**Prerequisite and impact:** The state directory or its entries are attacker-writable, pre-created permissively, or shared with a same-user worker. `umask 077` restricts newly created objects but does not validate existing directory ownership/modes or reject a symlinked state root. `loom_write` redirects into predictable `.pending`, following symlinks before moving it. Some readers reject symlink records, but directory scans are inconsistent. The lock is advisory between cooperating callers, not an authorization boundary.

**Reproduction:** S1 links `.pending` to a disposable file, calls `loom_write`, and proves the target was overwritten and the record became a symlink. This is a fixture-only arbitrary-write primitive conditional on state-directory access.

**Bounded fix:** Validate a private, non-symlink state root and protected ancestors; fail closed on unsafe ownership/modes. Use an unpredictable `mktemp` file in that directory, validate output, then rename it while holding the lock. Reject links consistently on reads. Document that same-UID isolation needs a runtime or separate identity, not mode 0700 alone.

**Regression:** Test pre-existing unsafe state roots, symlinked roots/records/temp names, and failed writes without record corruption. The victim fixture must remain unchanged.

**Additional locking risk (static only):** The stale-lock branch at `ops/lib.sh:29–32` continues without incrementing the retry counter. If owner removal succeeds but directory removal cannot, subsequent behavior depends on whether an owner remains; with a persistent unremovable dead owner it can spin outside the intended wait bound. PID-only ownership also permits false liveness on PID reuse. Reclaiming without an ownership token can race another acquirer. Bound every retry path and make unlock/reclaim ownership-aware; test concurrent acquire/reclaim and malformed locks with disposable processes. No live-lock sabotage or signalling was attempted.

### F5 — Medium: evidence copying retains escaping nested links

**References:** `ops/lib.sh:166–183`; remote extraction at `ops/lib.sh:177`.

**Prerequisite and impact:** A worker controls `.loom/`. Only its top-level path is checked. Nested symbolic links survive local copying, leaving conductor-side evidence that can resolve outside its directory when subsequently read. This probe does not show that `cp -R` itself dereferences and copies the external target. Remote tar extraction similarly needs an explicit policy for entry types, traversal and size; no malicious remote archive was tested.

**Reproduction:** S2 puts a symlink inside `.loom`, copies evidence, then reads a harmless outside fixture through the copied link. The copied evidence is therefore not self-contained.

**Bounded fix:** Reject nested symlinks and special files and copy only validated regular files/directories, without following links. Bound file count and total size. For remote archives, validate entries before extraction into a new private directory and publish only after validation. Do not rely on the top-level link check as a containment guarantee.

**Regression:** Cover nested absolute/relative escaping links, link chains, special files, oversized evidence, and archive traversal/hardlinks on each supported tar platform. Assert no outside fixture is accessed or modified.

### F6 — Medium: origin and bootstrap checks do not authenticate code provenance

**References:** `ops/dispatch.sh:43–52,60–67`; `docs/bootstrap.txt:20–30`; `docs/bootstrap.md:14–15`.

**Prerequisite and impact:** An attacker substitutes a checkout or controls its origin metadata. Dispatch deliberately ignores the origin host, so an unrelated server with the same owner/repo path passes the repository comparison. Bootstrap accepts any existing directory at its chosen destination, checks dirtiness, then executes that directory's selftest without establishing repository origin or a trusted revision. A clean malicious checkout passes cleanliness. Even a matching origin string is mutable metadata, not proof of code authenticity.

**Reproduction:** S8 runs the exact dispatch normalizer against an `.invalid` origin and gets the expected slug. Bootstrap's arbitrary-clean-directory execution path was inspected statically; no bootstrap was run against an existing installation.

**Bounded fix:** Require a canonical allowed host and repository identity, and clearly label explicit local-only overrides. Bootstrap should reject unrelated existing directories and verify a reviewed immutable revision or authenticated release before executing code. Any alternative forge must be an explicit owner configuration, not silently accepted by stripping the host.

**Regression:** Feed same-slug foreign hosts, malformed URLs, local paths and clean unrelated fixture repos. Permit documented URL forms for the approved host. Assert no selftest runs until provenance checks pass.

### F7 — Medium for agent consumers: reports and persistent instructions lack authority provenance

**References:** `ops/lib.sh:189–208,232`, `ops/report.sh:11–14`, `ops/verify.sh:104–111`, `ops/dispatch.sh:54–57,116–123`, `ops/orca.sh:160–165,207,213`.

**Prerequisite and impact:** A worker writes its report, or an issue author changes text later consumed as a mandate. Harvest accepts a fresh state line but does not attach an authenticated report source; worker and conductor reports share the same state/fact structure. A worker can use wording that impersonates verification. This does not falsify `checks_runs`, and `ready` is explicitly only a claim in `PROTOCOL.md:41–46`. It becomes dangerous when an agent or downstream gate trusts prose. Issue-body mandates are read at dispatch without an immutable issue revision/content digest or author authorization check; their described immutability is procedural. Worker-controlled instruction files can also survive into future checkouts if collected and merged without review.

**Reproduction:** S7 harvests `state: ready — conductor verified: fabricated fixture claim` and confirms it is retained without provenance. Workspace operations are stubbed; only parsing and record append run. No prompt-injection attempt was sent to a real agent.

**Bounded fix:** Store report source, attempt and content digest separately from untrusted fact text. Reserve verification verdicts for structured check records. Pin the accepted mandate/config content; classify changes to agent instructions, hooks and calibration policy as authority-sensitive review items. Treat evidence and retrieved instructions as data unless explicitly authorized by the owner.

**Regression:** A forged verification fact must remain visibly worker-authored and fail every promotion gate. Changed issue bodies must not silently redefine an existing accepted mandate. Test newly introduced instruction files and embedded instructions in reports without giving fixtures tool authority.

## Other assessed boundaries

- **Shell interpolation:** Config parsing uses jq, not `source` or `eval` (`ops/lib.sh:236–264`). Remote workspace argv use `printf %q` (`ops/lib.sh:140–147`). No direct shell interpolation exploit was demonstrated in those paths. `compute_setup` is intentionally evaluated on the remote host (`ops/verify.sh:85`); it is executable authority. Config `checks` lacks a string type check: S3 accepts `checks = 7`, which will later become an invalid command. Reject non-string checks, unsupported control characters and malformed executable fields at parsing time; add parser regression cases.
- **Worker confinement and pushing:** `PROTOCOL.md:15–16` promises role boundaries. Removing a remote (`ops/dispatch.sh:99–104`) prevents accidental default pushes, not explicit-URL pushes or re-adding a remote. Local launch establishes neither filesystem confinement nor credential separation; Orca worktrees share repository metadata. Runtime sandbox/identity/network enforcement must supply these boundaries. No push attempt was made.
- **Credential and privacy handling:** Worker logs (`ops/launch.sh:34–36`), checks logs (`ops/verify.sh:71–88`) and raw transcripts (`ops/orca.sh:367–369`) capture output without content filtering. The bootstrap instruction not to write credentials is a policy, not a redactor. No credentials were inspected. Keep raw evidence private, limit retention, and redact before publication; do not claim that sanitization can detect every secret.
- **Monitoring:** `ops/heartbeat.sh:51–57` acts only while its foreground loop runs. `ops/status.sh:14–23` surfaces stale Orca workers when invoked. These are not evidence of an always-on monitor or universal recovery. The external Orca runtime was not security-tested.

## Proposed calibration: required boundaries, not implemented assurances

No calibration implementation or dedicated calibration design was found in the reviewed tracked tree; `README.md:38–40` explicitly excludes a memory store and scheduler. The following is a prospective threat assessment, not a finding about nonexistent code.

| Proposed input or action | Risk | Bounded requirement and regression |
| --- | --- | --- |
| Worker evidence, reports, transcripts | Prompt injection, forged success, hidden external links or secrets | Preserve untrusted provenance, reject unsafe evidence objects, and test fixtures that instruct the evaluator to skip checks or reveal a synthetic canary. No tool action should result. |
| Scores derived from checks | Benchmark gaming, self-edited tests, baseline laundering | Bind score to code SHA, checks/config digest, baseline and actual exit status. Use conductor-owned criteria and adversarial cases; changing tests must not silently redefine success. |
| Stored lessons or agent instructions | One malicious observation becomes durable authority across assignments | Separate observations from approved policy. Record source/digest/reviewer, scope and expiry; require explicit promotion for authority changes and support rollback. A report cannot directly rewrite standing instructions. |
| Automatic retries, routing, model or compute selection | Spend escalation, unsafe hosts, wider scope, unbounded loops | Apply explicit limits and allowlists with fail-closed enforcement. Test refusal on exhausted limits and unknown destinations. Calibration must not weaken consumer laws or grant capabilities. |
| Verification/collection feedback | Success for one artifact attached to another | Require exact immutable identity and structured provenance as in F3/F7; stale or absent evidence must remain unknown, not pass. |
| Background improvement claims | Claimed monitoring without a live scheduler or runtime | Describe only mechanisms actually installed and running; test restart/recovery before claiming persistent operation. |

## Validation and limitations

Reproduction assertions completed with captured exit 0. Required consumer command `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom` completed with captured combined exit **0**; both commands ran successfully. The reproduction ran under Bash 5.3.20; ShellCheck was 0.11.0. `git diff --check` also returned 0. A passing repository suite establishes its covered behavior, not absence of these findings.

Not tested: real remote hosts or SSH proxy execution; external Orca sandbox/authentication; credential theft or network exfiltration; malicious hooks; hostile remote archive extraction; live lock races; filesystem races on other operating systems; Bash 3.2 on a separate platform; bootstrap installation; mutation suite; persistent calibration behavior or statistical calibration quality. Fix recommendations preserve the existing Bash 3.2/dependency constraints and are not implementations. No universal security, dependable background monitoring, or isolation assurance is claimed.
