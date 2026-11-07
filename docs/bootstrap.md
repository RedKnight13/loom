# Bootstrap prompt

A single copy-paste block that sets Loom up on a machine, proves it, and stops
before creating anything in your repository. It is written for Claude Code,
Codex, or any agent that can run shell commands.

**Copy it from the site:** <https://redknight13.github.io/loom/copy.html>
— the page has a one-click copy button. The raw text is
[bootstrap.txt](bootstrap.txt) if you prefer to read or download it.

## What it does

1. Checks prerequisites and reports versions.
2. Clones Loom to `~/loom` (never overwriting a dirty checkout).
3. Runs the offline selftest and `shellcheck`; stops on either non-zero exit.
   The long, macOS-only `ops/mutate.sh` is the contributor and CI gate, not a
   setup requirement.
4. Asks for the consumer repo, its checks command, the worktrees directory,
   the executor, and how many workers may run at once — offering the number
   `loom capacity` suggests from Orca's connected hosts. It never guesses.
   Creates a local, untracked config inside the Loom checkout; it does not
   commit it. Commit a config only when it lives in the consumer repo, as a
   separate task outside this bootstrap.
5. Verifies `gh` and, if you choose Orca, that its runtime is ready and its
   version is at least **1.4.246**.
6. Renders a ticket with `--dry-run` and stops before opening it.

It never pushes, merges, or writes credentials to a file, and it does not claim
success without a captured exit code. Its final summary reports the two setup
gate exit codes: selftest and shellcheck.

## After the prompt

```bash
loom accept --consumer consumers/<name>.toml --short first-check \
  --title "First check" --scope "<one area>" --out "everything else" \
  --done "<checks command> exits 0"
LOOM_REPO=/path/to/repo loom dispatch --consumer consumers/<name>.toml --issue <N>
```

Then read [setup.md](setup.md) for the daily loop, the compute host, and the
troubleshooting table.

## Orca, or not

Orca is the supervised backend, MIT licensed:
<https://github.com/stablyai/orca>. Supported floor **1.4.246** (tested on
1.4.246; releases are tagged).

Choose `executor = "local"` for the zero-dependency path. One caveat: if Orca is
installed and its runtime is ready, `launch` refuses a local worker unless
`LOOM_ALLOW_LOCAL=1`; declaring `executor = "local"` makes the choice explicit.
