name: Handoffs — transfer / triage
author: Loom contributors
upstream: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns
license: MIT
when: Expertise changes; curated state and unresolved questions pass to next role.
cost: One active worker at a time; at most two transfers. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: Curated state can support a change of expertise; lost context, unclear ownership and repeated transfers undermine continuity. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Have the conductor settle the prior assignment and review its artifact, current state and unresolved questions before authorizing the next scoped assignment. Keep only one worker active at a time and allow at most two transfers. Stop if the receiver or ownership boundary is unclear; no overlapping workers on one ticket or automatic ownership transfer.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
