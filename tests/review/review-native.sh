#!/usr/bin/env bash
# Focused native supervision regressions; real local fixture processes only.
# shellcheck disable=SC1090,SC1091,SC2016,SC2030,SC2031,SC2154
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
if [[ $(uname -s) != Linux ]]; then printf 'SKIP review-native: Linux /proc required\n'; exit 0; fi
umask 077
source "$repo/ops/workflow.sh"
source "$repo/ops/native-supervisor.sh"
MAIL_FIXTURE_LIBRARY=1 source "$repo/tests/mail/run.sh"
case_name=${1:-all}
if [[ $case_name == all || $case_name == routing ]]; then
    mkdir -p "$scratch/routing"
    export LOOM_STATE=$scratch/routing
    printf '{}\n' > "$LOOM_STATE/legacy.json"
    for option in --context --protocol; do
        if loom_workflow_selected launch legacy -- bash worker "$option" value; then fail 'legacy worker argument selected native'; fi
        if loom_workflow_selected launch legacy "$option" value; then fail 'legacy assignment routing overridden'; fi
        if loom_workflow_selected launch missing -- bash worker "$option" value; then fail 'option boundary ignored'; fi
        loom_workflow_selected launch --context fixture || fail 'explicit native selection lost'
    done
    unset LOOM_STATE
    pass 'routing preserves legacy assignment and option boundary'
fi
if [[ $case_name == all || $case_name == mail ]]; then
    # Fast pinned bridge fixture isolates serialization from state-journal cost.
    # Actual bridge read/ack behavior is also exercised by native-workflow.sh.
    mail_runtime=$scratch/mail-runtime; mkdir -p "$mail_runtime/ops" "$scratch/mail-spool"
    cp "$repo/ops/native-supervisor.sh" "$mail_runtime/ops/"
    printf '#!/usr/bin/env bash\ncat "${2}.batch"\n' > "$mail_runtime/ops/worker-bridge.sh"
    printf '{}\n' > "$scratch/mail-binding"
    jq -cn --arg binding "$scratch/mail-binding" '{binding:$binding}' > "$scratch/mail-context"
    jq -cn '{delivery_mode:"next_boundary",wake:"unsupported",messages:[range(4)|{message:{message_id:.,body:("\u0001"*60000)},delivery:{state:"read"},claim_token:"fixture"}]}' > "$scratch/mail-context.batch"
    cp "$scratch/mail-context.batch" "$scratch/mail-original"
    jq -cn --arg context "$scratch/mail-context" --arg cd "$(loom_policy_digest "$scratch/mail-context")" --arg bridge "$mail_runtime/ops/worker-bridge.sh" --arg bd "$(loom_policy_digest "$mail_runtime/ops/worker-bridge.sh")" '{schema:1,context:$context,context_digest:$cd,bridge:$bridge,bridge_digest:$bd}' > "$scratch/native-context.mail"
    _nn_binding=$scratch/mail-binding
    source "$mail_runtime/ops/native-supervisor.sh"
    _loom_native_startup_mail "$scratch/native-context" "$scratch/mail-spool" || fail 'startup mail publication'
    (( $(stat -c %s "$scratch/mail-spool/startup-mail") < 1048576 )) || fail 'serialized startup mail exceeds spool cap'
    jq -e '.messages|length==2' "$scratch/mail-spool/startup-mail" >/dev/null || fail 'bounded aggregate selection'
    cmp "$scratch/mail-original" "$scratch/mail-context.batch" || fail 'overflow source changed'
    _loom_native_private "$scratch/mail-spool/startup-mail" || fail 'startup mail poisons spool validation'
    [[ ! -f $scratch/mail-spool/startup-mail.pending ]] || fail 'oversized pending file left in spool'
    source "$repo/ops/native-supervisor.sh"
    pass 'serialized escaped aggregate bounded; overflow preserved for bridge redelivery'

