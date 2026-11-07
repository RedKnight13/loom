#!/usr/bin/env bash
# verify.sh <assignment-id> [--baseline]
#
# The conductor's re-check, mechanized (the verification law). Runs the
# consumer's checks in a FRESH clone the worker never had access to:
#   --baseline  at the base the worker started from (run before or after
#               launch), so Done-means can be judged as "no new failures";
#   default     at the tip of the ticket branch in the worker's clone.
# Records the run in the assignment; a branch run also records a conductor
# report (ready = verified, failed = checks failed or could not run).
# Exit code: the checks' own exit code (126/127 = could not run).
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
usage='usage: verify.sh <assignment-id> [--baseline]'
[[ $# == 1 || ( $# == 2 && $2 == --baseline ) ]] || loom_error "$usage"
loom_id "$1"
kind=branch
[[ $# == 1 ]] || kind=baseline
loom_init
file=$(loom_record "$1")
! loom_alive "$file" || loom_error 'worker is still running; verify after it reports'
checks=$(jq -r '.checks // empty' "$file")
[[ -n $checks ]] || loom_error 'consumer declares no checks; nothing to verify'
checkout=$(jq -r '.checkout' "$file")
workdir=$(jq -r '.workdir' "$file")
short=$(jq -r '.short_name' "$file")
base=$(jq -r '.base_sha' "$file")

scratch=$(mktemp -d "${TMPDIR:-/tmp}/loom-verify.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git clone -q --no-checkout "$checkout" "$scratch/tree"
if [[ $kind == baseline ]]; then
    sha=$base
else
    git -C "$workdir" show-ref --verify --quiet "refs/heads/$short" || loom_error "worker clone has no branch $short"
    git -C "$scratch/tree" fetch -q "$workdir" "refs/heads/$short"
    sha=$(git -C "$scratch/tree" rev-parse FETCH_HEAD)
fi
git -C "$scratch/tree" -c advice.detachedHead=false checkout -q "$sha"

log="$LOOM_STATE/$1.checks-$kind.log"
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rc=0
(cd "$scratch/tree" && umask "$LOOM_CALLER_UMASK" && exec bash -c "$checks") < /dev/null > "$log" 2>&1 || rc=$?
case $rc in
    0) verdict="checks exit 0" ;;
    126|127) verdict="checks could not run (exit $rc): see ${log##*/}" ;;
    *) verdict="checks exit $rc" ;;
esac
rm -rf "$scratch"
trap - EXIT

loom_lock
file=$(loom_record "$1")
# shellcheck disable=SC2016  # jq variables
loom_write "$file" '.checks_runs = ((.checks_runs // []) + [{kind: $kind, sha: $sha, exit: $rc, at: $at}])' \
    --arg kind "$kind" --arg sha "$sha" --argjson rc "$rc" --arg at "$started"
if [[ $kind == branch ]]; then
    baseline=$(jq -r '[.checks_runs[] | select(.kind == "baseline")][-1].exit // "not run"' "$file")
    if [[ $rc == 0 ]]; then
        loom_append "$file" ready "conductor verified: $verdict at ${sha:0:7} (baseline: $baseline)"
    else
        loom_append "$file" failed "conductor check: $verdict at ${sha:0:7} (baseline: $baseline)"
    fi
fi
loom_unlock
printf '%s %s: %s at %s\n' "$1" "$kind" "$verdict" "${sha:0:7}"
[[ $rc == 0 ]] || tail -n 15 "$log" >&2
exit "$rc"
