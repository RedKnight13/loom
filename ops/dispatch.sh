#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
usage='usage: dispatch.sh <consumer.toml> <issue#> [--executor auto|local|orca]'
want=''
if [[ $# == 4 && $3 == --executor ]]; then want=$4; set -- "$1" "$2"; fi
[[ $# == 2 ]] || loom_error "$usage"
[[ -z $want || $want =~ ^(auto|local|orca)$ ]] || loom_error "$usage"
[[ $2 =~ ^[1-9][0-9]*$ ]] || loom_error 'issue must be a positive integer'
[[ -f $1 ]] || loom_error 'consumer config not found'

config=$(loom_config "$1")
# A config under version control must be committed: the record pins the exact
# config the assignment ran under (gap #20).
config_dir=$(cd "$(dirname "$1")" && pwd)
config_name=$(basename "$1")
config_commit=null
if git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [[ -z $(git -C "$config_dir" status --porcelain -- "$config_name") ]] || loom_error "consumer config has uncommitted changes; commit it first: $1"
    config_commit=$(jq -Rn --arg c "$(git -C "$config_dir" log -1 --format=%H -- "$config_name")" '$c')
fi
repo=$(jq -r '.repo' <<< "$config")
# Executor (gaps #25, #26): the consumer may require Orca; otherwise --executor
# or detection decides. Required-but-unreachable Orca refuses; never a silent
# fallback to starting workers outside Orca.
policy=$(jq -r '.executor // "auto"' <<< "$config")
[[ $policy == auto || -z $want || $want == "$policy" ]] || loom_error "consumer requires executor '$policy'; --executor $want refused"
[[ $policy != auto ]] || policy=${want:-auto}
orca_runtime=''
if [[ $policy != local ]]; then orca_runtime=$(loom_orca_ready) || orca_runtime=''; fi
case $policy in
    orca) [[ -n $orca_runtime ]] || loom_error 'executor orca required but the Orca CLI/runtime is not ready (orca status)'; executor=orca ;;
    local) executor=local ;;
    auto) if [[ -n $orca_runtime ]]; then executor=orca; else executor=local; fi ;;
esac
worktrees=$(jq -r '.worktrees' <<< "$config")
case $worktrees in \~) worktrees=$HOME ;; \~/*) worktrees="$HOME/${worktrees:2}" ;; esac
[[ $worktrees == /* ]] || loom_error 'worktrees must be an absolute path (or ~/...)'
checkout=$(git -C "${LOOM_REPO:-.}" rev-parse --show-toplevel) || loom_error 'run in the consumer checkout or set LOOM_REPO'
# The checkout must be the consumer's repo, or the base commit comes from the
# wrong project (gap #54). Compare the origin URL case-insensitively, ignoring
# scheme, host and a trailing .git. LOOM_ALLOW_ANY_CHECKOUT=1 covers a repo
# with no origin of its own (a local-only checkout).
if [[ ${LOOM_ALLOW_ANY_CHECKOUT:-0} != 1 ]]; then
    origin=$(git -C "$checkout" remote get-url origin 2>/dev/null || :)
    [[ -n $origin ]] || loom_error "checkout has no origin; expected $repo (set LOOM_ALLOW_ANY_CHECKOUT=1 for a local-only repo)"
    slug=$(printf '%s' "$origin" | sed -E 's#^(git@|ssh://git@|https?://|git://)##; s#^[^/:]+[:/]##; s#\.git$##; s#/$##' | tr '[:upper:]' '[:lower:]')
    want=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
    [[ $slug == "$want" ]] || loom_error "checkout origin is '$origin' ($slug), not $repo"
fi
issue=$(gh issue view "$2" --repo "$repo" --json number,title,body)
jq -e --argjson number "$2" '.number == $number and (.title | type == "string") and (.body | type == "string")' <<< "$issue" >/dev/null || loom_error 'invalid issue response'
mandate=$(jq -r '.body' <<< "$issue" | loom_mandate)
short=$(loom_short "$mandate")
default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name')
git check-ref-format --branch "$default_branch" >/dev/null || loom_error 'invalid default branch'
if git -C "$checkout" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
    base="refs/remotes/origin/$default_branch"
elif git -C "$checkout" show-ref --verify --quiet "refs/heads/$default_branch"; then
    base="refs/heads/$default_branch"
else
    loom_error 'default branch is not available locally; conductor must fetch it first'
fi
base_sha=$(git -C "$checkout" rev-parse --verify "$base^{commit}")
loom_init
loom_lock
# One ticket, one live worker. Attempts are numbered per short name across
# all tickets: a corrected ticket (mandates are immutable) may reuse a name.
attempt=1
open_ids=()
shopt -s nullglob
for file in "$LOOM_STATE"/*.json; do
    loom_validate "$file"
    if jq -e --arg repo "$repo" --argjson ticket "$2" '.repo == $repo and .ticket == $ticket' "$file" >/dev/null; then
        ! loom_alive "$file" || loom_error "ticket already has a live assignment: $(basename "$file" .json)"
    fi
    # Global cap for this consumer, when `workers` is declared.
    if jq -e --arg repo "$repo" '.repo == $repo' "$file" >/dev/null && loom_open "$file"; then
        open_ids+=("$(basename "$file" .json)")
    fi
    jq -e --arg short "$short" '.short_name == $short' "$file" >/dev/null || continue
    n=$(jq -r '.attempt' "$file")
    (( n < attempt )) || attempt=$((n + 1))
done
workers=$(jq '.workers // null' <<< "$config")
if [[ $workers != null ]]; then
    (( ${#open_ids[@]} < workers )) || loom_error "worker limit reached (workers=$workers): ${open_ids[*]}"
fi
mkdir -p "$worktrees"
workdir="$worktrees/$short.$attempt"
if [[ $executor == orca ]]; then workdir=""; else
    [[ ! -e $workdir && ! -L $workdir ]] || loom_error "workdir already exists; conductor must resolve it: $workdir"
fi
id="$short.$attempt"
[[ ! -e $LOOM_STATE/$id.json ]] || loom_error "assignment id collision: $id"
# A private clone, not a worktree: the worker owns its whole .git, so a
# sandboxed executor can commit. The clone has no remote, so it cannot push.
if [[ $executor == local ]]; then
    git clone -q --no-checkout "$checkout" "$workdir"
    git -C "$workdir" remote remove origin
    git -C "$workdir" fetch -q "$checkout" "$base_sha"
    git -C "$workdir" checkout -q -b "$short" "$base_sha"
    for key in user.name user.email; do
        if value=$(git -C "$checkout" config --get "$key"); then
            git -C "$workdir" config "$key" "$value"
        fi
    done
    printf 'WORK.md\nREPORT.md\n.loom/\n' >> "$workdir/.git/info/exclude"
    workfile="$workdir/WORK.md"
else
    workfile="$LOOM_STATE/$id.WORK.md"
fi
{
    printf '# %s\n\n%s\n\n## Consumer laws\n\n' "$(jq -r '.title' <<< "$issue")" "$mandate"
    jq -r '.laws[] | "- " + .' <<< "$config"
    if [[ $(jq -r '.checks // empty' <<< "$config") ]]; then
        printf '\n## Checks the conductor will run\n\nOn ready, the conductor runs exactly this in a fresh clone of your branch; run it yourself before reporting:\n\n    %s\n' "$(jq -r '.checks' <<< "$config")"
    fi
    printf '\n## How to report\n\nEnd every turn by appending one line to REPORT.md in this directory:\n\n    state: <ready|blocked|failed|waiting> — <one-line fact>\n\nready = a reviewable result is in this directory; blocked = one concrete question; failed = what failed and why; waiting = turn done, nothing owed.\n\nPut logs and other evidence under .loom/ in this directory. Loom keeps that directory out of the commit and copies it into the assignment record. Do not leave logs at the workspace root.\n\nDo not run git add or git commit: leave your changes in the working tree. Loom commits them onto branch %s when you report.\n' "$short"
} > "$workfile"
jq -n --argjson ticket "$2" --arg repo "$repo" --arg short "$short" \
      --arg workdir "$workdir" --arg checkout "$checkout" --arg base "$base_sha" \
      --argjson attempt "$attempt" --argjson limit "$(jq '.limit_min // null' <<< "$config")" \
      --argjson checks "$(jq '.checks // null' <<< "$config")" --argjson config_commit "$config_commit" \
      --arg executor "$executor" --arg runtime "$orca_runtime" \
      --argjson compute "$(jq 'if has("compute") then [.compute] | flatten else null end' <<< "$config")" \
      --argjson compute_setup "$(jq '.compute_setup // null' <<< "$config")" \
      --argjson compute_selector "$(jq '.compute_selector // null' <<< "$config")" \
      --argjson model "$(jq '.model // null' <<< "$config")" \
      --argjson effort "$(jq '.effort // null' <<< "$config")" \
      --argjson timeout "$(jq '.start_timeout_ms // null' <<< "$config")" \
      --argjson workers "$(jq '.workers // null' <<< "$config")" '
  {ticket: $ticket, repo: $repo, short_name: $short, attempt: $attempt,
   workdir: $workdir, checkout: $checkout, base_sha: $base,
   checks: $checks, compute: $compute, compute_setup: $compute_setup,
   compute_selector: $compute_selector, model: $model, effort: $effort,
   start_timeout_ms: $timeout, workers: $workers, config_commit: $config_commit, limit_min: $limit, worker_pid: null, worker_start: null,
   executor: (if $executor == "orca" then {kind: "orca", state: "pending", runtime: $runtime} else {kind: "local"} end),
   started_at: (now | todateiso8601), reports: []}
' > "$LOOM_STATE/.pending"
mv "$LOOM_STATE/.pending" "$LOOM_STATE/$id.json"
if [[ $executor == orca ]]; then
    printf '%s\n%s\n' "orca: workspace is created at start (ops/orca.sh start $id)" "$id"
else
    printf '%s\n%s\n' "$workdir" "$id"
fi
