#!/usr/bin/env bash
# Deterministic SSH transport invoking the actual installed helper and processes.
# shellcheck disable=SC1090,SC1091,SC2016,SC2030,SC2031,SC2154
set -euo pipefail
root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
umask 077
if [[ ${1:-} != --staged ]]; then
    runtime=$(mktemp -d)
    trap 'if [[ ${LOOM_ARTIFACT_KEEP_RUNTIME:-0} == 1 ]]; then printf "retained runtime: %s\n" "$runtime" >&2; else rm -rf -- "$runtime"; fi' EXIT
    mkdir -p "$runtime/ops" "$runtime/tests/ssh" "$runtime/tests/conformance"
    cp "$root"/ops/* "$runtime/ops/"
    cp -R "$root/schemas" "$runtime/"
    cp "$root/VERSION" "$runtime/"
    mkdir "$runtime/old"
    git -C "$root" archive 1be27207d420b1f59dc0aff6d9fd12f251efd63c ops schemas | tar -x -C "$runtime/old"
    chmod -R go-rwx "$runtime/old"
    mail_source=${LOOM_CONFORMANCE_MAIL_ROOT:-$root}
    cp "$mail_source/ops/mail.sh" "$mail_source/ops/worker-bridge.sh" "$runtime/ops/"
    cp "$root/tests/ssh/run.sh" "$runtime/tests/ssh/"
    cp "$0" "$runtime/tests/conformance/remote-artifacts.sh"
    export LOOM_CONFORMANCE_RUNTIME=$runtime LOOM_SSH_FIXTURES_APPROVED=1
    export LOOM_ARTIFACT_EVIDENCE=${LOOM_ARTIFACT_EVIDENCE:-$root/.loom/artifacts}
    mkdir -p "$LOOM_ARTIFACT_EVIDENCE"
    (cd "$runtime" && sha256sum ops/* schemas/*/*) > "$LOOM_ARTIFACT_EVIDENCE/runtime.sha256"
    bash "$runtime/tests/conformance/remote-artifacts.sh" --staged
    exit
fi
runtime=$LOOM_CONFORMANCE_RUNTIME
LOOM_SSH_FIXTURE_LIBRARY=1 source "$runtime/tests/ssh/run.sh"
source "$runtime/ops/coordination.sh"
source "$runtime/ops/workflow.sh"
fixture bootstrap
# No launch receipt and no workspace at the first usable preparation install.
mv "$dir/authorization" "$dir/original-fixture-authorization"
printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf accepted > result.txt\nprintf "state: ready — remote fixture\\n" >> REPORT.md\nprintf "remote output\\n"\n' > "$dir/worker"
printf 'test "$(cat result.txt)" = accepted\nprintf x >> %q\n(sleep 0.2; printf child > child-result) &\nexit 0\n' "$dir/check-count" > "$dir/check-script"
case ${LOOM_ARTIFACT_CASE:-success} in
    worker-failed) : ;;
    worker-report-failed) sed -i 's/state: ready/state: failed/' "$dir/worker" ;;
    check-nonzero) printf 'printf x >> %q\nexit 7\n' "$dir/check-count" > "$dir/check-script" ;;
    check-timeout) printf 'printf x >> %q\ntrap "" TERM\nwhile :; do sleep 0.1; done\n' "$dir/check-count" > "$dir/check-script" ;;
