# Legacy process settlement

Run `bash tests/legacy/settlement.sh` for the focused offline regression. The
standard `bash ops/selftest.sh` also runs it. Fixtures hold a background writer
behind an explicit release file: the command leader reports ready and exits,
but harvest must leave the report, index, commit and evidence untouched until
the writer finishes. Recovery, guard loss, watchdog timeout, identity reuse,
stale receipts, failed signals, PID-only fallback and uncertain post-kill
observations are covered. No existing selftest is skipped.

The legacy launcher records a guard as `worker_pid`, with an identity token and
a private process group. The guard waits for the command and all non-zombie
members of that group, then publishes a receipt bound to its identity. Harvest
requires that receipt and a fresh empty-group observation. The command's exit
status and report-offset behavior are preserved. A lost launcher can be
recovered by the watchdog after the guard completes. A lost guard without its
receipt stays pending, as do old records whose command has vanished without
group evidence. Those cases require conductor investigation; a ready line or a
missing PID cannot authorize sealing or redispatch.

Before a timeout signal the watchdog persists a stop request bound to the
verified guard. A successful signal is not settlement. The watchdog and
launcher retain the PID, identity and slot while any group member can write,
identity mismatches, or observation is uncertain. A bounded wait can report
`pending settlement_unproven`; later watchdog runs reconcile without signalling
again. Only an empty group with no live or mismatched guard permits recording
`failed watchdog_kill` and clearing ownership. That path never harvests the
early ready report or seals evidence. Old unguarded records can still receive
identity-checked timeout signals, but remain pending without completion proof.

Linux uses boot identity and `/proc` start ticks. Inaccessible `/proc` never
falls back to weaker identity. macOS uses `LC_ALL=C ps` start time and a validated
full PID/PGID/state snapshot, preserving the prior second-resolution identity
limit. The live guard pins its group until completion; the snapshot observer
runs in its own group so it does not count itself as a worker. The launch
handshake works without `BASHPID`, including Bash 3.2. Other platforms fail
before starting worker code. Empty, malformed or failed `ps` snapshots cannot
prove settlement. Zombies cannot write and do not block settlement.

On Linux the regression also reruns every integration case with Darwin routing
and the host's `ps`, plus controlled BSD-shaped parsing fixtures. This is routing
coverage, **not actual macOS validation**; the conductor's macOS CI must run the
full selftest and lint on macOS. The supported contract assumes full visibility
of the inherited process group in the same PID namespace. macOS start time
cannot distinguish same-second PID reuse, and neither backend offers atomic
check-and-signal. These are explicit legacy limitations, not pidfd guarantees.

Process groups are not containment: a worker must keep writers in its inherited
group. Deliberate `setsid`/`setpgid` escapes, remote writers, changes of user or
PID namespace, and hidden process listings are not supported supervision
contracts. No new dependency or native-supervisor change is introduced.

Run `bash tests/review/review-legacy.sh` for locking, ticket reservation,
collection and mailbox regressions. `LOOM_MUTATE_LEGACY_ONLY=1 bash
ops/mutate.sh` runs their focused mutants together with the affected settlement
mutants; it does not run the full matrix. The mutation harness checks an
unmutated control before interpreting any failure as a caught mutant.

Lock acquisitions use unique owner filenames and record a PID plus start time
when available. Only a successful unlink of the observed owner permits removal
of the empty directory. A losing stale reaper cannot remove even an unpublished
replacement directory, and a delayed unlock cannot clear a replacement's
pending write. Legacy PID-only locks remain readable. A crash before publishing
an owner leaves an unowned directory that requires investigation; absence of an
owner is not proof that an acquiring process is dead. Restricted offline drills
without `ps` use conservative PID-only claims. Concurrent older lock clients
must be drained before upgrading because their unconditional unlink is unsafe.

Pending records reserve their ticket, including records dispatched before the
worker starts. Both local launch and Orca start recheck sibling reservations
while holding the state lock. Historical duplicate pending records therefore
require explicit retirement before either can start.

Private-clone collection refuses a branch checked out in any linked consumer
worktree, with a second check just before the guarded ref update. Shared Orca
worktrees are observed without moving their branch. Git does not provide an
atomic transaction spanning worktree checkout state and a ref update, so
concurrent external checkout operations must be serialized by the conductor.
A follow-up clears current collection authorization but preserves the prior SHA
as a compare-and-swap baseline; any conductor edit still refuses recollection.
