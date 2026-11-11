#!/usr/bin/env bash
# Focused keeper observations with synthetic processes; no agent acceptance.
# shellcheck disable=SC1091,SC2016,SC2015,SC2030,SC2031
set -euo pipefail
native_tests=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
# shellcheck source=tests/native/run.sh
LOOM_NATIVE_FIXTURE_LIBRARY=1 source "$native_tests/run.sh"
source "$ops/native-supervisor.sh"

# Exercise unreadable live identities and exact start-token escape tracking
# against a real /proc entry, without changing host /proc permissions.
sleep 30 & probe=$!
_loom_native_proc "$probe" || fail 'probe identity unavailable'
probe_ticks=${_np[19]}
(
    mkdir -p "$scratch/scan"
    _nn_dir=$scratch/scan
    _nk_group=0
    declare -A _nk_known=()
    _nk_known[$probe]=0
    _loom_native_scan || fail 'scan with stale known token'
    [[ ! -f $_nn_dir/escaped ]] || fail 'reused PID was treated as known escape'
    _nk_known[$probe]=$probe_ticks
    _loom_native_scan || fail 'scan of known escape'
    [[ -f $_nn_dir/escaped ]] || fail 'known escape not recorded'
    # Rename only this test's sourced function; production is unchanged.
    eval "$(declare -f _loom_native_proc | sed '1s/_loom_native_proc/_fixture_proc/')"
    # shellcheck disable=SC2317 # called indirectly by the sourced scanner
    _loom_native_proc() {
        [[ $1 != "$probe" ]] || return 1
        _fixture_proc "$1"
    }
    if _loom_native_scan; then fail 'unreadable live process was treated as absent'; fi
)
kill "$probe"; wait "$probe" || :
pass 'scan rejects unreadable identities and distinguishes reused PID from known escape'

await_file() {
    local file=$1
    for _ in {1..500}; do [[ ! -f $file ]] || return 0; sleep 0.02; done
    fail "missing supervisor event: ${file##*/}"
}

# Instrument a private installed runtime, not the production test-hook surface.
# The scan race returns a stale empty snapshot after letting the worker fork a
# surviving descendant and exit. Settlement must rescan after capturing wait.
runtime=$scratch/runtime
mkdir -p "$runtime"
cp "$ops/"*.sh "$runtime/"
mv "$runtime/native-supervisor.sh" "$runtime/keeper-code.sh"
cat > "$runtime/native-supervisor.sh" <<'WRAPPER'
#!/usr/bin/env bash
source "${BASH_SOURCE[0]%/*}/keeper-code.sh"
eval "$(declare -f _loom_native_scan | sed '1s/_loom_native_scan/_fixture_scan/')"
_loom_native_scan() {
    printf 'scan\n' >> "$_nn_dir/scan-events"
    if [[ -f $_nn_dir/race && ! -f $_nn_dir/race-returned ]]; then
        touch "$_nn_dir/race-release"
        while _loom_native_proc "$child" && [[ ${_np[19]} == "$child_ticks" && ${_np[0]} != Z ]]; do sleep 0.01; done
        touch "$_nn_dir/race-returned"
        _nk_live=0
        return 0
    fi
    _fixture_scan
}
_loom_native_supervisor_main "$@"
WRAPPER
ops=$runtime
source "$ops/native.sh"

fixture cadence 'touch started; while [[ ! -f finish && $SECONDS -lt 30 ]]; do sleep 0.02; done; exit 7'
call "$dir/start"
await_file "$dir/workspaces/worker/started"
before=$(wc -l < "$spool/scan-events")
sleep 1.2
after=$(wc -l < "$spool/scan-events")
(( after-before>=1 && after-before<=4 )) || fail "idle scan cadence: $((after-before)) scans in 1.2 seconds"
touch "$dir/workspaces/worker/finish"
settled
jq -e '.result.terminal.exit_code==7' "$dir/result" >/dev/null || fail 'cadence leader exit'
pass 'idle full scans bounded while leader exit still settles'

fixture scan_race 'spool=${LOOM_BINDING_FILE%/binding}; touch "$spool/race"; while [[ ! -f $spool/race-release && $SECONDS -lt 30 ]]; do sleep 0.02; done; (touch descendant; while [[ ! -f finish && $SECONDS -lt 30 ]]; do sleep 0.02; done) >/dev/null 2>&1 & exit 5'
call "$dir/start"
await_file "$spool/race-returned"
await_file "$spool/child-exit"
sleep 0.7
[[ ! -f $spool/completion ]] || fail 'stale empty scan settled a surviving descendant'
touch "$dir/workspaces/worker/finish"
settled
jq -e '.result.terminal.exit_code==5' "$dir/result" >/dev/null || fail 'scan race lost wait status'
pass 'leader exit forces fresh group observation after a stale empty scan'

# An observed descendant changes session after at least one full scan, closes
# output, and outlives its leader. It must remain unknown even after it exits.
fixture escape '(touch descendant; while [[ ! -f escape && $SECONDS -lt 30 ]]; do sleep 0.02; done; exec setsid bash -c '\''touch escaped; while [[ ! -f finish && $SECONDS -lt 30 ]]; do sleep 0.02; done; touch descendant_done'\'') >/dev/null 2>&1 & while [[ ! -f leader_exit && $SECONDS -lt 30 ]]; do sleep 0.02; done; exit 3'
call "$dir/start"
await_file "$dir/workspaces/worker/descendant"
sleep 1
touch "$dir/workspaces/worker/escape"
await_file "$dir/workspaces/worker/escaped"
await_file "$spool/escaped"
touch "$dir/workspaces/worker/leader_exit"
await_file "$spool/child-exit"
touch "$dir/workspaces/worker/finish"
await_file "$dir/workspaces/worker/descendant_done"
inspect_request; call "$dir/inspect"
jq -e '.result.state=="unknown" and .result.terminal==null' "$dir/result" >/dev/null || fail 'observed escape promoted to exit'
[[ ! -f $spool/completion ]] || fail 'observed escape published completion'
pass 'known descendant session escape remains unknown after leader and descendant exit'
printf 'PASS focused supervisor fixtures\n'
