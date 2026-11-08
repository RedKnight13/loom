name: Independent voting
author: Loom contributors
upstream: https://www.anthropic.com/research/building-effective-agents
license: MIT
when: Same rubric/artifact, separate assessments before aggregation.
cost: Two reviewers plus conductor; one independent round. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: Separate assessments can expose conflicting evidence before aggregation; correlated errors and split judgments mean votes are not proof. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Give two isolated read-only reviewers the same artifact and rubric in separate assignments. Keep their assessments separate until both report, then have the conductor aggregate one independent round. Escalate disagreements for human resolution; a majority is not proof and implementation still needs trusted verification. Stop if isolation is unavailable.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
