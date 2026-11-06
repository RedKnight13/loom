#!/usr/bin/env bash
# launch.sh <assignment-id> -- <worker command...>
#
# Runs any worker command inside the assignment's workdir, records its PID and
# start time, waits for it, then harvests its REPORT.md into the record.
# Executor-agnostic: codex today, anything scriptable tomorrow.
#
# The worker gets no stdin (a worker blocked on stdin looks alive forever) and
# its own process group, so the watchdog can stop it and everything it spawned.
# Output goes to $LOOM_STATE/<id>.log, outside the workdir.
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
[[ $# -ge 3 && $2 == -- ]] || loom_error 'usage: launch.sh <assignment-id> -- <worker command...>'
id=$1
shift 2
loom_id "$id"
loom_init
loom_lock
file=$(loom_record "$id")
! loom_alive "$file" || loom_error 'assignment already has a live worker'
workdir=$(jq -r '.workdir' "$file")
[[ -d $workdir && ! -L $workdir ]] || loom_error "workdir missing: $workdir"
offset=0
if [[ -f $workdir/REPORT.md ]]; then
    offset=$(wc -l < "$workdir/REPORT.md")
    offset=$((offset + 0))
fi
log="$LOOM_STATE/$id.log"
set -m
(cd "$workdir" && exec "$@") < /dev/null >> "$log" 2>&1 &
child=$!
set +m
start=$(loom_pstart "$child") || start=gone
# shellcheck disable=SC2016  # $pid/$start/$offset are jq variables
loom_write "$file" '
  .worker_pid = $pid | .worker_start = $start |
  .launched_at = (now | todateiso8601) | .report_offset = $offset
' --argjson pid "$child" --arg start "$start" --argjson offset "$offset"
loom_unlock
printf '%s launched pid %s\n' "$id" "$child"

rc=0
wait "$child" || rc=$?

loom_lock
file=$(loom_record "$id")
# The watchdog may already have ended this worker and recorded why.
if [[ $(jq -r '.worker_pid // empty' "$file") == "$child" ]]; then
    state=$(loom_harvest "$file" "worker_exit_no_report (exit $rc)")
    printf '%s %s (worker exit %s)\n' "$id" "$state" "$rc"
else
    printf '%s already settled by watchdog (worker exit %s)\n' "$id" "$rc"
fi
loom_unlock
