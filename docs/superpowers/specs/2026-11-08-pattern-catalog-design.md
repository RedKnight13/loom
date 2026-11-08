# Pattern catalog — community patterns in the same session

Date: 2026-11-08
Status: design for build now. Per-repo v1. One catalog, one schema, no migration.

## 1. Intent

A person sets up Loom in a repo once. After that, the session already in that
repo can use any complete pattern in the Loom checkout's catalog without
installing that pattern as its own product. Elephant-Goldfish, the DeepSeek
Super-agent prototype, and later community patterns arrive the same way: the
session finds Loom, reads the pattern file, and works **using this pattern**.

The feel to match is First Mate. One checkout. The agent reads the files. It
asks before it changes the machine. The person keeps talking to one session.

Why this exists: advanced patterns are real and recent, and each one currently
wants its own install. Loom already is the base way of working. This design
makes that one install the door to the rest.

## 2. Goals

1. **Per repo.** A repo that has the Loom session bridge can use the catalog.
   A repo without it does not. A pattern used in one repo does not follow the
   person into another repo.
2. **One catalog.** Every selectable pattern lives at
   `catalog/<id>/PATTERN.md` in the Loom checkout. There is no second link, no
   separate clone, and no separate runtime.
3. **Contributions are PRs.** Anyone may open a pull request adding a pattern
   to the Loom repo. The owner's review and merge is the trust gate.
4. **One schema now.** Built-in families and community patterns use the same
   file shape from the first build. No migration and no parallel field sets.
5. **Explicit name wins.** A person who names a pattern they know gets that
   pattern. The session does not substitute its own pick.
6. **No opinion is still a choice.** When the person explicitly says they have
   no preference, the session says "Let me propose an ideal flow for us," makes
   one pick using the criteria in section 8, and continues in that same session.
7. **Attribution on every pattern.** A pattern missing any required field is
   not offered and is not used.
8. **Same session.** The line "using this pattern" is said and followed in the
   session the person is already talking to. No second session is opened to
   receive that instruction.
9. **The base turn holds.** The ticket, the mandate, the isolated copy, the
   report line, the trusted checks and the owner-only finish are unchanged.

## 3. Non-goals

- No machine-wide or global bridge in v1. Setup is per repo.
- No separate catalog repository, `catalog.url`, or catalog clone in v1.
- No migration of the old three-candidate wording. The build replaces it.
- Loom does not vendor or run the Elephant-Goldfish plugin or the DeepSeek
  Super-agent TypeScript runtime. A pattern is instructions the session reads.
- Loom does not gain a daemon, a panel, a listener, or a per-pattern installer.
- Loom does not replace the ticket, the mandate, the worktree, the report line,
  or the rule that only the owner finishes.
- This design does not implement the runtime routing or coordination contracts
  tracked separately.

## 4. Anti-goals

- Every advanced pattern switches on because Loom was installed.
- A pattern applies in a repo without the session bridge.
- The person is sent to a second session to hear which pattern was picked.
- A catalog entry hides who published it.
- The session invents a cost, an effectiveness gain, or an intelligence
  requirement.
- A choice made for one repo is written into another repo.
- A pattern weakens `PROTOCOL.md`, consumer laws, trusted checks, or the
  owner-only finish.
- The base Loom turn is skipped because a pattern is in use.

## 5. What they decided

These are the owner's decisions from the design conversation. A builder does
not reopen them.

- v1 is per repo. The machine-wide bridge is future work.
- The catalog lives in the Loom repo. Any contributor can raise a PR; the owner
  reviews and merges. Merge is the trust gate.
- The catalog is open to any contributor, not a closed set of approved authors.
- No opinion means the agent picks. The agent first says "Let me propose an
  ideal flow for us," then picks using the criteria in section 8.
- The session gives criteria for the pick, not a hidden preference.
- A named pattern wins. If a name matches more than one entry, the session
  lists the matches and does not pick.
- Attribution is required. A pattern with no attribution is not offered.
- The existing root session bridge is the per-repo permission. No second marker
  in v1.
- One schema now. Built-in families are written as catalog entries too; there
  is no migration path from the old table.

## 6. What already exists

Use it. Do not invent a second copy.

| Piece | Where | What this design does with it |
| --- | --- | --- |
| Base turn | `PROTOCOL.md` | Unchanged. Pattern steps sit on top. |
| One command, one JSON object | `ops/loom` | No new call contract in this design. |
| Session bridge | `templates/LOOM_SESSION.md` | Its presence in a repo is the catalog permission. |
| Saved choice | `<!-- loom-pattern:start -->` section | The selection is recorded there, in the repo in play. |
| Calibration | existing `loom calibrate --check` flow | A recorded choice changes fingerprinted bytes; the existing check, drift review, record, check sequence applies. |
| Catalog page | `docs/patterns.md` | Becomes the human explanation and links to catalog entries. It is not a second selection source. |
| Checkout update | `docs/bootstrap.txt` | The normal fast-forward brings new catalog entries. No separate pull. |
| Old three-candidate rule | `docs/patterns.md`, `docs/bootstrap.md` | Replaced by sections 7 and 8. Silence still does not select. |

