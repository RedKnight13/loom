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
  <script src="assets/site.js" defer></script>
</head>
<body class="setup-page">
<a class="skip" href="#main">Skip to content</a>
<header class="site-header wrap">
  <a class="brand" href="index.html" aria-label="Loom home"><span class="mark" aria-hidden="true">▥</span> loom</a>
  <nav aria-label="Main navigation"><a href="index.html">Overview</a><a href="setup.html">Setup</a><a href="patterns.html" aria-current="page">Patterns</a><a href="protocol.html">Protocol</a><a href="https://github.com/RedKnight13/loom">GitHub</a></nav>
</header>
<main id="main" class="wrap" tabindex="-1">
<div class="manual-heading">
  <p class="intro">Choose the simplest adequate workflow</p>
  <h1>Find a pattern<br>that fits the work</h1>
  <p class="lead">One worker or several? A sequence, a review loop, or independent checks? See the tradeoffs before adding more agents.</p>
  <p><a href="copy.html">Copy the bootstrap prompt</a> or <a href="setup.html#manual-reference">return to setup</a>. You can keep a single scoped worker or defer selection.</p>
</div>
<section class="pattern-explorer" id="explore" aria-labelledby="explore-title">
 <div class="explorer-heading"><h2 id="explore-title">What changes when you add another agent?</h2><p>Some patterns split the work. Others separate context, change ownership or add a review loop. Explore the difference before choosing. These are illustrated recipes, not running agents.</p></div>
 <div class="explorer-layout"><div class="pattern-picker" aria-label="Choose a pattern to explore" hidden><button type="button" data-pattern-target="solo-baseline" aria-controls="pattern-solo-baseline" aria-pressed="false">Solo</button><button type="button" data-pattern-target="pipeline" aria-controls="pattern-pipeline" aria-pressed="false">Pipeline</button><button type="button" data-pattern-target="parallel-fan-out" aria-controls="pattern-parallel-fan-out" aria-pressed="false">Parallel fan-out</button><button type="button" data-pattern-target="orchestrator-workers" aria-controls="pattern-orchestrator-workers" aria-pressed="false">Orchestrator + workers</button><button type="button" data-pattern-target="specialist-routing" aria-controls="pattern-specialist-routing" aria-pressed="false">Specialist routing</button><button type="button" data-pattern-target="evaluator-optimizer" aria-controls="pattern-evaluator-optimizer" aria-pressed="false">Maker + checker</button><button type="button" data-pattern-target="fresh-context-review" aria-controls="pattern-fresh-context-review" aria-pressed="false">Fresh-context review</button><button type="button" data-pattern-target="independent-voting" aria-controls="pattern-independent-voting" aria-pressed="false">Independent voting</button><button type="button" data-pattern-target="handoffs" aria-controls="pattern-handoffs" aria-pressed="false">Handoffs</button><button type="button" data-pattern-target="group-debate" aria-controls="pattern-group-debate" aria-pressed="false">Group discussion</button><button type="button" data-pattern-target="magentic-planning" aria-controls="pattern-magentic-planning" aria-pressed="false">Adaptive planning</button></div><div class="pattern-stories"><article class="pattern-story" id="pattern-solo-baseline" data-pattern="solo-baseline" aria-labelledby="pattern-title-solo-baseline">
 <p class="pattern-fit">One bounded change</p><h3 id="pattern-title-solo-baseline">Solo</h3><p class="pattern-thesis">Keep one task in one context.</p><p>Start here for a small fix or test. One worker keeps the task in one context.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Solo flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="One worker implements and checks the task in a single context, then hands the diff and test results to human review."><defs><marker id="tip-solo-baseline" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><rect class="map-zone" x="140" y="40" width="440" height="220" rx="12"/><text class="map-zone-label" x="156" y="64">One worker · one task context</text><g class="map-role"><rect x="250.0" y="88" width="220" height="60" rx="8"/><text x="360" y="115" text-anchor="middle">Worker</text><text class="map-sub" x="360" y="135" text-anchor="middle">implements + self-checks</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 360 148 V 184" marker-end="url(#tip-solo-baseline)"/><g class="map-role"><rect x="250.0" y="190" width="220" height="60" rx="8"/><text x="360" y="217" text-anchor="middle">Reviewable change</text><text class="map-sub" x="360" y="237" text-anchor="middle">diff + test results</text></g><text class="map-note" x="360" y="310" text-anchor="middle">Human review follows. No coordination layer inside the task.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>One worker implements and checks the task in a single context, then hands the diff and test results to human review.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Fix a CLI flag and add its regression test.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>One worker; one verification/rework cycle. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>Self-review can miss defects. Keep trusted checks and human review.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://www.anthropic.com/research/building-effective-agents">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/solo-baseline/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-pipeline" data-pattern="pipeline" aria-labelledby="pattern-title-pipeline">
 <p class="pattern-fit">Work with fixed stages</p><h3 id="pattern-title-pipeline">Pipeline</h3><p class="pattern-thesis">Each stage needs the previous result.</p><p>Use when each stage needs the previous artifact, such as a specification followed by an implementation.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Pipeline flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="The specification becomes the input to implementation. The resulting change becomes the input to verification. A failed stage stops the sequence."><defs><marker id="tip-pipeline" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><g class="map-role"><rect x="46.0" y="120" width="148" height="60" rx="8"/><text x="120" y="147" text-anchor="middle">Specify</text><text class="map-sub" x="120" y="167" text-anchor="middle">output: contract</text></g><g class="map-role"><rect x="286.0" y="120" width="148" height="60" rx="8"/><text x="360" y="147" text-anchor="middle">Implement</text><text class="map-sub" x="360" y="167" text-anchor="middle">output: change</text></g><g class="map-role"><rect x="526.0" y="120" width="148" height="60" rx="8"/><text x="600" y="147" text-anchor="middle">Verify</text><text class="map-sub" x="600" y="167" text-anchor="middle">output: evidence</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 194 150 H 286" marker-end="url(#tip-pipeline)"/><text class="map-label" x="240" y="132" text-anchor="middle">contract</text><path class="map-link flow-edge" style="--edge-delay:1000ms" pathLength="1" d="M 434 150 H 526" marker-end="url(#tip-pipeline)"/><text class="map-label" x="480" y="132" text-anchor="middle">change</text><text class="map-note" x="360" y="310" text-anchor="middle">A failed stage stops the next stage. Work is sequential.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>The specification becomes the input to implementation. The resulting change becomes the input to verification. A failed stage stops the sequence.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Turn a written API spec into an implementation, then verify it.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>Up to three stages; one worker active at a time. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>A failed stage stops dependent work. Errors can travel downstream.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://www.anthropic.com/research/building-effective-agents">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/pipeline/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-parallel-fan-out" data-pattern="parallel-fan-out" aria-labelledby="pattern-title-parallel-fan-out">
 <p class="pattern-fit">Independent pieces of work</p><h3 id="pattern-title-parallel-fan-out">Parallel fan-out</h3><p class="pattern-thesis">Different tasks happen at the same time.</p><p>Split independent files or tasks, then review the combined result.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Parallel fan-out flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="The conductor splits a task into independent parts. Workers run in parallel, then their results meet at a combined check."><defs><marker id="tip-parallel-fan-out" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><g class="map-role"><rect x="32.0" y="130" width="136" height="60" rx="8"/><text x="100" y="165" text-anchor="middle">Split scope</text></g><g class="map-role"><rect x="286.0" y="60" width="148" height="60" rx="8"/><text x="360" y="87" text-anchor="middle">Worker A</text><text class="map-sub" x="360" y="107" text-anchor="middle">integration A</text></g><g class="map-role"><rect x="286.0" y="200" width="148" height="60" rx="8"/><text x="360" y="227" text-anchor="middle">Worker B</text><text class="map-sub" x="360" y="247" text-anchor="middle">integration B</text></g><g class="map-role"><rect x="552.0" y="130" width="136" height="60" rx="8"/><text x="620" y="157" text-anchor="middle">Combine</text><text class="map-sub" x="620" y="177" text-anchor="middle">integration check</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 168 160 C 220 160 230 90 286 90" marker-end="url(#tip-parallel-fan-out)"/><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 168 160 C 220 160 230 230 286 230" marker-end="url(#tip-parallel-fan-out)"/><path class="map-link flow-edge" style="--edge-delay:1400ms" pathLength="1" d="M 434 90 C 490 90 490 160 552 160" marker-end="url(#tip-parallel-fan-out)"/><path class="map-link flow-edge" style="--edge-delay:1400ms" pathLength="1" d="M 434 230 C 490 230 490 160 552 160" marker-end="url(#tip-parallel-fan-out)"/><text class="map-note" x="360" y="322" text-anchor="middle">Different briefs. Independent files. One combined result.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>The conductor splits a task into independent parts. Workers run in parallel, then their results meet at a combined check.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Update two independent integrations, then test them together.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>Up to two workers in parallel; add integration and review effort. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>Shared-file changes can conflict. More workers can cost more even when work finishes sooner.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://www.anthropic.com/research/building-effective-agents">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/parallel-fan-out/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-orchestrator-workers" data-pattern="orchestrator-workers" aria-labelledby="pattern-title-orchestrator-workers">
 <p class="pattern-fit">Discover subtasks as you go</p><h3 id="pattern-title-orchestrator-workers">Orchestrator + workers</h3><p class="pattern-thesis">The conductor discovers the next subtasks.</p><p>Keep the overall context with a conductor while workers handle scoped subtasks.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Orchestrator + workers flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="The conductor assigns an investigation, reads its report, and uses the findings to define the next bounded task before combining results."><defs><marker id="tip-orchestrator-workers" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><g class="map-role"><rect x="260.0" y="48" width="200" height="60" rx="8"/><text x="360" y="75" text-anchor="middle">Conductor</text><text class="map-sub" x="360" y="95" text-anchor="middle">holds overall context</text></g><g class="map-role"><rect x="80.0" y="204" width="180" height="60" rx="8"/><text x="170" y="231" text-anchor="middle">Worker A</text><text class="map-sub" x="170" y="251" text-anchor="middle">scoped investigation</text></g><g class="map-role"><rect x="460.0" y="204" width="180" height="60" rx="8"/><text x="550" y="231" text-anchor="middle">Worker B</text><text class="map-sub" x="550" y="251" text-anchor="middle">new scoped task</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 292 108 L 196 204" marker-end="url(#tip-orchestrator-workers)"/><text class="map-label" x="206" y="148" text-anchor="middle">assign</text><path class="map-link flow-edge" style="--edge-delay:1000ms" pathLength="1" d="M 130 204 C 80 95 190 42 260 65" marker-end="url(#tip-orchestrator-workers)"/><text class="map-label" x="138" y="91" text-anchor="middle">report</text><path class="map-link flow-edge" style="--edge-delay:2000ms" pathLength="1" d="M 460 78 C 560 78 550 160 550 204" marker-end="url(#tip-orchestrator-workers)"/><text class="map-label" x="563" y="141" text-anchor="middle">next task</text><path class="map-link flow-edge" style="--edge-delay:2600ms" pathLength="1" d="M 476 234 Q 360 250 360 108" marker-end="url(#tip-orchestrator-workers)"/><text class="map-label" x="408" y="202" text-anchor="middle">result</text><text class="map-note" x="360" y="322" text-anchor="middle">The next assignment depends on what the conductor learns.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>The conductor assigns an investigation, reads its report, and uses the findings to define the next bounded task before combining results.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Investigate a bug; send a targeted reproduction and a fix to workers as evidence arrives.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>Up to two active workers, three total subtasks, one synthesis review. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>The conductor can decompose badly. Workers do not recursively launch more workers.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://www.anthropic.com/research/building-effective-agents">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/orchestrator-workers/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-specialist-routing" data-pattern="specialist-routing" aria-labelledby="pattern-title-specialist-routing">
 <p class="pattern-fit">Choose the relevant expertise</p><h3 id="pattern-title-specialist-routing">Specialist routing</h3><p class="pattern-thesis">Choose one specialist. Do not launch them all.</p><p>Classify a known task and give one selected specialist the relevant brief.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Specialist routing flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="The task is classified and sent to one matching specialist. The other specialists do not receive the task."><defs><marker id="tip-specialist-routing" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><g class="map-role"><rect x="28.0" y="130" width="144" height="60" rx="8"/><text x="100" y="165" text-anchor="middle">Incoming task</text></g><path class="map-decision" d="M 300 98 L 362 160 L 300 222 L 238 160 Z"/><text x="300" y="165" text-anchor="middle">Classify</text><g class="map-role"><rect x="506.0" y="40" width="148" height="60" rx="8"/><text x="580" y="67" text-anchor="middle">UI specialist</text><text class="map-sub" x="580" y="87" text-anchor="middle">not selected</text></g><g class="map-role"><rect x="506.0" y="130" width="148" height="60" rx="8"/><text x="580" y="157" text-anchor="middle">Database</text><text class="map-sub" x="580" y="177" text-anchor="middle">selected specialist</text></g><g class="map-role"><rect x="506.0" y="220" width="148" height="60" rx="8"/><text x="580" y="247" text-anchor="middle">API specialist</text><text class="map-sub" x="580" y="267" text-anchor="middle">not selected</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 172 160 H 238" marker-end="url(#tip-specialist-routing)"/><path class="map-link flow-edge" style="--edge-delay:900ms" pathLength="1" d="M 362 160 H 506" marker-end="url(#tip-specialist-routing)"/><text class="map-label" x="436" y="144" text-anchor="middle">selected</text><path class="map-link map-quiet" style="--edge-delay:0ms" pathLength="1" d="M 324 122 L 506 70" marker-end="url(#tip-specialist-routing)"/><path class="map-link map-quiet" style="--edge-delay:0ms" pathLength="1" d="M 324 198 L 506 250" marker-end="url(#tip-specialist-routing)"/><text class="map-note" x="360" y="322" text-anchor="middle">Only the selected route receives the task.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>The task is classified and sent to one matching specialist. The other specialists do not receive the task.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Send a database migration question to the database specialist.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>One routing decision and one selected worker per task. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>A wrong category gives the wrong brief. This recipe does not install a model router.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://www.anthropic.com/research/building-effective-agents">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/specialist-routing/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-evaluator-optimizer" data-pattern="evaluator-optimizer" aria-labelledby="pattern-title-evaluator-optimizer">
 <p class="pattern-fit">Improve against a clear rubric</p><h3 id="pattern-title-evaluator-optimizer">Maker + checker</h3><p class="pattern-thesis">Revise the same artifact against a rubric.</p><p>Give the checker an artifact and criteria, then authorize a scoped revision when useful.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Maker + checker flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="The maker sends an artifact to the checker. Critique goes back to the maker for revision, with at most two review rounds before a decision."><defs><marker id="tip-evaluator-optimizer" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><g class="map-role"><rect x="110.0" y="105" width="180" height="60" rx="8"/><text x="200" y="132" text-anchor="middle">Maker</text><text class="map-sub" x="200" y="152" text-anchor="middle">produces artifact</text></g><g class="map-role"><rect x="430.0" y="105" width="180" height="60" rx="8"/><text x="520" y="132" text-anchor="middle">Checker</text><text class="map-sub" x="520" y="152" text-anchor="middle">uses agreed rubric</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 290 135 H 430" marker-end="url(#tip-evaluator-optimizer)"/><text class="map-label" x="360" y="115" text-anchor="middle">artifact</text><path class="map-link flow-edge" style="--edge-delay:1000ms" pathLength="1" d="M 520 165 C 520 260 200 260 200 165" marker-end="url(#tip-evaluator-optimizer)"/><text class="map-label" x="360" y="263" text-anchor="middle">critique → scoped revision · at most 2 rounds</text><path class="map-link flow-edge" style="--edge-delay:2400ms" pathLength="1" d="M 520 105 V 54 H 635" marker-end="url(#tip-evaluator-optimizer)"/><text class="map-label" x="600" y="39" text-anchor="middle">meets rubric</text><text class="map-note" x="360" y="322" text-anchor="middle">A review loop, not an endless retry. Trusted checks still apply.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>The maker sends an artifact to the checker. Critique goes back to the maker for revision, with at most two review rounds before a decision.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Ask a checker to review a patch against explicit acceptance criteria.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>One maker and one checker, sequential; at most two revision rounds. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>Critique is not proof. Stop when improvement stalls or the round cap is reached.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://www.anthropic.com/research/building-effective-agents">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/evaluator-optimizer/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-fresh-context-review" data-pattern="fresh-context-review" aria-labelledby="pattern-title-fresh-context-review">
 <p class="pattern-fit">Find hidden assumptions</p><h3 id="pattern-title-fresh-context-review">Fresh-context review</h3><p class="pattern-thesis">Keep the history out of the review.</p><p>An Elephant–Goldfish-inspired separation: the reviewer sees the draft and references, not the earlier conversation.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Fresh-context review flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="The designer works with the original context. Only the draft and referenced material cross to a fresh reviewer; the earlier conversation stays behind."><defs><marker id="tip-fresh-context-review" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><rect class="map-zone" x="20" y="40" width="280" height="222" rx="12"/><text class="map-zone-label" x="36" y="64">Context-rich session</text><rect class="map-zone" x="420" y="40" width="280" height="222" rx="12"/><text class="map-zone-label" x="436" y="64">Fresh context · isolated</text><g class="map-role"><rect x="48.0" y="100" width="224" height="60" rx="8"/><text x="160" y="127" text-anchor="middle">Designer</text><text class="map-sub" x="160" y="147" text-anchor="middle">knows the conversation</text></g><g class="map-role"><rect x="448.0" y="100" width="224" height="60" rx="8"/><text x="560" y="127" text-anchor="middle">Reviewer</text><text class="map-sub" x="560" y="147" text-anchor="middle">draft + references only</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 272 130 H 448" marker-end="url(#tip-fresh-context-review)"/><text class="map-label" x="360" y="111" text-anchor="middle">draft only</text><text class="map-note" x="160" y="222" text-anchor="middle">Conversation stays here</text><text class="map-note" x="560" y="222" text-anchor="middle">No prior transcript</text><text class="map-note" x="360" y="310" text-anchor="middle">This is a context boundary, not merely a second agent.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>The designer works with the original context. Only the draft and referenced material cross to a fresh reviewer; the earlier conversation stays behind.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Review an architecture draft for assumptions its author no longer notices.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>One designer and one isolated reviewer; at most two rounds. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>Freshness requires real context isolation. Missing references can weaken the review.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://github.com/google/elephant-goldfish-model">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/fresh-context-review/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-independent-voting" data-pattern="independent-voting" aria-labelledby="pattern-title-independent-voting">
 <p class="pattern-fit">Compare separate assessments</p><h3 id="pattern-title-independent-voting">Independent voting</h3><p class="pattern-thesis">Same question. Separate assessments.</p><p>Ask separate reviewers to assess the same artifact before they see each other’s conclusions.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Independent voting flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="Two isolated reviewers receive the same artifact and rubric. Their separate assessments are compared by evidence; agreement alone is not proof."><defs><marker id="tip-independent-voting" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><rect class="map-zone" x="250" y="35" width="210" height="105" rx="12"/><text class="map-zone-label" x="266" y="59">Isolated review A</text><rect class="map-zone" x="250" y="175" width="210" height="105" rx="12"/><text class="map-zone-label" x="266" y="199">Isolated review B</text><g class="map-role"><rect x="17.0" y="130" width="156" height="60" rx="8"/><text x="95" y="157" text-anchor="middle">Same artifact</text><text class="map-sub" x="95" y="177" text-anchor="middle">same rubric</text></g><g class="map-role"><rect x="275.0" y="71" width="160" height="60" rx="8"/><text x="355" y="106" text-anchor="middle">Reviewer A</text></g><g class="map-role"><rect x="275.0" y="211" width="160" height="60" rx="8"/><text x="355" y="246" text-anchor="middle">Reviewer B</text></g><g class="map-role"><rect x="538.0" y="130" width="164" height="60" rx="8"/><text x="620" y="157" text-anchor="middle">Compare</text><text class="map-sub" x="620" y="177" text-anchor="middle">evidence, not votes</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 173 160 L 275 101" marker-end="url(#tip-independent-voting)"/><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 173 160 L 275 241" marker-end="url(#tip-independent-voting)"/><path class="map-link flow-edge" style="--edge-delay:1500ms" pathLength="1" d="M 435 101 L 538 160" marker-end="url(#tip-independent-voting)"/><path class="map-link flow-edge" style="--edge-delay:1500ms" pathLength="1" d="M 435 241 L 538 160" marker-end="url(#tip-independent-voting)"/><text class="map-note" x="360" y="322" text-anchor="middle">Reviewers do not see each other’s answers before aggregation.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>Two isolated reviewers receive the same artifact and rubric. Their separate assessments are compared by evidence; agreement alone is not proof.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Have two isolated reviewers assess one patch before comparing their findings.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>Two reviewers plus the conductor; one independent round. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>A majority can still be wrong. Escalate disagreement; keep verification separate.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://www.anthropic.com/research/building-effective-agents">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/independent-voting/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-handoffs" data-pattern="handoffs" aria-labelledby="pattern-title-handoffs">
 <p class="pattern-fit">Change expertise without losing ownership</p><h3 id="pattern-title-handoffs">Handoffs</h3><p class="pattern-thesis">Responsibility moves to the next worker.</p><p>Pass the reviewed artifact, current state and unresolved questions to the next role.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Handoffs flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="The first assignment ends. Its artifact and unresolved questions pass to the next assignment, with one active worker at a time."><defs><marker id="tip-handoffs" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><rect class="map-zone" x="20" y="52" width="220" height="206" rx="12"/><text class="map-zone-label" x="36" y="76">Earlier assignment</text><rect class="map-zone" x="480" y="52" width="220" height="206" rx="12"/><text class="map-zone-label" x="496" y="76">Next assignment</text><g class="map-role"><rect x="36.0" y="116" width="188" height="60" rx="8"/><text x="130" y="143" text-anchor="middle">Investigator</text><text class="map-sub" x="130" y="163" text-anchor="middle">settled before transfer</text></g><g class="map-role"><rect x="262.0" y="116" width="196" height="60" rx="8"/><text x="360" y="143" text-anchor="middle">Handoff</text><text class="map-sub" x="360" y="163" text-anchor="middle">artifact + open questions</text></g><g class="map-role"><rect x="496.0" y="116" width="188" height="60" rx="8"/><text x="590" y="143" text-anchor="middle">Implementer</text><text class="map-sub" x="590" y="163" text-anchor="middle">new scoped assignment</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 224 146 H 262" marker-end="url(#tip-handoffs)"/><path class="map-link flow-edge" style="--edge-delay:1500ms" pathLength="1" d="M 458 146 H 496" marker-end="url(#tip-handoffs)"/><text class="map-note" x="360" y="310" text-anchor="middle">One active worker at a time. Ownership must be explicit.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>The first assignment ends. Its artifact and unresolved questions pass to the next assignment, with one active worker at a time.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>An investigator hands a reproduced bug and open questions to the implementer.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>One active worker at a time; at most two transfers. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>Settle the prior assignment first. A handoff must make the new ownership explicit.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/handoffs/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-group-debate" data-pattern="group-debate" aria-labelledby="pattern-title-group-debate">
 <p class="pattern-fit">Explore competing perspectives</p><h3 id="pattern-title-group-debate">Group discussion</h3><p class="pattern-thesis">Perspectives share a conversation.</p><p>Bring competing views into a bounded discussion with a moderator. Shared discussion is not fresh-context review.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Group discussion flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="Participants exchange competing views within shared context. A moderator closes the bounded discussion or escalates an unresolved decision."><defs><marker id="tip-group-debate" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><rect class="map-zone" x="130" y="26" width="460" height="272" rx="12"/><text class="map-zone-label" x="146" y="50">Shared context · bounded discussion</text><g class="map-role"><rect x="160.0" y="80" width="180" height="60" rx="8"/><text x="250" y="115" text-anchor="middle">Perspective A</text></g><g class="map-role"><rect x="380.0" y="80" width="180" height="60" rx="8"/><text x="470" y="115" text-anchor="middle">Perspective B</text></g><g class="map-role"><rect x="260.0" y="212" width="200" height="60" rx="8"/><text x="360" y="239" text-anchor="middle">Moderator</text><text class="map-sub" x="360" y="259" text-anchor="middle">collects disagreements</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 340 94 H 380" marker-end="url(#tip-group-debate)"/><path class="map-link flow-edge" style="--edge-delay:600ms" pathLength="1" d="M 380 125 H 340" marker-end="url(#tip-group-debate)"/><path class="map-link flow-edge" style="--edge-delay:1400ms" pathLength="1" d="M 250 140 L 320 212" marker-end="url(#tip-group-debate)"/><path class="map-link flow-edge" style="--edge-delay:1400ms" pathLength="1" d="M 470 140 L 400 212" marker-end="url(#tip-group-debate)"/><text class="map-note" x="360" y="322" text-anchor="middle">At most 3 participants and 2 rounds. Not independent review.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>Participants exchange competing views within shared context. A moderator closes the bounded discussion or escalates an unresolved decision.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Discuss a design tradeoff with opposing views and a moderator.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>At most three participants including moderator; two rounds. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>Recipe-only unless the harness supplies bounded shared discussion. Loom mail is not a group-chat manager.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/group-debate/PATTERN.md">Read the recipe</a></p>
 </article><article class="pattern-story" id="pattern-magentic-planning" data-pattern="magentic-planning" aria-labelledby="pattern-title-magentic-planning">
 <p class="pattern-fit">Work with an evolving task ledger</p><h3 id="pattern-title-magentic-planning">Adaptive planning</h3><p class="pattern-thesis">New evidence changes the plan.</p><p>Make an evolving plan explicit, then revisit it when new evidence changes the next task.</p>
 <div class="pattern-diagram" tabindex="0" role="region" aria-label="Adaptive planning flow; scroll horizontally on small screens"><svg viewBox="0 0 720 350" role="img" aria-label="A planner assigns work from a task ledger, reviews progress, and updates the ledger within a replan limit. This is an informational recipe, not an automatic Loom runtime."><defs><marker id="tip-magentic-planning" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#58759a" stroke-width="1.5"/></marker></defs><g class="map-role"><rect x="38.0" y="70" width="224" height="60" rx="8"/><text x="150" y="97" text-anchor="middle">Planner + ledger</text><text class="map-sub" x="150" y="117" text-anchor="middle">current tasks + evidence</text></g><g class="map-role"><rect x="470.0" y="70" width="200" height="60" rx="8"/><text x="570" y="97" text-anchor="middle">Scoped worker</text><text class="map-sub" x="570" y="117" text-anchor="middle">one bounded task</text></g><g class="map-role"><rect x="470.0" y="215" width="200" height="60" rx="8"/><text x="570" y="242" text-anchor="middle">Review progress</text><text class="map-sub" x="570" y="262" text-anchor="middle">what changed?</text></g><path class="map-link flow-edge" style="--edge-delay:0ms" pathLength="1" d="M 262 100 H 470" marker-end="url(#tip-magentic-planning)"/><text class="map-label" x="360" y="81" text-anchor="middle">next task</text><path class="map-link flow-edge" style="--edge-delay:900ms" pathLength="1" d="M 570 130 V 215" marker-end="url(#tip-magentic-planning)"/><path class="map-link flow-edge" style="--edge-delay:1800ms" pathLength="1" d="M 470 245 H 150 V 130" marker-end="url(#tip-magentic-planning)"/><text class="map-label" x="300" y="266" text-anchor="middle">update ledger · at most 2 replans</text><text class="map-note" x="360" y="322" text-anchor="middle">Recipe-only: this diagram does not imply an automatic manager.</text></svg></div>
 <details class="flow-description"><summary>Read the flow</summary><p>A planner assigns work from a task ledger, reviews progress, and updates the ledger within a replan limit. This is an informational recipe, not an automatic Loom runtime.</p></details>
 <div class="pattern-controls"><span>Illustrated handoffs, not a live run</span><button type="button" data-play-pattern hidden>Show the handoff</button></div>
 <div class="pattern-example"><span>Try it for</span><p>Investigate an unfamiliar subsystem with a task ledger and explicit replanning limits.</p></div><dl class="pattern-facts"><div><dt>Planning bounds</dt><dd>One planner, at most two scoped workers; two replans before human review. Actual spend depends on the task and models.</dd></div><div><dt>Keep in mind</dt><dd>Informational recipe: Loom does not supply a magentic manager or automatic planning loop.</dd></div></dl>
 <p class="pattern-source">Loom contributors · MIT · <a href="https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns">Upstream reference</a> · <a href="https://github.com/RedKnight13/loom/blob/main/catalog/magentic-planning/PATTERN.md">Read the recipe</a></p>
 </article></div></div>
 <p class="explorer-next">Found a useful pattern? <a href="setup.html">Set up Loom</a>, then tell your agent its name. Availability depends on your harness, isolation, permissions and budget.</p>
</section>

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
<footer class="wrap site-footer"><span>Loom · MIT</span><nav aria-label="Resources"><a href="https://github.com/RedKnight13/loom">GitHub</a><a href="protocol.html">Protocol</a><a href="https://github.com/RedKnight13/loom/blob/main/ops/README.md">Operations</a><a href="support.html">Support</a></nav></footer>
</body>
</html>
