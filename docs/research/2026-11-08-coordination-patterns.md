# Ten coordination patterns for reliable coding and product work

Research date and source access date: **2026-11-08**. This is a practical shortlist, not a popularity ranking or a claim that ten agents beat one. No models were launched, paid API experiments performed, services installed, or telemetry enabled. Recommendations below are proposals for the architect, not product changes or owner decisions.

## Selection and evidence rules

Select a pattern for a demonstrated task need using four criteria: primary-source evidence for its mechanism; usefulness for coding/product deliverables; coordination and operating complexity; and portability to a native local/SSH executor. These criteria are qualitative, not fabricated scores. Prefer the least complex adequate pattern. Keep a solo baseline in every comparison.

The ten families align with the advisor catalog's terminology. They are not mutually exclusive: pipeline, fan-out, manager, handoff and group discussion describe control flow; voting describes aggregation; evaluator-optimizer describes feedback; Elephant-Goldfish describes context and review discipline; magentic planning adds an evolving task ledger. For example, a manager can fan out isolated reviews and then run a bounded revision loop. Count that as a composition, not three independent productivity gains.

**Evidence labels:** **D** = documented mechanism/example, high confidence about what the source describes, no measured gain implied; **E** = author-reported empirical evidence, moderate confidence within its stated experiment, weak transfer to Loom; **R** = our recommendation/inference, unmeasured. All fit, cost, stopping and Loom/adapter mappings below are **R** unless explicitly labeled otherwise. A cited API is not evidence that it is installed, configured or usable here. Source identifiers correspond to the dated ledger at the end.

## Single-agent baseline — separate from the ten

One scoped worker owns one context, tools and deliverable; trusted checks and human acceptance remain separate from self-review. OpenAI recommends expanding a single agent's capabilities before splitting work and requires bounded run exits. [O3]

Use this baseline for small changes, tightly coupled files, a clear reproduction, or uncertain parallel capacity. Avoid relying on it alone where an independent assessment is required. Cost includes the worker's entire loop, retries, tools and verification; wall-clock is serial but there is little integration overhead. Human attention can remain low when the mandate and checks are precise. Self-review can preserve mistaken assumptions. Stop at accepted evidence, a decision outside scope, failed prerequisites or the approved budget. Native mapping: one ticket, one assignment and immutable result revision. An external adapter needs bounded execution, artifact retrieval and a trustworthy completion receipt; live messaging is optional.

## Ten selected patterns

### 1. Sequential pipeline — prompt chaining

**Mechanism/evidence (D):** fixed stages consume prior outputs; intermediate gates prevent invalid outputs advancing. Anthropic documents chaining; OpenAI documents code-driven chains; LangGraph provides executable workflow examples. [A1] [O1] [L1]

**Roles/context:** producer → transformer → verifier, each receiving an explicit artifact and required references rather than an unbounded transcript. **Fit/avoid (R):** good for requirements → implementation → acceptance and ordered migrations; avoid artificial stages around a tiny edit or uncertain decomposition.

**Economics/effectiveness (R):** repeated briefing and stage checks add tokens; latency approaches the sum of stage times. Checkpoints may reduce expensive downstream rework and make human review easier, but early semantic mistakes can propagate through every stage. No coding productivity gain is measured here.

**Bounds/capabilities (R):** declare a finite DAG, per-stage deadline and retry allowance; block dependents on failed gates or changed inputs. Require typed artifact contracts, dependency tracking and exit evidence. **Native mapping:** durable stage tasks referencing exact revisions. **Adapter:** import/export stage results and failures; return control at boundaries, preserve ordering and deduplicate retries. A framework chain without durable stage receipts is insufficient for recovery.

### 2. Specialist routing

**Mechanism/evidence (D):** classify the request and select a focused specialist; OpenAI gives structured-output routing as a code-orchestration example. Routing chooses a destination; it need not transfer the entire conversation. [A1] [O1]

**Roles/context:** router plus one selected specialist with category-specific instructions, tools and a minimal brief. **Fit/avoid (R):** recurring, distinguishable jobs such as dependency audit, interface work or documentation. Avoid unstable categories, cross-cutting changes or a router as expensive as the job.

**Economics/effectiveness (R):** pay routing and misroute/recovery costs; a suitable cheaper observed model may offset them, but no savings follow from the label “specialist.” Adds initial latency; can reduce repeated human triage when classification is reliable. Misclassification can silently omit requirements.

**Bounds/capabilities (R):** one initial route with an explicit unknown/ambiguous outcome and a bounded reroute allowance. Require schema validation, capability and permission matching, and a route rationale. **Native mapping:** select an eligible assignment recipe before launch. **Adapter:** report actual model/tools/location and refuse unsupported targets. Do not silently choose another provider, lower effort or broaden tools when the selected route is unavailable.

### 3. Parallel fan-out/fan-in — sectioning, concurrent, scatter-gather

**Mechanism/evidence (D):** predefined independent branches run concurrently and return to an aggregator. OpenAI documents parallel execution; Claude's SDK documents separate subagent contexts and parallel analyses. [O1] [A5]