fi
if [[ $case_name == all || $case_name == metadata ]]; then
    _rh_spool=$scratch/artifacts; _rw_tmp=$scratch/artifact-temp
    mkdir -p "$_rh_spool" "$_rw_tmp"
    _rh_workflow=$scratch/workflow-config
    printf '{"artifact_bytes":65536}\n' > "$_rh_workflow"
    _rw_request=$scratch/check-request
    printf '{"request_id":"first","timeout_ms":1000,"op":"workspace.check"}\n' > "$_rw_request"
    printf '{"sha":"fixture-sha","check_exit":0,"captured":true}\n' > "$_rh_spool/workflow-check-receipt"
    jq -cS 'del(.request_id,.timeout_ms)' "$_rw_request" | git hash-object --stdin > "$_rh_spool/workflow-check-intent"
    # Inject failure of the second publication, after durable artifact bytes.
    eval "$(declare -f loom_output_atomic | sed '1s/loom_output_atomic/review_atomic/')"
    loom_output_atomic() { [[ $1 != "$_rh_spool/workflow-check-meta" ]] || return 1; review_atomic "$@"; }
    rc=0; _loom_rw_publish_check "$_rh_spool/workflow-check-receipt" || rc=$?
    [[ $rc != 0 && -f $_rh_spool/workflow-check && ! -e $_rh_spool/workflow-check-meta ]] || fail 'publication fault not exercised'
    cp "$_rh_spool/workflow-check" "$scratch/original-artifact"
    eval "$(declare -f review_atomic | sed '1s/review_atomic/loom_output_atomic/')"
    _loom_rw_publish_check "$_rh_spool/workflow-check-receipt" || fail 'publication replay'
    [[ -f $_rh_spool/workflow-check-meta ]] || fail 'metadata not reconstructed'
    cmp "$scratch/original-artifact" "$_rh_spool/workflow-check" || fail 'immutable artifact changed'
    [[ $(loom_policy_digest "$_rh_spool/workflow-check") == "$(jq -r .digest "$_rh_spool/workflow-check-meta")" ]] || fail 'repaired metadata digest'
    rm "$_rh_spool/workflow-check-meta"
    jq '.receipt.result.check_exit=9' "$_rh_spool/workflow-check" > "$scratch/corrupt"
    mv "$scratch/corrupt" "$_rh_spool/workflow-check"
    if _loom_rw_publish_check "$_rh_spool/workflow-check-receipt"; then fail 'corrupt artifact repaired as trusted'; fi
    pass 'partial check publication reconstructs metadata from immutable receipt'
