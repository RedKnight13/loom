#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2030,SC2031,SC2154 # actual fixture libraries provide shared state
set -euo pipefail
trap 'printf "FAIL at line %s (exit %s)\n" "$LINENO" "$?" >&2' ERR
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
: "${LOOM_COORDINATION_PROTOCOL_MODULE:=$root/ops/protocol.sh}"
: "${LOOM_COORDINATION_STATE_MODULE:=$root/ops/state.sh}"
: "${LOOM_COORDINATION_POLICY_MODULE:=$root/ops/policy.sh}"
export LOOM_COORDINATION_PROTOCOL_MODULE LOOM_COORDINATION_STATE_MODULE LOOM_COORDINATION_POLICY_MODULE
for module in "$LOOM_COORDINATION_PROTOCOL_MODULE" "$LOOM_COORDINATION_STATE_MODULE" "$LOOM_COORDINATION_POLICY_MODULE"; do
    [[ -f $module ]] || { printf 'Missing actual S1/S2/S3 module: %s\n' "$module" >&2; exit 2; }
done
# shellcheck source=/dev/null
source "$LOOM_COORDINATION_STATE_MODULE"
# shellcheck source=/dev/null
source "$LOOM_COORDINATION_POLICY_MODULE"
# shellcheck source=/dev/null
source "$LOOM_COORDINATION_PROTOCOL_MODULE"
# shellcheck source=ops/coordination.sh
source "$root/ops/coordination.sh"
umask 077
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export LOOM_STATE=$scratch/state
mkdir "$LOOM_STATE"
loom_state_init fixture-store >/dev/null
loom_policy_capacity_init_request fixture-store owner > "$scratch/init"
loom_state_transact "$scratch/init" >/dev/null
jq -cn '{schema:2,repo:"example/project",execution:{provider:"native",transport:"process",placement:{allowed_hosts:["fixture-host"],selection:"explicit",selected_host:"fixture-host",allow_local:true,fallback:"deny"},agent_profile:"fixture",model:null,effort:null},limits:{workers:2,operation_timeout_ms:30000},ticket_provider:"github"}' > "$scratch/config"
jq -cn --arg root "$scratch" '{schema:2,hosts:[{id:"fixture-host",transport:"process",destination:null,workspace_root:$root,identity:"fixture-identity",helper:{version:"1",digest:"git-blob-sha1-v1:1111111111111111111111111111111111111111"}}]}' > "$scratch/hosts"
jq -cn '{schema:2,agents:[{id:"fixture",executable:"/usr/bin/true",argv:[],prompt_ingress:"stdin",model:null,effort:null}],adapters:[]}' > "$scratch/profiles"
jq -cn --arg root "$scratch" '{schema:1,state_root:($root+"/state"),store_id:"fixture-store",actor_id:"owner",runs:["run-one","run-two"],create_runs:true,claims:[],proofs:[],config:($root+"/config"),hosts:($root+"/hosts"),profiles:($root+"/profiles")}' > "$scratch/context"
context=$scratch/context
seq=0
actor=owner
run="run-one"
epoch=0
digest=git-blob-sha1-v1:1111111111111111111111111111111111111111
request() {
    local op=$1 args=$2 revision=${3:-null}
    seq=$((seq+1))
    jq -cn --arg op "$op" --arg id "op-$seq" --arg actor "$actor" --arg run "$run" --argjson epoch "$epoch" --argjson args "$args" --argjson rev "$revision" '
      {protocol:"loom.coordination",version:{major:1,minor:0},request_id:$id,operation_id:$id,idempotency_key:$id,op:$op,
       actor:{id:$actor,run_id:$run,epoch:$epoch},target:{assignment_id:null,attempt_id:null,host_id:null},expected_revision:$rev,
       timeout_ms:30000,args:$args,extensions:{}} |
      if $op|IN("hello","run.show","run.use","run.list","task.show","task.list","gate.list") then .operation_id=null | .idempotency_key=null else . end' > "$scratch/request"
}
ok() {
    if ! loom_coordination_handle "$context" "$scratch/request" > "$scratch/response"; then
        cat "$scratch/request" "$scratch/response" >&2; exit 1
    fi
    jq -e '.ok' "$scratch/response" >/dev/null
}
deny() {
    local rc=0
    loom_coordination_handle "$context" "$scratch/request" > "$scratch/response" 2>"$scratch/error" || rc=$?
    [[ $rc == 2 ]] || { printf 'Expected refusal, got %s\n' "$rc"; cat "$scratch/request" "$scratch/response" "$scratch/error"; exit 1; }
    jq -e '.ok==false and .status=="refused"' "$scratch/response" >/dev/null
}
task() {
    request task.create "$(jq -cn --arg run "$run" --arg d "$digest" --argjson deps "${1:-[]}" '{run_id:$run,spec_ref:"spec/task",spec_digest:$d,deps:$deps,gates:[]}')"
    ok
    created=$(jq -r .result.task_id "$scratch/response")
}
rev() { loom_state_get "$1" "$2" | jq -r .revision; }
plan() {
    local task=$1 attempt=$2 revision=$3
    loom_policy_resolve "$scratch/config" "$scratch/hosts" "$scratch/profiles" > "$scratch/pin"
    local scope profile
    scope=$(loom_policy_scope < "$scratch/pin"); profile=$(jq -r .profile_digest "$scratch/pin")
    jq -cn --arg task "$task" --arg aid "$attempt" --arg run "$run" --arg actor "$actor" --argjson epoch "$epoch" \
      --argjson revision "$revision" --arg scope "$scope" --arg profile "$profile" --arg digest "$digest" --arg root "$scratch" '
      {schema:1,task_id:$task,expected_revision:$revision,operation_id:($aid+"-start"),idempotency_key:($aid+"-start"),placement_digest:$scope,
       actor:{id:$actor,run_id:$run,epoch:$epoch},binding:{schema:1,actor:{id:$actor,run_id:$run,epoch:$epoch},
       target:{assignment_id:($task+"-assignment"),attempt_id:$aid,host_id:"fixture-host"},workspace_id:"fixture-workspace",workspace:($root+"/workspace"),
       prompt_ref:"prompt-fixture",prompt:($root+"/prompt"),manifest_digest:$digest,profile_digest:$profile,prompt_digest:$digest,executable_digest:$digest,
       limits:{runtime_ms:null,stop_on_timeout:false,allow_kill:false,output_bytes:4096},stop_authorized:true,release_authorized:false}}' > "$scratch/plan"
}
launch_proof() {
    local bd
    bd=$(jq '.binding|del(.stop_authorized,.release_authorized)' "$scratch/plan" | loom_policy_scope)
    jq --slurpfile p "$scratch/plan" --arg bd "$bd" '.proofs += [ $p[0] | {kind:"launch",run_id:.actor.run_id,task_id,revision:.expected_revision,epoch:.actor.epoch,binding_digest:$bd,placement_digest,
      calibration_verified:true,capabilities_verified:true,workspace_verified:true,stop_authorized:.binding.stop_authorized}]' "$context" > "$scratch/new-context"
    mv "$scratch/new-context" "$context"
}
auth_deny() {
    local rc=0
    loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/authorization" 2>"$scratch/error" || rc=$?
    [[ $rc == 2 ]] || { printf 'Expected authorization refusal, got %s\n' "$rc"; cat "$scratch/error"; exit 1; }
}

