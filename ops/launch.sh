#!/usr/bin/env bash
# launch.sh <assignment-id> -- <worker command...>
#
# Runs a worker command in the assignment's workdir under a process-group guard,
# records the guard identity, waits for the group, then harvests REPORT.md.
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
loom_legacy_dispatch_fence
loom_lock
file=$(loom_record "$id")
# Dispatch pins the executor. Native assignments never consult unrelated Orca
# installations; LOOM_ALLOW_LOCAL is retained as an ignored legacy variable.
[[ $(loom_executor "$file") == local ]] || loom_error "$id is an Orca assignment: start it with ops/orca.sh start $id"
! loom_alive "$file" || loom_error 'assignment already has a live worker'
loom_no_open_sibling "$file"
workdir=$(jq -r '.workdir' "$file")
[[ -d $workdir && ! -L $workdir ]] || loom_error "workdir missing: $workdir"
offset=0
if [[ -f $workdir/REPORT.md ]]; then
    offset=$(wc -l < "$workdir/REPORT.md")
    offset=$((offset + 0))
fi
log="$LOOM_STATE/$id.log"
# Require the same process visibility used by the guard before starting work.
loom_legacy_identity "$$" >/dev/null || loom_error 'legacy launch requires readable Linux /proc or macOS ps identity'
dir=$(mktemp -d "$LOOM_STATE/$id.launch.XXXXXX")
set -m
(loom_legacy_run "$dir" "$workdir" "$@") < /dev/null >> "$log" 2>&1 &
child=$!
set +m
start=$(loom_pstart "$child") || loom_error 'legacy guard lost before launch'
identity=$(loom_legacy_identity "$child") || loom_error 'legacy guard identity unavailable'
if ! loom_legacy_proc "$child" || [[ ${_loom_proc[2]} != "$child" ]]; then
    loom_error 'legacy guard has no private process group'
fi
# shellcheck disable=SC2016  # $pid/$start/$offset are jq variables
loom_write "$file" '
  .worker_pid = $pid | .worker_start = $start |
  .legacy_guard = {pgid:$pid, identity:$identity, directory:$directory} |
  .launched_at = (now | todateiso8601) | .report_offset = $offset
' --argjson pid "$child" --arg start "$start" --argjson offset "$offset" \
    --arg identity "$identity" --arg directory "${dir##*/}"
printf '%s %s\n' "$child" "$identity" > "$dir/start.tmp"
mv "$dir/start.tmp" "$dir/start"
loom_unlock
printf '%s launched pid %s\n' "$id" "$child"

rc=0
wait "$child" || rc=$?

loom_lock
file=$(loom_record "$id")
# The watchdog may already have ended this worker and recorded why.
if [[ $(jq -r '.worker_pid // empty' "$file") == "$child" &&
      $(jq -r '.legacy_guard.identity // empty' "$file") == "$identity" ]]; then
    if jq -e '.legacy_guard.stop_requested == true' "$file" >/dev/null; then
        result=$(loom_legacy_finish_stop "$file")
        printf '%s %s (worker exit %s)\n' "$id" "$result" "$rc"
    else
        state=$(loom_harvest "$file" "worker_exit_no_report (exit $rc)")
        printf '%s %s (worker exit %s)\n' "$id" "$state" "$rc"
    fi
elif [[ $(jq -r '.worker_pid // empty' "$file") == '' ]]; then
    printf '%s already settled by watchdog (worker exit %s)\n' "$id" "$rc"
else
    loom_error 'assignment identity changed before harvest'
fi
loom_unlock
