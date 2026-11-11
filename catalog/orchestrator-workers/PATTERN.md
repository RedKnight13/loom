name: Orchestrator-workers
author: Loom contributors
upstream: https://www.anthropic.com/research/building-effective-agents
license: MIT
when: Subtasks discovered during work; conductor keeps overall context.
cost: At most two active workers, three total subtasks, one synthesis review. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: Bounded decomposition accommodates subtasks discovered during work; decomposition mistakes and coordination overhead remain risks. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Have the conductor propose scoped tickets as subtasks emerge, with at most two active workers and three total subtasks. Use existing dispatch, verification and collection, followed by one synthesis review. Pause for a new scope or dependency decision; workers do not recursively spawn other workers.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
