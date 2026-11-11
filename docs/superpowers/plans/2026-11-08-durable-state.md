# Durable state implementation plan

Implement S2 against the executor-boundary design and protocol 1.0 reference.
All workloads are synthetic; shared CLI/lib routing is outside this slice.

1. Define source-safe `loom_state_*` and `loom_events_read` APIs, closed storage
   envelopes and a canonical JSON transaction format; publish the integration seam.
2. Implement Linux capability checks, private paths, bounded identity-aware locking,
   immutable journal commit barriers, atomic multi-record CAS and operation dedupe.
3. Replay every committed transaction, validate sequence/hash/revision/epoch chains,
   rebuild disposable snapshots, and expose explicit legacy read-only projections.
4. Exercise real process crashes at write/flush/rename boundaries, corruption,
   concurrent writers, stale identities, payload conflicts and schema/path isolation.
5. Run focused tests and `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`;
   capture command exits in `.loom/validation.md`, then report reviewable work.

Storage does not decide task transitions or interpret provider receipts: S6/S7
validate their domain payloads before calling the atomic storage API. Each storage
mutation has its own immutable operation outcome; a long-lived execution operation
is a revisioned `operation` entity whose intent and reconciliation are separate
idempotent storage mutations. No lock spans a provider call.