esac
# One task message is queued before launch. This does not test/clear the separately
# reported multi-message fairness defect.
cat >> "$dir/worker" <<'WORKER_MAIL'
jq -e '.messages|any(.message.message_id=="startup" and .delivery.state=="read")' "$LOOM_STARTUP_MAIL_FILE" >/dev/null || exit 31
WORKER_MAIL
if [[ ${LOOM_ARTIFACT_CASE:-success} == worker-failed ]]; then printf 'exit 7\n' >> "$dir/worker"; fi
jq -cn --arg sha "$(cat "$dir/base")" --arg digest "$(loom_policy_digest "$dir/check-script")" '{schema:1,base_sha:$sha,check_digest:$digest,report_offset:0}' > "$dir/manifest"
jq --arg md "$(loom_policy_digest "$dir/manifest")" --arg ed "$(loom_policy_digest "$dir/worker")" '.manifest_digest=$md|.executable_digest=$ed' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
jq --arg md "$(loom_policy_digest "$dir/manifest")" '.args.manifest_digest=$md' "$dir/prepare" > "$dir/new"; mv "$dir/new" "$dir/prepare"
jq --arg md "$(loom_policy_digest "$dir/manifest")" '.args.manifest_digest=$md' "$dir/start" > "$dir/new"; mv "$dir/new" "$dir/start"
jq '.authority_store_id="workflow-authority"' "$dir/context" > "$dir/new"; mv "$dir/new" "$dir/context"
jq -cn --slurpfile b "$dir/binding" --arg sha "$(cat "$dir/base")" '{schema:1,actor:$b[0].actor,target:$b[0].target,base_sha:$sha,manifest_digest:$b[0].manifest_digest}' > "$dir/context.prepare"
jq -cn --arg dir "$dir" --arg check "$(loom_policy_digest "$dir/check-script")" --arg interpreter "$(loom_policy_digest /usr/bin/bash)" '{schema:1,manifest:($dir+"/manifest"),check_script:($dir+"/check-script"),check_digest:$check,interpreter_digest:$interpreter,seal_authorized:true,check_authorized:true,allow_kill:true,output_bytes:65536,check_timeout_ms:5000,artifact_bytes:1048576,max_files:100,max_worktree_bytes:1048576,author_name:"Loom Fixture",author_email:"fixture@example.invalid"}' > "$dir/context.workflow"
jq --slurpfile q "$dir/prepare" '.workflow_access="owner"|.contexts={attempt:.contexts.fixture}|.contexts.attempt.prepare.args=$q[0].args' "$dir/install-config" > "$dir/new"; mv "$dir/new" "$dir/install-config"
jq '.context_id="attempt"' "$dir/client" > "$dir/new"; mv "$dir/new" "$dir/client"
if [[ ${LOOM_ARTIFACT_CASE:-success} == check-timeout ]]; then
    jq '.check_timeout_ms=300' "$dir/context.workflow" > "$dir/new"; mv "$dir/new" "$dir/context.workflow"
fi
install_route() {
    local version=$1
    bash "$runtime/ops/remote-helper.sh" install "$dir/install-config" "$dir/installations/$version" > "$dir/install-result"
    bash "$runtime/ops/remote-helper.sh" identity "$dir/installations/$version" "$(jq -r .context_id "$dir/client")" > "$dir/identity"
    jq --arg helper "$dir/installations/$version/remote-helper.sh" --slurpfile identity "$dir/identity" '.helper_command=$helper|.identity=$identity[0]' "$dir/client" > "$dir/new"; mv "$dir/new" "$dir/client"
}
install_route preparation
loom_ssh_preflight "$dir/client" > "$dir/preflight"
jq '.op="hello"|.operation_id=null|.idempotency_key=null|.args={versions:[{major:1,minor:0}],required_capabilities:["workspace.prepare.v1"]}' "$dir/start" > "$dir/hello"
call "$dir/hello"
jq -e '[.result.capabilities[].name]==["workspace.prepare.v1"]' "$dir/result" >/dev/null || fail 'preparation advertised execution'
jq '.args.required_capabilities=["execution.start.v1"]' "$dir/hello" > "$dir/prepare-execution-hello"
call "$dir/prepare-execution-hello" 2
call "$dir/start" 2
[[ ! -d $dir/workspaces/worker ]] || fail 'preparation-only launched'
loom_ssh_upload "$dir/client" "$dir/input.bundle" "$(loom_policy_digest "$dir/input.bundle")" > "$dir/upload"
FAULT=after call "$dir/prepare" 1
call "$dir/prepare"
jq -e '.result.disposition=="existing"' "$dir/result" >/dev/null || fail 'prepare lost-reply replay'
[[ $(git -C "$dir/workspaces/worker" rev-parse HEAD) == "$(cat "$dir/base")" && ! -e $dir/authorization ]] || fail 'prepare bootstrap order'
cp "$dir/client" "$dir/preparation-client"
pass 'fresh hello/upload/prepare without launch authorization; start refused; lost preparation reply replayed'

