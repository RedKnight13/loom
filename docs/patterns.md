---
layout: null
---
{::nomarkdown}
<!DOCTYPE html>
{:/nomarkdown}
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Coordination patterns and model roles — Loom</title>
  <meta name="description" content="Compare bounded coordination recipes, choose a pattern explicitly, and match model roles to observed harness capabilities. Advisory guidance, not automatic routing.">
  <link rel="stylesheet" href="assets/site.css">
</head>
<body class="setup-page">
<a class="skip" href="#main">Skip to content</a>
<header class="site-header wrap">
  <a class="brand" href="index.html" aria-label="Loom home"><span class="mark" aria-hidden="true">▥</span> loom</a>
  <nav aria-label="Main navigation"><a href="index.html">Overview</a><a href="setup.html">Setup</a><a href="copy.html">Bootstrap prompt</a></nav>
</header>
<main id="main" class="wrap" tabindex="-1">
<div class="manual-heading">
  <p class="intro">Choose the simplest adequate workflow</p>
  <h1>Coordination patterns<br>and model roles</h1>
  <p class="lead">Three recommendations for your task. One explicit choice. Advice grounded in the capabilities you actually have.</p>
  <p><a href="copy.html">Copy the bootstrap prompt</a> or <a href="setup.html#manual-reference">return to setup</a>. You can keep a single scoped worker or defer selection.</p>
</div>
<div class="setup-reference">
<aside class="setup-toc" aria-label="Pattern reference navigation">
  <nav aria-label="Pattern sections">
    <a href="#recommendations">Three recommendations</a>
    <a href="#cost">Cost and effectiveness</a>
    <a href="#models">Model-role matching</a>
    <a href="#catalog">Full maintained catalog</a>
    <a href="#choice">Save an explicit choice</a>
    <a href="#mechanics">Loom mechanics and limits</a>
    <a href="#sources">Primary sources</a>
  </nav>
</aside>
<div class="setup-doc" markdown="1">

## Three recommendations
{: id="recommendations"}

Bootstrap inspects the task, repository, dependencies/shared files, trusted
checks, budget, authorized execution location, harnesses, worker cap and existing
choice. It then offers **exactly three candidates**, marks **one recommended**,
and includes a **single scoped worker baseline** even when that is not one of
the three. A small fix can favor solo work; independent subtasks can favor
fan-out; architectural uncertainty can favor design plus fresh review. These
are examples, not a fixed team prescription. Start with the simplest adequate
workflow, as recommended by [Anthropic][effective] and [Microsoft][azure].

Use these columns for the three-row recommendation table:

<div class="table-region" role="region" tabindex="0" aria-label="Recommendation table fields; scroll horizontally if needed" markdown="1">

| Candidate and status | Fit / rationale | Roles / peak concurrency | Cost increase vs baseline | Time / human productivity | Effectiveness / tradeoffs | Constraints |
| --- | --- | --- | --- | --- | --- | --- |
| Name; one marked recommended | Task evidence, dependencies | Count workers and coordinator; context boundaries | Assumptions, rate source/date or unknown; confidence | Expected direction, bottlenecks; no invented gain | Source plus task-specific inference; defects/rework risk | Caps, budgets, tools, host policy, stop conditions |

</div>

