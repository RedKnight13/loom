# Bootstrap coordination advice, v1

## Contract

Bootstrap offers exactly three task-appropriate coordination candidates, one
recommended, with a single scoped worker baseline. Each compares fit, roles and
peak concurrency, cost assumptions/confidence, expected elapsed time and human
productivity, effectiveness evidence/tradeoffs and constraints. Each candidate
also has a role table with observed agent/provider/model, authorized execution
location, supported effort, rationale, availability evidence and cost basis.
Unknown and unavailable entries remain explicit; three candidates does not mean
three feasible teams. Manual choice shows the full maintained catalog, not an
exhaustive universe of patterns. Solo, deferred and existing-choice paths remain
safe. Missing discovery does not block advisory choice.

This is a documentation/session protocol, not a runtime implementation. No new
commands, dependencies, model calls, TOML keys, scheduler, telemetry or workers.
The owner directs Loom toward standalone coordination with open capability
adapters for any orchestrator. That runtime redesign is separate work: this
feature must not claim native messaging, remote lifecycle or adapter parity
already exists, or invent APIs for another orchestrator.

## Provider-neutral discovery and current limits

Inventory executor/harness capabilities first: project read/write and shell
access, placement, model inventory, effort control, isolation, supported worker
lifecycle and concurrency. Local/custom harnesses need no Orca for advisory
selection. Read installed help and supported provider inventory on the authorized
intended host. When unavailable, accept explicitly user-supplied observed
inventory with provenance, or report unknown and ask only what is needed. Never
scrape tokens, change login, buy accounts or call a model as a discovery test.
Distinguish installed, configured and launch-verified evidence; none proves
future quota. Respect existing model choices, caps, budgets and placement policy.

Source inspection at base `0caf4a6` establishes current implementation limits:

- `ops/loom` capacity counts connected Orca hosts, or suggests one locally.
  It does not inventory models, accounts, quotas or safe worker concurrency.
- `ops/dispatch.sh` snapshots consumer model/effort into the assignment.
  `ops/orca.sh` forwards those values at start; Loom start only exposes `--agent`.
  Per-role routing needs explicitly reviewed consumer configurations; advice
  does not modify shared config or pinned assignment records.
- Local `launch ID -- CMD...` uses the authorized command/harness. Do not claim
  Orca model/effort fields configure that command. Verify effective settings
  where the executor exposes them; missing evidence remains unverified.
- The inspected Orca CLI schema has model/effort launch fields and host/account
  commands, but no universal model catalog. Its account command covers specific
  managed providers. These are optional adapter observations, not prerequisites
  or guarantees about another installed version.
- Existing executor guards and remote placement requirements remain unchanged.
  No custom harness or orchestrator API is added by these docs.

Recommend suitable smaller/cheaper observed models for bounded execution and
stronger reasoning for ambiguous design only when fit/cost evidence supports it.
An independent reviewer requires a separate context with a controlled input
bundle. Model diversity is optional and cannot establish independence.

## Choice lifecycle and persistence

Inspect task/repo/checks and existing selection before proposing candidates.
A still-applicable approved choice is reused; reconsideration shows a proposal
without overwriting it. Initial choice offers candidate, manual catalog, simple
baseline or defer. If the task is unknown, ask for the task rather than fabricate
fit. Missing capabilities produce labelled recipe-only/unavailable candidates
and a simpler route. Unsupported recipes cannot be activated by choosing a name.
Silence or timeout never selects or launches. Existing tasks without a choice
continue only their already authorized work, without adding workers. If an
approved choice becomes infeasible, stop only work dependent on that capability.

After explicit selection, store one `loom-pattern:start/end` section inside the
supported root `loom-session` bridge. Include recipe, task fit, roles/context,
worker total/peak, review/retry/time/token bounds, stop conditions, model advice
versus applied configuration, evidence/unknowns and approval scope. Reconcile
duplicate/conflicting markers across both root entry files before editing;
preserve surrounding instructions and customizations. Do not save unapproved
recommendations or private host/account/path details in shared content.

`ops/calibrate.sh` schema 1 fingerprints both present root entry files, so the
operative selection is covered without a schema change. Linked checklist or
pattern artifact bytes are not covered; review them separately. Check first,
review drift, explicitly record an approved change, then check again before
delegation. Markers have no runtime parser/enforcement. Unsupported loading stays
unwired and manual entry must not be called persistence. Selection grants no
permission to install, change model/cap/placement or launch.

## Research and bounded recipes

[The catalog](../../patterns.md) cites the four primary sources required by the
mandate: Anthropic's effective-agents and multi-agent-research articles,
Microsoft's orchestration guide, and Google's EGM repository. It maintains eleven
families with aliases, context boundaries, proposed worker/review bounds, risks,
stop rules and existing ticket/verify/collect mappings. Proposed bounds are
Loom guidance for review, not source measurements or automatically applied caps.
EGM-inspired design/review does not install EGM or implement its complete plugin;
user approval of architecture and truly fresh review remain required.

Separate spend, wall-clock time, accepted work per human hour and defects/rework.
Estimate cost using token budgets and verified current rates, plus coordination,
review, retries, tools and compute; subscription quota is not a cash invoice.
Unknown prices stay unknown. Arithmetic is explicitly illustrative. No universal
percentages or transposed research benchmark gains; percentages require a
measured task-matched baseline and provenance. No automatic outcome tracking.

## Surface and validation

Only bootstrap text/reference, setup, copy page, catalog, session template and
this spec change. Preserve the checkout-update behavior from PR93 and runtime
fixtures including PR92. Use a standalone catalog page with existing CSS and
accurate title/description; no layout or navigation-anchor changes required.
Setup and copy pages link directly to manual catalog and model-role guidance.

Run `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom`, with captured exits.
Reuse cached Pages build/Playwright tooling without installations. Browser-check
generated pages, exact prompt copy, links/anchors, narrow/wide layouts, keyboard
navigation and catalog access with JavaScript disabled. Inspect screenshots.
Review scenarios: budget task, independent parallel work, architecture/fresh
review, no Orca, unknown model inventory, one worker, existing selection, manual
unavailable choice, model override conflict and calibration drift. Include
local/custom harness advice and unknown execution fields. Keep evidence under
`.loom/`, documenting limits: static/manual checks cannot prove LLM compliance,
fresh-session loading, live launch acceptance or gains. No real workers or model
test calls; no full mutation gate for this prose-only change. The conductor
reviews and publishes; the worker leaves changes unstaged.
