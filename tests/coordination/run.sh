#!/usr/bin/env bash
set -euo pipefail
trap 'printf "FAIL at line %s (exit %s)\n" "$LINENO" "$?" >&2' ERR
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
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
request hello '{"versions":[{"major":1,"minor":0}],"required_capabilities":[]}'
ok
request run.create '{"objective":"Fixture DAG","owner_id":"owner","parent_run_id":null}'
ok
cp "$scratch/request" "$scratch/create"
cp "$scratch/response" "$scratch/created"
ok
jq -e --slurpfile old "$scratch/created" '.result==$old[0].result' "$scratch/response" >/dev/null
jq '.args.objective="conflicting retry"' "$scratch/request" > "$scratch/changed"
mv "$scratch/changed" "$scratch/request"
deny
# Same semantic operation with a new transport request ID still deduplicates.
cp "$scratch/create" "$scratch/request"
jq '.request_id="retry-transport" | .timeout_ms=29999' "$scratch/request" > "$scratch/changed"
mv "$scratch/changed" "$scratch/request"
ok
# Two identical writers both recover the same durable operation.
request task.create "$(jq -cn --arg d "$digest" '{run_id:"run-one",spec_ref:"spec/duplicate",spec_digest:$d,deps:[],gates:[]}')"
( set +e; loom_coordination_handle "$context" "$scratch/request" > "$scratch/r1" 2>"$scratch/e1"; echo $? > "$scratch/x1" ) & p1=$!
( set +e; loom_coordination_handle "$context" "$scratch/request" > "$scratch/r2" 2>"$scratch/e2"; echo $? > "$scratch/x2" ) & p2=$!
wait "$p1" "$p2"
[[ $(cat "$scratch/x1")$(cat "$scratch/x2") == 00 ]]
jq -e --slurpfile other "$scratch/r2" '.result==$other[0].result' "$scratch/r1" >/dev/null
printf 'PASS exact retry, concurrent dedupe and conflict\n'
request run.show '{"run_id":"run-one"}'
ok
actor=forged
request task.create "$(jq -cn --arg d "$digest" '{run_id:"run-one",spec_ref:"spec/task",spec_digest:$d,deps:[],gates:[]}')"
deny
actor=owner
epoch=1
request task.create "$(jq -cn --arg d "$digest" '{run_id:"run-one",spec_ref:"spec/task",spec_digest:$d,deps:[],gates:[]}')"
deny
epoch=0
task
a=$created
task "$(jq -cn --arg id "$a" '[{task_id:$id,policy:"accepted"}]')"
b=$created
[[ $(jq -r .result.state "$scratch/response") == pending ]]
request task.update "$(jq -cn --arg id "$b" '{task_id:$id,transition:"ready",evidence_refs:[]}')" 1
deny
request task.update "$(jq -cn --arg id "$a" '{task_id:$id,transition:"succeeded",evidence_refs:["mail/ack","ui/idle"]}')" 1
deny
request task.create "$(jq -cn --arg d "$digest" '{run_id:"run-one",spec_ref:"spec/task",spec_digest:$d,deps:[{task_id:"missing",policy:"accepted"}],gates:[]}')"
deny
# A self edge is a cycle and is refused atomically even with the deterministic ID.
key=$(_loom_coord_key "$scratch/request")
jq --arg id "coord-$key" '.args.deps[0].task_id=$id' "$scratch/request" > "$scratch/changed"
mv "$scratch/changed" "$scratch/request"
deny
run="run-two"
request run.create '{"objective":"Other run","owner_id":"owner","parent_run_id":null}'
ok
request task.create "$(jq -cn --arg id "$a" --arg d "$digest" '{run_id:"run-two",spec_ref:"spec/task",spec_digest:$d,deps:[{task_id:$id,policy:"accepted"}],gates:[]}')"
deny
run="run-one"
printf 'PASS actor/epoch fences, missing/self/cross-run dependencies, no implicit acceptance\n'
request gate.create "$(jq -cn --arg id "$a" '{task_id:$id,question:"Approve fixture?",resolver_id:"resolver",options:["approved","rejected"]}')"
ok
gate=$(jq -r .result.gate_id "$scratch/response")
plan "$a" attempt-one "$(rev task "$a")"
auth_deny
launch_proof
auth_deny
request gate.resolve "$(jq -cn --arg id "$gate" '{gate_id:$id,decision:"approved",evidence_ref:"decision/owner"}')" 1
cp "$scratch/request" "$scratch/resolve-one"
jq '.actor_id="intruder"' "$context" > "$scratch/intruder-context"
actor=intruder
request gate.resolve "$(jq -cn --arg id "$gate" '{gate_id:$id,decision:"approved",evidence_ref:"decision/forged"}')" 1
original_context=$context
context=$scratch/intruder-context
deny
context=$original_context
actor=resolver
jq '.actor_id="resolver"' "$context" > "$scratch/resolver-context"
request gate.resolve "$(jq -cn --arg id "$gate" '{gate_id:$id,decision:"rejected",evidence_ref:"decision/resolver"}')" 1
actor=owner
cp "$scratch/request" "$scratch/resolve-two"
( set +e; loom_coordination_handle "$context" "$scratch/resolve-one" > "$scratch/r1" 2>"$scratch/e1"; echo $? > "$scratch/x1" ) & p1=$!
( set +e; loom_coordination_handle "$scratch/resolver-context" "$scratch/resolve-two" > "$scratch/r2" 2>"$scratch/e2"; echo $? > "$scratch/x2" ) & p2=$!
wait "$p1" "$p2"
[[ $(cat "$scratch/x1")$(cat "$scratch/x2") == 02 || $(cat "$scratch/x1")$(cat "$scratch/x2") == 20 ]]
# Continue with a fresh ungated task regardless of the winning decision.
task
c=$created
task "$(jq -cn --arg id "$c" '[{task_id:$id,policy:"accepted"}]')"
accepted_child=$created
plan "$c" attempt-two 1
auth_deny
launch_proof
loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/authorization"
cp "$scratch/authorization" "$scratch/auth-first"
loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/authorization"
cmp "$scratch/auth-first" "$scratch/authorization"
jq -e '.launch_receipt.durable and .capacity_receipt.durable and (.launch_receipt.result|keys)==["actor","binding_digest","target"]' "$scratch/authorization" >/dev/null
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 1 ]]
# Running graph edits and forged readiness cannot enter via extra wire fields.
request task.update "$(jq -cn --arg id "$c" '{task_id:$id,transition:"running",evidence_refs:[],deps:[]}')" "$(rev task "$c")"
deny
request gate.create "$(jq -cn --arg id "$c" '{task_id:$id,question:"Pause for review",resolver_id:"owner",options:["approved","rejected"]}')"
ok
[[ $(loom_state_get task "$c" | jq -r .data.state) == waiting ]]
[[ $(loom_state_get attempt attempt-two | jq -r .data.execution_state) == reserved ]]
printf 'PASS simultaneous resolvers, unmet gates, forged authorization, durable S4 shape and replay\n'
# The owner cannot take over while any reserved/unknown intent remains.
runrev=$(rev run "$run")
jq --argjson rev "$runrev" '.claims=[{run_id:"run-one",expected_owner:"owner",expected_revision:$rev,epoch:0,reason:"explicit takeover"}]' "$context" > "$scratch/new-context"
mv "$scratch/new-context" "$context"
request run.claim '{"run_id":"run-one","expected_owner":"owner","reason":"explicit takeover"}' "$runrev"
deny
# Prove a ready report needs actual settlement and success needs exact checked tip.
crev=$(rev task "$c")
request task.update "$(jq -cn --arg id "$c" '{task_id:$id,transition:"review",evidence_refs:["report/current"]}')" "$crev"
deny
jq --arg task "$c" --argjson rev "$crev" '.proofs += [{kind:"harvest",run_id:"run-one",task_id:$task,revision:$rev,epoch:0,attempt_id:"attempt-two",evidence_ref:"report/current",confirmed_stopped:true,quiescent:true,current_report:true,report_state:"ready",report_digest:"git-blob-sha1-v1:1111111111111111111111111111111111111111",exit_code:0}]' "$context" > "$scratch/new-context"
mv "$scratch/new-context" "$context"
ok
crev=$(rev task "$c")
request task.update "$(jq -cn --arg id "$c" '{task_id:$id,transition:"succeeded",evidence_refs:["checks/accepted"]}')" "$crev"
deny
jq --arg task "$c" --argjson rev "$crev" --arg config "$(jq -r .config_digest "$scratch/pin")" '.proofs += [{kind:"accept",run_id:"run-one",task_id:$task,revision:$rev,epoch:0,attempt_id:"attempt-two",evidence_ref:"checks/accepted",reviewed:true,check_exit:0,checked_sha:"1111111111111111111111111111111111111111",collected_sha:"1111111111111111111111111111111111111111",current_sha:"2222222222222222222222222222222222222222",config_digest:$config,manifest_digest:"git-blob-sha1-v1:1111111111111111111111111111111111111111"}]' "$context" > "$scratch/new-context"
mv "$scratch/new-context" "$context"
deny
jq '.proofs |= map(if .kind=="accept" then .current_sha=.checked_sha else . end)' "$context" > "$scratch/new-context"
mv "$scratch/new-context" "$context"
ok
[[ $(loom_state_get task "$accepted_child" | jq -r .data.state) == ready ]]
# Acceptance doesn't free a global slot without separate exact process proof.
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 1 ]]
printf 'PASS running gate waiting, takeover uncertainty, report versus acceptance and moved-tip fence\n'

