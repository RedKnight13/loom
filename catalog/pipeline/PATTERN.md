name: Pipeline — sequential / prompt chaining
author: Loom contributors
upstream: https://www.anthropic.com/research/building-effective-agents
license: MIT
when: Fixed dependent stages; each receives reviewed previous artifact.
cost: Up to three stages, one worker at a time; one check per stage. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: Reviewed stage artifacts make fixed dependencies explicit; serial latency and mistakes passed downstream can erase the benefit. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: No specific requirement observed; choose from observed model capabilities for the task, without inventing a model-strength threshold.
steps:
Define at most three dependent stages with reviewed input and output artifacts. Use separate scoped tickets as needed and only one active worker at a time. The conductor reviews each stage and its check before authorizing the next; a failed stage stops dependent work. Do not install or imply an automatic pipeline.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
