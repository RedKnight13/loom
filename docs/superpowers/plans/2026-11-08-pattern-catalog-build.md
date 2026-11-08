# Pattern catalog build plan

Date: 2026-11-08
Source: `docs/superpowers/specs/2026-11-08-pattern-catalog-design.md`
Status: ready to dispatch. Workers never push; the conductor verifies and merges.

## Shape

Three tickets. Two run in parallel, then the third takes the first free slot.

| Ticket | Short name | Owns |
| --- | --- | --- |
| A | `catalog-entries` | `catalog/<id>/PATTERN.md` × 11, `docs/patterns.md` |
| B | `catalog-bootstrap` | `docs/bootstrap.txt`, `docs/bootstrap.md`, `docs/copy.html` |
| C | `catalog-session` | `templates/LOOM_SESSION.md`, `docs/setup.md`, `docs/support.md`, `ops/README.md` |

The root `AGENTS.md` in the conductor checkout is local, git-ignored machine
setup. No ticket edits it. The conductor updates it after merge and re-records
calibration.

Dispatch A and B together. Dispatch C when either finishes.

## Shared invariants

- The spec is authoritative. Read it before editing.
- `catalog/README.md` and `catalog/PATTERN.template.md` already exist. Build on
  them; do not replace the contribution and review rules.
- No `ops/` code changes, no new `ops/loom` contract, no global bridge, no
  `catalog.url`, no clone, no migration.
- Historical specs stay historical. Do not rewrite
  `2026-11-08-coordination-patterns.md` or other dated records.
- No private paths, host names, identities, tokens or account details.
- Gates after the edit: `bash ops/selftest.sh`, then
  `shellcheck -x ops/*.sh ops/loom`, then `bash ops/mutate.sh`. Capture the
  exit code of each. A check not run is reported as not run.
- No push. End with the structured report line and the exact tested revision.

## Ticket A — catalog entries and the pattern page

### Entries

Create one folder per built-in family:

| id | Source for `upstream` |
| --- | --- |
| `solo-baseline` | https://www.anthropic.com/research/building-effective-agents |
| `pipeline` | https://www.anthropic.com/research/building-effective-agents |
| `specialist-routing` | https://www.anthropic.com/research/building-effective-agents |
| `parallel-fan-out` | https://www.anthropic.com/research/building-effective-agents |
| `orchestrator-workers` | https://www.anthropic.com/research/building-effective-agents |
| `evaluator-optimizer` | https://www.anthropic.com/research/building-effective-agents |
| `fresh-context-review` | https://github.com/google/elephant-goldfish-model |
| `independent-voting` | https://www.anthropic.com/research/building-effective-agents |
| `group-debate` | https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns |
| `handoffs` | https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns |
| `magentic-planning` | https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns |

Each file is `catalog/<id>/PATTERN.md` with all nine fields from the spec.