## 7. Choice

The set is every complete `catalog/<id>/PATTERN.md` in the Loom checkout:
built-in families and community patterns together.

- **The person names a pattern.** That name wins. The session says the
  attribution and the estimate, then **using this pattern**. It does not
  substitute its own pick.
- **The person says they have no opinion.** The session says: "Let me propose
  an ideal flow for us." It applies section 8, picks one, says the name,
  attribution and estimate, says **using this pattern**, records it as in
  section 9, and continues.
- **The person asks to choose by hand.** The session lists every complete
  pattern with its attribution. They pick. Then **using this pattern**.
- **A non-answer is not no opinion.** Silence is not consent and does not
  select. The session asks once; if there is still no answer, it continues the
  base turn without a pattern and records no choice.
- **A saved choice that still fits is reused.** The session says the name. It
  does not quietly swap it. A different recommendation is a proposal until the
  person accepts it or says the session should pick.
- **Ambiguity.** If a typed name matches more than one entry, list the matches
  and do not pick. If it matches none, say so and do not substitute a pattern.

## 8. Criteria for the pick

When the person has no opinion, the session applies these in order. The first
criterion that rejects an entry removes it; the first eligible entry after that
wins, with the reasoning stated in one short paragraph.

1. **Eligibility.** Drop any pattern that needs a capability, isolation,
   placement, worker slot or permission the repo does not have, or that would
   exceed the approved bounds. Unknown capability is ineligible, not a guess.
2. **Task shape.** Match the work in front of it:
   - one scoped change: Solo baseline;
   - independent subtasks: parallel fan-out/fan-in;
   - fixed dependent stages: pipeline;
   - unclear design or architecture: fresh-context design/review;
   - a clear rubric and an artifact to judge: evaluator-optimizer;
   - expertise changes mid-task: handoff;
   - competing perspectives with isolated contexts: independent voting;
   - open-ended planning with no manager: magentic stays informational.
3. **Evidence.** Prefer the entry whose `when`, `cost`, `effectiveness` and
   `intelligence` fields are specific and match the observed inventory. An
   unsupported or missing dimension is unknown, not invented.
4. **Cost.** Choose the lowest-bounded pattern that satisfies 1–3. Fewer
   workers, fewer rounds and shorter elapsed time win when outcomes are
   comparable.
5. **Safety and reversibility.** Prefer the pattern that preserves the base
   turn, can be stopped, and adds no automatic behavior. A pattern that needs
   new permissions or weakens a gate is ineligible.
6. **Tie-break.** Simplest option, fewest workers, closest to the solo
   baseline. Say that the tie-break was used.

If no pattern is eligible, say so and offer the solo baseline with human
review. Do not invent a pattern or relax a constraint to make one fit.

## 9. Per-repo permission and persistence

The root `AGENTS.md` or `CLAUDE.md` session bridge is the permission. A repo
with the bridge may use catalog patterns. A repo without it follows the base
Loom way only and does not apply a catalog pattern.

After a selection, save one `loom-pattern:start` / `loom-pattern:end` section
in the repo's root bridge, using the existing template. Do not add a second
section on a rerun and do not overwrite an approved choice silently.

That write changes fingerprinted entry bytes. The existing rule applies: run
`loom calibrate --check`, review the named drift, record explicitly, then check
again before delegation. If that flow is unavailable, keep the choice for this
session only and say that it was not persisted.

**Open:** whether to record immediately or only when the person asks. The v1
default is to record immediately through the existing flow; revisit if it
proves noisy. This is the one decision deliberately left open.

## 10. The catalog

```
catalog/<id>/PATTERN.md
```

`<id>` is a stable slug: lowercase letters, digits and hyphens. The name people
say is inside the file.

- The catalog is tracked in this repository. There is no `catalog.url`, no
  clone and no fetch step.
- A new pattern arrives with the normal Loom checkout update
  (`docs/bootstrap.txt` step 2). The update already fast-forwards a clean
  checkout; it does not need a second pull.
- Nothing machine-local goes in `$LOOM_TOOLS`. The checkout must stay clean so
  that fast-forward still works.
- `catalog/README.md` explains the contribution flow and the review checklist.
- A folder missing any required field is ignored: not listed, not recommended,
  not used. If the person names it, say it is incomplete.

### Contribution and review