fi
if [[ $case_name == all || $case_name == keeper ]]; then
    runtime=$scratch/check-runtime; mkdir -p "$runtime/ops" "$runtime/schemas" "$scratch/check-work" "$scratch/check-data"
    cp "$repo"/ops/* "$runtime/ops/"
    cp -R "$repo/schemas/"* "$runtime/schemas/"
    # Fault only the live check child's identity, after its initial capture.
    cat >> "$runtime/ops/native.sh" <<'FAULT'

eval "$(declare -f _loom_native_proc | sed '1s/_loom_native_proc/review_proc/')"
_loom_native_proc() {
    local unreadable=''
    if [[ -f ${LOOM_REVIEW_CHILD_FILE:-/nonexistent} ]]; then
        IFS= read -r unreadable < "$LOOM_REVIEW_CHILD_FILE"
        [[ $1 != "$unreadable" ]] || return 1
    fi
    review_proc "$@"
}
FAULT
    printf 'sleep 0.1\nprintf "%%s\\n" "$$" > %q\ntrap "" TERM\nsleep 6\n' "$scratch/check-child" > "$scratch/check-script"
    jq -cn --arg root "$scratch" --arg digest "$(loom_policy_digest "$scratch/check-script")" --arg interpreter "$(loom_policy_digest /usr/bin/bash)" '{workspace:($root+"/check-work"),script:($root+"/check-script"),result_dir:($root+"/check-data"),script_digest:$digest,interpreter_digest:$interpreter,timeout_ms:500,output_bytes:4096}' > "$scratch/check-plan"
    rc=0; check_started=$(date +%s%3N)
    LOOM_REVIEW_CHILD_FILE=$scratch/check-child timeout --kill-after=1 3 setsid --wait bash "$runtime/ops/workflow.sh" --check-keeper "$scratch/check-plan" > "$scratch/check-log" 2>&1 || rc=$?
    check_elapsed=$(( $(date +%s%3N)-check_started ))
    [[ $rc == 137 && $check_elapsed -lt 2500 && -f $scratch/check-data/check-timeout && ! -f $scratch/check-data/check-terminal ]] || fail "unreadable live child blocked deadline: exit=$rc elapsed_ms=$check_elapsed"
    pass 'unreadable live child retains bounded supervision and no terminal success'
    # An unreadable existing scan entry is uncertainty even after child exit.
    rm -rf "$scratch/check-data"; mkdir "$scratch/check-data"
    printf 'exit 0\n' > "$scratch/check-script"
    printf '%s\n' "$BASHPID" > "$scratch/check-child"
    jq --arg digest "$(loom_policy_digest "$scratch/check-script")" '.script_digest=$digest' "$scratch/check-plan" > "$scratch/plan-new"
    mv "$scratch/plan-new" "$scratch/check-plan"
    rc=0
    LOOM_REVIEW_CHILD_FILE=$scratch/check-child timeout --kill-after=1 3 setsid --wait bash "$runtime/ops/workflow.sh" --check-keeper "$scratch/check-plan" > "$scratch/check-log" 2>&1 || rc=$?
    [[ $rc == 137 && -f $scratch/check-data/check-timeout && ! -f $scratch/check-data/check-terminal ]] || fail "unreadable scan entry falsely settled: exit=$rc"
    pass 'unreadable existing scan entry cannot prove empty group'

fi
if [[ $case_name == all || $case_name == reconcile ]]; then
    fixture late-kill 'trap "" TERM; touch started; sleep 8'
    call "$dir/start"
    for _ in {1..100}; do [[ ! -f $dir/workspaces/worker/started ]] || break; sleep 0.02; done
    stop_request true
    LOOM_NATIVE_TEST_FAULT=stop_observation call "$dir/stop" 1
    for _ in {1..200}; do [[ ! -f $spool/signals ]] || ! jq -e 'index("KILL")!=null' "$spool/signals" >/dev/null || break; sleep 0.02; done
    keeper=$(jq -r .supervisor_pid "$spool/identity")
    for _ in {1..200}; do
        if _loom_native_proc "$keeper"; then [[ ${_np[0]} != Z && ${_np[0]} != X ]] || break
        else [[ -d /proc/$keeper ]] || break; fi
        sleep 0.02
    done
    if _loom_native_proc "$keeper" && [[ ${_np[0]} != Z && ${_np[0]} != X ]]; then fail 'keeper did not finish KILL'; fi
    [[ ! -f $spool/completion ]] || fail 'caller unexpectedly wrote completion'
    cp "$spool/identity" "$dir/identity-good"
    jq '.supervisor_start_ticks="0"' "$dir/identity-good" > "$spool/identity"
    inspect_request; call "$dir/inspect"
    [[ $(jq -r .result.state "$dir/result") == unknown && ! -f $spool/completion ]] || fail 'changed identity settled'
    cp "$dir/identity-good" "$spool/identity"
    jq '.op="execution.reconcile"|.args={operation_id:"stop"}' "$dir/inspect" > "$dir/reconcile"
    call "$dir/reconcile"
    jq -e '.result.observation.state=="exited" and .result.observation.terminal.captured==false and .result.observation.terminal.exit_code==null' "$dir/result" >/dev/null || fail 'late KILL reconciliation stayed unknown'
    [[ $(cat "$spool/signals") == '["TERM","KILL"]' ]] || fail 'reconciliation changed signals'
    rm "$spool/completion"
    call "$dir/inspect"
    jq -e '.result.state=="exited"' "$dir/result" >/dev/null || fail 'completion fact did not replay'
    pass 'late KILL reconciliation settles exact empty group with no new signal'
fi
printf 'PASS review-native %s\n' "$case_name"
