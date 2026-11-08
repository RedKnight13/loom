name: Magentic planning — adaptive / task-ledger orchestration
author: Loom contributors
upstream: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns
license: MIT
when: Open-ended planning, explicit evolving task ledger.
cost: One planner, at most two scoped workers; two replans before human review. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: An evolving ledger can make open-ended planning explicit; runaway planning and side effects require bounded replanning and human review, not an assumed runtime. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Keep magentic execution informational/recipe-only: Loom has no magentic manager or runtime. A conductor may borrow a manual ledger and scoped tickets within existing authorization, using one planner and at most two scoped workers. Limit replanning to two rounds before human review. Stop on stalled progress, budget exhaustion or a plan change needing approval; this entry cannot enable automatic execution.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