request run.create '{"objective":"Replay fixture","owner_id":"owner","parent_run_id":null}'
ok
task '[]'
cp "$scratch/request" "$scratch/historic"
cp "$context" "$scratch/old-context"
revision=$(rev run "$run")
jq --argjson rev "$revision" '.actor_id="replacement" | .claims=[{run_id:"run-one",expected_owner:"owner",expected_revision:$rev,epoch:0,reason:"fixture takeover"}]' "$context" > "$scratch/replacement"
context=$scratch/replacement; actor=replacement
request run.claim '{"run_id":"run-one","expected_owner":"owner","reason":"fixture takeover"}' "$revision"
ok
printf 'takeover: '; jq -c '.result|{owner_id,epoch,revision}' "$scratch/response"
context=$scratch/old-context
rc=0; loom_coordination_handle "$context" "$scratch/historic" > "$scratch/replay" || rc=$?
printf 'old-owner epoch-0 retry: exit=%s ' "$rc"; jq -c '{ok,status,state:.result.state}' "$scratch/replay"
[[ $rc == 2 ]] && jq -e '.ok==false' "$scratch/replay" >/dev/null
# Compare to new old-epoch mutation (must refuse).
actor=owner; epoch=0
request task.create "$(jq -cn --arg d "$digest" '{run_id:"run-one",spec_ref:"spec/new",spec_digest:$d,deps:[],gates:[]}')"
deny
printf 'new old-owner mutation: refused; PASS stale owner refused on both historical and fresh mutations\n'
# Independent run exercises cancellation then actual normalized settlement proof.
run='run-two'; actor=owner; epoch=0
request run.create '{"objective":"Cancellation fixture","owner_id":"owner","parent_run_id":null}'
ok; task '[]'; cancelled_task=$created
plan "$cancelled_task" attempt-cancel 1; launch_proof
loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/authorization"
request task.update "$(jq -cn --arg id "$cancelled_task" '{task_id:$id,transition:"cancelled",evidence_refs:[]}')" "$(rev task "$cancelled_task")"
ok
revision=$(rev task "$cancelled_task")
jq --arg id "$cancelled_task" --argjson rev "$revision" '.proofs += [{kind:"settlement",run_id:"run-two",task_id:$id,revision:$rev,epoch:0,attempt_id:"attempt-cancel",evidence_ref:"fixture/exit",confirmed_stopped:true,quiescent:true}]' "$context" > "$scratch/new"; mv "$scratch/new" "$context"
request task.update "$(jq -cn --arg id "$cancelled_task" '{task_id:$id,transition:"cancelled",evidence_refs:["fixture/exit"]}')" "$revision"
ok
printf 'cancelled task settlement with trusted proof: '; jq -c '{ok,status,error:.error.code}' "$scratch/response"
loom_state_get attempt attempt-cancel | jq -c '.data|{execution_state,confirmed_stopped}'
loom_state_get attempt attempt-cancel | jq -e '.data.execution_state=="exited" and .data.confirmed_stopped==true' >/dev/null
loom_state_get task "$cancelled_task" | jq -e '.data.state=="cancelled"' >/dev/null
printf 'PASS cancellation remains terminal while proven attempt settlement is recorded\n'
