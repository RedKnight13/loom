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
! loom_alive "$file" || loom_error 'worker is still running; collect after it reports'
workdir=$(jq -r '.workdir' "$file")
checkout=$(jq -r '.checkout' "$file")
short=$(jq -r '.branch // .short_name' "$file")  # the branch (Orca names its own)
base=$(jq -r '.base_sha' "$file")
state=$(jq -r '.reports[-1].state // "none"' "$file")
[[ $(git -C "$checkout" branch --show-current) != "$short" ]] || loom_error "branch $short is checked out in the consumer checkout"
git -C "$workdir" show-ref --verify --quiet "refs/heads/$short" || loom_error "worker clone has no branch $short"
[[ -z $(git -C "$workdir" status --porcelain) ]] || printf 'loom: warning: worker clone has uncommitted changes (not collected)\n' >&2
# An Orca worktree shares the checkout's repository: its branch is already
# home (and checked out there, so it cannot be fetched into).
if [[ $(cd "$workdir" && cd "$(git rev-parse --git-common-dir)" && pwd -P) != "$(cd "$checkout" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]]; then
    git -C "$checkout" fetch -q "$workdir" "+refs/heads/$short:refs/heads/$short"
fi
count=$(git -C "$checkout" rev-list --count "$base..$short")
sha=$(git -C "$checkout" rev-parse --verify "$short^{commit}")
loom_lock
file=$(loom_record "$1")
# shellcheck disable=SC2016
loom_write "$file" '.collected_sha = $s' --arg s "$sha"
loom_unlock
printf '%s: branch %s collected, %s commit(s) over base, latest report: %s\n' "$1" "$short" "$count" "$state"
git -C "$checkout" log --oneline "$base..$short"
