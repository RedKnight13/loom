name: Specialist routing
author: Loom contributors
upstream: https://www.anthropic.com/research/building-effective-agents
license: MIT
when: Known task categories; selected specialist gets relevant brief.
cost: One selected worker per task; one routing decision. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: A relevant brief can focus a specialist on a known category; misclassification or unclear access defeats that fit. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Have the conductor make one routing decision from a known task category and the observed access. Give the selected worker only the relevant brief under the reviewed ticket, consumer and harness. Stop if category or access is unclear; this does not install a model router.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