mkdir "$dir/authority2"
LOOM_STATE=$dir/authority2 loom_state_init workflow-authority > "$dir/authority-init"
loom_policy_capacity_init_request workflow-authority owner > "$dir/cap2"
LOOM_STATE=$dir/authority2 loom_state_transact "$dir/cap2" > "$dir/cap2-receipt"
jq -cn --arg dir "$dir" '{schema:1,state_root:($dir+"/authority2"),store_id:"workflow-authority",actor_id:"owner",runs:["run"],create_runs:true,claims:[],proofs:[],config:($dir+"/config"),hosts:($dir+"/hosts"),profiles:($dir+"/profiles")}' > "$dir/co-context"
co() {
    local op=$1 args=$2
    jq -cn --arg op "$op" --argjson args "$args" --slurpfile b "$dir/binding" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$op,operation_id:$op,idempotency_key:$op,op:$op,actor:$b[0].actor,target:{assignment_id:null,attempt_id:null,host_id:null},expected_revision:null,timeout_ms:30000,args:$args,extensions:{}}' > "$dir/co-request"
    LOOM_STATE=$dir/authority2 bash "$runtime/ops/loom" "${op%%.*}" --context "$dir/co-context" --request "$dir/co-request" --protocol 1 > "$dir/co-result"
}
co run.create '{"objective":"Remote artifact fixture","owner_id":"owner","parent_run_id":null}'
co task.create '{"run_id":"run","spec_ref":"fixture","spec_digest":"git-blob-sha1-v1:1111111111111111111111111111111111111111","deps":[],"gates":[]}'
task=$(jq -r .result.task_id "$dir/co-result")
scope=$(loom_policy_scope < "$dir/pin"); bd=$(jq 'del(.stop_authorized,.release_authorized)' "$dir/binding" | loom_policy_scope)
jq -cn --slurpfile b "$dir/binding" --arg task "$task" --arg scope "$scope" '{schema:1,task_id:$task,expected_revision:1,operation_id:"start",idempotency_key:"start",placement_digest:$scope,actor:$b[0].actor,binding:$b[0]}' > "$dir/plan"
# Capability and workspace receipts above are real; calibration here remains
# synthetic trusted provisioning for a fixture executable, never a real model.
jq --arg task "$task" --arg bd "$bd" --arg scope "$scope" '.proofs=[{kind:"launch",run_id:"run",task_id:$task,revision:1,epoch:0,binding_digest:$bd,placement_digest:$scope,calibration_verified:true,capabilities_verified:true,workspace_verified:true,stop_authorized:true}]' "$dir/co-context" > "$dir/new"; mv "$dir/new" "$dir/co-context"
loom_coordination_authorize "$dir/co-context" "$dir/plan" > "$dir/authorization"
# Adding final S6 authorization changes identity: old preparation pins fail.
rc=0; loom_ssh_preflight "$dir/preparation-client" > "$dir/old-pin" || rc=$?
[[ $rc != 0 ]] || fail 'preparation pin silently acquired execution'
jq -cn --arg context "$dir/context" --arg cd "$(loom_policy_digest "$dir/context")" --arg bridge "$runtime/ops/worker-bridge.sh" --arg bd "$(loom_policy_digest "$runtime/ops/worker-bridge.sh")" '{schema:1,context:$context,context_digest:$cd,bridge:$bridge,bridge_digest:$bd}' > "$dir/context.mail"
install_route execution
jq '.args.required_capabilities=["workspace.seal.v1","workspace.check.v1","workspace.export.v1","workspace.read.v1"]' "$dir/hello" > "$dir/artifact-hello"
call "$dir/artifact-hello"
[[ $(jq '[.result.capabilities[]|select(.name|IN("workspace.seal.v1","workspace.check.v1","workspace.export.v1","workspace.read.v1"))]|length' "$dir/result") == 4 ]] || fail 'missing negotiated capability'
# Actual frozen old validator accepts new helper legacy hello shape.
call "$dir/hello"; cp "$dir/result" "$dir/legacy-hello"
(source "$runtime/old/ops/protocol.sh"; loom_protocol_validate response "$dir/legacy-hello" "$dir/hello") || fail 'old validator rejected new helper hello'
(
    old_runtime=$runtime/old
    ops=$old_runtime/ops; runtime=$old_runtime
    fixture old-peer
    jq '.op="hello"|.operation_id=null|.idempotency_key=null|.args={versions:[{major:1,minor:0}],required_capabilities:["workspace.seal.v1","workspace.check.v1","workspace.export.v1","workspace.read.v1"]}' "$dir/start" > "$dir/new-hello"
    call "$dir/new-hello" 2
    [[ ! -d $dir/workspaces/worker ]] || fail 'old helper executed on unsupported capability'
    jq '.args.required_capabilities=["workspace.prepare.v1"]' "$dir/new-hello" > "$dir/old-hello-request"
    call "$dir/old-hello-request"; cp "$dir/result" "$dir/old-hello"
)
cmp <(jq -cS .result.capabilities "$dir/legacy-hello") <(jq -cS .result.capabilities "$scratch/old-peer/old-hello") || fail 'legacy capability golden changed'
pass 'actual frozen old-validator/new-helper and new-client/old-helper compatibility'
# Worker-facing installation exposes the same bound process but no workflow grant.
cp "$dir/install-config" "$dir/owner-install"
jq 'del(.workflow_access)' "$dir/install-config" > "$dir/new"; mv "$dir/new" "$dir/install-config"
cp "$dir/client" "$dir/owner-client"
install_route worker
call "$dir/artifact-hello" 2
cp "$dir/owner-client" "$dir/client"; cp "$dir/owner-install" "$dir/install-config"
pass 'real S6 launch approval only after preparation; explicit pin transition and owner/worker capability separation'