**Roles/context:** dispatcher, disjoint workers, integrator; each worker sees only its input and shared contract. **Fit/avoid (R):** independent source investigations, read-only audits or clearly separated modules. Avoid overlapping writes, hidden shared dependencies and one unresolved bottleneck.

**Economics/effectiveness (R):** total worker cost is summed, with duplicated setup and synthesis added. Ideal elapsed time is the slowest branch plus setup/integration, but queues and conflicts erode this. Human review becomes concentrated at integration, sometimes more demanding. Source evidence supports the mechanism; the compiler case demonstrates that apparent parallelism can collapse at a shared blocker. [A7]

**Bounds/capabilities (R):** explicit branch count, concurrency, per-branch deadline and completeness policy; missing results are failures or disclosed partial results, never silently dropped. **Native mapping:** separate assignments/workspaces, a join task, then verification of the combined revision. **Adapter:** concurrent execution, branch identity, isolated artifacts, cancellation status and all-result reconciliation. Parallel function requests alone do not supply these guarantees.

### 4. Orchestrator-workers — manager, agents as tools

**Mechanism/evidence (D/E):** a manager discovers subtasks, delegates bounded work and owns synthesis. Anthropic's research system implements this; OpenAI's `Agent.as_tool()` retains manager ownership; LangGraph's `Send` supports dynamic workers with separate inputs and collected output. [A2] [O1] [L1]

**Roles/context:** context-rich manager and scoped workers returning evidence/artifact references. **Fit/avoid (R):** a task whose subproblems emerge during investigation. Avoid known fixed workflows or decomposition that cannot create independently useful results.

**Economics/effectiveness (R):** manager reasoning, duplicate discovery, worker setup and compression all cost tokens. Parallel branches may shorten elapsed time; manager capacity and integration can become bottlenecks. A single accountable synthesis can reduce human coordination, but a bad decomposition misdirects every worker. Research-system results do not establish coding gains.

**Bounds/capabilities (R):** cap total children, simultaneous workers, nesting depth and replans before starting; stop for scope expansion, insufficient evidence or exhausted budget. **Native mapping:** a parent task with durable child assignments and explicit join criteria. **Adapter:** correlated parent/child receipts, actual capabilities, bounded child creation and recoverable outputs. Nested vendor agents should remain one opaque external job unless child lifecycle evidence is exposed; never invent Loom child records from narrative claims.

### 5. Evaluator-optimizer — maker-checker, critic/revision loop

**Mechanism/evidence (D):** a generator produces an artifact; an evaluator returns rubric-based feedback; revision repeats conditionally. Anthropic and LangGraph describe this loop. [A1] [L1]

**Roles/context:** maker sees requirements and feedback; checker receives the current artifact, rubric and relevant evidence. Freshness is a separate option, not inherent to a critic. **Fit/avoid (R):** checkable acceptance criteria, localized repairs and drafts with actionable criticism. Avoid subjective “keep improving” goals or a checker with no reliable oracle.

**Economics/effectiveness (R):** cost grows with generation, grading and rework in every round; elapsed time is mostly serial. Human attention may fall when cheap objective checks catch problems early, or rise when critiques oscillate. A model approval is fallible and does not replace tests. General vendor examples are not measured Loom effectiveness evidence.

**Bounds/capabilities (R):** define rubric, maximum rounds, budget and stagnation test; stop on acceptance, repeated identical failures or disagreement requiring judgment. **Native mapping:** versioned review findings and revision assignments, with trusted check evidence attached to each version. **Adapter:** structured findings, artifact identity and round count; preserve failed checks and prevent an optimizer from changing its own acceptance policy. Do not auto-resubmit forever.

### 6. Independent voting — ensemble assessment

**Mechanism/evidence (D):** separate attempts assess the same problem before aggregation. Anthropic distinguishes voting from sectioning and gives code-vulnerability review as an example. [A1]

**Roles/context:** independent reviewers plus an adjudicator, all using the same frozen artifact and rubric; reviewers cannot see others' assessments before submitting. **Fit/avoid (R):** consequential review where different failure-finding attempts are useful. Avoid paying several agents for a deterministic test, or treating a majority as correctness.

**Economics/effectiveness (R):** duplicate full assessment cost plus adjudication; parallel reviews can reduce elapsed time versus sequential review, but disagreements demand human attention. Correlated errors limit value; model-family diversity alone does not prove independence. Anthropic's conformity experiments provide counterevidence to assuming independent-looking agents behave differently. [A6]

**Bounds/capabilities (R):** set voter count and evidence threshold first; one sealed round, with a bounded dispute review. A tie or unsupported unanimous claim is not approval. **Native mapping:** read-only assignments, sealed results until a join, and a separate adjudication record. **Adapter:** context isolation, common artifact hash and delayed peer-result visibility. Simple output aggregation or vendor-internal discussion cannot honestly be labeled independent voting.

### 7. Fresh-context design/review — Elephant-Goldfish-inspired

