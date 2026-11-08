#!/usr/bin/env bash
# shellcheck disable=SC2016  # the sed patterns below are literal on purpose
# Proves the selftest has teeth: each mutant re-introduces a fixed defect, and
# the selftest must fail on every one. A gap fix adds its mutant here.
#
#   bash ops/mutate.sh               run here, mutants in parallel
#   bash ops/mutate.sh --on HOST     run the whole check on a compute host (#42)
#
# LOOM_MUTATE_PREFIX optionally selects a mutant ID prefix (e.g. mlife).
# LOOM_MUTATE_JOBS caps parallel mutants (default: CPU count). Exit 0 = every
# mutant caught; 1 = a mutant survived, did not apply, or was not valid bash;
# 2 = the harness itself is broken (the unmutated copy fails its selftest).
set -u
if [[ ${LOOM_MUTATE_CALIBRATION_ONLY:-0} == 1 ]]; then
    export LOOM_SELFTEST_CALIBRATION_ONLY=1
fi
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if [[ ${1:-} == --on ]]; then
    [[ $# == 2 && $2 =~ ^[A-Za-z0-9][A-Za-z0-9._@-]*$ ]] || { echo 'usage: mutate.sh [--on HOST]' >&2; exit 2; }
    # Ship the tracked tree; run there; clean up; the remote exit is ours.
    # shellcheck disable=SC2029  # expands on the host on purpose
    # COPYFILE_DISABLE / --no-xattrs: no macOS metadata in the shipped tree.
    git ls-files -z | COPYFILE_DISABLE=1 xargs -0 tar --no-xattrs -czf - | "${LOOM_SSH:-ssh}" -o BatchMode=yes -o ConnectTimeout=5 "$2" \
        'd=$(mktemp -d); trap "rm -rf \"$d\"" EXIT; cd "$d" && tar xzf - && echo "== mutants on $(hostname)" && bash ops/mutate.sh'
    exit $?
fi

base=$(mktemp -d "${TMPDIR:-/tmp}/loom-mutants.XXXXXX")
# Calibration refuses symlink ancestors; on macOS TMPDIR is /var/... and /var
# is a symlink to /private/var, so copy into the resolved path.
base=$(cd "$base" && pwd -P)
trap 'rm -rf "$base"' EXIT
jobs_max=${LOOM_MUTATE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
order=()

# Each mutant gets the whole tracked tree (ops/loom reads ../VERSION), not just ops/.
# A shipped tree (--on HOST) has no .git: then every file present is the tree.
tree_files() {
    local source
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git ls-files -z
        # Include the new source before Loom harvests it.
        for source in ops/calibrate.sh templates/LOOM_SESSION.md; do
            if [[ -f $source ]] && ! git ls-files --error-unmatch "$source" >/dev/null 2>&1; then
                printf '%s\0' "$source"
            fi
        done
    else find . -type f ! -path './.git/*' -print0; fi
}
copy_tree() { mkdir -p "$1" && tree_files | xargs -0 tar cf - | (cd "$1" && tar xf -); }

# Control: the unmutated copy must pass, or every "caught" below proves nothing.
copy_tree "$base/control"
if ! bash "$base/control/ops/selftest.sh" >/dev/null 2>"$base/control/err"; then
    echo "HARNESS BROKEN: the unmutated copy fails its selftest -> $(grep FAIL "$base/control/err" | tail -1)"
    exit 2
fi

one() {  # one <file> <sed> <description> <name>: writes $base/<name>/result
    local m="$base/$4" r
    copy_tree "$m"
    # Portable in-place edit (GNU and BSD sed).
    sed -i.orig "$2" "$m/ops/$1" && rm -f "$m/ops/$1.orig"
    if cmp -s "ops/$1" "$m/ops/$1"; then
        r="MUTATION DID NOT APPLY: $3"
    # A mutant that breaks the syntax would be "caught" for the wrong reason.
    elif ! bash -n "$m/ops/$1" 2>/dev/null; then
        r="MUTANT IS NOT VALID BASH: $3"
    elif LOOM_STATE="$m/state" bash "$m/ops/selftest.sh" >/dev/null 2>"$m/err"; then
        r="MUTANT SURVIVED: $3"
    else
        r="caught: $3 -> $(tail -1 "$m/err")"
    fi
    printf '%s\n' "$r" > "$m/result"
}
run() {
    if [[ ${LOOM_MUTATE_CALIBRATION_ONLY:-0} == 1 && $4 != mcal* ]]; then return 0; fi
    [[ -z ${LOOM_MUTATE_PREFIX:-} || $4 == "$LOOM_MUTATE_PREFIX"* ]] || return 0
    while [[ $(jobs -rp | wc -l) -ge $jobs_max ]]; do sleep 0.2; done
    order+=("$4")
    one "$@" &
}
run watchdog.sh 's/kill -KILL -- "-$pid" 2>\/dev\/null || //' "no process-group kill" m1
run lib.sh 's/\[\[ $now == "$start" \]\]/true/' "no PID start-time check" m2
run lib.sh 's/tail -n +"$((offset + 1))"/cat/' "report_offset ignored" m3
run launch.sh 's/if \[\[ $(jq -r .\.worker_pid \/\/ empty. "$file") == "$child" \]\]; then/if true; then/' "launcher double-reports after watchdog" m4
run dispatch.sh 's/git -C "$workdir" remote remove origin/true/' "clone keeps a push remote" m5
run watchdog.sh 's/($override \/\/ .limit_min \/\/ 30)/($override \/\/ 30)/' "watchdog ignores consumer limit" m6
run lib.sh '/s="${s%"${s##\*\[!\[:space:\]\]}"}"/d' "start time not trimmed at the end" m7
run lib.sh 's/loom_ws "$host" "$workdir" git add -A \&\&/true \&\&/' "harvest does not stage worker files" m8
run dispatch.sh 's/\.short_name == \$short/.short_name == "never"/' "attempts not numbered per short name" m9
run verify.sh 's/(cd "$scratch\/tree" \&\& umask/(cd "$workdir" \&\& umask/' "verify runs in the worker clone" m10
run verify.sh 's/^    126|127|255) verdict=.*/    126|127|255) verdict="checks exit $rc" ;;/' "could-not-run reported as a test failure" m11
run heartbeat.sh 's/acted=$(bash "$ops\/watchdog.sh" .*/acted=/' "heartbeat never runs the watchdog" m12
run ticket.sh '/does not survive dispatch.s parser/d' "ticket.sh skips the parser self-check" m13
run launch.sh 's/ \&\& umask "$LOOM_CALLER_UMASK"//' "worker inherits loom's umask" m14
run verify.sh 's/ \&\& umask "$LOOM_CALLER_UMASK"//' "checks inherit loom's umask" m15
run dispatch.sh '/consumer config has uncommitted changes/d' "dispatch accepts an uncommitted config" m16
run lib.sh 's/for try in 1 2; do/for try in 2; do/' "no retry after a fixer hook" m17
run launch.sh "s/^    loom_error 'the Orca CLI is available: workers start only through it.*/    :/" "launch.sh starts workers while Orca is available" m18
run orca.sh "s/if \[\[ \$rc != 0 \]\] || grep -q 'stop_unknown' \"\$receipt\"; then/if false; then/" "stop claimed without Orca's confirmation" m19
run status.sh 's/select($last <= (now - $limit \* 60))/select(false)/' "stale Orca worker never surfaced" m20
run dispatch.sh "s#\[\[ -n \$orca_runtime \]\] || loom_error 'executor orca required[^;]*; ##" "required Orca not enforced" m21
run lib.sh 's/        loom_orca_running "$1"/        false/' "a running Orca worker is not live" m22
run collect.sh 's/^elif \[\[ $(cd "$workdir" \&\& cd/elif true || [[ $(cd "$workdir" \&\& cd/' "collect fetches into a shared-repo branch" m23
run verify.sh 's/^\[\[ $kind == baseline \]\] || ! loom_alive/! loom_alive/' "baseline refused while the worker runs" m24
run orca.sh 's/workdir=\${workspace##\*::}/workdir=/' "workspace split removed" m25
run orca.sh '/branch is not collected/d' "release allowed before collect" m26
run status.sh 's/select(has("acked") | not) //' "acked assignment still listed" m27
run lib.sh '/loom_take_evidence "\$workdir" "\$id"/d' "evidence not copied" m28
run lib.sh 's/for f in WORK.md REPORT.md .loom\/;/for f in WORK.md REPORT.md;/' "evidence directory not excluded at harvest" m29
run verify.sh 's/^    host=$(loom_compute_pick $hosts) || loom_error .*/    host=$(loom_compute_pick $hosts) || host=""/' "unreachable compute host falls back to this machine" m30
run verify.sh "s/^hosts=\$(jq -r '(.compute \/\/ \[\])\[\]' \"\$file\")/hosts=''/" "compute host ignored" m31
run verify.sh 's/if ! eval %q; then/if ! true %q; then/' "compute_setup never applied" m32
run verify.sh 's/^\[\[ -z $on \]\] || hosts=$on/:/' "--on host ignored" m33
run loom 's/base_args+=(--on "$2"); shift 2 ;;/shift 2 ;;/' "loom verify drops --on" m34
run orca.sh 's/worker-show --dispatch "\$dispatch"/show --dispatch "$dispatch"/' "harvest never asks worker-show" m35
run orca.sh 's/check --peek --json/check --json/' "check scripted without --peek" m36
run orca.sh 's/owner_fenced/stopped/' "abandon recorded as a stop" m37
run ticket.sh 's/args+=(--label "\$label")/:/' "ticket.sh drops labels" m38
run heartbeat.sh 's/loom_alive "\$f" && return 1/:/' "watch ignores Orca workers" m51
run dispatch.sh '/checkout origin is/d' "dispatch accepts a foreign checkout" m52
run orca.sh 's/if \[\[ -z \$placement_host \]\]; then/if false; then/' "start ignores an unconnected Orca host" m39
run orca.sh 's/tried+=("\$candidate: known to Orca but not connected")/break/' "placement stops at compute[0] (#45)" m40
run lib.sh 's/select(.id == \$w or .name == \$w) | select(.connected == true or .kind == "local")\] | length > 0/select(.id == $w or .name == $w)][0] | .connected == true or .kind == "local"/' "a duplicate host name hides the connected one (#45)" m41
run orca.sh 's/^        repo_sel="path:\$rpath"$/        :/' "remote worker given the conductor checkout (#47)" m42
run orca.sh 's/^    ws_host=\$placement_host$/    ws_host=""/' "remote workspace treated as local (#47)" m43
run lib.sh 's/^    host=\$(loom_ws_host "\$file")$/    host=""/' "harvest reads the workspace here, not on its host (#47)" m44
run loom "s/items:\$items, actions:\$actions}' >\&3/items:\$items, actions:\$actions}'/" "failure JSON swallowed by the capture (#48)" m45
run collect.sh 's/^    loom_git_ssh -C "\$checkout" fetch/    : fetch/' "collect skips the remote fetch (#47)" m46
run orca.sh 's/\[\[ -n \$rpath \]\] || loom_error/[[ -n $rpath ]] || :/' "start without the project on the host (#47)" m47
run orca.sh 's/\.executor\.dispatch = (if \$d == "" then null else \$d end)/.executor.dispatch = null/' "failed start drops its dispatch (#50)" m48
run orca.sh 's/\[\[ \$xstate == running || ( \$xstate == failed_start \&\& -n \$dispatch ) \]\]/[[ $xstate == running ]]/' "abandon refuses a failed start (#50)" m49
run orca.sh "s/grep -q 'dispatch_not_found' \"\$show\" || loom_error/false || loom_error/" "a dispatch Orca forgot blocks the abandon (#50)" m50
run dispatch.sh 's/if \[\[ \$workers != null \]\]; then/if false; then/' "worker limit ignored" m53
run dispatch.sh '/git -C "\$config_dir" ls-files --error-unmatch/c\
    true; then' "ignored config records an empty commit (#68)" m54
run loom 's/ ${label_args\[@\]+"${label_args\[@\]}"}//' "loom accept drops label pass-through (#67)" m67
run verify.sh 's/^elif \[\[ -n $collected \]\]; then/elif false; then/' "verify checks the stale worker tip after collect (#74)" m74
run calibrate.sh '/Calibration proof is missing/s/cal_refuse evidence/cal_finish ready/' "calibration accepts missing proof" mcal1
run calibrate.sh '/Calibration wiring changed/s/\[\[.*\]\]/true/' "calibration ignores drift" mcal2
run calibrate.sh '/Calibration proof is corrupt/s/cal_refuse evidence/cal_finish ready/' "calibration ignores corrupt proof" mcal3
run calibrate.sh '/^        cal_reobserve$/d' "calibration check misses concurrent drift" mcal4
run calibrate.sh '/^    cal_reobserve$/d' "calibration record publishes stale observation" mcal5
run calibrate.sh '/export GIT_DIR=\/dev\/null GIT_DEFAULT_HASH=sha1 GIT_CONFIG_COUNT=0/d' "calibration hashes use caller object format" mcal6
run calibrate.sh '/cal_no_links "\$consumer"/s/! cal_no_links "\$consumer"/false/' "calibration follows config ancestor symlinks" mcal7
run loom '/\[\[ -f \$source_path/s/\[\[.*\]\]/true/' "calibration reads nonregular early sources" mcal8
run calibrate.sh 's/cal_json_hash() { jq -Sc ./cal_json_hash() { jq -Scj ./' "calibration canonical JSON loses its trailing newline" mcal9
run calibrate.sh '/\[\[ \$state_dir == \/\* \]\] || state_dir=/c\
    [[ $state_dir == /* ]] || cal_refuse evidence "relative state rejected"' "calibration rejects relative state" mcal10
run calibrate.sh "s/'\.state == \$expected'/'\.state == \"blocked\" or .state == \"failed\"'/" "calibration drill conflates blocked and failed" mcal11
run orca.sh 's/\.executor.dispatch = \$v.dispatch/.executor.dispatch = .executor.dispatch/' "follow-up keeps old dispatch" mlife1
run orca.sh 's/elif .state == "completed" and/elif true and/' "harvest accepts no positive dispatch completion" mlife2
run orca.sh 's/if .dispatch != \$d then/if false then/' "harvest accepts another dispatch completion" mlife3
run orca.sh 's/IN("live", "working", "running")/IN("never", "working", "running")/; s/IN("idle", "exited", "absent", "completed")/IN("live", "idle", "exited", "absent", "completed")/' "harvest ignores live retained worker" mlife4
run orca.sh 's/\.report_offset = \$offset/.report_offset = 0/' "follow-up reuses an old report" mlife5
run orca.sh 's/followup_link "\$ancestor" "\$child"/true/' "reconcile ignores follow-up identity chain" mlife6
run orca.sh 's/cp -R "\$old" "\$archive\/"/true/' "continuation drops old evidence" mlife7
run orca.sh 's/id=${matches\[0\]%.json}/:/' "legacy dispatch selector is not mapped to its assignment" mlife8
run orca.sh 's/elif \[\[ \$xstate == running \]\] \&\& jq/elif jq/' "settled queue-only receipt clears continuation fence" mlife9
run orca.sh 's/(.liveness == "unverifiable" and/(false and/' "durable success rejected after telemetry expires" mlife10
run orca.sh 's/\.durable == true/true/' "stale completion accepted without durable evidence" mlife11
run orca.sh 's/\.receipt\.XXXXXX/\.XXXXXX.receipt/' "receipt template has a suffix after the random field" mportable1
run orca.sh 's/ "\$LOOM_STATE\/\$id.orca-"\*\.receipt\.\*//' "history omits portable receipt names" mportable2
run orca.sh '/orca_call "\$receipt" orchestration worker-show/s/ --full//' "show requests compact completion without durable proof" mportable3

run orca.sh 's/elif live_completion then/elif false then/' "durable success rejected while completed terminal remains live" mproof1
run orca.sh '/def live_completion:/,/;$/s/\.state == "completed"/true/' "live proof accepts incomplete or failed dispatch" mproof2
run orca.sh '/def live_completion:/,/;$/s/\.worker_dispatch == \$d/true/' "live proof accepts missing worker identity" mproof3
run orca.sh '/def live_completion:/,/;$/s/\.worker_state == "succeeded"/true/' "live proof accepts failed or working worker" mproof4
run orca.sh '/def live_completion:/,/;$/s/\.projection_dispatch == \$d/true/' "live proof accepts missing projection identity" mproof5
run orca.sh '/def live_completion:/,/;$/s/\.outcome == "succeeded"/true/' "live proof accepts missing or failed outcome" mproof6
run orca.sh '/def live_completion:/,/;$/s/\.durable == true/true/' "live proof accepts nondurable completion" mproof7
run orca.sh '/def live_completion:/,/;$/s/\.live_status == "fresh"/true/' "live proof accepts missing or stale freshness" mproof8
run orca.sh '/def live_completion:/,/;$/s/(\.completed_at |.*);/true;/' "live proof accepts missing completion timestamp" mproof9
run orca.sh '/def live_completion:/,/;$/s/\.liveness == "live"/(.liveness | IN("live", "working", "running"))/' "live proof accepts explicitly working liveness" mproof10
run orca.sh 's/\[\[ -n \$agent \]\] || agent=\$(jq -r /agent=\$(jq -r /' "CLI agent override ignored" m68

wait
[[ ${#order[@]} -gt 0 ]] || { echo "HARNESS BROKEN: no mutants match the selected prefix"; exit 2; }
survived=0
for n in "${order[@]}"; do
    r=$(cat "$base/$n/result" 2>/dev/null || echo "NO RESULT: $n")
    printf '%s\n' "$r"
    [[ $r == caught:* ]] || survived=1
done
echo "SURVIVED=$survived"
exit "$survived"
