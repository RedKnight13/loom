#!/usr/bin/env bash
# Opt-in native facade. Contexts are trusted operator provisioning, not wire data.
# shellcheck disable=SC1090,SC1091,SC2016,SC2015,SC2030,SC2031,SC2154,SC2017 # Host loader supplies _nn/_rh bindings; chunk count rounds down intentionally.

loom_workflow_root() ( cd -- "${BASH_SOURCE[0]%/*}" && pwd -P; )
loom_workflow_load() {
    local ops
    ops=$(loom_workflow_root)
    source "$ops/policy.sh"
    source "$ops/state.sh"
    source "$ops/protocol.sh"
    source "$ops/coordination.sh"
    source "$ops/native.sh"
    source "$ops/transport-ssh.sh"
    source "$ops/remote-helper.sh"
    source "$ops/events.sh"
    source "$ops/output.sh"
}
loom_workflow_error() { printf 'loom workflow: %s\n' "$*" >&2; return 2; }
loom_workflow_source() (
    set -euo pipefail
    local ops file name selected digest
    ops=$(loom_workflow_root)
    {
        printf 'check-interpreter %s\n' "$(git hash-object --no-filters /usr/bin/bash)"
        for file in "$ops/loom" "$ops"/*.sh "$ops/../schemas"/*/*; do
            [[ -f $file ]] || continue
            digest=$(git hash-object --no-filters "$file") || return 2
            printf '%s %s\n' "${file#"$ops/"}" "$digest"
        done
        # Only explicit installation-module variables are inspected; no agent
        # environment or credential values enter this source fingerprint.
        for name in LOOM_COORDINATION_POLICY_MODULE LOOM_COORDINATION_PROTOCOL_MODULE LOOM_COORDINATION_STATE_MODULE LOOM_NATIVE_POLICY_MODULE LOOM_NATIVE_PROTOCOL_MODULE LOOM_NATIVE_STATE_MODULE LOOM_MAIL_POLICY_MODULE LOOM_MAIL_PROTOCOL_MODULE LOOM_MAIL_STATE_MODULE LOOM_MAIL_NATIVE_MODULE LOOM_MAIL_SSH_MODULE LOOM_SSH_PROTOCOL_MODULE LOOM_WORKFLOW_MAIL_MODULE LOOM_WORKFLOW_BRIDGE_MODULE; do
            selected=${!name:-}
            [[ -n $selected ]] || continue
            [[ -f $selected && ! -L $selected ]] || return 2
            digest=$(git hash-object --no-filters "$selected") || return 2
            printf '%s %s\n' "$name" "$digest"
            [[ $(realpath -m "${selected%/*}/..") != "${ops%/*}" ]] || continue
            for file in "${selected%/*}"/*.sh "${selected%/*}/../schemas"/*/*; do
                [[ -f $file ]] || continue
                digest=$(git hash-object --no-filters "$file") || return 2
                printf '%s/%s %s\n' "$name" "${file#"${selected%/*}/../schemas/"}" "$digest"
            done
        done
    } | git hash-object --stdin
)

loom_workflow_route() {
    local id=$1 store=${LOOM_STATE:-$HOME/.loom} key
    key=$(printf '%s\n' "$id" | git hash-object --stdin)
    [[ -f $store/v2/workflows/$key/context ]] || return 1
    printf '%s\n' "$store/v2/workflows/$key/context"
}
loom_workflow_selected() {
    local arg
    for arg in "$@"; do [[ $arg != --context && $arg != --protocol ]] || return 0; done
    if [[ $# -ge 2 && -f ${LOOM_STATE:-$HOME/.loom}/$2.json && $2 != */* ]]; then return 1; fi
    [[ $# -lt 2 ]] || ! loom_workflow_route "$2" >/dev/null || return 0
    case ${1:-} in
        mail|events|boundary) return 0 ;;
        status|list|watch|run|task|gate|peek|inbox|send|ask|reply|capacity|detect|hosts|compute|release|abandon|keep-open|request|reference|worktree|repo|base-ref|automation)
            [[ ! -d ${LOOM_STATE:-$HOME/.loom}/v2 ]] || return 0 ;;
    esac
    return 1
}
_loom_workflow_context() {
    local file=$1 value
    loom_policy_json "$file" || return 2
    jq -e 'keys==["binding","check_script","checkout","coordination","execution","mail","manifest","pin","plan","schema","source_digest","transport"] and .schema==2 and
      (.transport|IN("process","ssh")) and all(.binding,.coordination,.execution,.manifest,.pin,.plan,.source_digest;type=="string") and
      all(.check_script,.checkout,.mail; .==null or type=="string")' "$file" >/dev/null || { loom_workflow_error invalid_workflow_context; return 2; }
    for value in binding coordination execution manifest pin plan; do
        loom_policy_json "$(jq -r --arg k "$value" '.[$k]' "$file")" || return 2
    done
    _wf_context=$file
    _wf_co=$(jq -r .coordination "$file")
    _wf_binding=$(jq -r .binding "$file")
    _wf_pin=$(jq -r .pin "$file")
    _wf_plan=$(jq -r .plan "$file")
    _wf_exec=$(jq -r .execution "$file")
    _wf_workspace=$(jq -r .workspace "$_wf_binding")
    _wf_id=$(jq -r .target.assignment_id "$_wf_binding")
    _wf_task=$(jq -r .task_id "$_wf_plan")
    _wf_store=$(jq -r .state_root "$_wf_co")
    [[ ${LOOM_STATE:-$_wf_store} == "$_wf_store" ]] || { loom_workflow_error authority_store_mismatch; return 2; }
    export LOOM_STATE=$_wf_store
    _wf_dir=$_wf_store/v2/workflows/$(printf '%s\n' "$_wf_id" | git hash-object --stdin)
    [[ ! -f $_wf_store/$_wf_id.json ]] || { loom_workflow_error ambiguous_legacy_assignment; return 2; }
    jq -e --slurpfile b "$_wf_binding" --slurpfile p "$_wf_pin" --slurpfile plan "$_wf_plan" '
      .transport==$p[0].transport and $p[0].provider=="native" and $plan[0].binding==$b[0] and
      $plan[0].actor==$b[0].actor' "$file" >/dev/null || { loom_workflow_error binding_mismatch; return 2; }
    if [[ $(jq -r .transport "$file") == process ]]; then
        jq -e --arg b "$_wf_binding" --arg p "$_wf_pin" '.binding==$b and .pin==$p' "$_wf_exec" >/dev/null || return 2
    fi
    [[ $(loom_policy_digest "$(jq -r .manifest "$file")") == "$(jq -r .manifest_digest "$_wf_binding")" ]] || { loom_workflow_error manifest_changed; return 2; }
    jq -e 'keys==["base_sha","check_digest","report_offset","schema"] and .schema==1 and
      (.base_sha|test("^[0-9a-f]{40}$")) and (.report_offset|type=="number" and .>=0 and .==floor) and
      (.check_digest==null or (.check_digest|type=="string"))' "$(jq -r .manifest "$file")" >/dev/null || return 2
}
_loom_workflow_policy() {
    loom_policy_check "$_wf_pin" "$(jq -r .config "$_wf_co")" "$(jq -r .hosts "$_wf_co")" "$(jq -r .profiles "$_wf_co")" || return 2
}
_loom_workflow_source_check() {
    [[ $(loom_workflow_source) == "$(jq -r .source_digest "$_wf_context")" ]] || { loom_workflow_error source_changed; return 2; }
}
_loom_workflow_request() {
    local op=$1 args=$2 revision=${3:-null} key=${4:-$1}
    jq -cn --arg op "$op" --argjson args "$args" --argjson rev "$revision" --arg key "$key" --slurpfile b "$_wf_binding" --slurpfile p "$_wf_pin" '
      {protocol:"loom.execution",version:{major:1,minor:0},request_id:$key,operation_id:(if ($op|IN("execution.start","execution.stop","execution.release","workspace.seal","workspace.check")) then $key else null end),idempotency_key:(if ($op|IN("execution.start","execution.stop","execution.release","workspace.seal","workspace.check")) then $key else null end),op:$op,actor:$b[0].actor,target:$b[0].target,expected_revision:$rev,timeout_ms:$p[0].limits.operation_timeout_ms,args:$args,extensions:{}}'
}
_loom_workflow_execute() {
    if [[ $(jq -r .transport "$_wf_context") == process ]]; then loom_native_handle "$_wf_exec" "$1"
    else loom_ssh_handle "$_wf_exec" "$1"; fi
}
_loom_workflow_inspect() {
    _loom_workflow_request execution.inspect '{}' > "$_wf_tmp/request"
    _loom_workflow_execute "$_wf_tmp/request" > "$_wf_tmp/inspect" || return $?
}
_loom_workflow_settled() {
    _loom_workflow_inspect || return $?
    jq -e '.ok and .result.state=="exited" and .result.identity_verified and .result.terminal.captured' "$_wf_tmp/inspect" >/dev/null || { loom_workflow_error settlement_unknown; return 2; }
}
_loom_workflow_local() {
    [[ $(jq -r .transport "$_wf_context") == process ]] || { loom_workflow_error 'unsupported: remote report/seal/check/collect importer; no local fallback'; return 2; }
    _loom_workflow_policy || return 2
    [[ -d $_wf_workspace && ! -L $_wf_workspace && $(realpath -e "$_wf_workspace") == "$_wf_workspace" ]] || return 2
}
_loom_workflow_task() {
    loom_state_get task "$_wf_task" > "$_wf_tmp/task" || return $?
    jq -e --slurpfile b "$_wf_binding" '.run_id==$b[0].actor.run_id and .data.attempt_ids[-1]==$b[0].target.attempt_id' "$_wf_tmp/task" >/dev/null || { loom_workflow_error superseded_attempt; return 2; }
}
_loom_workflow_launch_authority() {
    loom_state_get run "$(jq -r .actor.run_id "$_wf_binding")" > "$_wf_tmp/run" || return $?
    jq -e --slurpfile b "$_wf_binding" --arg task "$_wf_task" '
      .epoch==$b[0].actor.epoch and .data.owner_id==$b[0].actor.id and
      .data.tasks[$task].state=="running" and .data.tasks[$task].attempt_ids[-1]==$b[0].target.attempt_id and
      .data.attempts[$b[0].target.attempt_id].launch_authorized==true and
      (.data.attempts[$b[0].target.attempt_id].stop_requested//false|not) and
      .data.attempts[$b[0].target.attempt_id].binding==$b[0]' "$_wf_tmp/run" >/dev/null || { loom_workflow_error launch_authority_changed; return 2; }
}
_loom_workflow_promotion_authority() {
    loom_state_get run "$(jq -r .actor.run_id "$_wf_binding")" > "$_wf_tmp/promotion-run" || return $?
    jq -e --slurpfile b "$_wf_binding" --arg task "$_wf_task" '.epoch==$b[0].actor.epoch and .data.owner_id==$b[0].actor.id and .data.tasks[$task].state=="review" and .data.tasks[$task].attempt_ids[-1]==$b[0].target.attempt_id and .data.attempts[$b[0].target.attempt_id].binding==$b[0]' "$_wf_tmp/promotion-run" >/dev/null || { loom_workflow_error promotion_authority_changed; return 2; }
}
_loom_workflow_transition() {
    local to=$1 proof=$2 key
    key=workflow-$to-$(git hash-object "$proof")
    jq --slurpfile proof "$proof" '.proofs=[$proof[0]]' "$_wf_co" > "$_wf_tmp/coordination"
    jq -cn --arg to "$to" --arg key "$key" --arg task "$_wf_task" --slurpfile b "$_wf_binding" --slurpfile t "$_wf_tmp/task" --slurpfile p "$proof" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$key,operation_id:$key,idempotency_key:$key,op:"task.update",actor:$b[0].actor,target:{assignment_id:null,attempt_id:null,host_id:null},expected_revision:$t[0].revision,timeout_ms:30000,args:{task_id:$task,transition:$to,evidence_refs:[$p[0].evidence_ref]},extensions:{}}' > "$_wf_tmp/transition"
    loom_coordination_handle "$_wf_tmp/coordination" "$_wf_tmp/transition"
}
_loom_workflow_proof() {
    jq -cn --arg kind "$1" --arg task "$_wf_task" --slurpfile b "$_wf_binding" --slurpfile t "$_wf_tmp/task" '{kind:$kind,run_id:$b[0].actor.run_id,task_id:$task,revision:$t[0].revision,epoch:$b[0].actor.epoch,attempt_id:$b[0].target.attempt_id,evidence_ref:("workflow/"+$kind),confirmed_stopped:true,quiescent:true}'
}
# Seal a private clone with an isolated Git index; workers never stage or commit.
_loom_workflow_seal() (
    local old tree sha index _rw_workspace=$_wf_workspace
    old=$(_loom_remote_git -C "$_wf_workspace" rev-parse HEAD) || return 2
    index=$_wf_tmp/index
    export GIT_INDEX_FILE=$index
    _loom_rw_git_index read-tree "$old" || return 2
    _loom_remote_git -C "$_wf_workspace" ls-files -z --cached --others --exclude-standard -- ':!:WORK.md' ':!:REPORT.md' ':!:.loom' > "$_wf_tmp/files" || return 2
    _loom_rw_git_index update-index --add --remove -z --stdin < "$_wf_tmp/files" || return 2
    tree=$(_loom_rw_git_index write-tree) || return 2
    if [[ $tree == "$(_loom_remote_git -C "$_wf_workspace" rev-parse 'HEAD^{tree}')" ]]; then printf '%s\n' "$old"; return; fi
    sha=$(printf 'Loom sealed worker result\n' | _loom_remote_git -C "$_wf_workspace" -c core.hooksPath=/dev/null commit-tree "$tree" -p "$old") || return 2
    _loom_remote_git -C "$_wf_workspace" update-ref HEAD "$sha" "$old" || return 2
    # Update the workspace index after the compare-and-swap succeeds.
    GIT_INDEX_FILE="$_wf_workspace/.git/index" _loom_rw_git_index read-tree "$sha" || return 2
    printf '%s\n' "$sha"
)
_loom_workflow_clean_sha() {
    local current
    current=$(_loom_remote_git -C "$_wf_workspace" rev-parse HEAD) || return 2
    [[ -z $(_loom_remote_git -C "$_wf_workspace" status --porcelain --untracked-files=all -- ':!:WORK.md' ':!:REPORT.md' ':!:.loom') ]] || { loom_workflow_error workspace_changed; return 2; }
    [[ $current == "$(jq -r .sha "$_wf_dir/harvest")" ]] || { loom_workflow_error checked_source_changed; return 2; }
    [[ -f $_wf_workspace/REPORT.md && ! -L $_wf_workspace/REPORT.md && $(loom_policy_digest "$_wf_workspace/REPORT.md") == "$(jq -r .proof.report_digest "$_wf_dir/harvest")" ]] || { loom_workflow_error report_changed; return 2; }
    printf '%s\n' "$current"
}
_loom_workflow_harvest() {
    local offset report state code digest sha proof_kind transition
    if [[ $(jq -r .transport "$_wf_context") == ssh ]]; then _loom_workflow_remote_harvest; return; fi
    _loom_workflow_local && _loom_workflow_settled && _loom_workflow_task || return $?
    if [[ $(jq -r .data.state "$_wf_tmp/task") == review && -f $_wf_dir/harvest ]]; then
        _loom_workflow_clean_sha >/dev/null || return 2
        cat "$_wf_dir/harvest"; return
    fi
    offset=$(jq -r .report_offset "$(jq -r .manifest "$_wf_context")")
    report=$_wf_workspace/REPORT.md
    [[ -f $report && ! -L $report && $(stat -c %s "$report") -le 1048576 ]] || { loom_workflow_error current_report_missing; return 2; }
    state=$(tail -n +"$((offset+1))" "$report" | sed -nE 's/^state: (ready|blocked|failed|waiting) — .+/\1/p' | tail -1)
    [[ -n $state ]] || { loom_workflow_error current_report_missing; return 2; }
    digest=$(loom_policy_digest "$report")
    code=$(jq -r .result.terminal.exit_code "$_wf_tmp/inspect")
    proof_kind=settlement; transition=failed
    if [[ $code == 0 && $state == ready ]]; then proof_kind=harvest; transition=review; fi
    _loom_workflow_proof "$proof_kind" | jq --arg state "$state" --arg digest "$digest" --argjson code "$code" '.+{current_report:true,report_state:$state,report_digest:$digest,exit_code:$code}' > "$_wf_tmp/proof"
    if [[ $transition == review ]]; then sha=$(_loom_workflow_seal) || return $?; else sha=$(_loom_remote_git -C "$_wf_workspace" rev-parse HEAD) || return 2; fi
    # Persist verified evidence before committing the authority transition.
    jq -cn --arg sha "$sha" --slurpfile proof "$_wf_tmp/proof" --slurpfile execution "$_wf_tmp/inspect" '{sha:$sha,proof:$proof[0],execution:$execution[0]}' | loom_output_atomic "$_wf_dir/harvest" || return 1
    _loom_workflow_transition "$transition" "$_wf_tmp/proof"
}
_loom_workflow_verify() {
    local sha script rc=0 digest intent data
    if [[ $(jq -r .transport "$_wf_context") == ssh ]]; then _loom_workflow_remote_verify; return; fi
    _loom_workflow_local && _loom_workflow_source_check && _loom_workflow_settled && _loom_workflow_task || return $?
    [[ $(jq -r .data.state "$_wf_tmp/task") == review ]] || { loom_workflow_error review_required; return 2; }
    sha=$(_loom_workflow_clean_sha) || return 2
    script=$(jq -r '.check_script//empty' "$_wf_context")
    [[ -n $script ]] && loom_policy_file "$script" || { loom_workflow_error check_script_required; return 2; }
    digest=$(loom_policy_digest "$script")
    [[ $digest == "$(jq -r .check_digest "$(jq -r .manifest "$_wf_context")")" ]] || { loom_workflow_error check_script_changed; return 2; }
    exec 9> "$_wf_dir/check.lock"; flock -w 2 9 || { loom_workflow_error check_busy; return 1; }
    intent=$(jq -cn --arg sha "$sha" --arg digest "$digest" --arg source "$(loom_workflow_source)" --arg config "$(jq -r .config_digest "$_wf_pin")" '{sha:$sha,digest:$digest,source:$source,config:$config}' | git hash-object --stdin)
    if [[ -f $_wf_dir/check-intent ]]; then
        [[ $(cat "$_wf_dir/check-intent") == "$intent" ]] || { loom_workflow_error check_intent_changed; return 2; }
        [[ -f $_wf_dir/check ]] || { loom_workflow_error check_outcome_unknown; return 1; }
        cat "$_wf_dir/check"
        [[ $(jq .check_exit "$_wf_dir/check") == 0 ]] || return 1
        _loom_workflow_local_check_receipt "$sha"
        return $?
    fi
    printf '%s\n' "$intent" | loom_output_atomic "$_wf_dir/check-intent" || return 1
    _loom_remote_git -c core.hooksPath=/dev/null clone -q --no-hardlinks --no-checkout "$_wf_workspace" "$_wf_tmp/check" || return 2
    _loom_remote_git -C "$_wf_tmp/check" -c core.hooksPath=/dev/null checkout -q --detach "$sha" || return 2
    cp "$script" "$_wf_tmp/check-script"
    data=$_wf_store/workflow-checks/${_wf_dir##*/}
    _loom_state_ancestors "$data" || return 2
    mkdir -p "${data%/*}" && mkdir "$data" || return 1
    _loom_state_private "$data" dir || return 2
    jq -cn --arg dir "$_wf_tmp" --arg result "$data" --arg digest "$digest" --arg interpreter "$(loom_policy_digest /usr/bin/bash)" --slurpfile pin "$_wf_pin" '{workspace:($dir+"/check"),script:($dir+"/check-script"),result_dir:$result,script_digest:$digest,interpreter_digest:$interpreter,timeout_ms:([$pin[0].limits.operation_timeout_ms,30000]|min),output_bytes:65536}' > "$_wf_tmp/check-plan"
    setsid --wait /usr/bin/bash "$(loom_workflow_root)/workflow.sh" --check-keeper "$_wf_tmp/check-plan" > "$_wf_dir/check.log" 2>&1 || rc=$?
    rm -f -- "$data/pipe"
    [[ $rc == 0 && -f $data/check-terminal ]] || { loom_workflow_error check_outcome_unknown; return 1; }
    rc=$(jq -r .exit_code "$data/check-terminal")
    [[ $sha == "$(_loom_workflow_clean_sha)" ]] || return 2
    jq -cn --arg sha "$sha" --arg digest "$digest" --arg source "$(loom_workflow_source)" --arg config "$(jq -r .config_digest "$_wf_pin")" --argjson code "$rc" --slurpfile process "$data/check-terminal" '{checked_sha:$sha,check_digest:$digest,source_digest:$source,config_digest:$config,check_exit:$code,transport:"process",captured:true,process:$process[0]}' | loom_output_atomic "$_wf_dir/check" || return 1
    cat "$_wf_dir/check"
    (( rc==0 )) || return 1
}
_loom_workflow_local_check_receipt() {
    local sha=$1 script digest intent data
    script=$(jq -r '.check_script//empty' "$_wf_context")
    loom_policy_file "$script" || return 2
    digest=$(loom_policy_digest "$script")
    [[ $digest == "$(jq -r .check_digest "$(jq -r .manifest "$_wf_context")")" ]] || return 2
    intent=$(jq -cn --arg sha "$sha" --arg digest "$digest" --arg source "$(loom_workflow_source)" --arg config "$(jq -r .config_digest "$_wf_pin")" '{sha:$sha,digest:$digest,source:$source,config:$config}' | git hash-object --stdin)
    [[ -f $_wf_dir/check-intent && $(cat "$_wf_dir/check-intent") == "$intent" ]] || return 2
    data=$_wf_store/workflow-checks/${_wf_dir##*/}/check-terminal
    loom_policy_json "$data" && loom_policy_json "$_wf_dir/check" || return 2
    jq -e --arg sha "$sha" --arg digest "$digest" --arg source "$(loom_workflow_source)" --arg config "$(jq -r .config_digest "$_wf_pin")" --slurpfile p "$data" '.transport=="process" and .check_exit==0 and .captured==true and .checked_sha==$sha and .check_digest==$digest and .source_digest==$source and .config_digest==$config and .process==$p[0] and .process.captured==true and .process.exit_code==0 and .process.group_empty==true and .process.escaped==false and .process.timed_out==false and .process.output_eof==true' "$_wf_dir/check" >/dev/null || { loom_workflow_error checked_process_receipt_required; return 2; }
}
_loom_workflow_collect_ref() {
    local checkout=$1 target=$2 sha=$3 old
    old=$(_loom_remote_git -C "$checkout" show-ref --verify --hash "$target" 2>/dev/null) || old=''
    if [[ -n $old ]]; then
        [[ -f $_wf_dir/collect ]] && jq -e --arg ref "$target" --arg old "$old" '.ref==$ref and .collected_sha==$old' "$_wf_dir/collect" >/dev/null || { loom_workflow_error collected_ref_changed_or_unowned; return 2; }
        [[ $old == "$sha" ]] || { loom_workflow_error collected_ref_changed; return 2; }
    else
        [[ ! -f $_wf_dir/collect ]] || { loom_workflow_error collected_ref_removed; return 2; }
        old=0000000000000000000000000000000000000000
    fi
    _loom_remote_git -C "$checkout" update-ref "$target" "$sha" "$old"
}
_loom_workflow_collect() {
    local sha checkout target
    if [[ $(jq -r .transport "$_wf_context") == ssh ]]; then _loom_workflow_remote_collect; return; fi
    _loom_workflow_local && _loom_workflow_source_check && _loom_workflow_settled && _loom_workflow_task || return $?
    [[ $(jq -r .data.state "$_wf_tmp/task") == review ]] || return 2
    sha=$(_loom_workflow_clean_sha) || return 2
    _loom_workflow_promotion_authority && _loom_workflow_local_check_receipt "$sha" || return $?
    checkout=$(jq -r '.checkout//empty' "$_wf_context")
    [[ -n $checkout && -d $checkout && ! -L $checkout && $(realpath -e "$checkout") == "$checkout" ]] || return 2
    target=refs/loom/collected/$(printf '%s\n' "$_wf_id" | git hash-object --stdin)
    _loom_remote_git -C "$checkout" -c core.hooksPath=/dev/null fetch -q --no-tags "$_wf_workspace" "$sha" || return 2
    _loom_workflow_collect_ref "$checkout" "$target" "$sha" || return 2
    [[ $sha == "$(_loom_workflow_clean_sha)" ]] || return 2
    jq -cn --arg sha "$sha" --arg ref "$target" '{collected_sha:$sha,ref:$ref}' | loom_output_atomic "$_wf_dir/collect" || return 1
    cat "$_wf_dir/collect"
}
_loom_workflow_ack() {
    local reviewed=$1 sha
    if [[ $(jq -r .transport "$_wf_context") == ssh ]]; then _loom_workflow_remote_ack "$reviewed"; return; fi
    _loom_workflow_local && _loom_workflow_source_check && _loom_workflow_settled && _loom_workflow_task || return $?
    sha=$(_loom_workflow_clean_sha) || return 2
    [[ $reviewed == "$sha" ]] || { loom_workflow_error exact_reviewed_sha_required; return 2; }
    _loom_workflow_promotion_authority && _loom_workflow_local_check_receipt "$sha" || return $?
    jq -e --arg sha "$sha" '.collected_sha==$sha' "$_wf_dir/collect" >/dev/null || return 2
    [[ $(_loom_remote_git -C "$(jq -r .checkout "$_wf_context")" rev-parse "$(jq -r .ref "$_wf_dir/collect")") == "$sha" ]] || { loom_workflow_error collected_ref_changed; return 2; }
    _loom_workflow_proof accept | jq --arg sha "$sha" --slurpfile p "$_wf_pin" --slurpfile b "$_wf_binding" '.+{reviewed:true,check_exit:0,checked_sha:$sha,collected_sha:$sha,current_sha:$sha,config_digest:$p[0].config_digest,manifest_digest:$b[0].manifest_digest}' > "$_wf_tmp/proof"
    _loom_workflow_transition succeeded "$_wf_tmp/proof"
}
_loom_workflow_dispatch() {
    local authorization
    _loom_workflow_policy && _loom_workflow_source_check || return 2
    if [[ $(jq -r .transport "$_wf_context") == process ]]; then
        _loom_workflow_local || return 2
        [[ $(_loom_remote_git -C "$_wf_workspace" rev-parse HEAD) == "$(jq -r .base_sha "$(jq -r .manifest "$_wf_context")")" ]] || { loom_workflow_error base_changed; return 2; }
    else
        loom_ssh_preflight "$_wf_exec" > "$_wf_tmp/preflight" || return $?
        _loom_workflow_request hello '{"versions":[{"major":1,"minor":0}],"required_capabilities":["workspace.seal.v1","workspace.check.v1","workspace.export.v1","workspace.read.v1"]}' > "$_wf_tmp/hello"
        _loom_workflow_execute "$_wf_tmp/hello" > "$_wf_tmp/hello-result" || return $?
    fi
    # S6 validates the exact operator-provisioned calibration/workspace proof;
    # the facade never asserts those booleans on behalf of a real provider.
    loom_coordination_authorize "$_wf_co" "$_wf_plan" > "$_wf_tmp/authorization" || return $?
    if [[ $(jq -r .transport "$_wf_context") == process ]]; then
    authorization=$(jq -r .authorization "$_wf_exec")
    if [[ -f $authorization ]]; then cmp -s "$authorization" "$_wf_tmp/authorization" || { loom_workflow_error authorization_conflict; return 2; }
    else loom_output_atomic "$authorization" < "$_wf_tmp/authorization" || return 1; fi
    fi
    if [[ -f $_wf_dir/context ]]; then cmp -s "$_wf_context" "$_wf_dir/context" || { loom_workflow_error route_conflict; return 2; }
    else loom_output_atomic "$_wf_dir/context" < "$_wf_context" || return 1; fi
    jq -cn --arg id "$_wf_id" --slurpfile a "$_wf_tmp/authorization" '{assignment_id:$id,authorization:$a[0],ticket_provider:"github",ticket_access:"not_run_pinned_assignment"}'
}
_loom_workflow_raw() {
    local command=$1 context=$2 request=$3 op module
    loom_protocol_check_request "$request" || return 2
    op=$(jq -r .op "$request")
    if jq -e '.schema==2 and has("coordination")' "$context" >/dev/null; then
        _loom_workflow_context "$context" || return 2
        if [[ $op == execution.start ]]; then _loom_workflow_source_check && _loom_workflow_policy && _loom_workflow_launch_authority || return 2; fi
        case $command in
            run|task|gate) context=$_wf_co ;;
            mail|send|ask|reply|peek|inbox) context=$(jq -r .mail "$_wf_context") ;;
            *) context=$_wf_exec ;;
        esac
    fi
    case $command:$op in
        run:run.*|task:task.*|gate:gate.*) loom_coordination_handle "$context" "$request" ;;
        mail:mail.*|send:mail.send|ask:mail.send|reply:mail.reply|peek:mail.poll|inbox:mail.poll)
            module=${LOOM_WORKFLOW_MAIL_MODULE:-$(loom_workflow_root)/mail.sh}
            [[ -f $module ]] || { loom_workflow_error mail_module_not_installed; return 2; }
            source "$module"; loom_mail_handle "$context" "$request" ;;
        workspace:workspace.*|start:execution.start|launch:execution.start|show:execution.inspect|status:execution.inspect|read:execution.read|stop:execution.stop|release:execution.release|reconcile:execution.reconcile|list:execution.list)
            if jq -e 'has("helper_command")' "$context" >/dev/null; then loom_ssh_handle "$context" "$request"; else loom_native_handle "$context" "$request"; fi ;;
        *) loom_workflow_error command_request_mismatch ;;
    esac
}
loom_workflow_main() (
    set -euo pipefail
    umask 077
    loom_workflow_load
    local command=${1:-} context='' request='' protocol='' id='' reviewed='' limit=1000 cursor=0 arg rc=0 args
    local _wf_context _wf_co _wf_binding _wf_pin _wf_plan _wf_exec _wf_workspace _wf_id _wf_task _wf_store _wf_dir _wf_tmp
    shift || true
    _wf_tmp=$(mktemp -d)
    trap 'rm -rf -- "$_wf_tmp"' EXIT
    while (( $# )); do
        case $1 in
            --context|--request|--protocol|--reviewed|--deadline-ms|--after)
                (( $#>=2 )) || return 2
                case $1 in
                    --context) context=$2 ;; --request) request=$2 ;; --protocol) protocol=$2 ;;
                    --reviewed) reviewed=$2 ;; --deadline-ms) limit=$2 ;; --after) cursor=$2 ;;
                esac; shift 2 ;;
            *) [[ -z $id ]] || { loom_workflow_error unexpected_argument; return 2; }; id=$1; shift ;;
        esac
    done
    [[ -z $protocol || $protocol == 1 ]] || { loom_workflow_error unsupported_protocol; return 2; }
    if [[ -z $context && -n $id ]]; then context=$(loom_workflow_route "$id") || return 2; fi
    [[ -n $context ]] || { loom_workflow_error 'explicit --context required for native or mixed scopes'; return 2; }
    if [[ -n $request ]]; then
        _loom_workflow_raw "$command" "$context" "$request"
        return
    fi
    [[ -z $protocol ]] || { loom_workflow_error 'protocol 1 requires an exact --request'; return 2; }
    if [[ $command == boundary ]]; then
        arg=${LOOM_WORKFLOW_BRIDGE_MODULE:-$(loom_workflow_root)/worker-bridge.sh}
        [[ -f $arg ]] || { loom_workflow_error mail_bridge_not_installed; return 2; }
        source "$arg"; loom_worker_bridge_boundary "$context" 20; return
    fi
    _loom_workflow_context "$context" || return 2
    [[ -z $id || $id == "$_wf_id" ]] || { loom_workflow_error assignment_mismatch; return 2; }
    mkdir -p "$_wf_dir"
    _loom_native_private "$_wf_dir" dir || return 2
    # Serialize facade evidence operations, never worker runtime or raw mail reads.
    exec 8> "$_wf_dir/workflow.lock"
    flock -w 2 8 || { loom_workflow_error workflow_busy; return 2; }
    case $command in
        dispatch) _loom_workflow_dispatch ;;
        start|launch)
            _loom_workflow_policy && _loom_workflow_source_check && _loom_workflow_launch_authority || return 2
            args=$(jq -cn --slurpfile b "$_wf_binding" --slurpfile p "$_wf_pin" '{workspace_id:$b[0].workspace_id,profile_id:$p[0].profile.id,profile_digest:$b[0].profile_digest,argv:$p[0].argv,prompt_ref:$b[0].prompt_ref,model:$p[0].model,effort:$p[0].effort,limits:$b[0].limits,manifest_digest:$b[0].manifest_digest}')
            _loom_workflow_request execution.start "$args" null "$(jq -r .operation_id "$_wf_plan")" > "$_wf_tmp/request"
            _loom_workflow_execute "$_wf_tmp/request" ;;
        show|status) _loom_workflow_inspect; cat "$_wf_tmp/inspect" ;;
        read)
            _loom_workflow_request execution.read '{"source":"combined.base64","limit_bytes":65536}' > "$_wf_tmp/request"
            _loom_workflow_execute "$_wf_tmp/request" ;;
        stop|reconcile)
            # Mutations with revision/kill/reason choices require explicit wire args.
            loom_workflow_error 'use --request with exact revision, operation ID and arguments'; return 2 ;;
        harvest) _loom_workflow_harvest ;;
        verify) _loom_workflow_verify ;;
        collect) _loom_workflow_collect ;;
        ack) _loom_workflow_ack "$reviewed" ;;
        events) loom_events_read "$cursor" 100 ;;
        capacity) loom_policy_capacity "$(jq -r .config "$_wf_co")" "$(jq -r .hosts "$_wf_co")" "$(jq -r .profiles "$_wf_co")" ;;
        watch)
            [[ $limit =~ ^[0-9]{1,5}$ ]] && (( limit>=100 && limit<=30000 )) || return 2
            # Hard outer deadline includes validation and inspection. No mail read.
            timeout --kill-after=1 "$(awk -v n="$limit" 'BEGIN{print n/1000}')" bash "$(loom_workflow_root)/workflow.sh" --watch "$context" > "$_wf_tmp/watch" || rc=$?
            if (( rc==124 || rc==137 )); then jq -cn '{state:"unknown",deadline_reached:true,runner:"stopped",mail_consumed:false}'
            else cat "$_wf_tmp/watch"; return "$rc"; fi ;;
        *) loom_workflow_error 'unsupported native workflow operation; no adapter fallback'; return 2 ;;
    esac
)
_loom_workflow_watch() (
    set -euo pipefail
    loom_workflow_load
    local _wf_context _wf_co _wf_binding _wf_pin _wf_plan _wf_exec _wf_workspace _wf_id _wf_task _wf_store _wf_dir _wf_tmp
    _wf_tmp=$(mktemp -d); trap 'rm -rf -- "$_wf_tmp"' EXIT
    _loom_workflow_context "$1"
    while :; do
        _loom_workflow_inspect
        if [[ $(jq -r .result.state "$_wf_tmp/inspect") == exited ]]; then cat "$_wf_tmp/inspect"; return; fi
        sleep 0.1
    done
)