- `author`: `Loom contributors`.
- `upstream`: the URL above.
- `license`: `MIT` (the repository license covers Loom's summary text).
- `name`: the family name people say, including the aliases already listed in
  `docs/patterns.md` where they help matching.
- `when`: the fit and context boundary from the table.
- `cost`: the proposed worker/review bounds as a basis, never a promise.
- `effectiveness`: the basis for the claim, taken from the fit and risk text.
  No invented percentages, elapsed times or quality gains.
- `intelligence`: the basis for model strength, or `no specific requirement
  observed` where the table gives none.
- `steps`: the Loom mapping expanded into what the session does on top of a
  normal Loom turn. It must keep one assignment, one worktree, one report line,
  no push, and must not grant permissions or change a gate.

The entries are Loom's own summaries. Do not copy source prose.

### `docs/patterns.md`

- Remove the default "exactly three candidates" rule and the four-response
  prompt built on it.
- Add the new selection summary: an explicit name wins; no opinion means the
  session says "Let me propose an ideal flow for us," applies the criteria, and
  picks one; silence does not select.
- Link each family to its `catalog/<id>/PATTERN.md` entry. Keep the explanation,
  comparison table, model-role guidance and primary sources. Do not duplicate
  the nine fields.
- Keep the statement that the page is the explanation, not a second selection
  source.

### Done

- Eleven valid entries, one per family, each with every field.
- No shipped sentence in `docs/patterns.md` still offers exactly three
  candidates as the default.
- Gates exit 0, or the report names exactly what was not run.

## Ticket B — bootstrap prompt and public copy

Files: `docs/bootstrap.txt`, `docs/bootstrap.md`, `docs/copy.html`.

Replace step 6 of the prompt and the "Three choices" section of the mirror
with the new flow:

- The set is every complete catalog entry in the Loom checkout.
- A named pattern wins. If the name is ambiguous, list the matches and do not
  pick. If it is unknown, say so and do not substitute.
- No opinion: say "Let me propose an ideal flow for us," apply the criteria,
  pick one, and announce name, attribution, estimate and **using this pattern**.
- Silence is not no opinion. Ask once, then continue the base turn without a
  pattern and record no choice.
- The catalog is per repo: the root session bridge is the permission.
- New entries arrive with the normal checkout update. There is no separate
  catalog URL, clone or pull.
- Keep the existing capacity, role-advice, mandate and authorization language.
  Keep an approved choice reusable; a changed recommendation stays a proposal.

`docs/copy.html` must carry the same rule in its "What to expect" list. The
three files must not contradict each other.

### Done

- `grep -n 'exactly three\|three candidates\|three task-appropriate\|three choices'`
  finds no current-rule sentence in these files.
- The no-opinion sentence, the criteria reference, the silence rule and the
  per-repo permission are present.
- Gates exit 0, or the report names exactly what was not run.

## Ticket C — session template, setup and support pages

Files: `templates/LOOM_SESSION.md`, `docs/setup.md`, `docs/support.md`, and
`ops/README.md` only if it states the old rule. Do not edit the root
`AGENTS.md`; it is local, git-ignored machine setup.

- `templates/LOOM_SESSION.md`: the bridge remains the per-repo permission. Add
  the no-opinion proposal sentence, the pick criteria summary, and the
  recording/calibration rule: a recorded choice changes fingerprinted bytes, so
  run `--check`, review drift, record explicitly, then check again before
  delegation. If that flow is unavailable, keep the choice session-only.
- `docs/setup.md`: replace the two "three task-appropriate choices" claims with
  the catalog and no-opinion rule. Document the catalog path, the PR
  contribution flow and the review checklist by linking `catalog/README.md`.
  Keep the existing capacity and model-role language.
- `docs/support.md`: correct any claim that setup offers exactly three choices.
- `ops/README.md`: correct only if it states the old rule.

### Done

- No current-rule sentence in these files still promises three candidates.
- The per-repo permission, the no-opinion script, the criteria reference and the
  calibration recording rule are present.
- Gates exit 0, or the report names exactly what was not run.

## Verification before merge

1. Confirm eleven `catalog/*/PATTERN.md` folders and all nine fields each.
2. `grep -rn 'exactly three\|three candidates\|three task-appropriate\|three choices'`
   across shipped docs. Historical specs may match; current docs must not.
3. Read `docs/bootstrap.txt`, `docs/bootstrap.md`, `docs/copy.html` and
   `docs/patterns.md` side by side for one rule, one voice.
4. Confirm no private data, no new dependency, no runtime change.
5. Confirm each worker's captured exits and the tested revision.
6. Merge only after the conductor verifies the combined revision.

## Out of scope

- Machine-wide bridge.
- Separate catalog repository, `catalog.url`, clone or fetch.
- `ops/protocol.sh`, executor contracts, runtime routing.
- Migrating the old table; the build writes the new schema directly.
- Starting workers, installing plugins or changing models.