**Mechanism/evidence (D):** Google's EGM repository assigns contextual design to the Elephant and review of the draft/referenced material, without prior conversation, to Goldfish reviewers; the human resolves tradeoffs and approves architecture. EGM stops review when fresh contexts cannot be created. It is an open-source project, not evidence of guaranteed Google-product quality gains. [G1]

**Roles/context:** designer, isolated reviewer, owner. **Fit/avoid (R):** architecture, specifications and interfaces whose hidden assumptions matter. Avoid mandatory ceremony for trivial changes, or pretending a reviewer with inherited discussion is fresh.

**Economics/effectiveness (R):** spec preparation, repeated source reading and review add cost and serial delay. Owner attention is deliberately spent on unresolved tradeoffs; downstream ambiguity may fall, but this report has no comparative productivity measurement. Insufficient source access can yield shallow or false findings.

**Bounds/capabilities (R):** freeze each reviewed draft, limit review/revision rounds, and stop unresolved design choices for the owner. Require observable input isolation and read-only reviewer permissions. **Native mapping:** explicit context manifests and separate design/review assignments, followed by an approval gate. **Adapter:** a genuinely new non-fork context with declared inherited instructions and references. If isolation is unknown, mark the recipe unavailable; changing model or clearing the visible chat is not proof of isolation. This borrows EGM's discipline, not its entire plugin workflow.

### 8. Handoffs — delegated ownership, transfer

**Mechanism/evidence (D):** the recipient becomes the active specialist, unlike a tool-call worker returning to its manager. OpenAI handoffs normally inherit conversation history; input filtering changes this in supported client-managed configurations. [O2]

**Roles/context:** current owner → successor, carrying necessary state, artifacts and unresolved questions. **Fit/avoid (R):** a job changes expertise or permission boundary during work. Avoid gratuitous transfers or multiple simultaneous writers claiming the same task.

**Economics/effectiveness (R):** briefing, history and reorientation add tokens; serial transfer adds latency. Clear ownership can reduce human chasing, but missing context and repeated bouncing create rework. SDK control transfer is evidence of a mechanism, not durable reassignment or completed work.

**Bounds/capabilities (R):** bound hops, detect cycles and require receiver acceptance; stop if the receiver or authority is unclear. **Native mapping:** an atomic ownership transition with a predecessor checkpoint and one live writer epoch. **Adapter:** map the vendor handoff to a Loom task only through an explicit contract; otherwise it remains internal to one external run. Never infer completion from the predecessor yielding. Filter confidential and irrelevant history explicitly; an OpenAI server-managed conversation requiring isolation needs a separate run with selected input, not a reused conversation identifier. [O2]

### 9. Group chat/debate — roundtable, council

**Mechanism/evidence (D):** participants contribute to a shared discussion under a turn manager. Microsoft documents group chat; Claude teams expose inter-agent messaging and shared tasks. xAI's hosted research mode describes agent discussion with leader synthesis, but does not expose a general client-controlled debate topology. [M1] [A3] [X2]

**Roles/context:** moderator and contrasting specialists share selected arguments; shared context deliberately permits influence. **Fit/avoid (R):** exploring competing hypotheses or product tradeoffs. Avoid “consensus” for verifiable correctness or substituting debate for independent review.

**Economics/effectiveness (R):** each round repeats a growing transcript across participants; sequential turns and moderation add latency. A short argument summary may help the owner decide, while an unbounded transcript increases attention cost. Agreement can reflect conformity rather than evidence. [A6]

**Bounds/capabilities (R):** predeclare participants, turns, transcript/token budget and final decision authority; stop at the cap with unresolved positions preserved. **Native mapping:** a bounded discussion task over durable mail plus a moderator, not an all-to-all wake storm. **Adapter:** ordered delivery, participant identity, bounded turn scheduling and inspectable conclusions. Hidden vendor debate is an external research result, not auditable Loom peer review.

### 10. Magentic planning — adaptive, task-ledger orchestration

**Mechanism/evidence (D):** an orchestrator maintains a task ledger, checks progress and replans when stalled. AutoGen's Magentic-One distinguishes task and progress ledgers; Microsoft's framework generalizes the pattern but explicitly says performance beyond the original design is untested. [M2] [M3]

**Roles/context:** planner/manager, tool-using specialists and a shared versioned ledger. **Fit/avoid (R):** open-ended investigation requiring an inspectable evolving plan. Avoid urgent deterministic repairs and tasks without objective progress signals.

**Economics/effectiveness (R):** planning, ledger maintenance, discarded work and replans add cost; elapsed time is unpredictable. A reviewable plan can focus human decisions, but progress narration can hide stalling. No Loom gain is established.

**Bounds/capabilities (R):** cap plan versions, tool actions, spend, time and consecutive no-progress steps; route changed goals to the owner. **Native mapping:** versioned task DAG, evidence-backed progress and explicit plan-change gates. **Adapter:** export plan/progress state and preserve pending actions through interruption; require idempotent actions and durable checkpoints. A blackboard is a possible shared-state implementation, not an eleventh selected pattern: unrestricted shared writes do not supply scheduling, ownership or acceptance semantics. Choose the documented magentic variant rather than inventing a vendor-native blackboard.

