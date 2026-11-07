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
run verify.sh 's/(cd "$scratch\/tree" \&\& exec bash/(cd "$workdir" \&\& exec bash/' "verify runs in the worker clone" m10
run verify.sh '/126|127) verdict=/d' "could-not-run reported as a test failure" m11
echo "SURVIVED=$survived"
exit "$survived"