# Fresh actual store keeps the fault scenarios independent and bounded.
reset_store() {
    local name=$1
    LOOM_STATE=$scratch/$name
    mkdir "$LOOM_STATE"
    loom_state_init fixture-store >/dev/null
    loom_policy_capacity_init_request fixture-store owner > "$scratch/init"
    loom_state_transact "$scratch/init" >/dev/null
    jq --arg state "$LOOM_STATE" '.state_root=$state | .proofs=[] | .claims=[] | .actor_id="owner"' "$context" > "$scratch/new-context"
    mv "$scratch/new-context" "$context"
    run="run-one"; actor=owner; epoch=0
    request run.create '{"objective":"Fault fixtures","owner_id":"owner","parent_run_id":null}'
    ok
}
reset_store fault-state
task
f=$created
plan "$f" fault-attempt 1
launch_proof
rc=0
LOOM_COORDINATION_TESTING=1 LOOM_COORDINATION_TEST_FAIL=after_capacity \
    loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/partial" 2>"$scratch/error" || rc=$?
[[ $rc == 1 && ! -s $scratch/partial ]]
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 1 ]]
# A gate arriving after reservation invalidates launch but retains the capacity.
request gate.create "$(jq -cn --arg id "$f" '{task_id:$id,question:"New approval",resolver_id:"owner",options:["approved"]}')"
ok
auth_deny
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 1 ]]
# A changed key may not create another reservation for this task.
plan "$f" another-attempt "$(rev task "$f")"
launch_proof
auth_deny
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 1 ]]
printf 'PASS partial reservation failure retains capacity and prevents double allocation\n'

