#!/usr/bin/env bash
# Synthetic keeper CPU and detection latency, not real-agent acceptance.
# Usage: bash tests/native/supervisor-bench.sh [source-tree] [idle-seconds] [sleepers]
# Run versions serially on the same host with identical arguments. CPU excludes
# provisioning and settlement; timings include polling and durable receipt I/O.
# shellcheck disable=SC1091,SC2016,SC2015
set -euo pipefail
tree=${1:-$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)}
duration=${2:-6}
sleepers=${3:-200}
LOOM_NATIVE_FIXTURE_LIBRARY=1 source "$tree/tests/native/run.sh"
load_pids=()
bench_cleanup() {
    local pid work
    # Release only our own fixture gates even when an assertion fails.
    for work in "$scratch"/*/workspaces/worker; do
        [[ ! -d $work ]] || touch "$work/finish" "$work/leader_exit"
    done
    for pid in "${load_pids[@]}"; do kill "$pid" 2>/dev/null || :; done
    for pid in "${load_pids[@]}"; do wait "$pid" 2>/dev/null || :; done
    cleanup
}
trap bench_cleanup EXIT
for ((i=0; i<sleepers; i++)); do sleep 180 & load_pids+=("$!"); done
now() {
    local uptime _
    read -r uptime _ < /proc/uptime
    millis=$((10#${uptime%.*} * 1000 + 10#${uptime#*.} * 10))
}
await_file() {
    local file=$1 deadline
    now; deadline=$((millis+15000))
    while [[ ! -f $file ]]; do
        now; (( millis<deadline )) || fail "benchmark event timed out: ${file##*/}"
        sleep 0.01
    done
    now
}
fixture cpu 'touch started; while [[ ! -f finish && $SECONDS -lt 120 ]]; do sleep 0.02; done; exit 7'
call "$dir/start"
await_file "$dir/workspaces/worker/started"
keeper=$(jq -r .supervisor_pid "$spool/identity")
keeper_ticks=$(jq -r .supervisor_start_ticks "$spool/identity")
paths=(/proc/[0-9]*/stat); processes=${#paths[@]}
_loom_native_proc "$keeper" || fail 'keeper absent before CPU sample'
ticks_before=$((_np[11]+_np[12]))
child_ticks_before=$((_np[13]+_np[14]))
now; sample_start=$millis
sleep "$duration"
_loom_native_proc "$keeper" && [[ ${_np[19]} == "$keeper_ticks" ]] || fail 'keeper identity changed during sample'
ticks_after=$((_np[11]+_np[12]))
child_ticks_after=$((_np[13]+_np[14]))
now; sample_ms=$((millis-sample_start))
printf 'cpu visible_processes=%s sleepers=%s sample_ms=%s clock_ticks_per_second=%s keeper_ticks=%s reaped_child_ticks=%s\n' \
    "$processes" "$sleepers" "$sample_ms" "$(getconf CLK_TCK)" "$((ticks_after-ticks_before))" "$((child_ticks_after-child_ticks_before))"
now; trigger=$millis
touch "$dir/workspaces/worker/finish"
await_file "$spool/child-exit"; leader_ms=$((millis-trigger))
await_file "$spool/completion"; completion_ms=$((millis-trigger))
jq -e '.terminal.exit_code==7 and .group_empty' "$spool/completion" >/dev/null || fail 'benchmark leader receipt'
printf 'leader child_exit_ms=%s completion_ms=%s\n' "$leader_ms" "$completion_ms"

fixture descendant '(touch descendant; while [[ ! -f finish && $SECONDS -lt 120 ]]; do sleep 0.02; done) >/dev/null 2>&1 & while [[ ! -f leader_exit && $SECONDS -lt 120 ]]; do sleep 0.02; done; exit 5'
call "$dir/start"
await_file "$dir/workspaces/worker/descendant"
# Give both versions a complete observation before measuring survivor latency.
sleep 1
touch "$dir/workspaces/worker/leader_exit"
await_file "$spool/child-exit"
sleep 0.7
[[ ! -f $spool/completion ]] || fail 'surviving descendant was settled'
now; trigger=$millis
touch "$dir/workspaces/worker/finish"
await_file "$spool/completion"
jq -e '.terminal.exit_code==5 and .group_empty' "$spool/completion" >/dev/null || fail 'benchmark descendant receipt'
printf 'descendant completion_ms=%s\n' "$((millis-trigger))"

fixture cancel 'trap "exit 0" TERM; touch started; while [[ $SECONDS -lt 120 ]]; do sleep 1; done'
call "$dir/start"
await_file "$dir/workspaces/worker/started"
stop_request false
now; trigger=$millis
call "$dir/stop" & stopper=$!
await_file "$spool/stop"; stop_at=$millis
await_file "$spool/signals"; signals_ms=$((millis-stop_at))
await_file "$spool/completion"; completion_ms=$((millis-stop_at))
wait "$stopper"
now
jq -e '.result.confirmed_stopped and .result.requested_signals==["TERM"]' "$dir/result" >/dev/null || fail 'benchmark cancellation receipt'
printf 'cancel intent_to_signals_ms=%s intent_to_completion_ms=%s call_ms=%s\n' "$signals_ms" "$completion_ms" "$((millis-trigger))"
printf 'PASS synthetic supervisor benchmark\n'
