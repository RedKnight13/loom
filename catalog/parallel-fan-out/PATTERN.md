name: Parallel fan-out/fan-in — sectioning / concurrent / scatter-gather
author: Loom contributors
upstream: https://www.anthropic.com/research/building-effective-agents
license: MIT
when: Predefined independent work; minimal shared files and bounded briefs.
cost: Two workers concurrently plus conductor; one integration review. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: Independent work can progress concurrently; duplicate effort, shared-file conflicts and integration cost can outweigh the benefit. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Confirm independent scopes, minimal shared files and authorized parallel capacity before dispatch. The conductor assigns two workers separate tickets, assignments and isolated worktrees with bounded briefs. Verify each result, perform one explicit integration review and verify the combined revision. Stop if independence fails; separate passing branches do not prove integration.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