reset_store crash-state
task
f=$created
plan "$f" crash-attempt 1
launch_proof
rc=0
LOOM_COORDINATION_TESTING=1 LOOM_COORDINATION_TEST_CRASH=after_capacity \
    loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/crashed" 2>"$scratch/error" || rc=$?
[[ $rc == 137 && ! -s $scratch/crashed ]]
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 1 ]]
loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/authorization"
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 1 ]]
# Crash after journal rename loses acknowledgement; exact wire replay recovers it.
request task.create "$(jq -cn --arg d "$digest" '{run_id:"run-one",spec_ref:"spec/crash",spec_digest:$d,deps:[],gates:[]}')"
rc=0
LOOM_STATE_TESTING=1 LOOM_STATE_TEST_CRASH=journal.after_rename \
    loom_coordination_handle "$context" "$scratch/request" > "$scratch/crashed" 2>"$scratch/error" || rc=$?
# The handler can immediately reconcile the renamed journal transaction.
[[ $rc == 0 ]]
jq -e '.ok and .durable' "$scratch/crashed" >/dev/null
ok
printf 'PASS capacity crash replay and S2 journal crash recovery\n'

reset_store claims-state
runrev=$(rev run "$run")
for who in claimant-one claimant-two; do
    jq --arg actor "$who" --argjson rev "$runrev" '.actor_id=$actor | .claims=[{run_id:"run-one",expected_owner:"owner",expected_revision:$rev,epoch:0,reason:"authorized takeover"}]' "$context" > "$scratch/$who-context"
    actor=$who
    request run.claim '{"run_id":"run-one","expected_owner":"owner","reason":"authorized takeover"}' "$runrev"
    cp "$scratch/request" "$scratch/$who-request"
