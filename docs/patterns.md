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
  <p class="lead">Every complete catalog entry. One choice based on your task and the capabilities you actually have.</p>
  <p><a href="copy.html">Copy the bootstrap prompt</a> or <a href="setup.html#manual-reference">return to setup</a>. You can keep a single scoped worker or defer selection.</p>
</div>
<div class="setup-reference">
<aside class="setup-toc" aria-label="Pattern reference navigation">
  <nav aria-label="Pattern sections">
    <a href="#recommendations">Choose a pattern</a>
    <a href="#cost">Cost and effectiveness</a>
    <a href="#models">Model-role matching</a>
    <a href="#catalog">Built-in family comparison</a>
    <a href="#choice">Save an explicit choice</a>
    <a href="#mechanics">Loom mechanics and limits</a>
    <a href="#sources">Primary sources</a>
  </nav>
</aside>
<div class="setup-doc" markdown="1">

## Choose a pattern
{: id="recommendations"}

This page is the explanation, not a second selection source. The selection set
is every complete `catalog/<id>/PATTERN.md` in the Loom checkout, including
community entries. The [catalog contribution and review guide](https://github.com/RedKnight13/loom/blob/main/catalog/README.md)
describes the nine required fields; an incomplete entry is not offered or used.
If named, identify it as incomplete. New entries arrive with the normal checkout
update, with no separate catalog URL, clone or pull. The root Loom session
bridge is the per-repo permission; a repo without it follows the base Loom turn.

- **An explicit name wins.** Use the named complete entry. If a name is
  ambiguous, list the matches and do not pick. If unknown, say so and do not
  substitute another pattern.
- **Explicitly no opinion:** say "Let me propose an ideal flow for us," apply
  the criteria below, and pick one with a short explanation of the reasoning.
- **Manual choice:** list every complete entry with attribution and let the
  person pick. The catalog is not a claim to contain all possible patterns.
- **Silence does not select.** Ask once; if there is still no answer, continue
  the base turn without a pattern and record no choice.
- **Reuse a saved choice that still fits.** Say its name. A different
  recommendation remains a proposal until accepted or the person asks the
  session to pick; never silently replace an approved choice.

Before following the entry in this same session, announce its name, author,
upstream and license, plus cost, effectiveness and intelligence estimates grounded
in the entry and this task. Say **using this pattern** and follow its bounded
steps on top of the normal Loom turn. Selection grants no installation,
configuration change or worker-launch permission.

Apply these criteria in order when making the no-opinion pick:

1. **Eligibility:** reject missing or unknown capabilities, isolation, placement,
   worker slots or permissions, and anything exceeding approved bounds.
2. **Task shape:** match scoped work to solo; independent subtasks to fan-out;
   fixed dependent stages to pipeline; unclear design to fresh review; a clear
   rubric and artifact to evaluator-optimizer; changing expertise to handoff;
   isolated competing assessments to voting. Magentic without a manager stays
   informational.
3. **Evidence:** prefer specific `when`, `cost`, `effectiveness` and
   `intelligence` fields that match observed inventory. Unsupported dimensions
   remain unknown.
4. **Cost:** prefer the lowest bounds that satisfy the preceding criteria;
   compare workers, rounds and elapsed time where outcomes are comparable.
5. **Safety and reversibility:** preserve the base turn, a clear stop and no
   automatic behavior. Reject recipes needing new permissions or weaker gates.
6. **Tie-break:** choose the simplest option with fewest workers, closest to
   solo, and say when this tie-break was used.

If none is eligible, say so and offer solo work with human review; do not relax
constraints or invent a pattern. Start with the simplest adequate workflow,
as recommended by [Anthropic][effective] and [Microsoft][azure].

Give the selected or manually compared entries a [role table](#models).
Capability status is observed, not bestowed by a catalog label:

- **Recommendable:** task fit, approved bounds and required capabilities are
  observed; this is advice, not permission or launch verification.
- **Recipe-only:** a composition whose required capabilities or configuration
  remain unverified; explain what is needed without assuming eligibility.
- **Unavailable:** a requirement is absent, forbidden or incompatible; state
  why and offer a simpler route without silently changing the choice.

Without project access, comparisons remain provisional and wiring unverified.
Use explicitly user-supplied observed inventory where discovery is unavailable,
or label it unknown. No Orca prerequisite applies.

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

For **each selected or compared entry**, fill one row per role using this format:

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

## Built-in family comparison
{: id="catalog"}

Each family name links to its selectable catalog entry. This comparison explains
the eleven built-in families; complete community entries are selectable too.
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
| **[Solo baseline](https://github.com/RedKnight13/loom/blob/main/catalog/solo-baseline/PATTERN.md)** — single agent with tools ([Microsoft][azure]) | One scoped change; one task context | One worker; one verification/rework cycle | Self-review blind spots; stop at acceptance, scope conflict or exhausted budget | One ticket and worker, trusted verify, collect and human review; local or supported executor |
| **[Pipeline](https://github.com/RedKnight13/loom/blob/main/catalog/pipeline/PATTERN.md)** — sequential / prompt chaining ([Anthropic][effective], [Microsoft][azure]) | Fixed dependent stages; each receives reviewed previous artifact | Up to three stages, one worker at a time; one check per stage | Serial latency, propagated mistakes; stop on a failed stage | Separate scoped tickets as needed; conductor reviews output before the next stage; no automatic pipeline |
| **[Specialist routing](https://github.com/RedKnight13/loom/blob/main/catalog/specialist-routing/PATTERN.md)** ([Anthropic][effective]) | Known task categories; selected specialist gets relevant brief | One selected worker per task; one routing decision | Misclassification; stop when category or access is unclear | Conductor chooses a reviewed ticket/consumer/harness; no automatic model router |
| **[Parallel fan-out/fan-in](https://github.com/RedKnight13/loom/blob/main/catalog/parallel-fan-out/PATTERN.md)** — sectioning / concurrent / scatter-gather ([Anthropic][effective], [Microsoft][azure]) | Predefined independent work; minimal shared files and bounded briefs | Two workers concurrently plus conductor; one integration review | Duplicate work, conflicts, synthesis cost; stop if independence fails | Separate tickets/assignments, verify each, integrate explicitly and verify combined revision; requires authorized parallel capacity |
| **[Orchestrator-workers](https://github.com/RedKnight13/loom/blob/main/catalog/orchestrator-workers/PATTERN.md)** ([Anthropic][effective]) | Subtasks discovered during work; conductor keeps overall context | At most two active workers, three total subtasks, one synthesis review | Decomposition and coordination errors; pause on new scope/dependency | Conductor proposes bounded tickets dynamically; existing dispatch/verify/collect only; no recursive spawning by recipe |
| **[Evaluator-optimizer](https://github.com/RedKnight13/loom/blob/main/catalog/evaluator-optimizer/PATTERN.md)** — maker-checker / critic loop ([Anthropic][effective], [Microsoft][azure]) | Clear rubric; checker sees artifact and criteria | One maker and one checker, sequential; two critique/revision rounds | Circular critique, false approval; stop on acceptance, stalled improvement or round cap | Review deliverable then scoped revision; tests remain authoritative evidence; no automatic retry loop |
| **[Fresh-context design/review](https://github.com/RedKnight13/loom/blob/main/catalog/fresh-context-review/PATTERN.md)** — EGM-inspired ([EGM][egm]) | Context-rich designer drafts spec; isolated reviewer sees only draft and referenced material, never prior conversation | One designer and one fresh reviewer, sequential; two review rounds; user architecture approval before implementation | Missing context may expose assumptions; freshness cannot be faked; stop if isolation unavailable or tradeoff unresolved | Design/review tickets and owner approval; recipe-only until isolation observed; not the EGM plugin or its full staged workflow |
| **[Independent voting](https://github.com/RedKnight13/loom/blob/main/catalog/independent-voting/PATTERN.md)** ([Anthropic][effective]) | Same rubric/artifact, separate assessments before aggregation | Two reviewers plus conductor; one independent round | Correlated errors, inconclusive split; escalate disagreements, no majority-as-proof | Separate read-only review tasks; human resolves evidence, implementation still verified; requires isolated contexts |
| **[Group chat / debate](https://github.com/RedKnight13/loom/blob/main/catalog/group-debate/PATTERN.md)** — roundtable / council ([Microsoft][azure]) | Shared discussion for competing perspectives; shared context is not fresh review | At most three participants including moderator; two rounds | Conformity, discussion cost; stop on round cap or unresolved owner decision | Informational unless an authorized harness supplies bounded shared discussion; Loom mail alone does not install a group-chat manager |
| **[Handoffs](https://github.com/RedKnight13/loom/blob/main/catalog/handoffs/PATTERN.md)** — transfer / triage ([Microsoft][azure]) | Expertise changes; curated state and unresolved questions pass to next role | One active worker at a time; at most two transfers | Lost state, ownership gaps, bouncing; stop if receiver/boundary unclear | Conductor settles prior work and authorizes next scoped assignment; no automatic ownership transfer or overlapping worker on one ticket |
| **[Magentic planning](https://github.com/RedKnight13/loom/blob/main/catalog/magentic-planning/PATTERN.md)** — adaptive / task-ledger orchestration ([Microsoft][azure]) | Open-ended planning, explicit evolving task ledger | One planner, at most two scoped workers; two replans before human review | Runaway planning and side effects; stop at stalled progress, budget or plan change needing approval | Informational/recipe-only: manual plan and tickets can borrow the idea; Loom has no magentic manager/runtime; unavailable for automatic execution |

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
until explicitly accepted or the person asks the session to pick; never overwrite
the current choice on a setup rerun.
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
loading remains unwired; keep the choice session-only if the calibration flow is
unavailable and say it was not persisted.

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
