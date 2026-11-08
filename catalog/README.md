# Loom pattern catalog

A pattern is instructions a session reads, not a program Loom runs. Every
selectable pattern lives at:

```
catalog/<id>/PATTERN.md
```

`<id>` is a stable slug: lowercase letters, digits and hyphens. The name people
say is inside the file.

This catalog is the only selection source. `docs/patterns.md` explains the
families and links here; it does not carry a second set of fields. New patterns
arrive with the normal Loom checkout update. There is no separate catalog URL,
clone or pull.

## Add a pattern

1. Copy `catalog/PATTERN.template.md` into `catalog/<id>/PATTERN.md`.
2. Fill every field. Do not invent cost, effectiveness or intelligence numbers;
   state the basis, or say unknown.
3. Keep `steps` plain text and bounded. Say what the session does on top of a
   normal Loom turn.
4. Open a pull request against this repository.

Anyone may contribute. The owner reviews and merges; merge is the trust gate.

## Review checklist

- Every required field is present and specific.
- `author`, `upstream` and `license` are real and verifiable.
- The license permits inclusion in this repository.
- No secrets, private paths, customer data or unpublished material.
- `steps` are plain text, within the size bound, and contain no HTML or scripts.
- `steps` do not grant permissions, push or merge, weaken trusted checks, or
  start workers outside the session.
- `when`, `cost`, `effectiveness` and `intelligence` claim no unsupported
  numbers.
- A pattern with no attribution is not offered.

## What the session does

A repo with the Loom session bridge may use this catalog. A repo without the
bridge does not. The session shows the pattern name, `author`, `upstream`,
`license` and the three-part estimate before it says **using this pattern**.

`PROTOCOL.md`, the consumer laws, the trusted checks and the owner-only finish
override any pattern text. A pattern cannot grant itself authority, change a
gate, push, merge, or start a worker outside the session.
