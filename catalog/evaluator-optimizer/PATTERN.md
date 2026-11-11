name: Evaluator-optimizer — maker-checker / critic loop
author: Loom contributors
upstream: https://www.anthropic.com/research/building-effective-agents
license: MIT
when: Clear rubric; checker sees artifact and criteria.
cost: One maker and one checker, sequential; two critique/revision rounds. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: An explicit rubric gives critique a concrete target; circular critique and false approval remain possible, and tests still carry authority. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
State the rubric and give a sequential checker the artifact and criteria after the maker reports. Let the conductor authorize scoped revisions, with at most two critique/revision rounds. Stop on acceptance, stalled improvement or the round cap. Trusted checks remain evidence; neither critique nor approval replaces them or creates an automatic retry loop.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
