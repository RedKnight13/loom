#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2030,SC2031,SC2154 # actual fixture libraries provide shared state
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
LOOM_NATIVE_FIXTURE_LIBRARY=1 source "$root/tests/native/run.sh"
fixture recovery 'trap "exit 0" TERM; touch started; while :; do sleep 1; done'
call "$dir/start"
for _ in {1..100}; do [[ ! -f $dir/workspaces/worker/started ]] || break; sleep 0.02; done
stop_request false
call "$dir/stop"
cp "$spool/signals" "$dir/signals-before"
rm "$spool/stop"
call "$dir/stop"
cmp "$dir/signals-before" "$spool/signals"
jq -e '.result.confirmed_stopped' "$dir/result" >/dev/null
jq '.release_authorized=true' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
revision=$(LOOM_STATE=$dir/state loom_state_get host "$(printf 'attempt\n' | git hash-object --stdin)" | jq .revision)
jq --argjson revision "$revision" '.op="execution.release"|.operation_id="release"|.idempotency_key="release"|.expected_revision=$revision|.args={retention_policy:"release"}' "$dir/start" > "$dir/release"
call "$dir/release"
rm "$spool/released"
call "$dir/release"
jq -e '.result.resources|all(.state=="released")' "$dir/result" >/dev/null
printf 'PASS stop/release retries reconstruct committed cache without new signals\n'
