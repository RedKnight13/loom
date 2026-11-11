#!/usr/bin/env bash
# watchdog.sh [--limit-min N] [--id ASSIGNMENT]
#
# Limit: --limit-min N if given; else the assignment's own limit_min (from its
# consumer config at dispatch); else 30 minutes.
#
# For every assignment with a recorded worker:
#   - alive and silent past the limit → kill its process group, record
#     failed/watchdog_kill only after group settlement; retain uncertainty;
#   - positively settled group → harvest REPORT.md;
#   - lost/uncertain supervision → leave evidence pending, never signal.
# Signals require a matching identity; macOS retains ps start-time precision.
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
    if jq -e '.legacy_guard != null' "$file" >/dev/null; then
        settlement=$(loom_legacy_status "$file")
    else
        # Old records have no group-completion receipt. Preserve timeout kills
        # only for their exact live leader; its disappearance proves nothing.
        start=$(jq -r '.worker_start' "$file")
        now=$(loom_pstart "$pid") || now=
        if [[ -n $now && $now == "$start" ]]; then settlement=running; else settlement=unknown; fi
    fi
    if jq -e '.legacy_guard.stop_requested == true' "$file" >/dev/null; then
        result=$(loom_legacy_finish_stop "$file")
        printf '%s %s\n' "$id" "$result"
        continue
    fi
    case $settlement in
        settled)
            state=$(loom_harvest "$file" worker_lost_no_report)
            printf '%s %s worker_gone\n' "$id" "$state"
            continue ;;
        unknown)
            printf '%s pending settlement_unproven\n' "$id"
            continue ;;
    esac
    if jq -e --argjson override "${limit:-null}" '
      ($override // .limit_min // 30) as $limit |
      ([.started_at, .launched_at] + [.reports[].at] | map(select(. != null) | fromdateiso8601) | max)
        <= (now - $limit * 60)
    ' "$file" >/dev/null; then
        if jq -e '.legacy_guard != null' "$file" >/dev/null; then
            [[ $(loom_legacy_status "$file") == running ]] || continue
        else
            [[ $(loom_pstart "$pid") == "$start" ]] || continue
        fi
        if jq -e '.legacy_guard != null' "$file" >/dev/null; then
            # Persist the verified stop intent before signalling, so launcher
            # recovery cannot harvest an early ready report after a kill.
            loom_write "$file" '.legacy_guard.stop_requested = true'
        fi
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || :
        # Unguarded historical records cannot prove group completion and stay
        # pending. Neither successful kill nor failed PID fallback clears them.
        result=$(loom_legacy_finish_stop "$file")
        printf '%s %s\n' "$id" "$result"
    fi
done
