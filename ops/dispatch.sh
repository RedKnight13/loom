#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
[[ $# == 2 ]] || loom_error 'usage: dispatch.sh <consumer.toml> <issue#>'
[[ $2 =~ ^[1-9][0-9]*$ ]] || loom_error 'issue must be a positive integer'
[[ -f $1 ]] || loom_error 'consumer config not found'

config=$(loom_config "$1")
repo=$(jq -r '.repo' <<< "$config")
worktrees=$(jq -r '.worktrees' <<< "$config")
case $worktrees in \~) worktrees=$HOME ;; \~/*) worktrees="$HOME/${worktrees:2}" ;; esac
[[ $worktrees == /* ]] || loom_error 'worktrees must be an absolute path (or ~/...)'
checkout=$(git -C "${LOOM_REPO:-.}" rev-parse --show-toplevel) || loom_error 'run in the consumer checkout or set LOOM_REPO'
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
shopt -s nullglob
for file in "$LOOM_STATE"/*.json; do
    loom_validate "$file"
    if jq -e --arg repo "$repo" --argjson ticket "$2" '.repo == $repo and .ticket == $ticket' "$file" >/dev/null; then
        ! loom_alive "$file" || loom_error "ticket already has a live assignment: $(basename "$file" .json)"
    fi
    jq -e --arg short "$short" '.short_name == $short' "$file" >/dev/null || continue
    n=$(jq -r '.attempt' "$file")
    (( n < attempt )) || attempt=$((n + 1))
done
mkdir -p "$worktrees"
workdir="$worktrees/$short.$attempt"
[[ ! -e $workdir && ! -L $workdir ]] || loom_error "workdir already exists; conductor must resolve it: $workdir"
id="$short.$attempt"
[[ ! -e $LOOM_STATE/$id.json ]] || loom_error "assignment id collision: $id"
# A private clone, not a worktree: the worker owns its whole .git, so a
# sandboxed executor can commit. The clone has no remote, so it cannot push.
git clone -q --no-checkout "$checkout" "$workdir"
git -C "$workdir" remote remove origin
git -C "$workdir" fetch -q "$checkout" "$base_sha"
git -C "$workdir" checkout -q -b "$short" "$base_sha"
for key in user.name user.email; do
    if value=$(git -C "$checkout" config --get "$key"); then
        git -C "$workdir" config "$key" "$value"
    fi
done
printf 'WORK.md\nREPORT.md\n' >> "$workdir/.git/info/exclude"
{
    printf '# %s\n\n%s\n\n## Consumer laws\n\n' "$(jq -r '.title' <<< "$issue")" "$mandate"
    jq -r '.laws[] | "- " + .' <<< "$config"
    if [[ $(jq -r '.checks // empty' <<< "$config") ]]; then
        printf '\n## Checks the conductor will run\n\nOn ready, the conductor runs exactly this in a fresh clone of your branch; run it yourself before reporting:\n\n    %s\n' "$(jq -r '.checks' <<< "$config")"
    fi
    printf '\n## How to report\n\nEnd every turn by appending one line to REPORT.md in this directory:\n\n    state: <ready|blocked|failed|waiting> — <one-line fact>\n\nready = a reviewable result is in this directory; blocked = one concrete question; failed = what failed and why; waiting = turn done, nothing owed.\n\nDo not run git add or git commit: leave your changes in the working tree. Loom commits them onto branch %s when you report.\n' "$short"
} > "$workdir/WORK.md"
jq -n --argjson ticket "$2" --arg repo "$repo" --arg short "$short" \
      --arg workdir "$workdir" --arg checkout "$checkout" --arg base "$base_sha" \
      --argjson attempt "$attempt" --argjson limit "$(jq '.limit_min // null' <<< "$config")" \
      --argjson checks "$(jq '.checks // null' <<< "$config")" '
  {ticket: $ticket, repo: $repo, short_name: $short, attempt: $attempt,
   workdir: $workdir, checkout: $checkout, base_sha: $base,
   checks: $checks, limit_min: $limit, worker_pid: null, worker_start: null,
   started_at: (now | todateiso8601), reports: []}
' > "$LOOM_STATE/.pending"
mv "$LOOM_STATE/.pending" "$LOOM_STATE/$id.json"
printf '%s\n%s\n' "$workdir" "$id"
