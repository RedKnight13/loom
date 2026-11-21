# Worktree-owned Loom instances

A tools checkout can serve multiple Git worktrees. Setup reserves the consumer
worktree's ignored `.loom-instance/` directory. Its private consumer config,
calibration, assignment records, locks and native workflow routes belong to
that checkout. Resolve the checkout through `LOOM_REPO` or the current Git
worktree, including calls from subdirectories. Read-only commands must not
create state. An explicit `LOOM_STATE` still selects an operator-specified
store. Unconfigured consumers retain their existing behavior and records.

Assignment IDs remain local. Names exposed to shared worker pools, Orca and
Git refs must distinguish two instances dispatching the same ticket. Record
the worker branch at dispatch or, for Orca, when its receipt arrives. The
collect and verify commands continue to use that recorded branch. GitHub
tickets and repository refs remain shared GitHub and Git resources.

Setup is repeatable and leaves existing assignments in their original store.
Setup must preserve existing ignore rules, refuse tracked private paths and
symlinked instance directories, and never put runtime data in Git.
