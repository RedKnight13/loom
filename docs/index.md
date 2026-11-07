# loom

**Work coordination for agent executors.** Tickets, mandates, one worker per
ticket, structured reports, a watchdog. The conductor is the only role that
pushes, reviews and merges.

Version 0.6.0. One call, one JSON object:

```json
{"v":"0.6.0","cmd":"status","ok":true,"state":"waiting","fact":"nothing waits for a person","id":null,"ticket":null,"items":[],"actions":[]}
```

## Start here

- [Bootstrap prompt](bootstrap.md) — paste into Claude Code or Codex; it installs and proves Loom
- [Setup](setup.md) — install, consumer config, Orca, compute host
- [Support](support.md) — what works, what does not, known gaps
- [Setup checklist](setup.md#8-first-ticket-checklist) — before the first ticket

Supervised backend: [Orca](https://github.com/stablyai/orca) (MIT, 1.4.246+).
Loom works without it; the local executor is fully supported.

## The law and the tools

- [Protocol](https://github.com/RedKnight13/loom/blob/main/PROTOCOL.md) — roles, domain, report states
- [Operations](https://github.com/RedKnight13/loom/blob/main/ops/README.md) — every script and its guarantee
- [Mandate template](https://github.com/RedKnight13/loom/blob/main/templates/MANDATE.md) — the block a Ticket carries
- [Roadmap](https://github.com/RedKnight13/loom/blob/main/ROADMAP.md) — layers and the certification bar
- [README](https://github.com/RedKnight13/loom#readme) — quickstart and reference

## The short version

A request becomes a **Ticket** (a GitHub issue carrying an immutable
**Mandate**). `dispatch` gives one worker an isolated workspace. The worker
writes files and one structured line — `ready`, `blocked`, `failed`, `waiting` —
and never touches git. Loom commits the work, holds a **watchdog** keyed to PID
and process start time, re-runs the consumer's checks in a fresh clone (on its
compute host when declared), and surfaces only what needs a person.

Source: <https://github.com/RedKnight13/loom>
