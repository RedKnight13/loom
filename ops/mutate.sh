#!/usr/bin/env bash
# shellcheck disable=SC2016  # the sed patterns below are literal on purpose
# Proves the selftest has teeth: each mutant re-introduces a fixed defect, and
# the selftest must fail on every one. A gap fix adds its mutant here.
#
#   bash ops/mutate.sh               run here, mutants in parallel
#   bash ops/mutate.sh --on HOST     run the whole check on a compute host (#42)
#
# LOOM_MUTATE_JOBS caps parallel mutants (default: CPU count). Exit 0 = every
# mutant caught; 1 = a mutant survived, did not apply, or was not valid bash;
# 2 = the harness itself is broken (the unmutated copy fails its selftest).
set -u
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
trap 'rm -rf "$base"' EXIT
jobs_max=${LOOM_MUTATE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
order=()

# Each mutant gets the whole tracked tree (ops/loom reads ../VERSION), not just ops/.
# A shipped tree (--on HOST) has no .git: then every file present is the tree.
tree_files() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then git ls-files -z; else find . -type f ! -path './.git/*' -print0; fi
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
run lib.sh 's/git -C "$workdir" add -A \&\&/true \&\&/' "harvest does not stage worker files" m8
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
run collect.sh 's/^if \[\[ $(cd "$workdir" \&\& cd/if true || [[ $(cd "$workdir" \&\& cd/' "collect fetches into a shared-repo branch" m23
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
wait
survived=0
for n in "${order[@]}"; do
    r=$(cat "$base/$n/result" 2>/dev/null || echo "NO RESULT: $n")
    printf '%s\n' "$r"
    [[ $r == caught:* ]] || survived=1
done
echo "SURVIVED=$survived"
exit "$survived"