Give each candidate its own [role table](#models), including unavailable roles.
Status is determined by observation, not by a catalog label:

- **Recommendable:** the bounded recipe fits the task and its required capabilities
  are observed. This is advice, not permission or launch verification.
- **Recipe-only:** a useful composition, with capabilities or configuration still
  unverified. Explain what would be needed; selection cannot create it.
- **Unavailable:** a required capability is absent, forbidden or incompatible.
  State why and offer the simpler route.

If fewer than three are feasible, still show three candidates with honest
unavailable/recipe-only labels. Recommend the simplest safe route, identifying
any blocked execution; do not fabricate three runnable teams. Without project
access, the comparison is provisional and wiring remains unverified. Missing
automatic model discovery does not prevent advice: use explicitly user-supplied
observed inventory or label it unknown. No Orca prerequisite applies.

Offer four responses: choose a candidate, **manual catalog**, keep simple
baseline, or defer. Manual means show every family below with its current
capability status, then validate the selected recipe. This is the full maintained
catalog, **not all possible patterns**. Neither silence nor a timeout selects
anything. No choice grants installation, configuration changes or worker launch.

## Cost and effectiveness
{: id="cost"}

Keep four measures separate: **total spend**, **wall-clock completion time**,
**accepted work per human hour**, and **defects/rework**. More concurrent workers
can shorten an independent critical path while increasing total tokens and
integration effort. Faster output is not automatically more accepted work.
These are planning hypotheses to validate for this task, not measured gains.

For a cost estimate, budget input/output tokens for every role and round, then
multiply by **verified current provider rates** for the actual model, billing
channel and token class (including cache/reasoning treatment where applicable).
Cite rate pages with observation date. Add coordinator, reviewer, retry,
tool/service and compute costs; do not count coordinator/review twice if already
included in the role sum. Report uncertainty and low/high budget assumptions.
Missing rates, budgets or access mean **unknown**, not free. Subscription quota
consumption is not a cash invoice; report quota and marginal cash separately.

Illustrative arithmetic only, not a benchmark or a price quote: two bounded
workers each budgeted 10,000 input and 2,000 output tokens consume 20,000 input
and 4,000 output tokens before coordination, review or retries. If verified rates
are `Rin` and `Rout` per million tokens, that worker portion is
`0.020 × Rin + 0.004 × Rout`. Compare the whole recipe with a budgeted single
worker on the same task, checks and acceptance criteria. If its spend is `B`
and the recipe's is `T`, the absolute increase is `T − B`; unknown terms stay
unknown. This calculation establishes no speed or quality benefit.

Do not publish a productivity/cost-increase percentage without a task-matched
measured baseline, method and provenance. Qualitative estimates must name their
assumptions and confidence. Anthropic's [multi-agent research report][research]
describes benefits and substantial token overhead in its research system, and
warns that coding often has fewer independent subtasks. Its research results
are **not coding or Loom predictions**. Loom installs no telemetry or automatic
outcome tracking; any later measurement needs separate authorization.

## Match models to roles, from observed capabilities
{: id="models"}

Start provider-neutral: inspect the authorized executor, installed harnesses,
existing consumer settings, task needs and user model/effort preferences.
Local and custom harnesses are valid advisory paths. Discover read-only inventory
through the installed harness's help or available provider tools, on the intended
authorized execution host. Local observations do not establish remote access.
Use only supported inventory commands; if none exists, accept the user's explicit
observed inventory with provenance or leave fields unknown and ask minimally.
Never scrape auth/token files, run paid/model test calls, install a framework,
buy accounts or change logins to populate a recommendation.

When Orca is available, its `agent-context --json` describes the installed CLI.
The inspected adapter supports host/account discovery and model/effort launch
fields, but **no universal model catalog**. Do not invent `orca models` or
`orca agent list`. `account list` covers particular managed account providers;
it is not proof of other agents' access. Loom `capacity` counts connected hosts,
not installed agents, model choices, remaining quotas or safe concurrency.
Inventory should not depend on Orca being installed or ready.

Distinguish evidence levels:

- **Installed:** a harness binary/tool exists. Help examples are not model access.
- **Configured:** an approved config or supported inventory reports an exact
  agent/provider/model. A listed ID, default or alias can still be inaccessible.
- **Launch-verified:** a separately authorized launch receipt identifies the
  effective configuration at a stated time. Prior success does not prove current
  quota/access, and no test launch is authorized by bootstrap advice.

For **each of the three candidates**, fill one row per role using this format:

<div class="table-region" role="region" tabindex="0" aria-label="Model-role recommendation fields; scroll horizontally if needed" markdown="1">

| Role | Exact observed agent / provider / model | Host | Effort | Why suitable | Availability evidence | Cost basis / confidence |
| --- | --- | --- | --- | --- | --- | --- |
| Coordinator, designer, worker or reviewer | Exact IDs or unknown; distinguish alias from resolved ID | Authorized location; private reference in shared files | Observed supported value, unchanged preference, or unknown / unsupported | Task fit and limits | Installed / configured / launch-verified; source and freshness; unknown access/quota | Verified rate and token budget, subscription quota, or unknown; confidence |

</div>

Favor a suitable smaller/cheaper **observed** model for bounded execution and
stronger reasoning for ambiguous design, when evidence supports that fit and
cost. Preserve explicit user choices even when another model seems preferable;
present conflicts for review. Unknown inventory never justifies fabricated
model names or forced configuration changes. Reviewer independence comes from
**isolated context and a separate assessment**. Different model families are
optional diversity, not proof of independence or correctness.

Advice and applied settings are separate. The current Loom **Orca** `start`
exposes only `--agent`; model/effort come from the consumer snapshot pinned at
`dispatch`. Orca's lower-level launch flags do not create Loom per-role flags.
Per-role model routing is unsupported without explicitly reviewed consumer
configurations. Never auto-edit shared config or existing assignment records.
For local `launch ID -- CMD...`, the authorized command/harness controls model
selection; do not assume Orca settings are applied or invent custom adapters.
Before a separately authorized launch, check the effective agent/model/effort/
host fields the executor actually exposes. If absent or mismatched, report that
application is unverified and stop dependent work rather than claiming success.
Respect budgets, caps, host restrictions and authorization on every path.

## Full maintained catalog
{: id="catalog"}

The source links describe pattern families; the following Loom mappings and
bounds are **proposed recipes**, not installed plugins or source benchmarks.
Their status must be reevaluated for the current harness. A composition uses
existing tools under a conductor's supervision; it does not implement a framework.
All recipes inherit the [mechanics and stop rules](#mechanics). Counts below are
starting bounds to propose for explicit review, never automatically configured
caps. Count the coordinator separately from worker slots and lower every bound
to fit the approved budget and capacity. A missing bound blocks expansion.

<div class="table-region" role="region" tabindex="0" aria-label="Full maintained coordination catalog; scroll horizontally if needed" markdown="1">

| Family / aliases and source | Fit and context boundary | Proposed worker / review bounds | Risks and stop conditions | Loom mapping / capability requirement |
| --- | --- | --- | --- | --- |
| **Solo baseline** — single agent with tools ([Microsoft][azure]) | One scoped change; one task context | One worker; one verification/rework cycle | Self-review blind spots; stop at acceptance, scope conflict or exhausted budget | One ticket and worker, trusted verify, collect and human review; local or supported executor |
| **Pipeline** — sequential / prompt chaining ([Anthropic][effective], [Microsoft][azure]) | Fixed dependent stages; each receives reviewed previous artifact | Up to three stages, one worker at a time; one check per stage | Serial latency, propagated mistakes; stop on a failed stage | Separate scoped tickets as needed; conductor reviews output before the next stage; no automatic pipeline |
| **Specialist routing** ([Anthropic][effective]) | Known task categories; selected specialist gets relevant brief | One selected worker per task; one routing decision | Misclassification; stop when category or access is unclear | Conductor chooses a reviewed ticket/consumer/harness; no automatic model router |
| **Parallel fan-out/fan-in** — sectioning / concurrent / scatter-gather ([Anthropic][effective], [Microsoft][azure]) | Predefined independent work; minimal shared files and bounded briefs | Two workers concurrently plus conductor; one integration review | Duplicate work, conflicts, synthesis cost; stop if independence fails | Separate tickets/assignments, verify each, integrate explicitly and verify combined revision; requires authorized parallel capacity |
| **Orchestrator-workers** ([Anthropic][effective]) | Subtasks discovered during work; conductor keeps overall context | At most two active workers, three total subtasks, one synthesis review | Decomposition and coordination errors; pause on new scope/dependency | Conductor proposes bounded tickets dynamically; existing dispatch/verify/collect only; no recursive spawning by recipe |
| **Evaluator-optimizer** — maker-checker / critic loop ([Anthropic][effective], [Microsoft][azure]) | Clear rubric; checker sees artifact and criteria | One maker and one checker, sequential; two critique/revision rounds | Circular critique, false approval; stop on acceptance, stalled improvement or round cap | Review deliverable then scoped revision; tests remain authoritative evidence; no automatic retry loop |
| **Fresh-context design/review** — EGM-inspired ([EGM][egm]) | Context-rich designer drafts spec; isolated reviewer sees only draft and referenced material, never prior conversation | One designer and one fresh reviewer, sequential; two review rounds; user architecture approval before implementation | Missing context may expose assumptions; freshness cannot be faked; stop if isolation unavailable or tradeoff unresolved | Design/review tickets and owner approval; recipe-only until isolation observed; not the EGM plugin or its full staged workflow |
| **Independent voting** ([Anthropic][effective]) | Same rubric/artifact, separate assessments before aggregation | Two reviewers plus conductor; one independent round | Correlated errors, inconclusive split; escalate disagreements, no majority-as-proof | Separate read-only review tasks; human resolves evidence, implementation still verified; requires isolated contexts |
| **Group chat / debate** — roundtable / council ([Microsoft][azure]) | Shared discussion for competing perspectives; shared context is not fresh review | At most three participants including moderator; two rounds | Conformity, discussion cost; stop on round cap or unresolved owner decision | Informational unless an authorized harness supplies bounded shared discussion; Loom mail alone does not install a group-chat manager |
| **Handoffs** — transfer / triage ([Microsoft][azure]) | Expertise changes; curated state and unresolved questions pass to next role | One active worker at a time; at most two transfers | Lost state, ownership gaps, bouncing; stop if receiver/boundary unclear | Conductor settles prior work and authorizes next scoped assignment; no automatic ownership transfer or overlapping worker on one ticket |
| **Magentic planning** — adaptive / task-ledger orchestration ([Microsoft][azure]) | Open-ended planning, explicit evolving task ledger | One planner, at most two scoped workers; two replans before human review | Runaway planning and side effects; stop at stalled progress, budget or plan change needing approval | Informational/recipe-only: manual plan and tickets can borrow the idea; Loom has no magentic manager/runtime; unavailable for automatic execution |

</div>

The EGM source assigns design to a context-rich agent and review to fresh
contexts; the user resolves tradeoffs and approves architecture. This catalog
borrows that separation only. It does **not** install EGM, claim its plugin's
skills exist, or silently replace fresh review with same-context self-review.
If isolation is unavailable, label the recipe unavailable and offer solo work
with human review, clearly describing the change. [EGM source][egm]

## Save an explicit choice
{: id="choice"}

Reuse a still-applicable approved selection. New recommendations stay proposals
until explicitly accepted; never overwrite the current choice on a setup rerun.
If it becomes infeasible, stop work that depends on it and offer a simpler route
without silently changing the selection. Existing tasks with no choice keep
their existing authorization and checks; no extra workers are implied. Deferral
saves no approved choice and does not disable unrelated work.

After selection, use the [session template](https://github.com/RedKnight13/loom/blob/main/templates/LOOM_SESSION.md)
to save one `loom-pattern:start` / `loom-pattern:end` section inside the supported
root session bridge (`AGENTS.md` or `CLAUDE.md`). Store recipe, task fit,
roles/context boundaries, total/peak worker and review/retry/time/token bounds,
stop conditions, model-role advice, applied settings, evidence/unknowns and the
scope of user approval. Reconcile conflicting/duplicate sections across both
files; preserve surrounding instructions and user customizations. Do not store
private host names, account details or machine paths in shared instructions.

Root entry bytes are covered by the existing schema-1 fingerprint. After an
approved edit, compare calibration first, review drift, explicitly record as
appropriate, then check again. A separate linked pattern artifact may supplement
the choice, but **its bytes are not fingerprinted**; keep the operative choice
in the root section and review linked content separately. Unsupported entry
loading remains unwired; offer manual entry without claiming persistence.

## Loom mechanics and limits
{: id="mechanics"}

The conductor translates an approved recipe into bounded mandates, with one
live assignment per ticket. Workers receive only the context their role needs,
report through the existing protocol, and never push. After a ready report,
the conductor harvests where required, verifies the actual revision with trusted
checks and collects it for review. Dependent stages wait for those results.
Combining parallel results needs explicit integration and verification of the
combined revision; passing separate branches does not prove the combination.
See the [local](setup.html#5-local-executor) and
[Orca](setup.html#6-orca-executor) loops for supported commands.

Every recipe stops dependent work on failed/missing checks, calibration drift,
missing isolation/capabilities, unavailable approved placement/model, exhausted
worker/review/time/token bounds or unresolved owner decisions. Escalate instead
of spawning more, extending budgets or silently substituting a pattern/model.
User selection is not execution permission. Calibration remains an agent-followed
protocol, not an automatic launch guard; it cannot prove model access or quota.

This feature adds documentation and session instructions only: no model calls,
new runtime commands, TOML keys, scheduler, automatic workers, dependencies,
external frameworks, telemetry or model routing. Unsupported recipes cannot be
activated by prose. The underlying executor's existing limitations remain.

## Primary sources
{: id="sources"}

Reviewed 2026-11-08; revisit source and installed capability changes before
changing an approved choice. Sources establish pattern rationale, not project
benchmarks or current model access:

- [Anthropic: Building effective agents][effective] — chaining, routing,
  sectioning/voting, orchestrator-workers, evaluator-optimizer and simplicity.
- [Microsoft: AI agent orchestration patterns][azure] — sequential, concurrent,
  group chat, handoff and magentic planning, including when to avoid complexity.
- [Google: Elephant-Goldfish Model][egm] — context-rich design, fresh-context
  review and user architecture approval; a separate plugin, not part of Loom.
- [Anthropic: How we built our multi-agent research system][research] —
  task-dependent gains, coordination constraints and token costs in research.

[effective]: https://www.anthropic.com/research/building-effective-agents
[azure]: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns
[egm]: https://github.com/google/elephant-goldfish-model
[research]: https://www.anthropic.com/engineering/multi-agent-research-system

</div>
</div>
</main>
<footer class="wrap site-footer"><span>Loom · MIT</span><nav aria-label="Resources"><a href="setup.html">Setup</a><a href="copy.html">Bootstrap prompt</a><a href="support.html">Support</a></nav></footer>
</body>
</html>
