name: Solo baseline — single agent with tools
author: Loom contributors
upstream: https://www.anthropic.com/research/building-effective-agents
license: MIT
when: One scoped change; one task context.
cost: One worker; one verification/rework cycle. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: A single task context avoids coordination overhead for a scoped change; self-review can miss defects, so trusted verification and human review remain necessary. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Keep the scoped change in one ticket with one worker. Complete one verification/rework cycle, then report the artifact for trusted verification, collection and human review. Stop at acceptance, scope conflict or the approved budget.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