A contributor opens a PR adding or changing one `catalog/<id>/PATTERN.md`.
The owner's review is the trust gate. Review checks:

- every required field is present and specific;
- `author`, `upstream` and `license` are real and verifiable;
- the license permits inclusion;
- no secrets, private paths, customer data or unpublished material;
- `steps` are plain text and within the size bound;
- `steps` do not grant permissions, push or merge, weaken trusted checks, or
  spawn workers outside the session;
- `when`, `cost`, `effectiveness` and `intelligence` do not claim unsupported
  numbers.

## 11. A pattern file

`PATTERN.md` starts with these fields, each on its own line, each present:

| Field | What it is |
| --- | --- |
| `name` | The words people already use |
| `author` | Who published it |
| `upstream` | The link it came from |
| `license` | The license |
| `when` | When the session should pick it |
| `cost` | The basis for a cost increase. Not a promise |
| `effectiveness` | The basis for effectiveness. Not a promise |
| `intelligence` | The basis for how strong a model it needs. Not a promise |
| `steps` | What this session does next, on top of a normal Loom turn |

`steps` is the remainder of the file: plain text, no HTML, no scripts, bounded
in size. It may say to open workers. Those workers are part of the pattern,
directed from this session, and they still obey `PROTOCOL.md`: one assignment,
one worktree, one report line, no push.

Precedence is explicit: `PROTOCOL.md`, the consumer laws, the trusted checks
and the owner-only finish override any `steps` text. A pattern cannot grant
itself authority, change a gate, push, merge, or start a worker outside this
session.

Attribution is `author`, `upstream` and `license`, shown with the name. It is a
label plus the PR review, not proof on its own.

## 12. What the session says

Before it follows a pattern, the same session says all of this, in its own
words:

- the `name`
- the `author`, the `upstream`, and the `license`
- the cost increase, the effectiveness, and the intelligence, grounded in those
  fields and in this piece of work
- the line **using this pattern**

When the person had no opinion, it says "Let me propose an ideal flow for us"
first, then the pick and the criteria that decided it, then the announcement
above.

Then it follows `steps` for this piece of work. The next Loom turn still opens
or continues one ticket, works in one isolated copy, and ends in one structured
line. Only the owner finishes.

## 13. Calls made here

Marked so a reader can reject them. The owner's answers are in section 5;
these are the implementation calls made on top of them.

- Attribution is `author`, `upstream` and `license`, shown with the name.
- A pattern folder is `catalog/<id>/PATTERN.md` with the fields in section 11.
- The estimate is spoken from those fields plus the task. Unsupported figures
  stay unknown.
- The existing session bridge is the per-repo permission.
- The catalog is tracked in this repo; no `catalog.url`, clone or separate pull.
- New patterns arrive with the normal checkout update.
- One schema now: built-ins are catalog entries, and `docs/patterns.md` links to
  them instead of carrying a second field set.
- No opinion must be said explicitly. Silence asks once, then runs the base turn
  without a pattern.
- The criteria order in section 8 is the default; the session states any
  tie-break.
- The selection is recorded through the existing calibration flow.
- A pattern's `steps` are subordinate to the base protocol and the gates.

## 14. Left to the builder

- How a typed name matches `name` and any aliases, including case and extra
  words.
- The exact sentences, as long as section 12 is all present and no figure is
  invented.
- The exact trigger phrases for "no opinion".
- The size bound for `steps`.
- The exact wording of `catalog/README.md` and the PR review checklist.
- How `docs/patterns.md` links to catalog entries without duplicating their
  fields.

## 15. Done

A builder is done when all of these are true:

- A repo with the session bridge can name a pattern, or say it has no opinion,
  and hears the attribution, the three-part estimate and "using this pattern"
  in that same session.
- A repo without the bridge does not apply a catalog pattern.
- No opinion produces "Let me propose an ideal flow for us," one pick justified
  by section 8, and the announcement; silence produces no selection.
- Built-in families and community entries are both selectable from the one
  catalog schema.
- A named pattern wins; an ambiguous name lists matches and does not pick; an
  unknown name is said to be unknown.
- A folder missing a required field or attribution is not offered.
- A pattern added by a merged PR is available after the normal Loom update,
  with no separate pull.
- The base report line, the worktree, the calibration flow and the owner-only
  finish still hold while a pattern's steps run.
- Nothing adds a daemon, a new `ops/loom` contract, a machine-wide bridge, or a
  second session whose only job is to hear the pattern name.

## 16. Future, not now

- A separate community catalog repository, if the in-repo catalog outgrows the
  Loom checkout. That is when `catalog.url` and clone logic would return.
- A machine-wide bridge for harnesses with a supported global entry point.
- More than one catalog source.

None of these are in v1.
