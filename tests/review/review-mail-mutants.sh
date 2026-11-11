#!/usr/bin/env bash
# shellcheck disable=SC2016 # Mutation expressions are intentionally literal.
# Focused mutation runner only; never invokes the full mutation matrix.
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
logs=${1:-$root/.loom/review-mail-mutants}
mkdir -p "$logs"
logs=$(cd "$logs" && pwd -P)
private=$(mktemp -d)
trap 'rm -rf -- "$private"' EXIT
copy_tree() {
    mkdir -p "$1"
    cp -R "$root/ops" "$root/schemas" "$root/tests" "$root/VERSION" "$1/"
    chmod -R go-rwx "$1"
}
copy_tree "$private/control"
rc=0
REVIEW_MAIL_PRIVATE=1 bash "$private/control/tests/review/review-mail.sh" > "$logs/control.log" 2>&1 || rc=$?
printf 'control exit=%s\n' "$rc" | tee "$logs/control.exit"
(( rc==0 )) || exit 2
mutant() {
    local id=$1 file=$2 edit=$3 section=$4 rc=0
    copy_tree "$private/$id"
    sed "$edit" "$root/ops/$file" > "$private/$id/ops/$file"
    if cmp -s "$root/ops/$file" "$private/$id/ops/$file"; then printf 'mutation did not apply: %s\n' "$id"; exit 2; fi
    bash -n "$private/$id/ops/$file"
    REVIEW_MAIL_PRIVATE=1 bash "$private/$id/tests/review/review-mail.sh" "$section" > "$logs/$id.log" 2>&1 || rc=$?
    printf '%s exit=%s\n' "$id" "$rc" | tee "$logs/$id.exit"
    (( rc!=0 )) || { printf 'SURVIVED %s\n' "$id"; exit 1; }
    rm -rf "${private:?}/$id"
}
mutant claim-old-epoch coordination.sh 's/if \$q\[0\].op=="run.claim" then \$prior.outcome.result.response.epoch else \$q\[0\].actor.epoch end/\$q[0].actor.epoch/' claim
mutant claim-unfenced coordination.sh 's/^      \.epoch==(if .*$/      true and/' claim
mutant exchange-regenerate mail.sh 's/if loom_state_get operation "\$request_id" > /if false \&\& loom_state_get operation "$request_id" > /' replay
mutant expiry-stale mail.sh '/jq -e.*pump-d.*continue/d' expiry
mutant outbox-starvation worker-bridge.sh 's/\.outbox_after=\$r\[0\]\.outbox_after/.outbox_after=null/' outbox
mutant scratch-leak state.sh '/^    rm -f -- "\$tmp" || return 1$/d' state
mutant scratch-unreclaimed state.sh 's/rm -f -- "\$path" || return 1/true || return 1/;s/rm -rf -- "\$path" || return 1/true || return 1/' state
mutant cache-digest mail.sh '/jq -cS \.data.message "\$cache"/s/\[\[.*\]\]/true/' cache
mutant selection-refresh mail.sh '/jq -ce --arg id "\$id".*\.items\[\].*pump-d/c\
                loom_state_get delivery "$id" > "$_lm_tmp/pump-d" || return 2' selection
printf 'PASS focused review-mail control and nine killed mutants\n'
