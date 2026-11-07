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
usage='usage: verify.sh <assignment-id> [--baseline] [--on HOST]'
[[ $# -ge 1 ]] || loom_error "$usage"
id=$1
shift
kind=branch
on=''
while [[ $# -gt 0 ]]; do
    case $1 in
        --baseline) kind=baseline; shift ;;
        --on) [[ $# -ge 2 && $2 =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || loom_error "$usage"; on=$2; shift 2 ;;
        *) loom_error "$usage" ;;
    esac
done
set -- "$id"
loom_id "$1"
loom_init
file=$(loom_record "$1")
# A baseline runs at base_sha in a fresh clone and never reads the worker's
# workspace, so it may run at any time; a branch check needs the worker settled.
[[ $kind == baseline ]] || ! loom_alive "$file" || loom_error 'worker is still running; verify after it reports'
checks=$(jq -r '.checks // empty' "$file")
[[ -n $checks ]] || loom_error 'consumer declares no checks; nothing to verify'
checkout=$(jq -r '.checkout' "$file")
workdir=$(jq -r '.workdir' "$file")
short=$(jq -r '.branch // .short_name' "$file")  # the branch (Orca names its own)
base=$(jq -r '.base_sha' "$file")

# Compute host (gap #36): a consumer that declares one gets its checks run
# there; if none is reachable, refuse. Never fall back to this machine.
host=''
hosts=$(jq -r '(.compute // [])[]' "$file")
# --on HOST: the conductor names the compute host for this run (e.g. an
# assignment dispatched before its consumer declared one); recorded per run.
[[ -z $on ]] || hosts=$on
if [[ -n $hosts ]]; then
    # shellcheck disable=SC2086  # host names are single words
    host=$(loom_compute_pick $hosts) || loom_error "no compute host reachable ($(tr '\n' ' ' <<< "$hosts")); refusing to run checks on the conductor's machine"
fi

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
if [[ -z $host ]]; then
    (cd "$scratch/tree" && umask "$LOOM_CALLER_UMASK" && exec bash -c "$checks") < /dev/null > "$log" 2>&1 || rc=$?
else
    # Ship exactly this commit as a bundle; build a fresh tree on the host; run
    # the checks under the caller's umask after the consumer's setup; clean up.
    git -C "$scratch/tree" bundle create "$scratch/code.bundle" HEAD >/dev/null 2>&1
    rid="loom-$1-$kind-$$-$RANDOM"
    setup=$(jq -r '.compute_setup // ""' "$file")
    # shellcheck disable=SC2016  # expands on the compute host, not here
    upload=$(printf 'set -e; d="$HOME/.loom-remote/%s"; mkdir -p "$d"; cat > "$d/code.bundle"' "$rid")
    # shellcheck disable=SC2016  # expands on the compute host, not here
    run=$(printf 'd="$HOME/.loom-remote/%s"; cleanup() { cd /; rm -rf "$d"; }; cd "$d" && git clone -q code.bundle tree 2>/dev/null && cd tree && git -c advice.detachedHead=false checkout -q %q || { cleanup; exit 126; }; umask %q; if ! eval %q; then echo "loom: compute_setup failed on %s"; cleanup; exit 126; fi; rc=0; bash -c %q < /dev/null || rc=$?; cleanup; exit $rc' \
        "$rid" "$sha" "$LOOM_CALLER_UMASK" "${setup:-true}" "$host" "$checks")
    if loom_ssh "$host" "bash -c $(printf %q "$upload")" < "$scratch/code.bundle" > "$log" 2>&1; then
        { printf '== on compute host %s\n' "$host"; loom_ssh "$host" "bash -c $(printf %q "$run")" < /dev/null; } > "$log" 2>&1 || rc=$?
    else
        rc=255
    fi
fi
case $rc in
    0) verdict="checks exit 0" ;;
    126|127|255) verdict="checks could not run${host:+ on $host} (exit $rc): see ${log##*/}" ;;
    *) verdict="checks exit $rc" ;;
esac
rm -rf "$scratch"
trap - EXIT

loom_lock
file=$(loom_record "$1")
# shellcheck disable=SC2016  # jq variables
loom_write "$file" '.checks_runs = ((.checks_runs // []) + [{kind: $kind, sha: $sha, exit: $rc, at: $at, host: (if $host == "" then null else $host end)}])' \
    --arg kind "$kind" --arg sha "$sha" --argjson rc "$rc" --arg at "$started" --arg host "$host"
if [[ $kind == branch ]]; then
    baseline=$(jq -r '[.checks_runs[] | select(.kind == "baseline")][-1].exit // "not run"' "$file")
    if [[ $rc == 0 ]]; then
        loom_append "$file" ready "conductor verified: $verdict at ${sha:0:7} (baseline: $baseline)"
    else
        loom_append "$file" failed "conductor check: $verdict at ${sha:0:7} (baseline: $baseline)"
    fi
fi
loom_unlock
printf '%s %s: %s at %s%s\n' "$1" "$kind" "$verdict" "${sha:0:7}" "${host:+ on $host}"
[[ $rc == 0 ]] || tail -n 15 "$log" >&2
exit "$rc"
