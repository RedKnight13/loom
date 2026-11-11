#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031 # sourced helpers run in isolated subshells
# Offline regression: a ready report does not end a process group's writes.
set -euo pipefail
umask 022
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/loom-settlement.XXXXXX")
export LOOM_STATE="$scratch/state" LOOM_LOCK_WAIT=2
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
pids=()
cleanup() {
    local pid
    for pid in ${pids[@]+"${pids[@]}"}; do kill -KILL "$pid" 2>/dev/null || :; done
    rm -rf "$scratch"
}
trap cleanup EXIT
fail() { printf 'FAIL legacy settlement: %s\n' "$*" >&2; exit 1; }
await_file() {
    local _
    for _ in {1..100}; do [[ -s $1 ]] && return; sleep .05; done
    fail "fixture never reached ${1##*/}"
}
wait_done() {
    local pid=$1 _
    for _ in {1..200}; do
        if ! kill -0 "$pid" 2>/dev/null; then wait "$pid"; return; fi
        sleep .05
    done
    fail 'launcher failed to finish after group completion'
}
fixture() {
    id=$1
    fixture_ticket=$((${fixture_ticket:-0} + 1))
    work="$scratch/$id"
    mkdir -p "$work" "$LOOM_STATE"
    git -C "$work" init -q -b fixture
    git -C "$work" config user.name Fixture
    git -C "$work" config user.email fixture@example.invalid
    git -C "$work" -c commit.gpgsign=false commit -q --allow-empty -m fixture
    base=$(git -C "$work" rev-parse HEAD)
    file="$LOOM_STATE/$id.json"
    jq -n --arg w "$work" --arg sha "$base" --argjson ticket "$fixture_ticket" '{ticket:$ticket,repo:"fixture/offline",short_name:"fixture",attempt:1,
      workdir:$w,checkout:$w,base_sha:$sha,worker_pid:null,worker_start:null,
      started_at:(now|todateiso8601),reports:[],report_offset:0,executor:{kind:"local"}}' > "$file"
}
fixture delayed
cat > "$scratch/delayed-worker" <<'WORKER'
mkdir .loom
(
    while [[ ! -f release ]]; do sleep .05; done
    printf 'late log\n'
    printf 'late artifact\n' > result.txt
    printf 'late evidence\n' > .loom/result.txt
    printf 'state: ready — descendant finished\n' >> REPORT.md
) &
printf '%s\n' "$!" > descendant
printf 'state: ready — leader finished\n' > REPORT.md
umask > worker.umask
WORKER
bash "$root/ops/launch.sh" "$id" -- bash "$scratch/delayed-worker" > "$scratch/launch.log" 2>&1 &
launcher=$!; pids+=("$launcher")
await_file "$work/descendant"
pids+=("$(cat "$work/descendant")" "$(jq -r .worker_pid "$file")")
# The worker is deliberately held open, so this is a state assertion, not a
# race against a short sleep in the descendant.
sleep .5
[[ $(jq '.reports | length' "$file") == 0 ]] || fail 'leader ready was harvested while a descendant could still write'
[[ $(git -C "$work" rev-parse HEAD) == "$base" && ! -e $LOOM_STATE/$id.evidence ]] || fail 'evidence sealed early'
touch "$work/release"
wait_done "$launcher"
jq -e '.worker_pid == null and .reports[-1].fact == "descendant finished"' "$file" >/dev/null || fail 'final report missing'
[[ $(git -C "$work" show HEAD:result.txt) == 'late artifact' ]] || fail 'delayed artifact not committed'
[[ $(cat "$LOOM_STATE/$id.evidence/result.txt") == 'late evidence' ]] || fail 'delayed evidence not copied'
grep -qx 'late log' "$LOOM_STATE/$id.log" || fail 'delayed log missing'
[[ $(cat "$work/worker.umask") == 0022 ]] || fail 'worker lost caller umask'
printf 'PASS legacy delayed descendant settlement\n'

# Source only test helpers; the production scripts run in separate processes.
# shellcheck source=ops/lib.sh
source "$root/ops/lib.sh"
# Direct guard entry must initialize its own platform cache. The public launcher
# currently preflights identity too; exercise the helper independently so its
# Darwin observer never depends on inherited caller state.
(
    _loom_legacy_platform=
    uname() { printf 'Darwin\n'; }
    loom_legacy_identity() { printf 'fixture'; }
    loom_legacy_group() {
        local observer_pid observer_group
        observer_pid=$(exec bash -c 'printf "%s" "$PPID"')
        observer_group=$(ps -o pgid= -p "$observer_pid")
        [[ $observer_group != *"$1" ]] || return 2
        return 1
    }
    mkdir "$scratch/direct-guard"
    set -m
    (loom_legacy_run "$scratch/direct-guard" "$scratch" true) &
    direct_guard=$!
    set +m
    printf '%s fixture\n' "$direct_guard" > "$scratch/direct-guard/start"
    wait "$direct_guard" || fail 'direct Darwin guard did not isolate its observer'
    [[ -f $scratch/direct-guard/settled ]] || fail 'direct Darwin guard did not settle'
)
printf 'PASS legacy direct Darwin guard initialization and observer isolation\n'

