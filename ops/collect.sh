#!/usr/bin/env bash
# collect.sh <assignment-id>
#
# Conductor step after a `ready` report: fetch the ticket branch from the
# worker's private clone into the consumer checkout, and print what it adds
# over the base the worker started from. Never pushes; pushing, the PR and the
# merge stay the conductor's explicit acts. Records collected_sha so release
# can require a collected branch (gap #30).
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
[[ $# == 1 ]] || loom_error 'usage: collect.sh <assignment-id>'
loom_id "$1"
loom_init
file=$(loom_record "$1")
! jq -e '.seal_failed == true' "$file" >/dev/null || loom_error 'worker changes were not sealed'
! loom_alive "$file" || loom_error 'worker is still running; collect after it reports'
workdir=$(jq -r '.workdir' "$file")
checkout=$(jq -r '.checkout' "$file")
short=$(jq -r '.branch // .short_name' "$file")  # the branch (Orca names its own)
base=$(jq -r '.base_sha' "$file")
state=$(jq -r '.reports[-1].state // "none"' "$file")
[[ $(git -C "$checkout" branch --show-current) != "$short" ]] || loom_error "branch $short is checked out in the consumer checkout"
wh=$(loom_ws_host "$file")
loom_ws "$wh" "$workdir" git show-ref --verify --quiet "refs/heads/$short" || loom_error "worker clone has no branch $short"
[[ -z $(loom_ws "$wh" "$workdir" git status --porcelain) ]] || printf 'loom: warning: worker clone has uncommitted changes (not collected)\n' >&2
# An Orca worktree shares the checkout's repository: its branch is already
# home (and checked out there, so it cannot be fetched into).
shared=false
if [[ -z $wh ]] && [[ $(cd "$workdir" && cd "$(git rev-parse --git-common-dir)" && pwd -P) == "$(cd "$checkout" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]]; then shared=true; fi
if [[ $shared != true ]]; then
    previous=$(jq -r '.collected_sha // empty' "$file")
    destination="refs/heads/$short"
    current=$(git -C "$checkout" rev-parse --verify "$destination" 2>/dev/null || :)
    # A new attempt may supersede the last unchanged collection of this ticket.
    # An arbitrary pre-existing ref or any conductor edit is never inferred safe.
    if [[ -z $previous && -n $current ]]; then
        for prior_record in "$LOOM_STATE"/*.json; do
            [[ $prior_record != "$file" ]] || continue
            if jq -e --arg checkout "$checkout" --arg branch "$short" --arg sha "$current" --argjson attempt "$(jq .attempt "$file")" '
              .checkout==$checkout and (.branch//.short_name)==$branch and .attempt<$attempt and .collected_sha==$sha
            ' "$prior_record" >/dev/null; then previous=$current; break; fi
        done
    fi
    [[ -z $current || ( -n $previous && $current == "$previous" ) ]] || loom_error 'collection destination already exists or changed; preserve conductor changes'
    scratch_ref="refs/loom/collect/$1-$$"
    trap 'git -C "$checkout" update-ref -d "$scratch_ref"' EXIT
    if [[ -n $wh ]]; then
        loom_git_ssh -C "$checkout" fetch -q "$wh:$workdir" "refs/heads/$short:$scratch_ref"
    else
        git -C "$checkout" fetch -q "$workdir" "refs/heads/$short:$scratch_ref"
    fi
    incoming=$(git -C "$checkout" rev-parse --verify "$scratch_ref^{commit}")
    git -C "$checkout" update-ref "$destination" "$incoming" "${current:-0000000000000000000000000000000000000000}" || loom_error 'collection destination moved concurrently'
fi
if [[ $shared == true ]]; then sha=$(git -C "$checkout" rev-parse --verify "$short^{commit}"); else sha=$incoming; fi
count=$(git -C "$checkout" rev-list --count "$base..$sha")
loom_lock
file=$(loom_record "$1")
# shellcheck disable=SC2016
loom_write "$file" '.collected_sha = $s' --arg s "$sha"
loom_unlock
printf '%s: branch %s collected, %s commit(s) over base, latest report: %s\n' "$1" "$short" "$count" "$state"
git -C "$checkout" log --oneline "$base..$sha"
