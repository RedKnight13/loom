#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=ops/report.sh
source "${BASH_SOURCE[0]%/*}/report.sh"
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
    [[ $pid != "$$" && $pid != "$PPID" ]] || loom_error 'refusing to signal watchdog or its parent'
    kill -0 "$pid" 2>/dev/null || continue
    if jq -e --argjson limit "$limit" '
      ([.started_at] + [.reports[].at] | map(fromdateiso8601) | max) <= (now - $limit * 60)
    ' "$file" >/dev/null; then
        kill -KILL "$pid" || loom_error 'failed to kill stale worker'
        loom_append "$file" failed watchdog_kill true
        id=${file##*/}
        printf '%s failed watchdog_kill\n' "${id%.json}"
    fi
done