start_held() {
    fixture "$1"
    bash "${launch_ops:-$root/ops}/launch.sh" "$id" -- bash "$scratch/delayed-worker" > "$scratch/$id.log" 2>&1 &
    launcher=$!; pids+=("$launcher")
    await_file "$work/descendant"
    guard=$(jq -r '.worker_pid' "$file")
    descendant=$(cat "$work/descendant")
    pids+=("$guard" "$descendant")
}
assert_pending() {
    local rc=0
    cp "$file" "$scratch/before.json"
    (loom_harvest "$file" silent) > "$scratch/refusal.log" 2>&1 || rc=$?
    [[ $rc != 0 ]] || fail 'unproven harvest accepted'
    cmp -s "$file" "$scratch/before.json" || fail 'refused harvest changed the record'
    [[ $(git -C "$work" rev-parse HEAD) == "$base" && ! -e $LOOM_STATE/$id.evidence ]] || fail 'refused harvest sealed evidence'
    [[ -z $(git -C "$work" diff --cached --name-only) ]] || fail 'refused harvest staged files'
    if bash "$root/ops/launch.sh" "$id" -- true >/dev/null 2>&1; then fail 'pending worker allowed relaunch'; fi
    if bash "$root/ops/collect.sh" "$id" >/dev/null 2>&1; then fail 'pending worker allowed collect'; fi
    if bash "$root/ops/verify.sh" "$id" >/dev/null 2>&1; then fail 'pending worker allowed verify'; fi
}
wait_launcher() {
    local _
    for _ in {1..100}; do
        if ! kill -0 "$launcher" 2>/dev/null; then wait "$launcher"; return; fi
        sleep .05
    done
    fail 'launcher failed to finish'
}

# A launcher cancellation does not end the guarded group. Recovery is allowed
# only after the guard publishes its identity-bound, group-empty receipt.
start_held launcher-loss
kill -TERM "$launcher"
wait "$launcher" 2>/dev/null || :
assert_pending
[[ -z $(bash "$root/ops/watchdog.sh" --id "$id") ]] || fail 'fresh guard treated as lost'
touch "$work/release"
for _ in {1..100}; do [[ $(loom_legacy_status "$file") == settled ]] && break; sleep .05; done
[[ $(bash "$root/ops/watchdog.sh" --id "$id") == "$id ready worker_gone" ]] || fail 'completed guard did not recover launcher loss'
[[ $(git -C "$work" show HEAD:result.txt) == 'late artifact' ]] || fail 'recovery omitted descendant write'
[[ $(cat "$LOOM_STATE/$id.evidence/result.txt") == 'late evidence' ]] || fail 'recovery omitted evidence'
[[ -z $(bash "$root/ops/watchdog.sh" --id "$id") ]] || fail 'recovery harvested twice'

# Killing only the guard leaves a live descendant. Even after that descendant
# exits, no completion proof can be invented from its ready line or empty PGID.
start_held guard-loss
kill -KILL "$guard"
rc=0; wait_launcher || rc=$?
[[ $rc != 0 ]] || fail 'lost guard reported successful launch'
assert_pending
[[ $(bash "$root/ops/watchdog.sh" --limit-min 0 --id "$id") == "$id pending settlement_unproven" ]] || fail 'lost guard not surfaced as pending'
kill -0 "$descendant" || fail 'watchdog signalled descendants after losing identity'
touch "$work/release"
await_file "$work/result.txt"
assert_pending
[[ $(bash "$root/ops/watchdog.sh" --limit-min 0 --id "$id") == "$id pending settlement_unproven" ]] || fail 'empty group substituted for missing receipt'

# The normal watchdog deadline still kills a stable guard and its descendants,
# reports failure once, and never converts the early ready line into evidence.
start_held watchdog
[[ $(bash "$root/ops/watchdog.sh" --limit-min 0 --id "$id") == "$id failed watchdog_kill" ]] || fail 'watchdog did not kill guarded group'
wait_launcher
jq -e '.worker_pid == null and (.reports | length) == 1 and .reports[0].fact == "watchdog_kill"' "$file" >/dev/null || fail 'watchdog result changed'
[[ $(cat "$scratch/$id.log") == *'already settled by watchdog'* ]] || fail 'launcher did not recognize watchdog result'
if loom_legacy_proc "$descendant"; then [[ ${_loom_proc[0]} == Z || ${_loom_proc[0]} == X ]] || fail 'descendant survived watchdog'; fi
[[ ! -e $LOOM_STATE/$id.evidence ]] || fail 'watchdog sealed incomplete evidence'

