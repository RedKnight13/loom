#!/usr/bin/env bash
# Actual S6 -> S3/S2 authorization -> S4 fake workload integration.
# shellcheck disable=SC1091,SC2016 # installation modules and literal fixture text
set -euo pipefail
native_tests=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
LOOM_NATIVE_FIXTURE_LIBRARY=1 source "$native_tests/run.sh"
coordination=${LOOM_NATIVE_COORDINATION_MODULE:-$ops/coordination.sh}
[[ -f $coordination ]] || { printf 'Actual S6 module is required\n' >&2; exit 2; }
export LOOM_COORDINATION_PROTOCOL_MODULE=$LOOM_NATIVE_PROTOCOL_MODULE
export LOOM_COORDINATION_STATE_MODULE=$LOOM_NATIVE_STATE_MODULE
export LOOM_COORDINATION_POLICY_MODULE=$LOOM_NATIVE_POLICY_MODULE
# shellcheck source=/dev/null
source "$coordination"
dir='' # populated by fixture() from the shared test library

co_request() {
    local operation=$1 args=$2
    jq -cn --arg op "$operation" --argjson args "$args" --slurpfile b "$dir/binding" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$op,operation_id:$op,idempotency_key:$op,op:$op,actor:$b[0].actor,target:{assignment_id:null,attempt_id:null,host_id:null},expected_revision:null,timeout_ms:30000,args:$args,extensions:{}}' > "$dir/co-request"
    loom_coordination_handle "$dir/co-context" "$dir/co-request" > "$dir/co-result" || { cat "$dir/co-result" >&2; fail 'S6 request failed'; }
}

# Override only the fixture's authorization constructor, using the actual S6 API.
authorize() {
    local task scope binding_digest rc=0
    LOOM_STATE=$dir/authority loom_state_init fixture-authority >/dev/null
    loom_policy_capacity_init_request fixture-authority owner > "$dir/cap-init"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/cap-init" >/dev/null
    jq -cn --arg dir "$dir" '{schema:1,state_root:($dir+"/authority"),store_id:"fixture-authority",actor_id:"owner",runs:["run"],create_runs:true,claims:[],proofs:[],config:($dir+"/config"),hosts:($dir+"/hosts"),profiles:($dir+"/profiles")}' > "$dir/co-context"
    co_request run.create '{"objective":"Native integration fixture","owner_id":"owner","parent_run_id":null}'
    co_request task.create '{"run_id":"run","spec_ref":"fixture-spec","spec_digest":"git-blob-sha1-v1:1111111111111111111111111111111111111111","deps":[],"gates":[]}'
    task=$(jq -r .result.task_id "$dir/co-result")
    printf '%s\n' "$task" > "$dir/task-id"
    scope=$(loom_policy_scope < "$dir/pin")
    binding_digest=$(jq 'del(.stop_authorized,.release_authorized)' "$dir/binding" | loom_policy_scope)
    jq -cn --slurpfile b "$dir/binding" --arg task "$task" --arg scope "$scope" '{schema:1,task_id:$task,expected_revision:1,operation_id:"start",idempotency_key:"start",placement_digest:$scope,actor:$b[0].actor,binding:$b[0]}' > "$dir/plan"
    loom_coordination_authorize "$dir/co-context" "$dir/plan" > "$dir/denied" 2> "$dir/denied-error" || rc=$?
    [[ $rc == 2 && ! -d $dir/state/native ]] || fail 'launch without authority proof'
    # Synthetic trusted provisioning verifies this fake executable/workspace.
    # This is not a claim of real-agent calibration or authentication.
    jq --arg task "$task" --arg bd "$binding_digest" --arg scope "$scope" '.proofs=[{kind:"launch",run_id:"run",task_id:$task,revision:1,epoch:0,binding_digest:$bd,placement_digest:$scope,calibration_verified:true,capabilities_verified:true,workspace_verified:true,stop_authorized:true}]' "$dir/co-context" > "$dir/new-context"
    mv "$dir/new-context" "$dir/co-context"
    loom_coordination_authorize "$dir/co-context" "$dir/plan" > "$dir/authorization" || fail 'actual S6 authorization failed'
    loom_coordination_authorize "$dir/co-context" "$dir/plan" > "$dir/auth-replay" || fail 'S6 authorization replay'
    cmp "$dir/authorization" "$dir/auth-replay" || fail 'S6 replay changed receipts'
}

fixture coordination 'printf x >> launched; exit 11'
call "$dir/start"
settled
jq -e '.result.terminal.captured==true and .result.terminal.exit_code==11' "$dir/result" >/dev/null || fail 'S6-authorized captured exit'
call "$dir/start"
[[ $(cat "$dir/workspaces/worker/launched") == x ]] || fail 'S6/S4 replay relaunched'
LOOM_STATE=$dir/authority loom_state_get task "$(cat "$dir/task-id")" > "$dir/task-record"
jq -e '.data.state=="running" and .data.accepted_result==null' "$dir/task-record" >/dev/null || fail 'process exit promoted task'
LOOM_STATE=$dir/authority loom_policy_capacity "$dir/config" "$dir/hosts" "$dir/profiles" > "$dir/capacity"
jq -e '.reserved==1 and .available==0' "$dir/capacity" >/dev/null || fail 'native execution freed authority reservation'
printf 'PASS actual S6 authorization, S3 capacity, S2 journal, S4 launch/replay/exit; no implicit task acceptance\n'