## What the ecosystems actually establish

This matrix describes source coverage, not installed features. **Named** means directly described; **compose** means a host can assemble documented primitives, with that mapping our inference; **external** means a separate methodology such as EGM. “Not established” is limited to sources checked, not a claim of impossibility.

| Family | Anthropic / Claude | OpenAI | xAI / Grok |
| --- | --- | --- | --- |
| Pipeline | Named [A1] | Code chaining [O1] | Compose ordinary calls/tools [X1] |
| Specialist routing | Named [A1] | Code routing [O1] | Compose host routing [X1] |
| Fan-out/fan-in | SDK parallel subtasks [A5] | Code parallelism [O1] | Parallel tools are primitives; hosted research is a restricted separate mode [X1], [X2] |
| Orchestrator-workers | Research implementation [A2] | Agents as tools [O1] | Hosted leader/research collaboration; not arbitrary local workers [X2] |
| Evaluator-optimizer | Named [A1] | Code evaluation loop [O1] | Compose host loop; named first-class pattern not established [X1] |
| Independent voting | Named [A1] | Compose isolated runs and aggregation | Hosted mode does not establish independence; compose separately governed runs |
| Fresh design/review | External EGM; verify non-fork context [G1], [A5] | External EGM; explicit isolated input required [G1], [O2] | EGM-compatible isolation not established |
| Handoffs | Host composition; team lead is fixed [A3] | First-class SDK handoffs [O2] | First-class ownership-transfer contract not established |
| Group chat/debate | Teams provide messaging [A3] | Compose a host-controlled conversation | Hosted discussion/leader output documented [X2] |
| Magentic planning | Compose manager and persisted plan | Compose manager and external ledger | Named magentic/task-ledger contract not established |

**Current xAI caveat:** `grok-4.20-multi-agent` is documented as beta with 4- or 16-agent configurations. Default output exposes the leader; optional encrypted subagent state is not inspectable peer-review evidence. The mode accepts built-in/remote MCP tools but excludes client-side custom function tools, Chat Completions and `max_tokens`. All agents' tokens and server tools are billed. No task-matched quality or productivity benchmark is supplied on this page. [X2]

Ordinary Grok function calling supports multiple requested calls per response; the client must handle all results. This is neither parallel agent execution nor durable completion. [X1] The official Python SDK supplies sync/async clients and explicitly configured telemetry export; it is not a Loom mailbox/run/task store. [X3]

Claude teams are documented as experimental, with in-process resume limitations, potentially lagging task status and non-immediate shutdown. Those are direct reasons to reconcile actual lifecycle state, not trust a chat panel. [A3] Claude subagents have configurable instructions/tools/models, but a separate context can be a fork; freshness must be inspected rather than assumed. [A4], [A5]

## Evidence on effectiveness and overhead

No source reviewed establishes a universal best topology or a Loom coding productivity percentage.

| Evidence | What can be concluded | What cannot be concluded |
| --- | --- | --- |
| Anthropic research system, 2025 [A2], E | Reports **90.2%** better performance on its internal research evaluation for an Opus 4 lead with Sonnet 4 subagents versus single-agent Opus 4. Reports roughly **15×** tokens for multi-agent systems versus chat interactions, and **4×** for agents versus chat. | The token comparison is not 15× versus a solo agent, not a current price quote, and not a matched-token causal estimate of coordination. Internal research results do not predict Loom coding outcomes. |
| Google scaling study summary, 2026 [G2], E | Across GPT, Gemini and Claude families on Finance-Agent, BrowseComp-Plus, PlanCraft and Workbench, architecture fit matters; sequential planning can deteriorate under coordination overhead. | These are selected benchmark configurations, not this repository's tasks, models or human-review process. The blog summary is not a reproduced experiment here. |
| Anthropic compiler experiment, 2026 [A7], E | In the Opus 4.6 compiler project, agents collided at a shared kernel-compilation blocker; better decomposition/test oracles made parallel work useful again. | A capability demonstration without a task-matched solo control cannot estimate productivity uplift or normal project cost. |
| Anthropic swarm experiments, 2026 [A6], E | Game-building experiments found poor end products despite improved coordination in some newer models. Conformity and conflicting changes are observed risks. In vulnerability discovery, broader search scope confounded a simple swarm-versus-independent comparison. | More merged changes, more discovered items or more agent activity alone do not establish better accepted product work per human hour. |
| Microsoft Magentic framework [M2], D | Documents planning and progress management; expressly limits evidence for generalized teams. | An implemented orchestration class is not evidence that arbitrary specialist teams work well. |
| EGM [G1], D | Provides an explicit fresh-review process and a hard isolation prerequisite. | No controlled time, cost or defect reduction for Loom is established by its README. |

**R:** add agents only to address a named bottleneck: independent work, overloaded instructions/tools, a required security boundary, or a need for an independent assessment. If the bottleneck is shared state, an unclear acceptance test or unavailable owner judgment, more agents can amplify it. This is consistent with OpenAI's recommendation to make multi-agent adoption evaluation-driven. [O4]

