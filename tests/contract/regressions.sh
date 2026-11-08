#!/usr/bin/env bash
# Architect review regressions; invoked by run.sh in its existing fixture context.
# shellcheck disable=SC1091
source ops/protocol.sh
: "${work:?run through tests/contract/run.sh}"
printf 'contract: architecture review regressions\n'
pair() { fixture "$1" > "$work/pair-request"; fixture "$1" response > "$work/pair-response"; }
reject_pair() { invalid response "$work/pair-response" "$work/pair-request"; }
for spec in 'workspace.prepare|.result.workspace_id="wrong"' 'workspace.prepare|.result.host_id="wrong"' 'workspace.prepare|.result.base_sha=("2"*40)' 'workspace.prepare|.result.manifest_digest=("git-blob-sha1-v1:"+("2"*40))' 'workspace.export|.result.bytes=65537' 'workspace.export|.result.sha=("2"*40)' 'task.show|.result.task_id="wrong"' 'run.show|.result.run_id="wrong"' 'mail.read|.result.delivery.delivery_id="wrong"' 'mail.read|.result.message.message_id="wrong"' 'mail.read|.result.delivery.recipient="task:wrong"' 'mail.ack|.result.message_digest=("git-blob-sha1-v1:"+("2"*40))' 'execution.stop|.result.requested_signals=["KILL"]'; do
    pair "${spec%%|*}"
    jq "${spec#*|}" "$work/pair-response" > "$work/new"; mv "$work/new" "$work/pair-response"
    reject_pair
done
identity='{"kind":"provider","provider_id":"example","resource_id":"example","attempt_id":"wrong","host_id":"wrong","binding_digest":"git-blob-sha1-v1:1111111111111111111111111111111111111111"}'
pair execution.reconcile
jq --argjson identity "$identity" '.result.observation.identity=$identity | .result.observation.identity_verified=true' "$work/pair-response" > "$work/new"; mv "$work/new" "$work/pair-response"; reject_pair
for op in execution.list watch; do
    pair "$op"
    fixture execution.inspect response | jq --argjson identity "$identity" '.result | .identity=$identity | .identity_verified=true' > "$work/observation"
    node=items; [[ $op != watch ]] || node=observations
    jq --slurpfile observation "$work/observation" --arg node "$node" '.result[$node]=$observation' "$work/pair-response" > "$work/new"; mv "$work/new" "$work/pair-response"; reject_pair
done
pair execution.inspect
jq '.result.state="start_failed" | .result.resources=[{ref:"example",state:"owned"}]' "$work/pair-response" > "$work/new"; mv "$work/new" "$work/pair-response"
valid response "$work/pair-response" "$work/pair-request"
jq '.result.terminal={exit_code:0,signal:null,captured:true,evidence:[]}' "$work/pair-response" > "$work/bad"; invalid response "$work/bad" "$work/pair-request"
for state in waiting review succeeded; do
    pair task.show
    jq --arg state "$state" '.result.state=$state' "$work/pair-response" > "$work/new"; mv "$work/new" "$work/pair-response"
    valid response "$work/pair-response" "$work/pair-request"
done
pair execution.inspect
jq '.observed_at="2026-02-31T00:00:00Z"' "$work/pair-response" > "$work/bad"; invalid response "$work/bad"
for mode in extensions_full padded; do
    configure "$mode"; invoke 1
    jq -e '.status=="unknown" and .extensions["loom.transport"].exit_code==0' "$work/output" >/dev/null || fail "$mode normalized output"
done
configure deep_hello; invoke 0
configure effectful_hello; invoke 2
[[ $(cat "$work/invocations") == hello ]] || fail effectful-hello-started
jq -e '.extensions["loom.negotiation"].reported_effects[0].resource=="example"' "$work/output" >/dev/null || fail missing-preflight-effects
for spec in 'low_read|execution.read' 'low_list|hosts.list' 'low_cap|execution.start'; do
    configure "${spec%%|*}"
    fixture "${spec#*|}" > "$work/limited-request"
    if [[ ${spec%%|*} == low_list ]]; then jq '.args.limit=2' "$work/limited-request" > "$work/new"; mv "$work/new" "$work/limited-request"; fi
    invoke 2 "$work/limited-request"
    [[ $(cat "$work/invocations") == hello ]] || fail negotiated-limit-invoked
    jq -e '.error.code=="quota_exceeded"' "$work/output" >/dev/null || fail negotiated-limit-reason
done
configure ok
jq '.limits.metadata_bytes=1' "$work/config" > "$work/new"; mv "$work/new" "$work/config"
invoke 2; [[ ! -s $work/invocations ]] || fail metadata-limit-invoked
configure ok
jq '.capabilities|=map(.limits.max_bytes=1)' "$work/config" > "$work/new"; mv "$work/new" "$work/config"
invoke 2; [[ ! -s $work/invocations ]] || fail pinned-capability-limit-invoked
# The portable case runner accepts a pinned adapter/config and fixture cases.
configure ok
jq -s '[{request:.[0],exit:0,status:"completed",error_code:null}]' "$work/request" > "$work/cases"
bash tests/contract/conformance.sh "$work/config" "$(loom_protocol_digest "$work/config")" "$work/cases"
pass
