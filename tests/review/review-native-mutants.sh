#!/usr/bin/env bash
# Focused native mutants, never the full mutation matrix.
# shellcheck disable=SC2016
set -euo pipefail
root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
logs=${1:-$root/.loom/review-native-mutants}
mkdir -p "$logs"; logs=$(cd -- "$logs" && pwd -P)
private=$(mktemp -d)
trap 'rm -rf -- "$private"' EXIT
copy_tree() {
    mkdir -p "$1"
    cp -R "$root/ops" "$root/schemas" "$root/tests" "$root/VERSION" "$1/"
    chmod -R go-rwx "$1"
}
copy_tree "$private/control"
rc=0
bash "$private/control/tests/review/review-native.sh" > "$logs/control.log" 2>&1 || rc=$?
printf 'control exit=%s\n' "$rc" | tee "$logs/control.exit"
(( rc==0 )) || exit 2
mutant() {
    local id=$1 file=$2 edit=$3 section=$4 rc=0
    copy_tree "$private/$id"
    sed "$edit" "$root/ops/$file" > "$private/$id/ops/$file"
    if cmp -s "$root/ops/$file" "$private/$id/ops/$file"; then printf 'mutation did not apply: %s\n' "$id"; exit 2; fi
    bash -n "$private/$id/ops/$file"
    bash "$private/$id/tests/review/review-native.sh" "$section" > "$logs/$id.log" 2>&1 || rc=$?
    printf '%s exit=%s\n' "$id" "$rc" | tee "$logs/$id.exit"
    (( rc!=0 )) || { printf 'SURVIVED %s\n' "$id"; exit 1; }
    rm -rf -- "${private:?}/${id:?}"
}
mutant serialized-mail native-supervisor.sh 's/($next|tojson|utf8bytelength)/($next.messages|map(.message.body|utf8bytelength)|add)/' mail
mutant option-boundary workflow.sh '/\[\[ $arg != -- \]\] || break/d' routing
mutant legacy-routing workflow.sh '/if \[\[ $# -ge 2 && -f .*\/\$2.json/d' routing
mutant child-wait workflow.sh 's/else scan_unknown=true; fi/else child_done=true; fi/' keeper
mutant scan-unknown workflow.sh 's/|| scan_unknown=true; continue/|| :; continue/' keeper
mutant partial-metadata workflow.sh '/if \[\[ -e $_rh_spool\/workflow-check \]\]; then/a\        return 0' metadata
mutant kill-reconcile native.sh 's/else _loom_native_reconcile_kill || :; fi/else :; fi/' reconcile
mutant kill-identity native.sh 's/\.==\$fact.outcome.result and /true and /' reconcile
printf 'PASS review-native control and eight killed mutants\n'