jq -cn --arg dir "$dir" --slurpfile b "$dir/binding" '{schema:1,state_root:($dir+"/authority2"),store_id:"workflow-authority",actor:$b[0].actor,role:"owner",binding:null,commands:["mail.send","mail.poll","mail.status","mail.pump"],routes:[{attempt_id:"attempt",config:($dir+"/client")}]}' > "$dir/mail-owner"
mail_req() {
    local op=$1 args=$2 key=$3 revision=null
    if [[ $op == mail.pump ]]; then revision=$(LOOM_STATE=$dir/authority2 loom_state_get run run | jq .revision); fi
    jq -cn --arg op "$op" --argjson args "$args" --arg key "$key" --argjson revision "$revision" --slurpfile b "$dir/binding" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$key,operation_id:$key,idempotency_key:$key,op:$op,actor:$b[0].actor,target:{assignment_id:null,attempt_id:null,host_id:null},expected_revision:$revision,timeout_ms:30000,args:$args,extensions:{}}' > "$dir/mail-request"
    LOOM_STATE=$dir/authority2 bash "$runtime/ops/loom" mail --context "$dir/mail-owner" --request "$dir/mail-request" --protocol 1 > "$dir/mail-result" || { cat "$dir/mail-result" >&2; fail "mail $op"; }
}
mail_req mail.send "$(jq -cn --arg task "$task" '{message_id:"startup",from:"owner",to:[("task:"+$task)],kind:"question",subject:"fixture",body:"literal $(touch injected)",thread_id:null,in_reply_to:null,expires_at:null}')" startup
mail_delivery=$(jq -r .result.deliveries[0].delivery_id "$dir/mail-result")
mail_req mail.pump '{"run_id":"run","deadline_ms":30000}' pump-startup

