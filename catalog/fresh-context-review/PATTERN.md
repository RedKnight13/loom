name: Fresh-context design/review — EGM-inspired
author: Loom contributors
upstream: https://github.com/google/elephant-goldfish-model
license: MIT
when: Context-rich designer drafts spec; isolated reviewer sees only draft and referenced material, never prior conversation.
cost: One designer and one fresh reviewer, sequential; two review rounds; user architecture approval before implementation. Proposed planning bounds, not a cost or performance promise; count the conductor separately from worker slots and include coordination, checks and rework. Actual spend and elapsed time are unknown without task budgets and verified rates.
effectiveness: A reviewer without the prior conversation can expose assumptions in a context-rich draft; missing references can also impair review, and same-context review cannot supply freshness. Basis: task fit and failure risks in the maintained family comparison, not a measured Loom gain.
intelligence: Ambiguous design is the basis for considering stronger reasoning when observed capabilities support that fit; reviewer independence requires isolated context, not a particular model or model family.
steps:
Have the context-rich designer draft the specification, then give a separate fresh reviewer only that draft and its referenced material, never the prior conversation. Confirm isolation before using this recipe; otherwise label it unavailable and offer solo work with human review without silently switching. Bound review to two rounds and require user architecture approval before implementation. Stop at unresolved tradeoffs. This borrows the separation only and does not install the EGM plugin or its full workflow.

Keep every worker under this session and PROTOCOL.md: one assignment, one isolated worktree and one structured report line per turn, with at most one live assignment per ticket. Workers never push. PROTOCOL.md, consumer laws, trusted checks and the owner-only finish override these steps. This pattern grants no permission, changes no gate and authorizes no push, merge or work outside this session. Lower proposed bounds to approved capacity and budgets; missing bounds, failed checks, calibration drift or missing required capabilities stop dependent work.
