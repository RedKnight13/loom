#!/usr/bin/env bash
# shellcheck disable=SC2016  # the sed patterns below are literal on purpose
# Proves the selftest has teeth: each mutant re-introduces a fixed defect, and
# the selftest must fail on every one. A gap fix adds its mutant here.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
base=$(mktemp -d "${TMPDIR:-/tmp}/loom-mutants.XXXXXX")
survived=0
run() {
    local m="$base/$4"
    mkdir -p "$m"
    cp -R ops "$m/"
    sed -i '' "$2" "$m/ops/$1"
    if cmp -s "ops/$1" "$m/ops/$1"; then echo "MUTATION DID NOT APPLY: $3"; survived=1; return; fi
    # A mutant that breaks the syntax would be "caught" for the wrong reason.
    if ! bash -n "$m/ops/$1" 2>/dev/null; then echo "MUTANT IS NOT VALID BASH: $3"; survived=1; return; fi
    if bash "$m/ops/selftest.sh" >/dev/null 2>"$m/err"; then
        echo "MUTANT SURVIVED: $3"; survived=1
    else
        echo "caught: $3 -> $(tail -1 "$m/err")"
    fi
}
run watchdog.sh 's/kill -KILL -- "-$pid" 2>\/dev\/null || //' "no process-group kill" m1
run lib.sh 's/\[\[ $now == "$start" \]\]/true/' "no PID start-time check" m2
run lib.sh 's/tail -n +"$((offset + 1))"/cat/' "report_offset ignored" m3
run launch.sh 's/if \[\[ $(jq -r .\.worker_pid \/\/ empty. "$file") == "$child" \]\]; then/if true; then/' "launcher double-reports after watchdog" m4
run dispatch.sh 's/git -C "$workdir" remote remove origin/true/' "clone keeps a push remote" m5
run watchdog.sh 's/($override \/\/ .limit_min \/\/ 30)/($override \/\/ 30)/' "watchdog ignores consumer limit" m6
run lib.sh '/s="${s%"${s##\*\[!\[:space:\]\]}"}"/d' "start time not trimmed at the end" m7
run lib.sh 's/git -C "$workdir" add -A \&\&/true \&\&/' "harvest does not stage worker files" m8
run dispatch.sh 's/\.short_name == \$short/.short_name == "never"/' "attempts not numbered per short name" m9
run verify.sh 's/(cd "$scratch\/tree" \&\& umask/(cd "$workdir" \&\& umask/' "verify runs in the worker clone" m10
run verify.sh '/126|127) verdict=/d' "could-not-run reported as a test failure" m11
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
run collect.sh 's/^if \[\[ $(cd "$workdir" \&\& cd/if true || [[ $(cd "$workdir" \&\& cd/' "collect fetches into a shared-repo branch" m23
run verify.sh 's/^\[\[ $kind == baseline \]\] || ! loom_alive/! loom_alive/' "baseline refused while the worker runs" m24
run orca.sh 's/workdir=\${workspace##\*::}/workdir=/' "workspace split removed" m25
run orca.sh '/branch is not collected/d' "release allowed before collect" m26
run status.sh 's/select(has("acked") | not) //' "acked assignment still listed" m27
run lib.sh '/loom_take_evidence "\$workdir" "\$id"/d' "evidence not copied" m28
run lib.sh 's/for f in WORK.md REPORT.md .loom\/;/for f in WORK.md REPORT.md;/' "evidence directory not excluded at harvest" m29
echo "SURVIVED=$survived"
exit "$survived"
