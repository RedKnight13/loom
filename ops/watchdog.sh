#!/usr/bin/env bash
# watchdog.sh [--limit-min N]   (default 30)
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
limit=30
if [[ $# != 0 ]]; then
    [[ $# == 2 && $1 == --limit-min && $2 =~ ^[0-9]+$ && ${#2} -le 7 ]] || loom_error 'usage: watchdog.sh [--limit-min N] (nonnegative integer)'
    limit=$((10#$2))
fi
loom_init
loom_lock
shopt -s nullglob
for file in "$LOOM_STATE"/*.json; do
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
    if jq -e --argjson limit "$limit" '
      ([.started_at, .launched_at] + [.reports[].at] | map(select(. != null) | fromdateiso8601) | max)
        <= (now - $limit * 60)
    ' "$file" >/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || :
        loom_append "$file" failed watchdog_kill true
        printf '%s failed watchdog_kill\n' "$id"
    fi
done