## Cost, elapsed time and human productivity

The following is an accounting model, not measured performance:

`cash(recipe) = sum over roles, rounds and retries(tokens by billing class × verified rate) + tool/service charges + execution cost`

Include coordinator, reviewer, duplicate context, cache reads/writes, reasoning tokens where billed, failed attempts and integration; do not double-count roles already in the sum. Compare `cash(recipe) − cash(solo)` on identical scope and acceptance criteria. Without actual billing channel, current rates and token budgets, the result is **unknown**, not zero. Subscription quota consumption and marginal cash are different measures; local inference also consumes compute and operating time. No current rate or quota is asserted here.

For a pipeline, elapsed time roughly sums stage time and waits. For independent parallel work, the lower-bound shape is setup + slowest branch + integration + verification, subject to worker limits and shared rate limits. Human productivity should mean accepted work per active human hour, including briefing, approvals, conflict resolution and correction. Faster first output can coexist with worse human productivity and more defects. Every pattern's gain remains **unmeasured for Loom**.

## Model-role matching from the observed inventory

Read-only observations on the authorized executor found executable paths for `codex`, `claude` and `grok`; paths are intentionally omitted. This establishes **installed binary presence only**, not versions, official provenance, authentication or model availability. The workspace's consumer declares a worker cap of two and `executor = "auto"`, but no exact model or effort. Python's `agents` package was not import-discoverable in the checked interpreter; that does not prove absence in other environments. No remote host or account was probed.

**Configured** requires supported inventory or approved configuration naming the actual provider/model/effort. **Launch-verified** requires a separately authorized receipt showing effective settings and time. This research has neither configured model evidence nor launch verification for candidate roles; present availability is unknown. Public documentation model IDs are not local inventory, and the research-task runtime is not a general launch-capacity test.

| Role and applicable patterns | Capability to require | Candidate from observed inventory | Current evidence / recommendation |
| --- | --- | --- | --- |
| Router (2, 8) | Reliable classification, structured output, permission-aware destination choice | Any of the three installed harnesses only if its exact configured model passes task evals | Model/effort/access unknown; do not label a small model cheaper without rates and accuracy evidence |
| Designer/planner/manager (1, 4, 7, 10) | Dependency reasoning, explicit uncertainty, context selection, bounded delegation | `codex`, `claude`, `grok`: candidate harness names, no model recommendation | Installed only; select using an approved design/decomposition evaluation, not brand reputation |
| Scoped implementer/researcher (1–5, 8, 10) | Relevant tools, instruction adherence, structured result and bounded execution | Same installed candidates, subject to task/tool and execution-location checks | Effective tools, version, model and billing unknown; fit is provisional |
| Evaluator/independent reviewer (5–7) | Rubric adherence, source/test evidence, read-only access, independently constructed context where required | Same candidates only after isolation and permissions are observed | A different model family can add diversity but cannot establish independence or truth |
| Integrator/moderator (3, 4, 6, 9) | Conflict detection, evidence comparison, synthesis without suppressing dissent | Same candidates, with a trusted deterministic controller for transitions | No verified model or cost basis; human retains unresolved tradeoffs |
| Lifecycle controller (all) | Durable records, idempotency, authorization and reconciliation | Native deterministic Loom code; no model required for state truth | Recommended boundary, not a currently implemented capability claim |

Each future candidate should carry role, observed exact provider/model, authorized placement reference, effort, evidence freshness, cost/quota basis and unknowns. Preserve user choices. Unknown capability is **unknown**, not unsupported and not supported: refuse dependent automatic execution until resolved, while still allowing clearly labeled advice. Do not read credentials, install services or launch paid probes to fill this table.

## Three default shortlist strategies

These are three **selection strategies**, not a fixed trio of teams. At recommendation time show exactly three task-specific candidates, mark one recommended, and always show the solo comparison even when outside those three. Mark each candidate recommendable, recipe-only or unavailable according to observed prerequisites. Selection is not itself permission to launch.

| Strategy | Selection rule and example three-candidate slate | Candidate roles and evidence needed |
| --- | --- | --- |
| **Minimum adequate coordination** | For a small, well-understood change compare solo, pipeline, specialist routing; usually recommend solo unless staged acceptance or specialization solves an observed failure. | One implementer; pipeline adds a verifier stage, routing adds a classifier. All exact models/effort currently unknown; require scoped tool access and completion evidence. |
| **Exploit verified independence** | For separable investigation compare fan-out/fan-in, orchestrator-workers, pipeline. Recommend fan-out only with a stable split; recommend manager-workers when subdivision must emerge. | Dispatcher/manager, bounded workers, integrator. Require concurrency capacity, isolated artifacts and a combined-result check; current model, quota and remote placement remain unknown. |
| **Reduce uncertainty before execution** | For an architecture decision compare fresh-context design/review, evaluator-optimizer, bounded group debate. Prefer fresh review for hidden assumptions; use a critic loop for a clear rubric or debate for competing values. | Designer/maker plus reviewer, or moderator plus specialists; owner resolves tradeoffs. Require isolation for EGM-inspired review and declared decision criteria for debate; exact models and costs remain unknown. |

