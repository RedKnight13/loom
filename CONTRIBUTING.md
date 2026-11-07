# Contributing

Loom is small on purpose. A change is welcome when it makes a failure
impossible or observable, and it arrives with evidence.

## The gate

All three must exit 0 before a change lands:

```bash
bash ops/selftest.sh
shellcheck -x ops/*.sh ops/loom
bash ops/mutate.sh
```

`ops/mutate.sh` re-introduces each fixed defect and requires the selftest to
fail. A fix without a **selftest case** and a **mutant** that proves the case has
teeth is not done. Add the mutant in `ops/mutate.sh` in the same change.

## Rules the code keeps

- One JSON object per `ops/loom` call; exit 0 iff `ok`.
- Workers never push. Loom never runs `git push`.
- No inferring a report state from prose. Structured fields or nothing.
- No silent fallback: a declared executor or compute host that is unavailable
  refuses.
- A state file is validated on read. Corrupt state is never healthy.
- No new runtime, daemon, database or language. Bash, `git`, `jq`, `gh`, and
  optional Orca/SSH.

## Design changes

A change to the call contract, the report vocabulary, or the domain table gets a
spec in `docs/superpowers/specs/` first, then a plan in
`docs/superpowers/plans/`. The 0.5.0 and 0.6.0 specs are the worked examples.

## Commits

- One logical change.
- Say what was verified and the captured exit code.
- Do not commit generated state, `$LOOM_STATE`, worker evidence, or secrets.
- Do not add names, emails, or machine credentials to fixtures.

## Reporting a bug

Include `VERSION`, platform, the verb, the captured exit code, and the JSON
object. "Not run" is reported as "not run".