git clone -q --no-checkout "$dir/source" "$dir/checkout"
jq -cn --arg dir "$dir" --arg source "$(loom_workflow_source)" '{schema:2,transport:"ssh",coordination:($dir+"/co-context"),execution:($dir+"/client"),binding:($dir+"/binding"),pin:($dir+"/pin"),plan:($dir+"/plan"),mail:($dir+"/mail-owner"),manifest:($dir+"/manifest"),checkout:($dir+"/checkout"),check_script:($dir+"/check-script"),source_digest:$source}' > "$dir/workflow"
cli() {
    local name=$1 expected=$2 rc=0 started timing=latency.tsv
    shift 2
    [[ $name != moved-* && $name != failed-* ]] || timing='fault-latency.tsv'
    started=$(date +%s%3N)
    LOOM_STATE=$dir/authority2 bash "$runtime/ops/loom" "$@" > "$dir/cli-result" 2> "$dir/cli-error" || rc=$?
    printf '%s\t%s\t%s\n' "$name" "$(( $(date +%s%3N)-started ))" "$rc" >> "$LOOM_ARTIFACT_EVIDENCE/$timing"
    cp "$dir/cli-result" "$LOOM_ARTIFACT_EVIDENCE/$name.json"
    [[ $rc == "$expected" ]] || { cat "$dir/cli-result" "$dir/cli-error" >&2; fail "CLI $name exit=$rc wanted=$expected"; }
}
: > "$LOOM_ARTIFACT_EVIDENCE/latency.tsv"
: > "$LOOM_ARTIFACT_EVIDENCE/fault-latency.tsv"
cli dispatch 0 dispatch --context "$dir/workflow"
cli start 0 start assignment
cli watch 0 watch assignment --deadline-ms 30000
mail_req mail.pump '{"run_id":"run","deadline_ms":30000}' pump-read
LOOM_STATE=$dir/authority2 loom_state_get delivery "$mail_delivery" > "$dir/mail-delivery"
jq -e '.data.facts.read and (.data.facts.acked|not)' "$dir/mail-delivery" >/dev/null || fail 'remote startup read implicitly acked or missing'
[[ ! -e $dir/workspaces/worker/injected ]] || fail 'mail body evaluated'
cli harvest 0 harvest assignment
if [[ ${LOOM_ARTIFACT_CASE:-success} == worker-* ]]; then
    cli failed-verify 2 verify assignment
    cli failed-collect 2 collect assignment
    LOOM_STATE=$dir/authority2 loom_state_get task "$task" | jq -e '.data.state=="failed" and .data.accepted_result==null' >/dev/null
    pass 'nonzero remote worker ready report fails task; verify/collect cannot accept'
    exit 0
fi
workflow_dir=$(dirname "$(LOOM_STATE=$dir/authority2 loom_workflow_route assignment)")
cli failed-unverified-collect 2 collect assignment
[[ ! -e $dir/check-count ]] || fail 'collect executed unverified check'
printf '{}\n' > "$workflow_dir/check"
cli failed-invalid-proof-collect 2 collect assignment
[[ ! -e $dir/check-count ]] || fail 'collect executed check for invalid proof'
rm "$workflow_dir/check"
expected_check=0
[[ ${LOOM_ARTIFACT_CASE:-success} == success ]] || expected_check=1
cli verify "$expected_check" verify assignment
if [[ $expected_check == 1 ]]; then
    [[ $(cat "$dir/check-count") == x ]] || fail 'failed check did not execute exactly once'
    cli failed-verify-replay 1 verify assignment
    [[ $(cat "$dir/check-count") == x ]] || fail 'uncertain/failed check reran'
    cli failed-collect 2 collect assignment
    LOOM_STATE=$dir/authority2 loom_state_get task "$task" | jq -e '.data.state=="review" and .data.accepted_result==null' >/dev/null
    pass 'nonzero/timeout remote check remains unaccepted, same-operation replay never reexecutes'
    exit 0