# A forged old start token models PID reuse without relying on PID wraparound.
# Neither the watchdog nor harvest may touch the live process at that PID.
start_held identity-reuse
cp "$file" "$scratch/real-identity.json"
jq '.legacy_guard.identity = "00000000-0000-0000-0000-000000000000:0"' "$file" > "$scratch/reused"
mv "$scratch/reused" "$file"
assert_pending
[[ $(bash "$root/ops/watchdog.sh" --limit-min 0 --id "$id") == "$id pending settlement_unproven" ]] || fail 'reused identity did not stay pending'
kill -0 "$guard" || fail 'identity mismatch signalled the guard'
kill -0 "$descendant" || fail 'identity mismatch signalled the descendant'
jq '.legacy_guard.stop_requested = true' "$file" > "$scratch/reused-stop"
mv "$scratch/reused-stop" "$file"
[[ $(bash "$root/ops/watchdog.sh" --limit-min 0 --id "$id") == "$id pending settlement_unproven" ]] || fail 'stop intent bypassed identity mismatch'
kill -0 "$guard" || fail 'stop reconciliation signalled a reused guard'
assert_pending
mv "$scratch/real-identity.json" "$file"
touch "$work/release"
wait_launcher

# Even a matching receipt cannot override live group members or unreadable
# process evidence. Stub only the observation boundary to cover these failures.
fixture uncertain
jq '.worker_pid = 99999999 | .worker_start = "fixture" |
    .legacy_guard = {pgid:99999999,identity:"00000000-0000-0000-0000-000000000000:1",directory:"uncertain.launch"}' "$file" > "$scratch/uncertain.json"
mv "$scratch/uncertain.json" "$file"
mkdir "$LOOM_STATE/uncertain.launch"
printf '99999999 00000000-0000-0000-0000-000000000000:1 0\n' > "$LOOM_STATE/uncertain.launch/settled"
for observation in 0 2; do
    (
        loom_legacy_group() { return "$observation"; }
        [[ $(loom_legacy_status "$file") == unknown ]] || fail 'unsafe group observation authorized settlement'
        assert_pending
    )
done
printf '99999999 stale:1 0\n' > "$LOOM_STATE/uncertain.launch/settled"
[[ $(loom_legacy_status "$file") == unknown ]] || fail 'stale receipt accepted'
printf 'PASS legacy launcher cancellation, guard loss, watchdog, identity reuse and uncertain evidence\n'

