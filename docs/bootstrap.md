# Bootstrap prompt

Paste the block below into Claude Code, Codex, or any coding agent that can run
shell commands. It sets Loom up on the machine, proves it, and stops before
creating anything in your repository.

It takes a few minutes (the mutant suite is the slow part) and needs no
network beyond cloning, `gh`, and optional Orca.

## What the agent will do

1. Check prerequisites and report versions.
2. Clone Loom to `~/loom` (never overwrite a dirty checkout).
3. Run the offline selftest and `shellcheck`, and stop if either fails.
4. Ask you for the consumer repo, its checks command, the worktrees directory,
   and the executor, then write `consumers/<name>.toml`.
5. Verify `gh` auth and, if you chose Orca, that its runtime is ready and its
   version is supported.
6. Render a ticket with `--dry-run` and stop before opening it.

It never pushes, merges, or writes credentials to a file. It never claims
success without a captured exit code.

## The prompt

```text
Set up Loom on this machine. Loom is a work-coordination layer for coding
agents: https://github.com/RedKnight13/loom (MIT).

Rules for this task:
- Do not modify, commit to, or push any repository other than the Loom checkout.
- Do not install anything without asking first.
- Do not write credentials, tokens, or personal names into any file.
- Report the captured exit code of every command you run. Never say "done"
  without one. If a step fails, stop and show the last 20 lines of output.

1. Check prerequisites and report versions:
     bash --version | head -1
     git --version
     jq --version
     gh --version | head -1
     shellcheck --version | head -2
     orca --version 2>/dev/null || echo "orca: not installed (optional)"
   If jq, git, gh, or shellcheck is missing, say which and stop.

2. Ensure the checkout exists:
     test -d ~/loom || git clone https://github.com/RedKnight13/loom.git ~/loom
     git -C ~/loom status --short
   If the checkout already exists and is dirty, show the diff and stop.

3. Prove the checkout:
     cd ~/loom && bash ops/selftest.sh
     echo "SELFTEST=$?"
     shellcheck -x ops/*.sh ops/loom
     echo "LINT=$?"
     bash ops/mutate.sh
     echo "MUTATE=$?"
   All three must be 0. If any is not, stop.

4. Ask me for these, and do not guess:
   - the consumer repo that owns the tickets, as owner/name
   - the checks command you already trust for that repo (it must exit 0 on main)
   - the worktrees directory (default: ~/work/<repo>-workdirs)
   - executor: auto, local, or orca
   Then create consumers/<name>.toml from consumers/example.toml with those
   values, and show me the file. If the consumer repo is under git, commit only
   that config file, with the message "consumers: register <name>".

5. Verify connectivity:
     gh auth status
     gh repo view <owner/name> --json defaultBranchRef,name
   If executor is orca:
     orca status
     orca --version       # must be 1.4.246 or newer
     orca host list --json
   If a compute host is declared in the config, it must appear connected in that
   host list. If executor is local while Orca is installed and ready, note that
   `launch` needs LOOM_ALLOW_LOCAL=1; prefer setting executor = "local".

6. Render a ticket without opening it:
     cd ~/loom && bash ops/ticket.sh consumers/<name>.toml \
       --short first-check --title "First check" \
       --scope "<one file or area>" \
       --out "everything else" \
       --done "<the checks command> exits 0" \
       --dry-run
   Show me the Mandate. Stop here. Do not open an issue until I say go.

7. When I approve, report exactly:
     cd ~/loom && bash ops/loom version
     the single command to open the first ticket with `loom accept`
     the single command to dispatch it after that
   Do not run either command yet.

Finally, summarise: what you installed or changed, the three gate exit codes,
the executor chosen, and anything that will need my decision later.
```

## After the prompt

If every gate is 0, the next two commands are:

```bash
loom accept --consumer consumers/<name>.toml --short first-check \
  --title "First check" --scope "<one area>" --out "everything else" \
  --done "<checks command> exits 0"
LOOM_REPO=/path/to/repo loom dispatch --consumer consumers/<name>.toml --issue <N>
```

Then read [setup.md](setup.md) for the daily loop, the compute host, and the
troubleshooting table.

## If you want Orca

Orca is the supervised backend, MIT licensed:
<https://github.com/stablyai/orca>. Supported floor: **1.4.246** (tested on
1.4.246; releases are tagged, so newer is normally fine).

```bash
orca status          # app running, runtime ready
orca --version       # >= 1.4.246
orca repo add --path ~/src/your-repo
orca host list       # connect any declared compute host in the app first
```

Loom refuses to place a worker when the declared host is not connected. It never
falls back to the conductor's machine, and it never connects a host for you.

## If you do not want Orca

Choose `executor = "local"`. That path is fully supported: private clone, no
remote, watchdog, fresh-clone verify, collect. Nothing in the protocol needs
Orca.

One caveat: if Orca is installed **and its runtime is ready**, `launch.sh`
refuses to start a local worker unless `LOOM_ALLOW_LOCAL=1` is set. That is the
owner's policy, not a technical limit; declare `executor = "local"` to make the
choice explicit.