fi
[[ $(cat "$dir/check-count") == x ]] || fail 'check count'
cli verify-replay 0 verify assignment
[[ $(cat "$dir/check-count") == x ]] || fail 'check reran'
# Validate every persisted field against the exact request and current host
# operation receipt. Four architect regressions also exercise the actual CLI.
workflow_dir=$(dirname "$(LOOM_STATE=$dir/authority2 loom_workflow_route assignment)")
cp "$workflow_dir/check" "$dir/good-check"
host_check_intent=$(find "$dir/state/ssh" -name workflow-check-intent -print -quit)
host_workflow_spool=${host_check_intent%/*}
mv "$host_check_intent" "$dir/held-check-intent"
cli failed-missing-host-intent 1 collect assignment
[[ ! -e $host_check_intent && $(cat "$dir/check-count") == x ]] || fail 'collect recreated original check intent'
mv "$dir/held-check-intent" "$host_check_intent"
mkdir "$dir/held-check-state"
for record in "$host_workflow_spool"/workflow-check*; do mv "$record" "$dir/held-check-state/"; done
cli failed-missing-host-check-state 1 collect assignment
[[ ! -e $host_check_intent && $(cat "$dir/check-count") == x ]] || fail 'collect executed check after host state loss'
for record in "$dir/held-check-state"/*; do mv "$record" "$host_workflow_spool/"; done
pass 'absent/invalid local proof and absent host intent/state cannot dispatch or recreate a check'
mutation_index=0
for mutation in '.receipt.result.check_digest="git-blob-sha1-v1:1111111111111111111111111111111111111111"' '.receipt.result.manifest_digest="git-blob-sha1-v1:1111111111111111111111111111111111111111"' '.receipt.target.attempt_id="other"' '.receipt.result.check_exit=7|.receipt.result.process.exit_code=7'; do
    mutation_index=$((mutation_index+1))
    jq "$mutation" "$dir/good-check" > "$workflow_dir/check"
    cli failed-receipt-$mutation_index 2 collect assignment
    [[ ! -e $workflow_dir/collect ]] || fail 'tampered check produced collection'
done
cp "$dir/good-check" "$workflow_dir/check"
# Exercise all nested fields through the same validator against a read-only durable
# same-operation artifact; these cheap integrity cases do not add transport waits.
(
    export LOOM_STATE=$dir/authority2
    _loom_workflow_context "$dir/workflow"
    _wf_tmp=$dir/receipt-validation; mkdir "$_wf_tmp"
    cp "$workflow_dir/remote-seal" "$_wf_tmp/seal"
    _loom_workflow_request workspace.check "$(jq -c '.result|{sha,manifest_digest}' "$_wf_tmp/seal")" 1 workflow-check > "$_wf_tmp/expected-check-request"
    _loom_workflow_remote_read_check
    _loom_workflow_remote_check_receipt
    for mutation in '.check_exit=7' '.checked_sha="1111111111111111111111111111111111111111"' '.captured=false' '.check_digest="wrong"' '.config_digest="wrong"' '.source_digest="wrong"' '.receipt.result.sha="1111111111111111111111111111111111111111"' '.receipt.result.config_digest="wrong"' '.receipt.result.report_digest="wrong"' '.receipt.result.source.context_digest="wrong"' '.receipt.result.captured=false' '.receipt.result.process.captured=false' '.receipt.result.process.group_empty=false' '.receipt.result.process.escaped=true' '.receipt.result.process.timed_out=true' '.receipt.result.process.output_eof=false' '.receipt.operation_id="other"' '.receipt.target.assignment_id="other"' '.receipt.target.host_id="other"' '.receipt.version.major=2' '.receipt.revision=2' '.receipt.durable=false' '.receipt.ok=false' '.receipt.status="pending"' '.receipt.extensions["loom.ssh"].identity.context_digest="wrong"'; do
        jq "$mutation" "$dir/good-check" > "$workflow_dir/check"
        rc=0; _loom_workflow_remote_check_receipt > "$dir/tamper-output" 2> "$dir/tamper-error" || rc=$?
        [[ $rc == 2 ]] || fail "persisted receipt mutation accepted: $mutation"
    done
)
cp "$dir/good-check" "$workflow_dir/check"
pass 'canonical persisted receipt/request/host correlation refuses nested and outer tampering'
cli collect 0 collect assignment
sha=$(jq -r .items[0].collected_sha "$dir/cli-result")
cli collect-replay 0 collect assignment
collected_ref=$(jq -r .items[0].ref "$dir/cli-result")
original_sha=$sha
conductor_sha=$(GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid git -C "$dir/checkout" commit-tree "$(git -C "$dir/checkout" rev-parse "$sha^{tree}")" -p "$sha" -m 'conductor fixture')
git -C "$dir/checkout" update-ref "$collected_ref" "$conductor_sha" "$sha"
cli moved-collect 2 collect assignment
[[ $(git -C "$dir/checkout" rev-parse "$collected_ref") == "$conductor_sha" ]] || fail 'collection overwrote conductor ref'
git -C "$dir/checkout" update-ref "$collected_ref" "$original_sha" "$conductor_sha"
jq '.receipt.result.check_digest="git-blob-sha1-v1:1111111111111111111111111111111111111111"' "$dir/good-check" > "$workflow_dir/check"
cli failed-ack-receipt 2 ack assignment --reviewed "$sha"
cp "$dir/good-check" "$workflow_dir/check"
cli ack 0 ack assignment --reviewed "$sha"
LOOM_STATE=$dir/authority2 loom_state_get task "$task" > "$dir/final-task"
jq -e '.data.state=="succeeded"' "$dir/final-task" >/dev/null || fail 'remote acceptance'
pass 'full fake-SSH actual-process CLI seal/check/bundle download/collect/explicit acceptance; check group quiescence'
# Direct helper replay/provenance negatives do not require a live authority task.
jq --arg base "$(cat "$dir/base")" '.op="workspace.seal"|.operation_id="workflow-seal"|.idempotency_key="workflow-seal"|.expected_revision=1|.args={workspace_id:.args.workspace_id,base_sha:$base,manifest_digest:.args.manifest_digest}' "$dir/start" > "$dir/seal"
FAULT=after call "$dir/seal" 1
call "$dir/seal"
seal_receipt=$(find "$dir/state/ssh" -name workflow-seal-receipt -print -quit)
mv "$seal_receipt" "$seal_receipt-held"
call "$dir/seal" 1
jq '.operation_id="new-seal"|.idempotency_key="new-seal"' "$dir/seal" > "$dir/new-seal"
call "$dir/new-seal" 2
[[ $(git -C "$dir/workspaces/worker" rev-parse HEAD) == "$sha" ]] || fail 'uncertain seal recommitted'
mv "$seal_receipt-held" "$seal_receipt"
jq --arg sha "$sha" '.op="workspace.check"|.operation_id="workflow-check"|.idempotency_key="workflow-check"|.expected_revision=1|.args={sha:$sha,manifest_digest:.args.manifest_digest}' "$dir/start" > "$dir/check"
FAULT=after call "$dir/check" 1
call "$dir/check"
[[ $(cat "$dir/check-count") == x ]] || fail 'lost reply reran check'
receipt=$(find "$dir/state/ssh" -name workflow-check-receipt -print -quit)
mv "$receipt" "$receipt-held"
call "$dir/check" 1
jq '.operation_id="uncertain-new-key"|.idempotency_key="uncertain-new-key"' "$dir/check" > "$dir/uncertain-new-key"
call "$dir/uncertain-new-key" 2
[[ $(cat "$dir/check-count") == x ]] || fail 'missing receipt/new key reran check'
mv "$receipt-held" "$receipt"
jq '.operation_id="different"|.idempotency_key="different"' "$dir/check" > "$dir/different"
call "$dir/different" 2
jq '.args.argv=["touch","injected"]' "$dir/check" > "$dir/argv"
call "$dir/argv" 2
jq '.target.attempt_id="other"' "$dir/check" > "$dir/wrong-attempt"
call "$dir/wrong-attempt" 2
jq '.actor.id="other"' "$dir/check" > "$dir/wrong-actor"; call "$dir/wrong-actor" 2
jq '.args.sha="1111111111111111111111111111111111111111"' "$dir/check" > "$dir/wrong-sha"; call "$dir/wrong-sha" 2
jq '.args.manifest_digest="git-blob-sha1-v1:1111111111111111111111111111111111111111"' "$dir/check" > "$dir/wrong-manifest"; call "$dir/wrong-manifest" 2
jq --arg sha "$sha" '.op="workspace.export"|.operation_id=null|.idempotency_key=null|.expected_revision=null|.args={sha:$sha,kind:"git_bundle",limit_bytes:1048576}' "$dir/start" > "$dir/export"
call "$dir/export"; cp "$dir/result" "$dir/exported"
jq '.args.limit_bytes=1' "$dir/export" > "$dir/small-export"; call "$dir/small-export" 2
jq '.op="workspace.read"|.args={artifact:"workflow-bundle",limit_bytes:65536}' "$dir/export" > "$dir/artifact-read"
call "$dir/artifact-read"; cp "$dir/result" "$dir/old-read"
(source "$runtime/old/ops/protocol.sh"; loom_protocol_validate response "$dir/exported" "$dir/export"; loom_protocol_validate response "$dir/old-read" "$dir/artifact-read") || fail 'old validator rejected export/read'
# Repository-local commands never inherit the installed check authorization.
printf '#!/bin/sh\nprintf invoked >> %s\ncat\n' "$dir/git-command-marker" > "$dir/git-command"
chmod 700 "$dir/git-command"
cp "$dir/workspaces/worker/.git/config" "$dir/safe-git-config"
git -C "$dir/workspaces/worker" config filter.fixture.clean "$dir/git-command"
printf 'result.txt filter=fixture\n' > "$dir/workspaces/worker/.gitattributes"
call "$dir/seal" 2
cp "$dir/safe-git-config" "$dir/workspaces/worker/.git/config"
call "$dir/check" 2
rm "$dir/workspaces/worker/.gitattributes"
git -C "$dir/workspaces/worker" config core.fsmonitor "$dir/git-command"
call "$dir/export" 2
cp "$dir/safe-git-config" "$dir/workspaces/worker/.git/config"
printf '[core]\nfsmonitor = %s\n' "$dir/git-command" > "$dir/git-included"
git -C "$dir/workspaces/worker" config include.path "$dir/git-included"
call "$dir/artifact-read" 2
cp "$dir/safe-git-config" "$dir/workspaces/worker/.git/config"
[[ ! -e $dir/git-command-marker ]] || fail 'repository config executed outside pinned check'
call "$dir/artifact-read"
pass 'seal/check/export/read reject executable Git config and filter attributes without effects'
# Artifact substitution and malformed cursors refuse before opening unrelated data.
artifact_path=$(find "$dir/state/ssh" -name workflow-bundle -print -quit)
mv "$artifact_path" "$artifact_path-held"
ln -s "$dir/context" "$artifact_path"
call "$dir/artifact-read" 1
rm "$artifact_path"; mv "$artifact_path-held" "$artifact_path"
jq '.args.cursor="wrong-generation:0"' "$dir/artifact-read" > "$dir/bad-cursor"
call "$dir/bad-cursor" 2
jq '.args.artifact="etc/passwd"' "$dir/artifact-read" > "$dir/unknown-artifact"; call "$dir/unknown-artifact" 2
jq '.args.artifact="../escape"' "$dir/artifact-read" > "$dir/traversal"; call "$dir/traversal" 2
jq '.args.limit_bytes=1' "$dir/artifact-read" > "$dir/tiny-read"; call "$dir/tiny-read" 2
printf drift >> "$dir/workspaces/worker/result.txt"
call "$dir/check" 2
call "$dir/artifact-read"
cmp <(jq .result "$dir/old-read") <(jq .result "$dir/result") || fail 'historical artifact changed'
pass 'lost check reply, different-key fence, argv/binding/path/quota refusals and historical read after live drift'
printf '\n# changed installed check\n' >> "$dir/check-script"
call "$dir/check" 1
[[ $(cat "$dir/check-count") == x ]] || fail 'source drift reran check'
pass 'pinned check source change is unknown/refused without fallback or new execution'
printf 'PASS remote artifacts through deterministic transport; real network SSH not run; inherited release blockers remain\n'