The slates are examples. Substitute independent voting when repeated independent assessment is the need, handoffs when ownership really must change, and magentic planning when an evolving ledger is necessary. Never pad a slate with three purportedly runnable teams when the capabilities are unknown. Manual catalog selection should remain possible, with the same constraints and baseline.

## Architecture recommendations for the native core and open adapters

Everything in this section is **R** unless identified as an observation. The research supports boundaries and failure cases; it does not choose a database, daemon model or implementation language for the owner.

### Native truth and explicit adapter contracts

Loom should own ticket/mandate, task DAG, assignment/attempt, run, gate, message, result and verification records, independent of Orca, Herdr or a vendor SDK. Persist input and result revisions, authorization scope, execution target and effective model settings when exposed. SDK state can be imported as evidence, never become the only authoritative copy. A vendor conversation is not automatically a Loom task or assignment.

**Current checkout observation:** `ops/loom` delegates mailbox/run/task/gate commands to `ops/orca.sh`; `ops/README.md` describes Orca-first operation and an `auto` executor policy. `capacity` counts connected hosts rather than model capacity. These are current seams to replace or wrap, not proof that the desired native service already exists. See [ops/loom](../../ops/loom), [executor documentation](../../ops/README.md) and [protocol](../../PROTOCOL.md).

Define a versioned, open adapter contract with stable operation/result schemas and explicit capabilities: start, status/reconcile, collect, request-cancel, confirm-exit, context isolation, artifact isolation, optional send/wake/resume, and usage reporting. Return `supported`, `unsupported` or `unknown`, with version and observation provenance. Keep adapter IDs opaque and map them to native attempt IDs. Required capability missing or unknown must produce a visible non-success result. No implicit provider switch, remote-to-local execution, same-context review substitution or dropped branch is acceptable. A separately authorized alternative is a new recorded decision, not hidden fallback.

Make the native local/SSH executor conform to the same contract. Allow a minimal adapter with start/status/result but no mid-run messaging; advertise the limitation and allow only compatible recipes. External orchestration should be replaceable or absent without preventing native run/task/gate/mail inspection and lifecycle operation. Publicly documented patterns are implementable ideas, not mandatory SDK dependencies.

### Durable mail and waking busy agents

Persist a message before acknowledging acceptance. Record sender/recipient, assignment attempt, type, sequence, deduplication key, payload or immutable artifact reference, and delivery status. Separate **persisted → available → delivered/read → action accepted → completed/failed**; not every informational message needs every state. Read/ack is never task completion, and a worker's `ready` remains a claim requiring verification under Loom's existing protocol.

Treat wake-up as an optional, coalescible notification of durable mail. A busy worker keeps its mailbox; deliver at a safe boundary if the harness supports it. Otherwise retain pending mail, expose that limitation, and use the next authorized turn. Do not inject arbitrary terminal keystrokes or spawn duplicate workers because a wake failed. Notification failure must be visible and retryable without losing the accepted message. A message addressed to a completed attempt must not silently revive or retarget it; follow-ups require an explicit task/attempt decision.

Use non-destructive reads plus explicit acknowledgements, or an equivalent durable cursor protocol, so a background status check cannot consume the only copy. At-least-once delivery with deduplication and idempotent state changes is an attainable contract; do not promise exactly-once external side effects. A successful enqueue or a vendor “message sent” receipt cannot authorize integration, close a gate or settle work.

### Unknown liveness and lost remote processes

Persist launch intent and an idempotency key before starting remotely; retain the external receipt and process identity sufficient to distinguish a reused PID. If SSH disconnects or launch returns ambiguously, mark liveness **unknown**, not exited, failed or ready. Reconcile the same attempt before considering a retry. Native inspection must remain usable while an adapter is offline.

Use attempt epochs/fencing for task ownership and accepted artifacts. A heartbeat timeout can trigger diagnosis and stop new dependent work, but cannot prove the old process stopped. Prevent concurrent accepted writers; recover only after confirmed exit/cancellation or explicit owner-directed fencing with the remaining external-effect risk recorded. Cancellation request, cancellation acknowledgement, process exit and artifact acceptance are different events. Preserve late results for audit and reject stale-epoch results from automatic acceptance.

Checkpoint at task boundaries with immutable artifact references, observed exit codes and a completion envelope. If an external service cannot expose internal checkpoints, treat the job as opaque and disclose recovery limits. LangGraph distinguishes thread checkpoints from cross-thread storage and warns that in-memory checkpoints disappear on restart; persistent framework state still needs a Loom lifecycle mapping. [L2]

### Gates, budgets and observability

Bind each gate to an exact artifact/plan revision and explicit decision authority; stale approvals cannot approve changed output. Maintain the existing conductor-only integration/push boundary. Never let a model's prose or an SDK final answer change authoritative acceptance state by itself.

Enforce worker/round/tool/time budgets outside prompts where the executor supports it. If the provider lacks a hard token cap or confirmable cancellation, disclose that hard spend containment is unavailable; a local timeout is not evidence that billing or remote work stopped. Hosted xAI research's missing `max_tokens` support makes this distinction material. [X2]

