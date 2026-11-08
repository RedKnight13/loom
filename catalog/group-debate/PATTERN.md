name: Group chat / debate — roundtable / council
author: Loom contributors
upstream: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns
license: MIT
when: Shared discussion for competing perspectives; shared context is not fresh review.
cost: At most three participants including moderator; two rounds. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: Shared discussion can surface competing perspectives; conformity and discussion cost can obscure disagreement, and shared context is not fresh review. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Keep this informational unless an authorized harness supplies bounded shared discussion. If available, define the question and moderator, with at most three participants including the moderator and two rounds. Collect perspectives and evidence for review; stop at the cap or an unresolved owner decision. Shared discussion is not isolated review, and Loom mail does not supply a group-chat manager.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
