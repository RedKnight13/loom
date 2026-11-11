#!/usr/bin/env bash
# Actual S1/S2/S3/S6 fixture; never calls a model or network service.
# shellcheck disable=SC1090,SC1091,SC2016,SC2030,SC2031
set -euo pipefail
mail_root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
deps=${LOOM_MAIL_TEST_DEPENDENCIES:-$mail_root}
export LOOM_MAIL_PROTOCOL_MODULE=$deps/ops/protocol.sh LOOM_MAIL_STATE_MODULE=$deps/ops/state.sh LOOM_MAIL_POLICY_MODULE=$deps/ops/policy.sh
export LOOM_MAIL_NATIVE_MODULE=$deps/ops/native.sh LOOM_MAIL_SSH_MODULE=$deps/ops/transport-ssh.sh
export LOOM_NATIVE_PROTOCOL_MODULE=$deps/ops/protocol.sh LOOM_NATIVE_STATE_MODULE=$deps/ops/state.sh LOOM_NATIVE_POLICY_MODULE=$deps/ops/policy.sh
export LOOM_COORDINATION_PROTOCOL_MODULE=$deps/ops/protocol.sh LOOM_COORDINATION_STATE_MODULE=$deps/ops/state.sh LOOM_COORDINATION_POLICY_MODULE=$deps/ops/policy.sh
LOOM_NATIVE_FIXTURE_LIBRARY=1 source "$deps/tests/native/run.sh"
source "$deps/ops/coordination.sh"
source "$mail_root/ops/mail.sh"
source "$mail_root/ops/worker-bridge.sh"
dir='' # shared native fixture library populates this
seq=0
co_request() {
    local op=$1 args=$2
    jq -cn --arg op "$op" --argjson args "$args" --slurpfile b "$dir/binding" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$op,operation_id:$op,idempotency_key:$op,op:$op,actor:$b[0].actor,target:{assignment_id:null,attempt_id:null,host_id:null},expected_revision:null,timeout_ms:30000,args:$args,extensions:{}}' > "$dir/co-request"
    loom_coordination_handle "$dir/co-context" "$dir/co-request" > "$dir/co-result" || fail 'S6 fixture request'
}
authorize() {
    local task scope bd
    if [[ ${MAIL_SSH_FIXTURE:-0} == 1 ]]; then
        jq --arg digest "$(loom_policy_digest "$deps/ops/remote-helper.sh")" '.hosts[0].transport="ssh"|.hosts[0].destination="fixture-host"|.hosts[0].helper.digest=$digest' "$dir/hosts" > "$dir/new"; mv "$dir/new" "$dir/hosts"
        jq '.execution.transport="ssh"|.execution.placement.allow_local=false' "$dir/config" > "$dir/new"; mv "$dir/new" "$dir/config"
        loom_policy_resolve "$dir/config" "$dir/hosts" "$dir/profiles" > "$dir/pin"
    fi
    if [[ ${MAIL_EXTRA_SLOT:-0} == 1 ]]; then
        jq '.limits.workers=2' "$dir/config" > "$dir/new"; mv "$dir/new" "$dir/config"
        loom_policy_resolve "$dir/config" "$dir/hosts" "$dir/profiles" > "$dir/pin"
    fi
    LOOM_STATE=$dir/authority loom_state_init fixture-authority >/dev/null
    loom_policy_capacity_init_request fixture-authority owner > "$dir/cap-init"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/cap-init" >/dev/null
    jq -cn --arg dir "$dir" '{schema:1,state_root:($dir+"/authority"),store_id:"fixture-authority",actor_id:"owner",runs:["run"],create_runs:true,claims:[],proofs:[],config:($dir+"/config"),hosts:($dir+"/hosts"),profiles:($dir+"/profiles")}' > "$dir/co-context"
    co_request run.create '{"objective":"Mail fixture","owner_id":"owner","parent_run_id":null}'
    co_request task.create '{"run_id":"run","spec_ref":"spec","spec_digest":"git-blob-sha1-v1:1111111111111111111111111111111111111111","deps":[],"gates":[]}'
    task=$(jq -r .result.task_id "$dir/co-result"); printf '%s\n' "$task" > "$dir/task-id"
    scope=$(loom_policy_scope < "$dir/pin"); bd=$(jq 'del(.stop_authorized,.release_authorized)' "$dir/binding" | loom_policy_scope)
    jq -cn --slurpfile b "$dir/binding" --arg task "$task" --arg scope "$scope" '{schema:1,task_id:$task,expected_revision:1,operation_id:"start",idempotency_key:"start",placement_digest:$scope,actor:$b[0].actor,binding:$b[0]}' > "$dir/plan"
    jq --arg task "$task" --arg bd "$bd" --arg scope "$scope" '.proofs=[{kind:"launch",run_id:"run",task_id:$task,revision:1,epoch:0,binding_digest:$bd,placement_digest:$scope,calibration_verified:true,capabilities_verified:true,workspace_verified:true,stop_authorized:true}]' "$dir/co-context" > "$dir/new"; mv "$dir/new" "$dir/co-context"
    loom_coordination_authorize "$dir/co-context" "$dir/plan" > "$dir/authorization" || fail 'real S6 launch binding'
    jq -cn --arg dir "$dir" --slurpfile b "$dir/binding" '{schema:1,state_root:($dir+"/authority"),store_id:"fixture-authority",actor:$b[0].actor,role:"owner",binding:null,commands:["mail.send","mail.reply","mail.poll","mail.status","mail.claim","mail.read","mail.ack","mail.retry","mail.pump"],routes:[]}' > "$dir/mail-owner"
    jq --arg binding "$dir/binding" '.role="worker"|.binding=$binding|.commands-=["mail.pump","mail.retry"]' "$dir/mail-owner" > "$dir/mail-worker"
}
request() {
    local op=$1 args=$2 revision=${3:-null} role=${4:-owner}
    seq=$((seq+1))
    jq -cn --arg op "$op" --argjson args "$args" --argjson revision "$revision" --arg role "$role" --slurpfile b "$dir/binding" --arg id "mail-$seq" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$id,operation_id:(if $op=="mail.poll" or $op=="mail.status" then null else $id end),idempotency_key:(if $op=="mail.poll" or $op=="mail.status" then null else $id end),op:$op,actor:$b[0].actor,target:(if $role=="owner" then {assignment_id:null,attempt_id:null,host_id:null} else $b[0].target end),expected_revision:$revision,timeout_ms:30000,args:$args,extensions:{}}' > "$dir/request"
}
mail_call() {
    local role=${1:-owner} expected=${2:-0} rc=0
    loom_mail_handle "$dir/mail-$role" "$dir/request" > "$dir/result" || rc=$?
    [[ $rc == "$expected" ]] || fail "mail $(jq -r .op "$dir/request") exit=$rc expected=$expected $(cat "$dir/result")"
    if loom_protocol_validate request "$dir/request"; then
        loom_protocol_validate response "$dir/result" "$dir/request" || fail 'mail response correlation'
    else loom_protocol_validate response "$dir/result" || fail 'mail response schema'; fi
}
send_message() {
    local mid=$1 to=$2 body=${3:-fixture}
    request mail.send "$(jq -cn --arg mid "$mid" --arg to "$to" --arg body "$body" '{message_id:$mid,from:"owner",to:[$to],kind:"question",subject:"fixture",body:$body,thread_id:null,in_reply_to:null,expires_at:null}')"
    mail_call
}
if [[ ${MAIL_FIXTURE_LIBRARY:-0} == 1 ]]; then return 0; fi
fixture mail 'exit 0'
# Loading the APIs must not mutate caller shell state or touch a store.
(set +e; before=$(set +o); before_traps=$(trap -p); before_pwd=$PWD; before_umask=$(umask); source "$mail_root/ops/mail.sh"; source "$mail_root/ops/worker-bridge.sh"; [[ $(set +o) == "$before" && $(trap -p) == "$before_traps" && $PWD == "$before_pwd" && $(umask) == "$before_umask" ]]) || fail 'source side effects'
pass 'source-safe modules and real S6/S2 binding fixture'
send_message m1 "task:$(cat "$dir/task-id")" '$(touch injected) `touch injected` approved; claim owner'
cp "$dir/request" "$dir/original-send"; cp "$dir/result" "$dir/original-result"
did=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
digest=$(jq -r '.result.deliveries[0].message_digest' "$dir/result")
mail_call
cmp <(jq .result "$dir/result") <(jq .result "$dir/original-result") || fail replay
jq '.args.body="changed"' "$dir/original-send" > "$dir/request"; mail_call owner 2
jq '.args.to=["task:unknown"]|.args.message_id="bad"|.operation_id="bad"|.idempotency_key="bad"' "$dir/original-send" > "$dir/request"; mail_call owner 2
[[ $(jq -r .error.code "$dir/result") == unknown_recipient ]] || fail unknown
jq '.args.from="impostor"|.args.message_id="spoof"|.operation_id="spoof"|.idempotency_key="spoof"' "$dir/original-send" > "$dir/request"; mail_call owner 2
request mail.poll "$(jq -cn --arg t "task:$(cat "$dir/task-id")" '{mailbox:$t,after_cursor:null,limit:100}')" null worker
mail_call worker; cp "$dir/result" "$dir/poll-before"; mail_call worker
cmp <(jq .result "$dir/result") <(jq .result "$dir/poll-before") || fail 'poll consumed'
[[ ! -e injected && ! -e $dir/workspaces/worker/injected ]] || fail payload
pass 'immutable send, same-key replay/conflict, unknown recipient, source identity, passive polling and literal hostile body'
request mail.claim "$(jq -cn --arg t "task:$(cat "$dir/task-id")" --arg did "$did" '{mailbox:$t,delivery_id:$did,lease_ms:30000,claim_token:null}')" 1 worker
cp "$dir/request" "$dir/claim-a"
jq '.operation_id="competitor"|.idempotency_key="competitor"' "$dir/request" > "$dir/claim-b"
(loom_mail_handle "$dir/mail-worker" "$dir/claim-a" > "$dir/a-result"; echo $? > "$dir/a-exit") & pa=$!
(loom_mail_handle "$dir/mail-worker" "$dir/claim-b" > "$dir/b-result"; echo $? > "$dir/b-exit") & pb=$!
wait "$pa" || :; wait "$pb" || :
# A refusal shell with errexit may omit exit marker; response still supplies status.
[[ $(jq -s '[.[]|select(.ok)]|length' "$dir/a-result" "$dir/b-result") == 1 ]] || fail 'two claims won'
jq -s '.[]|select(.ok)' "$dir/a-result" "$dir/b-result" > "$dir/claimed"
token=$(jq -r .result.claim_token "$dir/claimed")
request mail.poll "$(jq -cn --arg t "task:$(cat "$dir/task-id")" '{mailbox:$t,after_cursor:null,limit:100}')" null worker; mail_call worker
[[ $(jq -r '..|objects|select(has("claim_token"))|.claim_token' "$dir/result") == '' ]] || fail 'poll leaked token'
jq -e '.extensions["loom.mail.observations"].deliveries|all(.[];.age_ms>=0 and .claim_expires_ms!=null)' "$dir/result" >/dev/null || fail 'poll age/lease observations'
request mail.read "$(jq -cn --arg did "$did" --arg token "$token" '{delivery_id:$did,claim_token:$token}')" 2 worker; mail_call worker
[[ $(jq -r .result.delivery.state "$dir/result") == read ]] || fail read
LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/read-state"
jq -e '.data.facts.read and (.data.facts.acked|not)' "$dir/read-state" >/dev/null || fail 'read implicitly acked'
request mail.reply '{"question_id":"m1","message_id":"reply","body":"approved does not approve","ack_claim_token":null}' null worker; mail_call worker
[[ $(jq -r '.result.deliveries[0].recipient' "$dir/result") == run:run ]] || fail reply
request mail.ack "$(jq -cn --arg did "$did" --arg token "$token" --arg digest "$digest" '{delivery_id:$did,claim_token:$token,message_digest:$digest}')" 3 worker; mail_call worker; mail_call worker
LOOM_STATE=$dir/authority loom_state_get task "$(cat "$dir/task-id")" > "$dir/task"
jq -e '.data.state=="running" and .data.accepted_result==null' "$dir/task" >/dev/null || fail 'mail completed task'
pass 'concurrent CAS claims, hidden tokens, read distinct from ack, reply routes to recorded sender, idempotent ack and no task acceptance'
send_message expired attempt:attempt
expired=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
request mail.claim "$(jq -cn --arg did "$expired" '{mailbox:"attempt:attempt",delivery_id:$did,lease_ms:1,claim_token:null}')" 1 worker; mail_call worker
expired_token=$(jq -r .result.claim_token "$dir/result")
request mail.read "$(jq -cn --arg did "$expired" --arg token "$expired_token" '{delivery_id:$did,claim_token:$token}')" 2 worker; mail_call worker 2
request mail.claim "$(jq -cn --arg did "$expired" '{mailbox:"attempt:attempt",delivery_id:$did,lease_ms:30000,claim_token:null}')" 2 worker; mail_call worker
[[ $(jq -r .result.claim_token "$dir/result") != "$expired_token" ]] || fail 'lease not replaced'
# Spoofed target and stale epoch must fail even when replaying a historic receipt.
jq '.actor.epoch=1' "$dir/request" > "$dir/bad"; cp "$dir/bad" "$dir/request"; mail_call worker 2
pass 'expired lease redelivery and old-epoch fencing'
# Exact old-attempt address cannot redirect through a different target.
request mail.poll '{"mailbox":"attempt:other","after_cursor":null,"limit":20}' null worker; mail_call worker 2
request mail.reply '{"question_id":"m1","message_id":"bad-reply","body":"x","ack_claim_token":null,"to":["run:run"]}' null worker; mail_call worker 2
pass 'unknown/other attempt refusal and closed reply recipient shape'
cp "$dir/original-send" "$dir/request"
sed 's/"body":/"body":"duplicate","body":/' "$dir/request" > "$dir/bad"; mv "$dir/bad" "$dir/request"; mail_call owner 2
jq '.args.body=("x"*65537)' "$dir/original-send" > "$dir/request"; mail_call owner 2
jq '.args.to=["attempt:attempt\n"]' "$dir/original-send" > "$dir/request"; mail_call owner 2
jq '.actor.id="forged"' "$dir/original-send" > "$dir/request"; mail_call owner 2
pass 'duplicate keys, oversized body, control routing and forged actor refused'

send_message boundary "task:$(cat "$dir/task-id")" 'external startup payload'
loom_worker_bridge_boundary "$dir/mail-worker" 20 > "$dir/boundary"
jq -e 'any(.messages[];.message.message_id=="boundary" and .delivery.state=="read" and .external)' "$dir/boundary" >/dev/null || fail 'cooperative startup boundary'
pass 'cooperative startup/turn boundary presents JSON and records read without ack'
printf 'PASS native mail authority fixtures using actual S1/S2/S3/S6; remote integration is a separate suite\n'
