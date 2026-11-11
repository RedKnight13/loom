#!/usr/bin/env bash
# Real fixture processes and actual S1-S7 modules; no Orca, models or network.
# shellcheck disable=SC1090,SC1091,SC2016,SC2030,SC2031,SC2154
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
umask 077
if [[ ${1:-} != --staged ]]; then
    runtime=$(mktemp -d)
    trap 'rm -rf -- "$runtime"' EXIT
    mkdir -p "$runtime/ops" "$runtime/tests/native" "$runtime/tests/mail" "$runtime/tests/conformance"
    cp "$repo"/ops/* "$runtime/ops/"
    cp -R "$repo/schemas" "$runtime/"
    cp "$repo/VERSION" "$runtime/"
    cp "$repo/tests/native/run.sh" "$runtime/tests/native/"
    mail_source=${LOOM_CONFORMANCE_MAIL_ROOT:-$repo}
    for module in mail.sh worker-bridge.sh; do
        [[ -f $mail_source/ops/$module ]] || { printf 'S7 required: set LOOM_CONFORMANCE_MAIL_ROOT to its actual installation\n' >&2; exit 2; }
        cp "$mail_source/ops/$module" "$runtime/ops/"
    done
    cp "$mail_source/tests/mail/run.sh" "$runtime/tests/mail/"
    export LOOM_CONFORMANCE_RUNTIME=$runtime
    export LOOM_CONFORMANCE_EVIDENCE=${LOOM_CONFORMANCE_EVIDENCE:-$repo/.loom/conformance}
    mkdir -p "$LOOM_CONFORMANCE_EVIDENCE"
    cp "$0" "$runtime/tests/conformance/native-workflow.sh"
    bash "$runtime/tests/conformance/native-workflow.sh" --staged
    exit
fi
runtime=$LOOM_CONFORMANCE_RUNTIME
export LOOM_MAIL_TEST_DEPENDENCIES=$runtime
MAIL_FIXTURE_LIBRARY=1 source "$runtime/tests/mail/run.sh"
source "$runtime/ops/workflow.sh"
# Synthetic trusted provisioning in the shared fixture remains the authorization
# source; routing cannot invent a successful real-agent calibration.
eval "$(declare -f authorize | sed '1s/authorize/mail_authorize/')"
authorize() {
    local sha tree manifest
    git -C "$dir/workspaces/worker" init -q -b main
    git -C "$dir/workspaces/worker" config user.name 'Loom Fixture'
    git -C "$dir/workspaces/worker" config user.email fixture@example.invalid
    tree=$(printf '' | git -C "$dir/workspaces/worker" mktree)
    sha=$(printf 'fixture base\n' | git -C "$dir/workspaces/worker" commit-tree "$tree")
    git -C "$dir/workspaces/worker" update-ref refs/heads/main "$sha"
    printf 'WORK.md\nREPORT.md\n.loom/\n' >> "$dir/workspaces/worker/.git/info/exclude"
    printf 'test "$(cat result.txt)" = accepted\nprintf x >> %q\n(sleep 0.15; printf child > child-result) &\n' "$dir/check-count" > "$dir/check-script"
    jq -cn --arg sha "$sha" --arg check "$(loom_policy_digest "$dir/check-script")" '{schema:1,base_sha:$sha,check_digest:$check,report_offset:0}' > "$dir/manifest"
    manifest=$(loom_policy_digest "$dir/manifest")
    jq --arg digest "$manifest" '.manifest_digest=$digest' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
    mail_authorize
    git init -q -b main "$dir/checkout"
    jq -cn --arg dir "$dir" --arg source "$(loom_workflow_source)" '{schema:2,transport:"process",coordination:($dir+"/co-context"),execution:($dir+"/context"),binding:($dir+"/binding"),pin:($dir+"/pin"),plan:($dir+"/plan"),mail:($dir+"/mail-owner"),manifest:($dir+"/manifest"),checkout:($dir+"/checkout"),check_script:($dir+"/check-script"),source_digest:$source}' > "$dir/workflow"
    jq -cn --arg context "$dir/mail-worker" --arg cd "$(loom_policy_digest "$dir/mail-worker")" --arg bridge "$runtime/ops/worker-bridge.sh" --arg bd "$(loom_policy_digest "$runtime/ops/worker-bridge.sh")" '{schema:1,context:$context,context_digest:$cd,bridge:$bridge,bridge_digest:$bd}' > "$dir/context.mail"
}
co_request() {
    local op=$1 args=$2
    jq -cn --arg op "$op" --argjson args "$args" --slurpfile b "$dir/binding" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$op,operation_id:$op,idempotency_key:$op,op:$op,actor:$b[0].actor,target:{assignment_id:null,attempt_id:null,host_id:null},expected_revision:null,timeout_ms:30000,args:$args,extensions:{}}' > "$dir/co-request"
    LOOM_STATE=$dir/authority bash "$runtime/ops/loom" "${op%%.*}" --context "$dir/co-context" --request "$dir/co-request" --protocol 1 > "$dir/co-result" || fail 'CLI coordination request'
}
cli() {
    local label=$1 expected=$2 started rc=0 timing=normal-latency.tsv
    shift 2
    [[ $label != tampered-* ]] || timing='integrity-latency.tsv'
    started=$(date +%s%3N)
    LOOM_STATE=$dir/authority bash "$runtime/ops/loom" "$@" > "$dir/cli-result" 2> "$dir/cli-error" || rc=$?
    printf '%s\t%s\t%s\n' "$label" "$(( $(date +%s%3N)-started ))" "$rc" >> "$LOOM_CONFORMANCE_EVIDENCE/$timing"
    [[ $rc == "$expected" ]] || { cat "$dir/cli-result" "$dir/cli-error" >&2; fail "CLI $label exit=$rc expected=$expected"; }
    jq -e 'keys==["actions","cmd","fact","id","items","ok","state","ticket","v"]' "$dir/cli-result" >/dev/null || fail 'public envelope changed'
}
mail_cli() {
    local rc=0
    LOOM_STATE=$dir/authority bash "$runtime/ops/loom" mail --context "$dir/mail-owner" --request "$dir/request" --protocol 1 > "$dir/result" || rc=$?
    [[ $rc == 0 ]] || fail 'mail CLI'
}
mkdir -p "$scratch/bin"
cat > "$scratch/bin/orca" <<'TRAP'
#!/usr/bin/env bash
printf 'forbidden orchestrator call\n' >> "${LOOM_FORBIDDEN_LOG:?}"
printf 'forbidden orchestrator call\n' >&2
exit 99
TRAP
cp "$scratch/bin/orca" "$scratch/bin/herdr"
cp "$scratch/bin/orca" "$scratch/bin/gh"
chmod 700 "$scratch/bin/"*
export PATH="$scratch/bin:$PATH" LOOM_ORCA="$scratch/bin/orca" LOOM_FORBIDDEN_LOG="$scratch/forbidden-calls"
: > "$LOOM_CONFORMANCE_EVIDENCE/normal-latency.tsv"
: > "$LOOM_CONFORMANCE_EVIDENCE/integrity-latency.tsv"
fixture complete 'jq -e '\''.messages|any(.message.message_id=="startup" and .delivery.state=="read")'\'' "$LOOM_STARTUP_MAIL_FILE" || exit 31
printf accepted > result.txt
printf "state: ready — fixture complete\n" >> REPORT.md
printf "captured output\n"'
send_message startup "task:$(cat "$dir/task-id")" 'literal $(touch injected)'
startup_delivery=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
cli dispatch 0 dispatch --context "$dir/workflow"
cli start 0 start assignment
# The public request has returned: subsequent calls are independent processes.
cli watch 0 watch assignment --deadline-ms 30000
cli status 0 status assignment
jq -e '.items[0].result.state=="exited" and .items[0].result.terminal.exit_code==0' "$dir/cli-result" >/dev/null || fail 'process did not settle'
cli replay 0 start assignment
cli read 0 read assignment
jq -e '.items[0].result.data|length>0' "$dir/cli-result" >/dev/null || fail 'missing output'
LOOM_STATE=$dir/authority loom_state_get delivery "$startup_delivery" > "$dir/delivery"
jq -e '.data.delivery.state=="read" and .data.facts.read and (.data.facts.acked|not)' "$dir/delivery" >/dev/null || fail 'startup read vs ack'
[[ ! -f $dir/workspaces/worker/injected ]] || fail 'mail evaluated'
# Explicit delivery ack has a separate request and never changes task result.
startup=$(find "$dir/state/native" -name startup-mail -print -quit)
token=$(jq -r '.messages[0].claim_token' "$startup")
revision=$(jq '.messages[0].delivery.revision' "$startup")
request mail.ack "$(jq -cn --arg id "$startup_delivery" --arg token "$token" --arg digest "$(jq -r .data.delivery.message_digest "$dir/delivery")" '{delivery_id:$id,claim_token:$token,message_digest:$digest}')" "$revision" worker
LOOM_STATE=$dir/authority bash "$runtime/ops/loom" mail --context "$dir/mail-worker" --request "$dir/request" --protocol 1 > "$dir/acked"
jq -e '.result.state=="acked"' "$dir/acked" >/dev/null || fail 'explicit ack'
pass 'explicit ack distinct from startup read and assignment acceptance'
LOOM_STATE=$dir/authority loom_state_get task "$(cat "$dir/task-id")" > "$dir/task"
jq -e '.data.state=="running" and .data.accepted_result==null' "$dir/task" >/dev/null || fail 'mail ack accepted task'
cli harvest 0 harvest assignment
cli verify 0 verify assignment
cli verify-replay 0 verify assignment
[[ $(cat "$dir/check-count") == x ]] || fail 'local check reran'
workflow_dir=$(dirname "$(LOOM_STATE=$dir/authority loom_workflow_route assignment)")
cp "$workflow_dir/check" "$dir/good-check"
jq '.process.exit_code=7' "$dir/good-check" > "$workflow_dir/check"
cli tampered-local-check 2 collect assignment
cp "$dir/good-check" "$workflow_dir/check"
cli collect 0 collect assignment
sha=$(jq -r '.items[0].collected_sha' "$dir/cli-result")
cli ack 0 ack assignment --reviewed "$sha"
LOOM_STATE=$dir/authority loom_state_get task "$(cat "$dir/task-id")" > "$dir/task"
jq -e '.data.state=="succeeded" and .data.accepted_result!=null' "$dir/task" >/dev/null || fail 'verified acceptance'
cli events 0 events assignment --after 0
pass 'no-Orca CLI run/task, startup mail, detached start/restart/replay, report, exact verify/collect/accept, events'
# Fault cases are measured separately; never mix their cost into normal latency.
mv "$LOOM_CONFORMANCE_EVIDENCE/normal-latency.tsv" "$LOOM_CONFORMANCE_EVIDENCE/normal.saved"
fixture failed 'printf "state: ready — misleading ready\n" >> REPORT.md; exit 7'
cli failed-dispatch 0 dispatch --context "$dir/workflow"
cli failed-start 0 start assignment
cli failed-watch 0 watch assignment --deadline-ms 30000
cli failed-harvest 0 harvest assignment
LOOM_STATE=$dir/authority loom_state_get task "$(cat "$dir/task-id")" > "$dir/task"
jq -e '.data.state=="failed" and .data.accepted_result==null' "$dir/task" >/dev/null || fail 'nonzero accepted'
cli failed-verify 2 verify assignment
pass 'nonzero captured worker exit cannot accept a ready report'
fixture drift 'printf accepted > result.txt; printf "state: ready — drift fixture\n" >> REPORT.md'
cli drift-dispatch 0 dispatch --context "$dir/workflow"
cli drift-start 0 start assignment
cli drift-watch 0 watch assignment --deadline-ms 30000
cli drift-harvest 0 harvest assignment
cli drift-verify 0 verify assignment
cp "$dir/workspaces/worker/REPORT.md" "$dir/saved-report"
printf 'state: ready — replaced report\n' > "$dir/workspaces/worker/REPORT.md"
cli changed-report 2 collect assignment
cp "$dir/saved-report" "$dir/workspaces/worker/REPORT.md"
printf changed > "$dir/workspaces/worker/result.txt"
cli changed-source 2 collect assignment
printf accepted > "$dir/workspaces/worker/result.txt"
printf '\n# source drift fixture\n' >> "$runtime/ops/workflow.sh"
cli changed-runtime 2 collect assignment
pass 'workspace and installed source changes invalidate checked receipts'
# Guarded stop/reconcile use exact contract requests through the registered route.
fixture stopped 'trap "exit 0" TERM; while :; do sleep 1; done'
cli stop-dispatch 0 dispatch --context "$dir/workflow"
cli stop-start 0 start assignment
cli bounded-watch 0 watch assignment --deadline-ms 100
jq -e '.items[0].deadline_reached and .items[0].mail_consumed==false' "$dir/cli-result" >/dev/null || fail 'watch deadline'
stop_request false
cli stop 0 stop assignment --request "$dir/stop"
jq -e '.items[0].result.confirmed_stopped' "$dir/cli-result" >/dev/null || fail 'guarded stop'
jq '.op="execution.reconcile"|.operation_id=null|.idempotency_key=null|.expected_revision=null|.args={operation_id:"start"}' "$dir/start" > "$dir/reconcile"
cli reconcile 0 reconcile assignment --request "$dir/reconcile"
pass 'bounded watcher and exact guarded stop/reconcile routed without fallback'
fixture gated 'touch forbidden; exit 0'
cli gate-dispatch 0 dispatch --context "$dir/workflow"
co_request gate.create "$(jq -cn --arg task "$(cat "$dir/task-id")" '{task_id:$task,question:"Pause before launch",resolver_id:"owner",options:["approved","rejected"]}')"
cli gate-refused 2 start assignment
[[ ! -e $dir/workspaces/worker/forbidden ]] || fail 'closed gate launched'
pass 'new gate after authorization blocks facade launch through current S6 state'
# Remote-only cannot be weakened by a legacy environment override.
fixture denied 'touch forbidden; exit 0'
jq '.execution.placement.allow_local=false' "$dir/config" > "$dir/new"; mv "$dir/new" "$dir/config"
LOOM_ALLOW_LOCAL=1 cli denied-local 2 dispatch --context "$dir/workflow"
[[ ! -e $dir/workspaces/worker/forbidden ]] || fail 'local fallback'
pass 'denied local policy has no environment fallback'
mv "$LOOM_CONFORMANCE_EVIDENCE/normal-latency.tsv" "$LOOM_CONFORMANCE_EVIDENCE/fault-latency.tsv"
mv "$LOOM_CONFORMANCE_EVIDENCE/normal.saved" "$LOOM_CONFORMANCE_EVIDENCE/normal-latency.tsv"
[[ ! -e $scratch/forbidden-calls ]] || fail 'orchestrator or GitHub was called'
printf 'PASS actual fixture process workflow; fake transport and real network acceptance are separate suites\n'