# Host-only artifact importer. Invoked by the pinned S7-aware SSH helper, never
# a coordination authority and never a request-supplied command dispatcher.
_loom_remote_workflow_config() {
    local file=$1 item
    loom_policy_json "$file" || return 2
    jq -e 'keys==(["schema","manifest","check_script","check_digest","check_timeout_ms","artifact_bytes","max_files","max_worktree_bytes","author_name","author_email","check_authorized","output_bytes","allow_kill","seal_authorized","interpreter_digest"]|sort) and .schema==1 and .check_authorized==true and .seal_authorized==true and .allow_kill==true and
      (.output_bytes|type=="number" and floor==. and .>=1024 and .<=1048576) and
      all(.manifest,.check_script,.check_digest;type=="string") and
      all(.author_name,.author_email;type=="string" and length>0 and length<=128 and (test("[[:cntrl:]<>]")|not)) and
      (.check_timeout_ms|type=="number" and floor==. and .>=1 and .<=30000) and
      (.artifact_bytes|type=="number" and floor==. and .>=1 and .<=67108864) and
      (.max_files|type=="number" and floor==. and .>=1 and .<=10000) and
      (.max_worktree_bytes|type=="number" and floor==. and .>=1 and .<=67108864)' "$file" >/dev/null || return 2
    [[ -x /usr/bin/bash && ! -L /usr/bin/bash && $(loom_policy_digest /usr/bin/bash) == "$(jq -r .interpreter_digest "$file")" ]] || return 2
    for item in manifest check_script; do _loom_ssh_private "$(jq -r --arg k "$item" '.[$k]' "$file")" || return 2; done
    loom_policy_json "$(jq -r .manifest "$file")" || return 2
    jq -e 'keys==["base_sha","check_digest","report_offset","schema"] and .schema==1 and (.base_sha|test("^[0-9a-f]{40}$")) and (.report_offset|type=="number" and floor==. and .>=0)' "$(jq -r .manifest "$file")" >/dev/null || return 2
    [[ $(loom_policy_digest "$(jq -r .manifest "$file")") == "$(jq -r .manifest_digest "$_nn_binding")" &&
       $(loom_policy_digest "$(jq -r .check_script "$file")") == "$(jq -r .check_digest "$file")" &&
       $(jq -r .check_digest "$file") == "$(jq -r .check_digest "$(jq -r .manifest "$file")")" ]] || return 2
}
_loom_rw_error() {
    loom_protocol_receipt "$_rw_request" "${2:-refused}" "$1" "$3"
    [[ ${2:-refused} == refused ]] && return 2
    return 1
}
_loom_rw_response() {
    jq -cn --slurpfile q "$_rw_request" --slurpfile result "$1" --argjson durable "${2:-false}" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '$q[0]|{protocol,version,request_id,operation_id,op,target}+{ok:true,status:"completed",revision:1,durable:$durable,result:$result[0],error:null,effects:[],evidence:[],observed_at:$at,extensions:{}}'
}
_loom_rw_current() {
    [[ $(_loom_remote_git -C "$_rw_workspace" rev-parse HEAD) == "$(jq -r .sha "$_rh_spool/workflow-seal")" ]] || return 2
    [[ -z $(_loom_remote_git -C "$_rw_workspace" status --porcelain --untracked-files=all -- ':!:WORK.md' ':!:REPORT.md' ':!:.loom') ]] || return 2
    [[ -f $_rw_workspace/REPORT.md && ! -L $_rw_workspace/REPORT.md && $(loom_policy_digest "$_rw_workspace/REPORT.md") == "$(jq -r .report_digest "$_rh_spool/workflow-seal")" ]] || return 2
    jq -e --argjson source "$_rh_identity" '.source==$source' "$_rh_spool/workflow-seal" >/dev/null
}
_loom_rw_artifact() {
    local name=$1 source=$2 limit=$3 size digest
    size=$(stat -c %s -- "$source") || return 2
    (( size<=limit )) || return 2
    digest=$(loom_policy_digest "$source") || return 2
    loom_output_atomic "$_rh_spool/$name" < "$source" || return 1
    jq -cn --arg name "$name" --arg digest "$digest" --arg sha "$_rw_sha" --argjson bytes "$size" '{artifact:$name,digest:$digest,bytes:$bytes,sha:$sha}' | loom_output_atomic "$_rh_spool/$name-meta"
}
_loom_rw_seal() {
    local file bytes=0 count=0 size tree before sha old offset state report_digest limit base
    base=$(jq -r .base_sha "$_rw_manifest")
    jq -e --slurpfile b "$_nn_binding" --arg base "$base" '.args=={workspace_id:$b[0].workspace_id,base_sha:$base,manifest_digest:$b[0].manifest_digest}' "$_rw_request" >/dev/null || { _loom_rw_error policy_denied refused 'Seal differs from provisioned manifest'; return; }
    old=$(_loom_remote_git -C "$_rw_workspace" rev-parse HEAD) || return 2
    [[ $old == "$base" ]] || { _loom_rw_error identity_mismatch refused 'Workspace base moved before seal'; return; }
    [[ -f $_rw_workspace/REPORT.md && ! -L $_rw_workspace/REPORT.md && $(stat -c %s "$_rw_workspace/REPORT.md") -le 1048576 ]] || { _loom_rw_error policy_denied refused 'Current regular report required'; return; }
    offset=$(jq -r .report_offset "$_rw_manifest")
    state=$(tail -n +"$((offset+1))" "$_rw_workspace/REPORT.md" | sed -nE 's/^state: (ready|blocked|failed|waiting) — .+/\1/p' | tail -1)
    [[ -n $state ]] || { _loom_rw_error policy_denied refused 'No fresh report state after consumed boundary'; return; }
    report_digest=$(loom_policy_digest "$_rw_workspace/REPORT.md")
    # Null-delimited names stay data, including spaces/quotes/newlines. Only
    # ordinary files enter a commit; links, submodules and reserved paths refuse.
    _loom_remote_git -C "$_rw_workspace" ls-files -z --cached --others --exclude-standard -- ':!:WORK.md' ':!:REPORT.md' ':!:.loom' > "$_rw_tmp/files" || return 2
    while IFS= read -r -d '' file; do
        [[ $file != /* && $file != ../* && $file != */../* && $file != .git && $file != .git/* && ! -L $_rw_workspace/$file ]] || return 2
        if [[ -e $_rw_workspace/$file ]]; then
            [[ -f $_rw_workspace/$file ]] || return 2
            size=$(stat -c %s -- "$_rw_workspace/$file"); bytes=$((bytes+size)); count=$((count+1))
            (( bytes<=$(jq -r .max_worktree_bytes "$_rh_workflow") && count<=$(jq -r .max_files "$_rh_workflow") )) || return 2
        fi
    done < "$_rw_tmp/files"
    # Isolated index; neutral Git environment; no caller Git hooks or identity.
    local index=$_rw_tmp/index
    GIT_INDEX_FILE=$index _loom_rw_git_index read-tree "$old" || return 2
    GIT_INDEX_FILE=$index _loom_rw_git_index update-index --add --remove -z --stdin < "$_rw_tmp/files" || return 2
    tree=$(GIT_INDEX_FILE=$index _loom_rw_git_index write-tree) || return 2
    before=$(_loom_remote_git -C "$_rw_workspace" rev-parse "$old^{tree}") || return 2
    sha=$old
    if [[ $tree != "$before" ]]; then
        sha=$(printf 'Loom sealed worker result\n' | _loom_remote_git -C "$_rw_workspace" -c "user.name=$(jq -r .author_name "$_rh_workflow")" -c "user.email=$(jq -r .author_email "$_rh_workflow")" -c commit.gpgsign=false commit-tree "$tree" -p "$old") || return 2
        _loom_remote_git -C "$_rw_workspace" update-ref HEAD "$sha" "$old" || return 2
    fi
    _loom_remote_git -C "$_rw_workspace" read-tree "$sha" || return 2
    [[ $report_digest == "$(loom_policy_digest "$_rw_workspace/REPORT.md")" ]] || return 2
    _rw_sha=$sha
    jq -cn --slurpfile b "$_nn_binding" --slurpfile p "$_nn_pin" --slurpfile inspect "$_rw_tmp/inspect" --arg sha "$sha" --arg base "$base" --arg report "$report_digest" --arg state "$state" --argjson source "$_rh_identity" '{workspace_id:$b[0].workspace_id,base_sha:$base,manifest_digest:$b[0].manifest_digest,sha:$sha,report_state:$state,report_digest:$report,execution:$inspect[0].result,config_digest:$p[0].config_digest,source:$source}' > "$_rw_tmp/result"
    loom_output_atomic "$_rh_spool/workflow-seal" < "$_rw_tmp/result" || return 1
    _loom_rw_current || return 2
    limit=$(jq -r .artifact_bytes "$_rh_workflow")
    _loom_remote_git -C "$_rw_workspace" update-ref refs/loom/sealed "$sha" || return 2
    (ulimit -f "$(( (limit+511)/512 ))"; _loom_remote_git -C "$_rw_workspace" bundle create "$_rw_tmp/bundle" refs/loom/sealed "^$base") > "$_rw_tmp/bundle-log" 2>&1 || {
        # An unchanged base has no incremental objects; a full bound bundle is
        # still limited and pinned, never an arbitrary ref expansion.
        [[ $sha == "$base" ]] || return 2
        (ulimit -f "$(( (limit+511)/512 ))"; _loom_remote_git -C "$_rw_workspace" bundle create "$_rw_tmp/bundle" refs/loom/sealed) > "$_rw_tmp/bundle-log" 2>&1 || return 2
    }
    _loom_rw_artifact workflow-bundle "$_rw_tmp/bundle" "$limit" || return $?
    jq -cn --slurpfile seal "$_rw_tmp/result" --rawfile report "$_rw_workspace/REPORT.md" '{seal:$seal[0],report:$report}' > "$_rw_tmp/evidence"
    _loom_rw_artifact workflow-evidence "$_rw_tmp/evidence" "$limit" || return $?
}
_loom_rw_git_index() {
    _loom_remote_git_guard "$_rw_workspace" || return 2
    if [[ ${1:-} == read-tree || ${1:-} == checkout || ${1:-} == reset ]]; then
        [[ ${!#} == --empty ]] || _loom_remote_git_tree_guard "$_rw_workspace" "${!#}" || return 2
    fi
    env -i PATH=/usr/bin:/bin LANG=C.UTF-8 HOME=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 GIT_NO_REPLACE_OBJECTS=1 GIT_INDEX_FILE="$GIT_INDEX_FILE" git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.attributesFile=/dev/null -C "$_rw_workspace" "$@"
}
_loom_rw_check() {
    local sha rc=0 script
    _loom_rw_current || { _loom_rw_error identity_mismatch refused 'Sealed source/report changed'; return; }
    sha=$(jq -r .sha "$_rh_spool/workflow-seal")
    jq -e --arg sha "$sha" --slurpfile b "$_nn_binding" '.args=={sha:$sha,manifest_digest:$b[0].manifest_digest}' "$_rw_request" >/dev/null || return 2
    script=$(jq -r .check_script "$_rh_workflow")
    _loom_remote_git clone --no-hardlinks --no-checkout "$_rw_workspace" "$_rw_tmp/check" >/dev/null 2>&1 || return 2
    _loom_remote_git -C "$_rw_tmp/check" checkout --detach "$sha" >/dev/null 2>&1 || return 2
    cp -- "$script" "$_rw_tmp/check-script" || return 2
    [[ $(loom_policy_digest "$_rw_tmp/check-script") == "$(jq -r .check_digest "$_rh_workflow")" ]] || return 2
    mkdir "$_rh_spool/workflow-check-data" || return 1
    jq -cn --arg dir "$_rw_tmp" --arg result "$_rh_spool/workflow-check-data" --slurpfile config "$_rh_workflow" '{workspace:($dir+"/check"),script:($dir+"/check-script"),result_dir:$result,script_digest:$config[0].check_digest,interpreter_digest:$config[0].interpreter_digest,timeout_ms:$config[0].check_timeout_ms,output_bytes:$config[0].output_bytes}' > "$_rw_tmp/check-plan"
    setsid --wait /usr/bin/bash "$_rh_runtime/ops/workflow.sh" --check-keeper "$_rw_tmp/check-plan" > "$_rh_spool/workflow-check-data/keeper-log" 2>&1 || rc=$?
    [[ $rc == 0 && -f $_rh_spool/workflow-check-data/check-terminal ]] || { _loom_rw_error outcome_unknown unknown 'Check group/terminal outcome unknown; original intent retained'; return; }
    jq -e '.group_empty and .captured and .escaped==false and .timed_out==false' "$_rh_spool/workflow-check-data/check-terminal" >/dev/null || return 1
    rc=$(jq -r .exit_code "$_rh_spool/workflow-check-data/check-terminal")
    loom_output_atomic "$_rh_spool/workflow-check-process" < "$_rh_spool/workflow-check-data/check-terminal" || return 1
    _loom_rw_current || return 2
    jq --argjson code "$rc" --arg check "$(jq -r .check_digest "$_rh_workflow")" --slurpfile process "$_rh_spool/workflow-check-data/check-terminal" '{sha,manifest_digest,report_digest,config_digest,source,check_digest:$check,check_exit:$code,captured:true,process:$process[0]}' "$_rh_spool/workflow-seal" > "$_rw_tmp/result"
}
_loom_rw_publish_check() {
    local receipt=$1
    [[ ! -e $_rh_spool/workflow-check ]] || return 0
    _rw_sha=$(jq -r .sha "$receipt")
    _loom_rw_response "$receipt" true > "$_rw_tmp/check-response" || return 1
    jq -cn --slurpfile request "$_rw_request" --slurpfile receipt "$_rw_tmp/check-response" '{request:$request[0],receipt:$receipt[0]}' > "$_rw_tmp/check-artifact" || return 1
    _loom_rw_artifact workflow-check "$_rw_tmp/check-artifact" "$(jq '[.artifact_bytes,49152]|min' "$_rh_workflow")"
}
_loom_rw_read() {
    local name cursor offset=0 digest bytes max count end generation operation_digest
    name=$(jq -r .args.artifact "$_rw_request")
    [[ $name == workflow-bundle || $name == workflow-evidence || $name == workflow-check ]] || { _loom_rw_error policy_denied refused 'Unknown immutable artifact'; return; }
    _loom_ssh_private "$_rh_spool/$name" && loom_policy_json "$_rh_spool/$name-meta" || return 2
    if [[ $name == workflow-check ]]; then
        [[ -f $_rh_spool/workflow-check-intent && -f $_rh_spool/workflow-check-receipt ]] || { _loom_rw_error outcome_unknown unknown 'Original check intent or receipt absent; read cannot execute a check'; return; }
        operation_digest=$(jq -cS '.request|del(.request_id,.timeout_ms)' "$_rh_spool/$name" | git hash-object --stdin) || return 2
        [[ $operation_digest == "$(cat "$_rh_spool/workflow-check-intent")" ]] && cmp -s <(jq -cS .receipt.result "$_rh_spool/$name") <(jq -cS . "$_rh_spool/workflow-check-receipt") || { _loom_rw_error outcome_unknown unknown 'Immutable check artifact disagrees with original operation'; return; }
    fi
    digest=$(loom_policy_digest "$_rh_spool/$name")
    [[ $digest == "$(jq -r .digest "$_rh_spool/$name-meta")" ]] || return 2
    bytes=$(stat -c %s "$_rh_spool/$name"); generation=${digest#*:}
    [[ $bytes == "$(jq -r .bytes "$_rh_spool/$name-meta")" ]] || return 2
    cursor=$(jq -r '.args.cursor//empty' "$_rw_request")
    if [[ -n $cursor ]]; then
        [[ $cursor =~ ^[0-9a-f]{40}:[0-9]{1,10}$ && ${cursor%:*} == "$generation" ]] || { _loom_rw_error policy_denied refused 'Artifact cursor differs'; return; }
        offset=$((10#${cursor##*:}))
    fi
    max=$(jq -r .args.limit_bytes "$_rw_request")
    (( max>=4 && offset<=bytes )) || { _loom_rw_error policy_denied refused 'Artifact cursor or chunk quota invalid'; return; }
    count=$(( max/4*3 )); (( offset+count<=bytes )) || count=$((bytes-offset))
    dd if="$_rh_spool/$name" of="$_rw_tmp/chunk" bs=1 skip="$offset" count="$count" status=none || return 2
    base64 -w0 "$_rw_tmp/chunk" > "$_rw_tmp/encoded" || return 2
    end=$((offset+count))
    jq -cn --arg source "$name" --arg generation "$generation" --rawfile data "$_rw_tmp/encoded" --arg next "$generation:$end" --argjson eof "$(if (( end==bytes )); then echo true; else echo false; fi)" '{source:$source,generation:$generation,data:$data,next_cursor:$next,eof:$eof,truncated:false,gap:null}' > "$_rw_tmp/result"
    _loom_rw_response "$_rw_tmp/result" false
}
_loom_remote_workflow_handle() (
    set -uo pipefail
    umask 077
    local _rw_request=$1 _rw_tmp _rw_workspace _rw_manifest _rw_sha op digest key rc=0 intent receipt
    _rw_tmp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$_rw_tmp"' EXIT
    loom_protocol_check_request "$_rw_request" || return 2
    _loom_remote_workflow_config "$_rh_workflow" && _loom_native_policy_check || { _loom_rw_error policy_denied refused 'Pinned workflow configuration changed'; return; }
    jq -e --slurpfile b "$_nn_binding" '.actor==$b[0].actor and .target==$b[0].target and (.extensions|length)==0' "$_rw_request" >/dev/null || { _loom_rw_error policy_denied refused 'Artifact actor or exact attempt binding differs'; return; }
    _rw_workspace=$(jq -r .workspace "$_nn_binding"); _rw_manifest=$(jq -r .manifest "$_rh_workflow")
    _loom_remote_git_guard "$_rw_workspace" || { _loom_rw_error policy_denied refused 'Unsupported repository configuration or attributes'; return; }
    _loom_ssh_private "$_rw_workspace" dir && [[ -d $_rw_workspace/.git && ! -L $_rw_workspace/.git && $(_loom_remote_git -C "$_rw_workspace" rev-parse --show-toplevel) == "$_rw_workspace" ]] || return 2
    jq '.op="execution.inspect"|.operation_id=null|.idempotency_key=null|.expected_revision=null|.args={}' "$_rw_request" > "$_rw_tmp/inspect-request"
    loom_native_handle "$_rh_context" "$_rw_tmp/inspect-request" > "$_rw_tmp/inspect" || return $?
    jq -e '.ok and .result.state=="exited" and .result.identity_verified and .result.terminal.captured' "$_rw_tmp/inspect" >/dev/null || { _loom_rw_error identity_mismatch refused 'Exact process settlement is not proven'; return; }
    op=$(jq -r .op "$_rw_request")
    exec 8> "$_rh_spool/workflow.lock"; flock -w 2 8 || { _loom_rw_error outcome_unknown unknown 'Workflow operation is busy'; return; }
    if [[ $op == workspace.read ]]; then _loom_rw_read; return; fi
    if [[ $op == workspace.export ]]; then
        _loom_rw_current || { _loom_rw_error identity_mismatch refused 'Sealed source/report changed'; return; }
        key=workflow-bundle; [[ $(jq -r .args.kind "$_rw_request") != evidence ]] || key=workflow-evidence
        jq -e --slurpfile q "$_rw_request" '.sha==$q[0].args.sha and .bytes<=$q[0].args.limit_bytes' "$_rh_spool/$key-meta" >/dev/null || { _loom_rw_error policy_denied refused 'Export SHA or quota differs'; return; }
        [[ $(loom_policy_digest "$_rh_spool/$key") == "$(jq -r .digest "$_rh_spool/$key-meta")" ]] || return 2
        _loom_rw_response "$_rh_spool/$key-meta" true; return
    fi
    [[ $op == workspace.seal || $op == workspace.check ]] || return 2
    # One seal/check per exact attempt; alternate keys cannot execute it again.
    key=${op#workspace.}; intent=$_rh_spool/workflow-$key-intent; receipt=$_rh_spool/workflow-$key-receipt
    digest=$(jq -cS 'del(.request_id,.timeout_ms)' "$_rw_request" | git hash-object --stdin)
    if [[ -f $intent ]]; then
        [[ $(cat "$intent") == "$digest" ]] || { _loom_rw_error idempotency_conflict refused 'Bound workflow operation has another immutable intent'; return; }
        [[ -f $receipt ]] || { _loom_rw_error outcome_unknown unknown 'Original workflow intent has no terminal receipt'; return; }
        _loom_rw_current || { _loom_rw_error identity_mismatch refused 'Sealed source/report changed since receipt'; return; }
        if [[ $op == workspace.check ]]; then _loom_rw_publish_check "$receipt" || { _loom_rw_error outcome_unknown unknown 'Check artifact publication uncertain'; return; }; fi
        _loom_rw_response "$receipt" true; return
    fi
    # Validate effect-free preconditions before the permanent uncertain fence.
    if [[ $op == workspace.check ]]; then
        _loom_rw_current || { _loom_rw_error identity_mismatch refused 'Sealed source/report changed'; return; }
        jq -e --slurpfile seal "$_rh_spool/workflow-seal" '.args.sha==$seal[0].sha and .args.manifest_digest==$seal[0].manifest_digest' "$_rw_request" >/dev/null || return 2
    fi
    printf '%s\n' "$digest" | loom_output_atomic "$intent" || { _loom_rw_error outcome_unknown unknown 'Cannot confirm durable workflow intent'; return; }
    if [[ $op == workspace.seal ]]; then _loom_rw_seal > "$_rw_tmp/diagnostic" || rc=$?
    else _loom_rw_check > "$_rw_tmp/diagnostic" || rc=$?; fi
    if (( rc!=0 )); then
        # After intent even a setup/storage error is conservatively uncertain.
        _loom_rw_error outcome_unknown unknown 'Workflow intent retained without a terminal receipt'; return
    fi
    loom_output_atomic "$receipt" < "$_rw_tmp/result" || { _loom_rw_error outcome_unknown unknown 'Cannot confirm terminal receipt persistence'; return; }
    if [[ $op == workspace.check ]]; then _loom_rw_publish_check "$receipt" || { _loom_rw_error outcome_unknown unknown 'Check artifact publication uncertain'; return; }; fi
    _loom_rw_response "$receipt" true
)


_loom_workflow_remote_seal() {
    local args
    _loom_workflow_policy && _loom_workflow_source_check && _loom_workflow_task || return $?
    args=$(jq -cn --slurpfile b "$_wf_binding" --slurpfile m "$(jq -r .manifest "$_wf_context")" '{workspace_id:$b[0].workspace_id,base_sha:$m[0].base_sha,manifest_digest:$b[0].manifest_digest}')
    _loom_workflow_request workspace.seal "$args" 1 workflow-seal > "$_wf_tmp/seal-request"
    _loom_workflow_execute "$_wf_tmp/seal-request" > "$_wf_tmp/seal" || return $?
    jq -e --slurpfile b "$_wf_binding" --slurpfile p "$_wf_pin" --slurpfile c "$_wf_exec" '.durable and .result.execution.binding==$b[0].target and .result.execution.state=="exited" and .result.execution.identity_verified and .result.execution.terminal.captured and .result.config_digest==$p[0].config_digest and .result.manifest_digest==$b[0].manifest_digest and .result.source==$c[0].identity' "$_wf_tmp/seal" >/dev/null || { loom_workflow_error remote_seal_provenance; return 2; }
    if [[ -f $_wf_dir/remote-seal ]]; then
        cmp -s <(jq -cS .result "$_wf_tmp/seal") <(jq -cS .result "$_wf_dir/remote-seal") || { loom_workflow_error sealed_receipt_changed; return 2; }
    fi
}
_loom_workflow_remote_harvest() {
    local kind=settlement transition=failed
    _loom_workflow_remote_seal || return $?
    if jq -e '.result.report_state=="ready" and .result.execution.terminal.exit_code==0' "$_wf_tmp/seal" >/dev/null; then kind=harvest; transition=review; fi
    _loom_workflow_proof "$kind" | jq --slurpfile seal "$_wf_tmp/seal" '.+{current_report:true,report_state:$seal[0].result.report_state,report_digest:$seal[0].result.report_digest,exit_code:$seal[0].result.execution.terminal.exit_code}' > "$_wf_tmp/proof"
    loom_output_atomic "$_wf_dir/remote-seal" < "$_wf_tmp/seal" || return 1
    jq -cn --slurpfile seal "$_wf_tmp/seal" --slurpfile proof "$_wf_tmp/proof" '{sha:$seal[0].result.sha,proof:$proof[0],remote:$seal[0]}' | loom_output_atomic "$_wf_dir/harvest" || return 1
    if [[ $(jq -r .data.state "$_wf_tmp/task") == "$transition" ]]; then cat "$_wf_dir/harvest"; return; fi
    _loom_workflow_transition "$transition" "$_wf_tmp/proof"
}
_loom_workflow_remote_verify() {
    _loom_workflow_remote_seal || return $?
    [[ $(jq -r .data.state "$_wf_tmp/task") == review ]] || return 2
    _loom_workflow_request workspace.check "$(jq -c '.result|{sha,manifest_digest}' "$_wf_tmp/seal")" 1 workflow-check > "$_wf_tmp/check-request"
    _loom_workflow_execute "$_wf_tmp/check-request" > "$_wf_tmp/checked" || return $?
    jq -e --slurpfile seal "$_wf_tmp/seal" --slurpfile m "$(jq -r .manifest "$_wf_context")" '.durable and .result.captured and .result.process.group_empty and .result.process.output_eof and .result.sha==$seal[0].result.sha and .result.source==$seal[0].result.source and .result.report_digest==$seal[0].result.report_digest and .result.manifest_digest==$seal[0].result.manifest_digest and .result.config_digest==$seal[0].result.config_digest and .result.check_digest==$m[0].check_digest' "$_wf_tmp/checked" >/dev/null || { loom_workflow_error remote_check_provenance; return 2; }
    jq --arg source "$(loom_workflow_source)" '{checked_sha:.result.sha,check_exit:.result.check_exit,captured:.result.captured,check_digest:.result.check_digest,config_digest:.result.config_digest,source_digest:$source,transport:"ssh",receipt:.}' "$_wf_tmp/checked" | loom_output_atomic "$_wf_dir/check" || return 1
    cat "$_wf_dir/check"
    [[ $(jq .check_exit "$_wf_dir/check") == 0 ]] || return 1
}
_loom_workflow_remote_checked() {
    _loom_workflow_remote_seal || return $?
    [[ $(jq -r .data.state "$_wf_tmp/task") == review ]] || return 2
    _loom_workflow_promotion_authority || return $?
    _loom_workflow_request workspace.check "$(jq -c '.result|{sha,manifest_digest}' "$_wf_tmp/seal")" 1 workflow-check > "$_wf_tmp/expected-check-request"
    # Collection cannot create a check operation when verify never recorded one.
    loom_policy_json "$_wf_dir/check" || { loom_workflow_error checked_remote_receipt_required; return 2; }
    jq '.receipt' "$_wf_dir/check" > "$_wf_tmp/persisted-check" || return 2
    loom_protocol_validate response "$_wf_tmp/persisted-check" "$_wf_tmp/expected-check-request" || { loom_workflow_error invalid_persisted_check_receipt; return 2; }
    # Promotion is read-only at the host check boundary. It cannot recreate a
    # lost intent by dispatching the create-or-replay workspace.check operation.
    _loom_workflow_remote_read_check || return $?
    _loom_workflow_remote_check_receipt
}
_loom_workflow_remote_read_check() {
    local generation bytes
    _loom_workflow_request workspace.read '{"artifact":"workflow-check","limit_bytes":65536}' > "$_wf_tmp/read-check-request"
    _loom_workflow_execute "$_wf_tmp/read-check-request" > "$_wf_tmp/read-check" || return $?
    jq -e '.result.source=="workflow-check" and .result.eof==true and .result.gap==null and .result.truncated==false' "$_wf_tmp/read-check" >/dev/null || return 2
    jq -j .result.data "$_wf_tmp/read-check" | base64 -d > "$_wf_tmp/check-artifact" || return 2
    generation=$(git hash-object --no-filters "$_wf_tmp/check-artifact"); bytes=$(stat -c %s "$_wf_tmp/check-artifact")
    jq -e --arg generation "$generation" --arg cursor "$generation:$bytes" '.result.generation==$generation and .result.next_cursor==$cursor' "$_wf_tmp/read-check" >/dev/null || return 2
    loom_policy_json "$_wf_tmp/check-artifact" || return 2
    cmp -s <(jq -cS '.request|del(.request_id,.timeout_ms)' "$_wf_tmp/check-artifact") <(jq -cS 'del(.request_id,.timeout_ms)' "$_wf_tmp/expected-check-request") || { loom_workflow_error original_check_request_changed; return 2; }
    jq '.receipt' "$_wf_tmp/check-artifact" > "$_wf_tmp/current-check" || return 2
    loom_protocol_validate response "$_wf_tmp/current-check" "$_wf_tmp/expected-check-request"
}
_loom_workflow_remote_check_receipt() {
    jq '.receipt' "$_wf_dir/check" > "$_wf_tmp/persisted-check" || return 2
    loom_protocol_validate response "$_wf_tmp/persisted-check" "$_wf_tmp/expected-check-request" || { loom_workflow_error invalid_persisted_check_receipt; return 2; }
    cmp -s <(jq -cS '{op,operation_id,target,ok,status,revision,durable,result,error}' "$_wf_tmp/persisted-check") <(jq -cS '{op,operation_id,target,ok,status,revision,durable,result,error}' "$_wf_tmp/current-check") || { loom_workflow_error persisted_check_differs_from_host_operation; return 2; }
    jq -e --arg source "$(loom_workflow_source)" --slurpfile s "$_wf_tmp/seal" --slurpfile m "$(jq -r .manifest "$_wf_context")" --slurpfile c "$_wf_exec" '
      .receipt as $receipt | $receipt.result as $r | $s[0].result as $seal |
      .transport=="ssh" and .captured==true and .check_exit==0 and .source_digest==$source and
      .checked_sha==$seal.sha and .checked_sha==$r.sha and .check_digest==$m[0].check_digest and .check_digest==$r.check_digest and
      .config_digest==$seal.config_digest and .config_digest==$r.config_digest and
      $receipt.ok==true and $receipt.status=="completed" and $receipt.durable==true and $receipt.revision==1 and
      $receipt.extensions["loom.ssh"].identity==$c[0].identity and $r.source==$c[0].identity and $r.source==$seal.source and
      $r.manifest_digest==$seal.manifest_digest and $r.report_digest==$seal.report_digest and
      $r.captured==true and $r.check_exit==0 and $r.process.captured==true and $r.process.exit_code==0 and
      $r.process.group_empty==true and $r.process.escaped==false and $r.process.timed_out==false and $r.process.output_eof==true' "$_wf_dir/check" >/dev/null || { loom_workflow_error checked_remote_receipt_required; return 2; }
}

_loom_workflow_remote_collect() {
    local sha checkout target
    _loom_workflow_remote_checked || return $?
    sha=$(jq -r .result.sha "$_wf_tmp/seal"); checkout=$(jq -r '.checkout//empty' "$_wf_context")
    [[ -n $checkout && -d $checkout && ! -L $checkout && $(realpath -e "$checkout") == "$checkout" ]] || return 2
    _loom_workflow_request workspace.export "$(jq -cn --arg sha "$sha" '{sha:$sha,kind:"git_bundle",limit_bytes:67108864}')" > "$_wf_tmp/export"
    _loom_workflow_execute "$_wf_tmp/export" > "$_wf_tmp/exported" || return $?
    loom_ssh_download "$_wf_exec" "$_wf_tmp/export" "$_wf_tmp/exported" "$_wf_tmp/bundle" || return $?
    _loom_remote_git -C "$checkout" -c core.hooksPath=/dev/null bundle verify "$_wf_tmp/bundle" >/dev/null 2>&1 || { loom_workflow_error invalid_bundle_or_missing_base; return 2; }
    target=refs/loom/collected/$(printf '%s\n' "$_wf_id" | git hash-object --stdin)
    _loom_remote_git -C "$checkout" -c core.hooksPath=/dev/null fetch -q --no-tags "$_wf_tmp/bundle" refs/loom/sealed || return 2
    [[ $(_loom_remote_git -C "$checkout" rev-parse FETCH_HEAD) == "$sha" ]] || { loom_workflow_error exported_sha_changed; return 2; }
    _loom_workflow_remote_checked || return $?
    _loom_workflow_collect_ref "$checkout" "$target" "$sha" || return 2
    jq -cn --arg sha "$sha" --arg ref "$target" --slurpfile artifact "$_wf_tmp/exported" '{collected_sha:$sha,ref:$ref,artifact:$artifact[0]}' | loom_output_atomic "$_wf_dir/collect" || return 1
    cat "$_wf_dir/collect"
}
_loom_workflow_remote_ack() {
    local reviewed=$1 sha
    _loom_workflow_remote_checked || return $?
    sha=$(jq -r .result.sha "$_wf_tmp/seal")
    [[ $reviewed == "$sha" ]] || { loom_workflow_error exact_reviewed_sha_required; return 2; }
    jq -e --arg sha "$sha" '.collected_sha==$sha' "$_wf_dir/collect" >/dev/null || return 2
    [[ $(_loom_remote_git -C "$(jq -r .checkout "$_wf_context")" rev-parse "$(jq -r .ref "$_wf_dir/collect")") == "$sha" ]] || return 2
    _loom_workflow_proof accept | jq --arg sha "$sha" --slurpfile p "$_wf_pin" --slurpfile b "$_wf_binding" '.+{reviewed:true,check_exit:0,checked_sha:$sha,collected_sha:$sha,current_sha:$sha,config_digest:$p[0].config_digest,manifest_digest:$b[0].manifest_digest}' > "$_wf_tmp/proof"
    _loom_workflow_transition succeeded "$_wf_tmp/proof"
}


# A finite keeper for an explicitly approved check. It anchors its own session
# until all observed group members exit, and never infers success from leader exit.
_loom_workflow_check_keeper() {
    set -uo pipefail
    umask 077
    local plan=$1 ops workspace script dir deadline output child ticks own_ticks code=0 waited=false live path pid escaped=false
    local writer generation fd empty_seen=false
    local -a _np
    local -A known=()
    for path in /proc/self/fd/*; do
        fd=${path##*/}
        if (( fd>2 && fd!=255 )); then exec {fd}>&-; fi
    done
    ops=$(loom_workflow_root)
    source "$ops/native.sh"; _loom_native_load || return 2
    loom_policy_json "$plan" || return 2
    workspace=$(jq -r .workspace "$plan"); script=$(jq -r .script "$plan"); dir=$(jq -r .result_dir "$plan")
    [[ $(loom_policy_digest "$script") == "$(jq -r .script_digest "$plan")" && $(loom_policy_digest /usr/bin/bash) == "$(jq -r .interpreter_digest "$plan")" ]] || return 2
    _loom_native_proc "$$" || return 2
    [[ ${_np[2]} == "$$" && ${_np[3]} == "$$" ]] || return 2
    own_ticks=${_np[19]}; deadline=$(( $(date +%s%3N)+$(jq -r .timeout_ms "$plan") )); output=$(jq -r .output_bytes "$plan")
    trap ':' TERM HUP INT
    generation=$(cat /proc/sys/kernel/random/uuid)
    jq -cn --argjson pid "$$" --arg ticks "$own_ticks" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" --arg nonce "$generation" '{pid:$pid,start_ticks:$ticks,boot_id:$boot,nonce:$nonce}' | loom_output_atomic "$dir/check-identity" || return 1
    mkfifo -m 600 "$dir/pipe" || return 1
    setsid /usr/bin/bash "$ops/output.sh" drain "$dir/output" "$output" "$generation" < "$dir/pipe" >/dev/null 2>&1 &
    writer=$!
    (cd "$workspace" && exec env -i PATH=/usr/bin:/bin LANG=C.UTF-8 HOME="$workspace" /usr/bin/bash "$script") </dev/null > "$dir/pipe" 2>&1 &
    child=$!
    _loom_native_proc "$child" || return 2
    ticks=${_np[19]}; known[$child]=$ticks
    while :; do
        live=0
        for path in /proc/[0-9]*/stat; do
            pid=${path#/proc/}; pid=${pid%/stat}
            [[ $pid != "$$" && $pid != "$BASHPID" && $pid != "$writer" ]] || continue
            _loom_native_proc "$pid" || continue
            [[ ${_np[0]} != Z && ${_np[0]} != X ]] || continue
            if [[ ${_np[2]} == "$$" ]]; then known[$pid]=${_np[19]}; live=$((live+1))
            elif [[ ${known[$pid]:-} == "${_np[19]}" ]]; then escaped=true; fi
        done
        if [[ $waited == false ]] && { ! _loom_native_proc "$child" || [[ ${_np[19]} != "$ticks" || ${_np[0]} == Z ]]; }; then
            wait "$child" || code=$?
            waited=true
        fi
        if [[ $waited == true && $live == 0 ]]; then
            [[ $empty_seen == false ]] || break
            empty_seen=true
        else empty_seen=false; fi
        if (( $(date +%s%3N)>=deadline )); then
            printf '{"timed_out":true}\n' | loom_output_atomic "$dir/check-timeout" || return 1
            # Self-group identity cannot be reused while this anchor is alive.
            _loom_native_proc "$$" && [[ ${_np[19]} == "$own_ticks" && ${_np[2]} == "$$" ]] || return 1
            kill -TERM -- "-$$" || return 1
            sleep 0.1
            _loom_native_proc "$$" && [[ ${_np[19]} == "$own_ticks" && ${_np[2]} == "$$" ]] || return 1
            kill -KILL -- "-$$"
            return 1
        fi
        sleep 0.02
    done
    [[ $escaped == false ]] || return 1
    wait "$writer" || return 1
    [[ $(jq .eof "$dir/output/index") == true ]] || return 1
    jq -cn --slurpfile output "$dir/output/index" --argjson exit "$code" --argjson pid "$$" --arg ticks "$own_ticks" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" '{captured:true,exit_code:$exit,group_empty:true,escaped:false,timed_out:false,output_eof:$output[0].eof,total_output_bytes:$output[0].end,lost_prefix_bytes:$output[0].first,keeper:{pid:$pid,start_ticks:$ticks,boot_id:$boot}}' | loom_output_atomic "$dir/check-terminal"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        --watch) shift; _loom_workflow_watch "$@" ;;
        --check-keeper) shift; _loom_workflow_check_keeper "$@" ;;
        *) loom_workflow_main "$@" ;;
    esac
fi