# Fault injection runs the actual watchdog and launcher against real held
# processes. Only the signal/observation boundaries are replaced, in a private
# copy; production files and the worker's ordinary group behavior are intact.
mkdir "$scratch/fault-ops"
cp "$root/ops/"*.sh "$scratch/fault-ops/"
cat >> "$scratch/fault-ops/lib.sh" <<'FAULTS'
# Test-only boundary: preserve the real implementations under private names.
eval "$(declare -f loom_legacy_group | sed '1s/loom_legacy_group/fixture_real_group/')"
loom_legacy_group() {
    case $(cat "$FAULT_MODE") in
        unreadable)
            # The guard's scan excludes itself; only lose visibility at the
            # watchdog/launcher settlement boundary after the signal.
            if [[ $# == 1 ]]; then return 2; fi
            fixture_real_group "$@" ;;
        *) fixture_real_group "$@" ;;
    esac
}
kill() {
    if [[ $1 != -KILL ]]; then builtin kill "$@"; return; fi
    printf '%s\n' "$*" >> "$FAULT_SIGNALS"
    case $(cat "$FAULT_MODE") in
        denied) return 1 ;;
        leader-only)
            [[ $* != *--* ]] || return 1
            builtin kill "$@" ;;
        *) builtin kill "$@" ;;
    esac
}
FAULTS
export FAULT_MODE="$scratch/fault-mode" FAULT_SIGNALS="$scratch/fault-signals"
launch_ops="$scratch/fault-ops"
for fault in denied leader-only unreadable; do
    printf 'normal\n' > "$FAULT_MODE"
    start_held "kill-$fault"
    printf '%s\n' "$fault" > "$FAULT_MODE"
    : > "$FAULT_SIGNALS"
    [[ $(bash "$scratch/fault-ops/watchdog.sh" --limit-min 0 --id "$id") == "$id pending settlement_unproven" ]] || fail "$fault kill cleared ownership"
    jq -e '.worker_pid != null and .legacy_guard.stop_requested and (.reports | length) == 0' "$file" >/dev/null || fail "$fault kill lost identity"
    # Use the same uncertain observation for direct harvest, plus verify that
    # public collect/verify/relaunch remain fenced by the retained identity.
    (
        # shellcheck source=ops/lib.sh
        source "$scratch/fault-ops/lib.sh"
        assert_pending
    )
    signals=$(wc -l < "$FAULT_SIGNALS")
    [[ $(bash "$scratch/fault-ops/watchdog.sh" --limit-min 0 --id "$id") == "$id pending settlement_unproven" ]] || fail "$fault kill retry did not retain uncertainty"
    [[ $(wc -l < "$FAULT_SIGNALS") == "$signals" ]] || fail 'pending stop signalled again'
    if [[ $fault != unreadable ]]; then
        kill -0 "$descendant" || fail "$fault fixture lost its writer"
        # Now end the original group explicitly; only positive settlement may
        # permit watchdog to record failure, never the early ready report.
        kill -KILL -- "-$guard" 2>/dev/null || :
    fi
    wait "$launcher" 2>/dev/null || :
    printf 'normal\n' > "$FAULT_MODE"
    # The real launcher may finish the stop after the fault disappears.
    bash "$root/ops/watchdog.sh" --id "$id" >/dev/null
    jq -e '.worker_pid == null and (.reports | length) == 1 and .reports[0].fact == "watchdog_kill"' "$file" >/dev/null || fail "$fault stop did not settle exactly once"
    [[ $(git -C "$work" rev-parse HEAD) == "$base" && ! -e $LOOM_STATE/$id.evidence ]] || fail "$fault stop sealed incomplete evidence"
done
printf 'PASS legacy failed signals, PID-only fallback and post-kill observation uncertainty\n'

# Exercise Darwin parsing with controlled BSD-shaped rows, including zombie
# suffixes and malformed/failed snapshots. This runs on every host.
(
    ps() { printf '  Sat Nov  7 05:26:31 2026    \n'; }
    [[ $(loom_pstart 42) == 'Sat Nov  7 05:26:31 2026' ]] || fail 'process start time not trimmed'
    _loom_legacy_platform=Darwin
    # shellcheck disable=SC2317 # invoked through the observation helper
    ps() { printf '  0 0 ?<L\n 42 42 S+\n 43 42 Z+\n 44 44 R\n'; }
    loom_legacy_proc 42 || fail 'Darwin process lookup failed'
    [[ ${_loom_proc[2]} == 42 && ${_loom_proc[0]} == S ]] || fail 'Darwin process fields wrong'
    rc=0; loom_legacy_group 42 42 || rc=$?
    [[ $rc == 1 ]] || fail 'Darwin zombie blocked settlement'
    loom_legacy_group 42 || fail 'Darwin live group missed'
    rc=0; loom_legacy_proc 99 || rc=$?
    [[ $rc == 1 ]] || fail 'Darwin missing PID not distinguished'
    # An indeterminate state in the target group cannot prove settlement.
    # shellcheck disable=SC2317 # invoked through the observation helper
    ps() { printf '42 42 S+\n43 42 ?E\n'; }
    loom_legacy_group 42 42 || fail 'Darwin indeterminate state treated as empty'
    # shellcheck disable=SC2317 # invoked through the observation helper
    ps() { printf '42 invalid S\n'; }
    rc=0; loom_legacy_group 42 || rc=$?
    [[ $rc == 2 ]] || fail 'Darwin malformed snapshot accepted'
    ps() { return 1; }
    rc=0; loom_legacy_proc 42 || rc=$?
    [[ $rc == 2 ]] || fail 'Darwin failed snapshot treated as absence'
    _loom_legacy_platform=Unsupported
    if loom_legacy_identity 42; then fail 'unsupported platform accepted'; fi
)
printf 'PASS legacy non-Linux observation routing\n'

# On Linux run every integration assertion again through the Darwin ps route.
# This verifies routing without claiming validation of a macOS kernel or Bash.
# macOS itself runs the full suite above with its native ps, without skips.
if [[ ${1:-} != --darwin-routing && $(uname -s) == Linux ]]; then
    mkdir "$scratch/platform-bin"
    printf '#!/bin/sh\nprintf "Darwin\\n"\n' > "$scratch/platform-bin/uname"
    chmod +x "$scratch/platform-bin/uname"
    PATH="$scratch/platform-bin:$PATH" bash "$0" --darwin-routing
fi