Record minimal local operational receipts needed for correctness; optional performance studies and external trace export require separate authorization. OpenAI Agents SDK tracing is enabled by default and must be explicitly disabled/configured for a no-hidden-export adapter. [O5] xAI's SDK describes telemetry export as opt-in. [X3] Do not record private prompts or raw reasoning merely to compare patterns. This report enables no collection.

**Herdr boundary:** no Herdr-specific capability is asserted. No uniquely identified official repository/version was supplied or relied upon, and similarly named projects must not be treated as interchangeable. An eventual integration needs provenance plus contract tests against the actual selected implementation; the same requirement applies to Orca and any other external orchestrator.

## What to measure before claiming gains

Proposed study, not run: use representative repository tasks stratified by coupling, ambiguity and review risk. Fix acceptance tests, input revisions and scope; compare solo against the candidate recipe using the same available model set, tools and budgets. Include repeated runs and failed/abandoned attempts. Report sample size, model/effort versions, rate dates, cache policy, task differences and uncertainty; avoid an aggregate win that hides a harmed task category.

Measure accepted deliverables, escaped defects, rework, total tokens/cash/quota, end-to-end and tail latency, active human minutes, intervention count, routing errors, duplicate work, integration conflicts and recovery success. Separate equal-budget comparisons from increased-budget scaling. Evaluate handoff accuracy and tool arguments as well as final outputs, consistent with OpenAI's evaluation guidance. [O4] An independent blinded review and deterministic checks where applicable reduce evaluator preference bias.

For architecture acceptance, exercise crash-after-enqueue, failed wake, duplicate delivery, read-without-completion, delayed results, adapter outage, ambiguous remote launch, disconnect during stop, stale artifact/gate and attempted duplicate writer. The expected outcomes are durable recoverability, explicit uncertainty and no unauthorized fallback. These failure tests are recommendations, not checks performed in this research task.

## Source ledger and claim checks

All sources below were opened/read on **2026-11-08**, not cited solely from search snippets. Dates are publication/update dates displayed by the source; “undated” means no reliable date was visible in the inspected content. Living documentation and repository branches can change. Confidence refers to faithful source interpretation, not independent replication. D sources are high-confidence documentation; E sources are moderate-confidence author reports with the limitations above.

