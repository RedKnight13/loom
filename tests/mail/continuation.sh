#!/usr/bin/env bash
# Authorized replacement via actual S6; mail never creates the continuation.
# shellcheck disable=SC1090,SC1091,SC2016,SC2154
set -euo pipefail
here=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
MAIL_FIXTURE_LIBRARY=1 source "$here/run.sh"
MAIL_EXTRA_SLOT=1 fixture continuation 'exit 0'
send_message exact-old attempt:attempt
old_delivery=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
send_message task-next "task:$(cat "$dir/task-id")"
task_delivery=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
request mail.claim "$(jq -cn --arg t "task:$(cat "$dir/task-id")" --arg id "$task_delivery" '{mailbox:$t,delivery_id:$id,lease_ms:1,claim_token:null}')" 1 worker
mail_call worker
cp "$dir/binding" "$dir/old-binding"
jq --arg binding "$dir/old-binding" '.binding=$binding' "$dir/mail-worker" > "$dir/old-worker"
task=$(cat "$dir/task-id")
rev=$(LOOM_STATE=$dir/authority loom_state_get task "$task" | jq .revision)
jq --arg task "$task" --argjson rev "$rev" '.proofs += [{kind:"settlement",run_id:"run",task_id:$task,revision:$rev,epoch:0,attempt_id:"attempt",evidence_ref:"fixture/settled",confirmed_stopped:true,quiescent:true}]' "$dir/co-context" > "$dir/new"; mv "$dir/new" "$dir/co-context"
request task.update "$(jq -cn --arg task "$task" '{task_id:$task,transition:"failed",evidence_refs:["fixture/settled"]}')" "$rev"
loom_coordination_handle "$dir/co-context" "$dir/request" > "$dir/settled"
rev=$(jq .result.revision "$dir/settled")
scope=$(loom_policy_scope < "$dir/pin")
request task.continue "$(jq -cn --arg task "$task" --arg scope "$scope" '{task_id:$task,parent_attempt_id:"attempt",placement_digest:$scope,message_ids:[],reason:"fixture explicit retry"}')" "$rev"
loom_coordination_handle "$dir/co-context" "$dir/request" > "$dir/continued"
new_attempt=$(jq -r .result.attempt_id "$dir/continued")
rev=$(jq .result.revision "$dir/continued")
jq --arg aid "$new_attempt" '.target.attempt_id=$aid' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
bd=$(jq 'del(.stop_authorized,.release_authorized)' "$dir/binding" | loom_policy_scope)
jq --arg task "$task" --arg bd "$bd" --arg scope "$scope" --argjson rev "$rev" '.proofs += [{kind:"launch",run_id:"run",task_id:$task,revision:$rev,epoch:0,binding_digest:$bd,placement_digest:$scope,calibration_verified:true,capabilities_verified:true,workspace_verified:true,stop_authorized:true}]' "$dir/co-context" > "$dir/new"; mv "$dir/new" "$dir/co-context"
jq --slurpfile b "$dir/binding" --argjson rev "$rev" '.binding=$b[0]|.expected_revision=$rev|.operation_id="start-second"|.idempotency_key="start-second"' "$dir/plan" > "$dir/plan-second"
loom_coordination_authorize "$dir/co-context" "$dir/plan-second" > "$dir/authorization-second"
loom_worker_bridge_boundary "$dir/mail-worker" 20 > "$dir/boundary"
jq -e --arg aid "$new_attempt" '(.messages|length)==1 and .messages[0].message.message_id=="task-next" and .messages[0].delivery.attempt_id==$aid' "$dir/boundary" >/dev/null || fail 'replacement did not claim task mail exclusively'
LOOM_STATE=$dir/authority loom_state_get delivery "$old_delivery" > "$dir/old-delivery"
jq -e '.data.delivery.attempt_id=="attempt" and .data.delivery.state=="pending"' "$dir/old-delivery" >/dev/null || fail 'old attempt mail redirected'
request mail.poll '{"mailbox":"attempt:attempt","after_cursor":null,"limit":100}' null worker; mail_call worker 2
request mail.poll "$(jq -cn --arg task "$task" '{mailbox:("task:"+$task),after_cursor:null,limit:100}')" null worker
jq --slurpfile b "$dir/old-binding" '.target=$b[0].target' "$dir/request" > "$dir/old-request"
rc=0; loom_mail_handle "$dir/old-worker" "$dir/old-request" > "$dir/refused" || rc=$?
[[ $rc == 2 ]] || fail 'old attempt stole current task mail'
printf 'PASS actual S6 continuation: expired task lease reassigns under CAS, exact old attempt mail remains isolated\n'
