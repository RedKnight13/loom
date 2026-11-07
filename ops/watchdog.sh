#!/usr/bin/env bash
# watchdog.sh [--limit-min N] [--id ASSIGNMENT]
#
# Limit: --limit-min N if given; else the assignment's own limit_min (from its
# consumer config at dispatch); else 30 minutes.
#
# For every assignment with a recorded worker:
#   - alive and silent past the limit → kill its process group, record
#     failed/watchdog_kill, keep the workdir for autopsy;
#   - gone (its launcher died with it, e.g. the conductor session ended) →
#     harvest REPORT.md, or record failed/worker_lost_no_report.
# A recycled PID never matches the recorded start time, so it is never killed.
# Prints one line per action; silent when healthy.
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
usage='usage: watchdog.sh [--limit-min N] [--id ASSIGNMENT]'
limit=
only=
while [[ $# -gt 0 ]]; do
    case $1 in
        --limit-min)
            [[ $# -ge 2 && $2 =~ ^[0-9]+$ && ${#2} -le 7 ]] || loom_error "$usage (N: nonnegative integer)"
            limit=$((10#$2)); shift 2 ;;
        --id)
            [[ $# -ge 2 ]] || loom_error "$usage"
            loom_id "$2"; only=$2; shift 2 ;;
        *) loom_error "$usage" ;;
    esac
done
loom_init
loom_lock
shopt -s nullglob
for file in "$LOOM_STATE"/*.json; do
    [[ -z $only || $file == "$LOOM_STATE/$only.json" ]] || continue
    [[ ! -L $file ]] || loom_error 'assignment is a symlink'
    loom_validate "$file"
    pid=$(jq -r '.worker_pid // empty' "$file")
    [[ -n $pid ]] || continue
    id=${file##*/}
    id=${id%.json}
    [[ $pid != "$$" && $pid != "$PPID" ]] || loom_error 'refusing to signal watchdog or its parent'
    if ! loom_alive "$file"; then
        state=$(loom_harvest "$file" worker_lost_no_report)
        printf '%s %s worker_gone\n' "$id" "$state"
        continue
    fi
    if jq -e --argjson override "${limit:-null}" '
      ($override // .limit_min // 30) as $limit |
      ([.started_at, .launched_at] + [.reports[].at] | map(select(. != null) | fromdateiso8601) | max)
        <= (now - $limit * 60)
    ' "$file" >/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || :
        loom_append "$file" failed watchdog_kill true
        printf '%s failed watchdog_kill\n' "$id"
    fi
done