| ID | Primary source, date | Exact claim used / confidence |
| --- | --- | --- |
| A1 | [Anthropic, Building effective agents](https://www.anthropic.com/research/building-effective-agents), published 2024-12-19; living article notes later tooling changes | Chaining, routing, sectioning/voting, manager-workers and evaluator loops are composable patterns; complexity has costs. D. |
| A2 | [Anthropic, How we built our multi-agent research system](https://www.anthropic.com/research/multi-agent-research-system), 2025-06-13 | Lead/subagent research design and explicitly qualified internal performance/token observations; coding dependencies limit transfer. D/E. |
| A3 | [Claude Code, Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams), undated living docs | Shared tasks/messaging; experimental status, resume/status/shutdown limitations and fixed lead. D. |
| A4 | [Claude Code, Create custom subagents](https://code.claude.com/docs/en/sub-agents), undated living docs | Specialized subagent instructions, tools and model configuration. D. |
| A5 | [Claude Code, Subagents in the SDK](https://code.claude.com/docs/en/agent-sdk/subagents), undated living docs | Context isolation, parallel work, restricted tools; forks inherit context and non-forks still inherit some instructions. D. |
| A6 | [Anthropic, Patterns and problems in emerging multiagent systems](https://www.anthropic.com/research/multiagent-systems), 2026-08-13 | Scope confounds in vulnerability comparison, game-development coordination limits and conformity failures. E, limited experiments rather than universal model rankings. |
| A7 | [Anthropic, Building a C compiler with a team of parallel Claudes](https://www.anthropic.com/research/building-c-compiler), 2026-02-05 | Parallel coding collided on a shared blocker; verifier/decomposition work was necessary. E, capability demonstration without matched solo control. |
| O1 | [OpenAI Agents SDK, Agent orchestration](https://openai.github.io/openai-agents-python/multi_agent/), undated living docs | Code- versus model-directed orchestration; agents as tools, handoffs, routing, chaining, evaluation loops and parallel execution. D. |
| O2 | [OpenAI Agents SDK, Handoffs](https://openai.github.io/openai-agents-python/handoffs/), undated living docs | Active-agent transfer, inherited history, filtering limitations and separate-run requirement for isolated server-managed input. D. |
| O3 | [OpenAI, A practical guide to building agents](https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/), web edition 2026-01-15 | Maximize single-agent capability first; runs need exits. D. This web edition date is not asserted as the original PDF release date. |
| O4 | [OpenAI, Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices), undated living docs | Adopt multi-agent designs based on evaluations; assess tool selection/arguments and handoffs. D. No dependency on a specific hosted eval service is recommended. |
| O5 | [OpenAI Agents SDK, Tracing](https://openai.github.io/openai-agents-python/tracing/), undated living docs | Tracing enabled by default; explicit disabling/configuration is available. D. |
| X1 | [xAI, Function Calling](https://docs.x.ai/developers/tools/function-calling), updated 2026-10-10 | Parallel function requests and client handling of custom tools, distinct from a multi-agent runtime. D. |
| X2 | [xAI, Multi Agent](https://docs.x.ai/developers/model-capabilities/text/multi-agent), updated 2026-10-10 | Beta hosted research collaboration, leader visibility, agent-count options, billing and explicit API/tool/token-cap restrictions. D; no independent effectiveness evidence here. |
| X3 | [xai-org/xai-sdk-python, README](https://github.com/xai-org/xai-sdk-python/blob/main/README.md), undated mutable repository | Official sync/async API SDK; telemetry exporting requires explicit configuration. D. |
| G1 | [google/elephant-goldfish-model, README](https://github.com/google/elephant-goldfish-model), undated mutable repository | Context-rich designer, fresh reviewers, owner architectural judgment and stopping when isolation is unavailable. D; no measured gain inferred. |
| G2 | [Google Research, Towards a science of scaling agent systems: When and why agent systems work](https://www.research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/), 2026-01-28 | Task structure and coordination overhead can reverse the benefit of multiple agents. E; author's study summary, not a reproduction or coding benchmark. |
| M1 | [Microsoft Azure Architecture Center, AI agent orchestration patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns), updated 2026-02-12 | Sequential, concurrent, handoff, group-chat and magentic terminology and tradeoffs. D. |
| M2 | [Microsoft Agent Framework, Magentic orchestration](https://learn.microsoft.com/en-us/agent-framework/workflows/orchestrations/magentic), updated 2026-09-21 | Adaptive manager, progress assessment, stall detection and explicit untested-generalization caveat. D. |
| M3 | [Microsoft AutoGen, Magentic-One](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/magentic-one.html), undated living docs | Task ledger and progress ledger, with replanning on stalls. D. |
| L1 | [LangGraph, Workflows and agents](https://docs.langchain.com/oss/python/langgraph/workflows-agents), undated living docs | Implemented workflow examples and dynamic `Send` workers with individual state and shared collected outputs. D. |
| L2 | [LangGraph, Persistence](https://docs.langchain.com/oss/python/langgraph/persistence), undated living docs | Thread checkpoints versus cross-thread store; in-memory checkpoints do not survive restart. D. |

**Source-check limits:** public documentation, author reports and public repository content were inspected; live APIs, example code and vendor-internal results were not exercised or replicated. Search discovery used agent-reach/Exa plus official-domain browsing; page reads included the public Jina reader and GitHub connector. The available local Python interpreter had no discoverable OpenAI Agents SDK, so official SDK documentation was inspected directly. Redirects were followed, including Anthropic engineering → research, Claude platform → Code docs and LangGraph durable-execution → persistence. A separate HTTP link check returned 200 for 21 of 22 sources; O3 returned 403 to that client but its cited text was read successfully through both browsing and the public reader. Claim-anchor searches located the relevant passages; the manual comparison above supplies their qualifications, not an automated correctness certification. Source dates and model inventories can go stale; recheck before executing a recipe.

**Repository checks:** `bash ops/selftest.sh && shellcheck -x ops/*.sh ops/loom` completed with captured combined exit code **0**; the selftest printed its final PASS and ShellCheck emitted no diagnostics. These are repository regression checks, not validation of research correctness. Captured outcomes and link/claim audit evidence are retained in the assignment's private evidence directory. The comparison's validity rests on the specific claims, source ledger and stated limitations above.

[A1]: https://www.anthropic.com/research/building-effective-agents
[A2]: https://www.anthropic.com/research/multi-agent-research-system
[A3]: https://code.claude.com/docs/en/agent-teams
[A4]: https://code.claude.com/docs/en/sub-agents
[A5]: https://code.claude.com/docs/en/agent-sdk/subagents
[A6]: https://www.anthropic.com/research/multiagent-systems
[A7]: https://www.anthropic.com/research/building-c-compiler
[O1]: https://openai.github.io/openai-agents-python/multi_agent/
[O2]: https://openai.github.io/openai-agents-python/handoffs/
[O3]: https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/
[O4]: https://developers.openai.com/api/docs/guides/evaluation-best-practices
[O5]: https://openai.github.io/openai-agents-python/tracing/
[X1]: https://docs.x.ai/developers/tools/function-calling
[X2]: https://docs.x.ai/developers/model-capabilities/text/multi-agent
[X3]: https://github.com/xai-org/xai-sdk-python/blob/main/README.md
[G1]: https://github.com/google/elephant-goldfish-model
[G2]: https://www.research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/
[M1]: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns
[M2]: https://learn.microsoft.com/en-us/agent-framework/workflows/orchestrations/magentic
[M3]: https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/magentic-one.html
[L1]: https://docs.langchain.com/oss/python/langgraph/workflows-agents
[L2]: https://docs.langchain.com/oss/python/langgraph/persistence