done
( set +e; loom_coordination_handle "$scratch/claimant-one-context" "$scratch/claimant-one-request" > "$scratch/r1" 2>"$scratch/e1"; echo $? > "$scratch/x1" ) & p1=$!
( set +e; loom_coordination_handle "$scratch/claimant-two-context" "$scratch/claimant-two-request" > "$scratch/r2" 2>"$scratch/e2"; echo $? > "$scratch/x2" ) & p2=$!
wait "$p1" "$p2"
[[ $(cat "$scratch/x1")$(cat "$scratch/x2") == 02 || $(cat "$scratch/x1")$(cat "$scratch/x2") == 20 ]]
[[ $(loom_state_get run run-one | jq .epoch) == 1 ]]
actor=owner
request task.create "$(jq -cn --arg d "$digest" '{run_id:"run-one",spec_ref:"spec/stale",spec_digest:$d,deps:[],gates:[]}')"
deny
printf 'PASS simultaneous claims and stale owner after epoch change\n'


reset_store continuation-state
task
parent=$created
task "$(jq -cn --arg id "$parent" '[{task_id:$id,policy:"settled"}]')"
dependent=$created
plan "$parent" parent-attempt 1
launch_proof
loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/authorization"
prev=$(rev task "$parent")
jq --arg id "$parent" --argjson revision "$prev" '.proofs += [{kind:"settlement",run_id:"run-one",task_id:$id,revision:$revision,epoch:0,attempt_id:"parent-attempt",evidence_ref:"exit/failed",confirmed_stopped:true,quiescent:true}]' "$context" > "$scratch/new-context"
mv "$scratch/new-context" "$context"
request task.update "$(jq -cn --arg id "$parent" '{task_id:$id,transition:"failed",evidence_refs:["exit/failed"]}')" "$prev"
ok
[[ $(loom_state_get task "$dependent" | jq -r .data.state) == pending ]]
request task.update "$(jq -cn --arg id "$dependent" '{task_id:$id,transition:"ready",evidence_refs:[]}')" 1
deny
prev=$(rev task "$parent")
request task.continue "$(jq -cn --arg id "$parent" --arg d "$digest" '{task_id:$id,parent_attempt_id:"parent-attempt",placement_digest:$d,message_ids:[],reason:"retry after failure"}')" "$prev"
deny
scope=$(loom_policy_scope < "$scratch/pin")
request task.continue "$(jq -cn --arg id "$parent" --arg d "$scope" '{task_id:$id,parent_attempt_id:"parent-attempt",placement_digest:$d,message_ids:[],reason:"retry after failure"}')" "$prev"
ok
next=$(jq -r .result.attempt_id "$scratch/response")
ok
[[ $(jq -r .result.attempt_id "$scratch/response") == "$next" ]]
[[ $(loom_state_get attempt parent-attempt | jq -r .data.execution_state) == exited ]]
[[ $(loom_state_get task "$dependent" | jq -r .data.state) == pending ]]
plan "$parent" "$next" "$(rev task "$parent")"
launch_proof
loom_coordination_authorize "$context" "$scratch/plan" > "$scratch/authorization"
[[ $(loom_state_get attempt "$next" | jq -r .data.parent_attempt_id) == parent-attempt ]]
[[ $(loom_state_get task "$parent" | jq -r '.data.attempt_ids[-1]') == "$next" ]]
[[ $(loom_policy_capacity "$scratch/config" "$scratch/hosts" "$scratch/profiles" | jq .occupied) == 2 ]]
printf 'PASS failed prerequisite, explicit continuation, pinned placement and retained parent capacity\n'
request task.list '{"run_id":"run-one","limit":100}'
loom_coordination_serve "$context" < "$scratch/request" > "$scratch/response"
jq -e '.result.items|length==2' "$scratch/response" >/dev/null
printf 'PASS source-safe serve and bounded list\n'

# Source-safe API leaves caller shell state unchanged.
( before=$(set +o); opts=$-; traps=$(trap -p); mask=$(umask); directory=$PWD
  source "$root/ops/coordination.sh"
  [[ $(set +o) == "$before" && $- == "$opts" && $(trap -p) == "$traps" && $(umask) == "$mask" && $PWD == "$directory" ]] )
printf 'PASS source-safe coordination API\n'
