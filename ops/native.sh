#!/usr/bin/env bash
# Native execution host spool API. S1/S2/S3 are external dependencies, never
# sourced until an explicit call. No options, traps, env or cwd changes on source.
# shellcheck disable=SC2030,SC2031,SC2015 # guards intentionally refuse either failed condition

loom_native_root() ( cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P; )

_loom_native_load() {
    local ops
    ops=$(loom_native_root) || return 1
    # Explicit module paths support separately deployed host helpers and tests.
    # shellcheck disable=SC1090,SC1091
    source "${LOOM_NATIVE_PROTOCOL_MODULE:-$ops/protocol.sh}" || return 2
    # shellcheck disable=SC1090,SC1091
    source "${LOOM_NATIVE_STATE_MODULE:-$ops/state.sh}" || return 2
    # shellcheck disable=SC1090,SC1091
    source "${LOOM_NATIVE_POLICY_MODULE:-$ops/policy.sh}" || return 2
    # shellcheck source=ops/output.sh
    source "$ops/output.sh" || return 2
}

_loom_native_proc() {
    local pid=$1 raw
    [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/stat ]] || return 1
    IFS= read -r raw < "/proc/$pid/stat" || return 1
    raw=${raw##*) }
    read -r -a _np <<< "$raw"
    [[ ${_np[19]:-} =~ ^[0-9]+$ ]] || return 1
}

_loom_native_probe() {
    local tool
    [[ $(uname -s) == Linux && ${BASH_VERSINFO[0]} -ge 4 ]] || return 2
    for tool in setsid sync flock jq git dd base64 stat timeout mktemp find sort iconv env mkfifo head tail cat date cmp readlink realpath mv rm mkdir uname; do
        command -v "$tool" >/dev/null || return 2
    done
    [[ -r /proc/sys/kernel/random/boot_id && -r /proc/sys/kernel/random/uuid ]] || return 2
    [[ $(date +%s%3N) =~ ^[0-9]{13,}$ ]] || return 2
    dd if=/dev/null of=/dev/null bs=1 iflag=fullblock status=none && base64 -w0 </dev/null >/dev/null &&
        setsid --wait true && sync -f "$_nn_root" && _loom_native_proc "$BASHPID"
}

_loom_native_private() {
    local file=$1 kind=${2:-file} part current='' mode owner
    local -a parts
    [[ $file == /* && $file != */ && $file != *//* && $file != *$'\n'* ]] || return 2
    IFS=/ read -r -a parts <<< "${file#/}"
    for part in "${parts[@]}"; do
        [[ -n $part && $part != . && $part != .. ]] || return 2
        current+=/$part
        [[ ! -L $current ]] || return 2
        if [[ -e $current ]]; then
            read -r owner mode < <(stat -c '%u %a' "$current")
            [[ $owner == "$EUID" || $owner == 0 ]] || return 2
            if (( (8#$mode & 0022)!=0 )); then
                [[ $owner == 0 ]] && (( (8#$mode & 01000)!=0 )) || return 2
            fi
        fi
    done
    [[ -O $file ]] || return 2
    if [[ $kind == dir ]]; then [[ -d $file ]] || return 2
    else [[ -f $file && $(stat -c %h "$file") == 1 && $(stat -c %s "$file") -le 1048576 ]] || return 2; fi
    mode=$(stat -c %a "$file"); (( (8#$mode & 0077)==0 ))
}

# Context and binding are explicitly provisioned, never derived from request paths.
_loom_native_context() {
    local context=$1 file
    _loom_native_private "$context" && loom_policy_json "$context" || return 2
    jq -e 'keys==(["schema","state_root","store_id","installation_id","transport_identity","config","hosts","profiles","pin","binding","authorization","authority_store_id"]|sort) and .schema==1 and all(.[];type=="string" or .==1) and
      all(.store_id,.authority_store_id,.installation_id,.transport_identity;length>0 and utf8bytelength<=128)' "$context" >/dev/null || return 2
    _nn_root=$(jq -r .state_root "$context"); _nn_store=$(jq -r .store_id "$context")
    _nn_binding=$(jq -r .binding "$context"); _nn_pin=$(jq -r .pin "$context")
    _loom_native_private "$_nn_root" dir && _loom_native_private "$_nn_binding" && _loom_native_private "$_nn_pin" || return 2
    loom_policy_json "$_nn_binding" || return 2
    jq -e 'keys==(["schema","actor","target","workspace_id","workspace","prompt_ref","prompt","manifest_digest","profile_digest","limits","stop_authorized","release_authorized","executable_digest","prompt_digest"]|sort) and .schema==1 and (.stop_authorized|type=="boolean") and (.release_authorized|type=="boolean") and
      all(.workspace_id,.workspace,.prompt_ref,.prompt,.manifest_digest,.profile_digest,.executable_digest,.prompt_digest;type=="string" and length>0) and
      (.actor|keys==["epoch","id","run_id"]) and (.target|keys==["assignment_id","attempt_id","host_id"])' "$_nn_binding" >/dev/null || return 2
    for file in config hosts profiles; do loom_policy_file "$(jq -r --arg k "$file" '.[$k]' "$context")" || return 2; done
    # Old attempts use pinned snapshots; mutating requests additionally check drift.
    loom_policy_json "$_nn_pin" || return 2
    [[ $(jq -r .provider "$_nn_pin") == native && $(jq -r .host.identity "$_nn_pin") == "$(jq -r .transport_identity "$context")" ]] || return 2
    [[ $(jq -r .target.host_id "$_nn_binding") == "$(jq -r .host.id "$_nn_pin")" ]] || return 2
    [[ $(jq -r .transport "$_nn_pin") != process || $(jq -r .placement.allow_local "$_nn_pin") == true ]] || return 2
    # Negotiation must precede launch authorization; hello has no effects and
    # cannot require the capacity/launch receipt it is helping the core obtain.
    if [[ ${2:-} != hello ]]; then
        _loom_native_private "$(jq -r .authorization "$context")" || return 2
        loom_policy_json "$(jq -r .authorization "$context")" || return 2
        jq -e --slurpfile c "$context" --slurpfile b "$_nn_binding" --slurpfile p "$_nn_pin" \
          --arg digest "$(jq -cS 'del(.stop_authorized,.release_authorized)' "$_nn_binding" | loom_policy_scope)" '
          keys==["capacity_receipt","launch_receipt"] and
          all(.capacity_receipt,.launch_receipt; .schema==2 and .durable==true and .store_id==$c[0].authority_store_id and (.sequence|type=="number" and .>0)) and
          .capacity_receipt.result.attempt_id==$b[0].target.attempt_id and .capacity_receipt.result.policy_pin==$p[0] and
          .launch_receipt.result.actor==$b[0].actor and .launch_receipt.result.target==$b[0].target and
          .launch_receipt.result.binding_digest==$digest' "$(jq -r .authorization "$context")" >/dev/null || return 2
    fi
    [[ $(jq -r .authority_store_id "$context") != "$_nn_store" ]] || return 2
    export LOOM_STATE=$_nn_root
    _nn_id=$(jq -r .target.attempt_id "$_nn_binding" | git hash-object --stdin) || return 1
    _nn_dir=$_nn_root/native/$_nn_id
    if [[ -e $_nn_root/native || -L $_nn_root/native ]]; then _loom_native_private "$_nn_root/native" dir || return 2; fi
    if [[ -e $_nn_dir || -L $_nn_dir ]]; then _loom_native_private "$_nn_dir" dir || return 2; fi
    _nn_context=$context
}

_loom_native_policy_check() {
    loom_policy_check "$_nn_pin" "$(jq -r .config "$_nn_context")" "$(jq -r .hosts "$_nn_context")" "$(jq -r .profiles "$_nn_context")"
}

_loom_native_response() {
    local status=$1 result=$2 durable=${3:-false}
    jq -cn --slurpfile q "$_nn_request" --arg status "$status" --argjson result "$result" --argjson durable "$durable" --argjson revision "${_nn_revision:-null}" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      $q[0]|{protocol,version,request_id,operation_id,op,target} +
      {ok:true,status:$status,revision:$revision,durable:$durable,result:$result,error:null,effects:[],evidence:[],observed_at:$at,extensions:{}}'
}

_loom_native_error() {
    if [[ ${2:-refused} == unknown && -n ${_nn_id:-} ]]; then
        loom_protocol_receipt "$_nn_request" unknown "$1" "$3" |
            jq -c --arg ref "native:$_nn_id" '.effects=[{kind:"native_attempt",resource:$ref,disposition:"unknown"}]'
    else loom_protocol_receipt "$_nn_request" "${2:-refused}" "$1" "$3"; fi
    [[ ${2:-refused} == refused ]] && return 2
    return 1
}

_loom_native_request_digest() {
    jq -cS 'del(.request_id,.timeout_ms)' "$1" | git hash-object --stdin
}

# S2 owns journal locking/flush/CAS. Host records are execution facts only. A
# null-run system actor cannot create run/task/gate/authority records through S2.
_loom_native_commit() {
    local request=$1 event=$2 data=$3 expected=${4:-null} tx result
    tx=$(mktemp "$_nn_root/.native-tx.XXXXXXXXXXXX") || return 1
    jq -cnS --slurpfile q "$request" --arg store "$_nn_store" --arg id "$_nn_id" --arg event "$event" --argjson data "$data" --argjson expected "$expected" '
      $q[0] as $q|{schema:2,store_id:$store,operation_id:$q.operation_id,idempotency_key:$q.idempotency_key,op:$q.op,
      actor:{id:$q.actor.id,run_id:null,epoch:0},target:$q.target,checks:[],
      changes:[{kind:"host",id:$id,expected_revision:$expected,run_id:null,epoch:0,data:$data}],
      events:[{type:$event,entity_ids:[$id],payload:{request:$q},observed_at:null}],result:{attempt_id:$q.target.attempt_id}}' > "$tx" || return 1
    result=$(loom_state_transact "$tx"); local rc=$?
    rm -f -- "$tx"
    (( rc==0 )) || return "$rc"
    _nn_revision=$(jq -r '.revisions[0].revision' <<< "$result")
}

# Durable immutable phase facts use the same S2 journal as reservation. Spool
# files are cached receipts; their loss cannot authorize another execution.
_loom_native_fact() {
    local phase=$1 payload=$2 tx rc=0
    tx=$(mktemp "$_nn_root/.native-fact.XXXXXXXXXXXX") || return 1
    jq -cnS --slurpfile q "$_nn_dir/request" --arg store "$_nn_store" --arg id "$_nn_id" --arg phase "$phase" --argjson payload "$payload" '
      $q[0] as $q | {schema:2,store_id:$store,operation_id:("native:"+$id+":"+$phase),idempotency_key:($id+":"+$phase),op:"native.fact",
      actor:{id:$q.actor.id,run_id:null,epoch:0},target:$q.target,checks:[],changes:[],
      events:[{type:("native."+$phase),entity_ids:[$id],payload:$payload,observed_at:null}],result:$payload}' > "$tx" || return 1
    loom_state_transact "$tx" >/dev/null || rc=$?
    rm -f -- "$tx"
    return "$rc"
}

_loom_native_identity_live() {
    local id=$1 pid ticks pgid sid boot child child_ticks
    [[ -f $id && ! -L $id ]] || return 1
    boot=$(cat /proc/sys/kernel/random/boot_id)
    jq -e --slurpfile c "$_nn_context" --slurpfile b "$_nn_binding" --arg boot "$boot" --argjson uid "$EUID" '
      .host_id==$b[0].target.host_id and .attempt_id==$b[0].target.attempt_id and .host_installation_id==$c[0].installation_id and
      .transport_identity==$c[0].transport_identity and .boot_id==$boot and .uid==$uid and .pgid==.supervisor_pid and .sid==.pgid' "$id" >/dev/null || return 1
    read -r pid ticks pgid sid < <(jq -r '[.supervisor_pid,.supervisor_start_ticks,.pgid,.sid]|@tsv' "$id")
    _loom_native_proc "$pid" || return 1
    [[ ${_np[19]} == "$ticks" && ${_np[2]} == "$pgid" && ${_np[3]} == "$sid" && ${_np[0]} != Z && $(stat -c %u "/proc/$pid") == "$EUID" ]] || return 1
    [[ $(jq -r .launch_nonce "$id") == "$(cat "${id%/*}/nonce")" ]] || return 1
    read -r child child_ticks < <(jq -r '[.pid,.start_ticks]|@tsv' "$id")
    if _loom_native_proc "$child"; then
        [[ ${_np[19]} == "$child_ticks" && ${_np[2]} == "$pgid" && ${_np[3]} == "$sid" && $(stat -c %u "/proc/$child") == "$EUID" ]] || return 1
    else
        [[ ! -d /proc/$child ]] || return 1
    fi
}

_loom_native_observe() {
    local state=unknown identity=null verified=false terminal=null resource=owned fact actor
    actor=$(jq -r .actor.id "$_nn_binding")
    if [[ ! -f $_nn_dir/identity ]]; then
        fact=$(loom_state_operation "$actor" native.fact "$_nn_id:identity" 2>/dev/null) || fact=''
        if [[ -n $fact ]]; then jq -c .outcome.result <<< "$fact" | loom_output_atomic "$_nn_dir/identity" || return 1; fi
    fi
    if [[ ! -f $_nn_dir/completion ]] && ! _loom_native_identity_live "$_nn_dir/identity"; then
        fact=$(loom_state_operation "$actor" native.fact "$_nn_id:completion" 2>/dev/null) || fact=''
        if [[ -n $fact ]]; then jq -c .outcome.result <<< "$fact" | loom_output_atomic "$_nn_dir/completion" || return 1
        else _loom_native_reconcile_kill || :; fi
    fi
    if [[ -f $_nn_dir/identity ]]; then identity=$(cat "$_nn_dir/identity"); fi
    if [[ -f $_nn_dir/completion ]]; then
        # Receipt includes exact binding/nonce; unknown or lost observation is
        # never upgraded by a successful signal syscall.
        if jq -e --slurpfile id "$_nn_dir/identity" '.identity==$id[0] and .group_empty==true and .escaped==false' "$_nn_dir/completion" >/dev/null; then
            state=exited; terminal=$(jq -c .terminal "$_nn_dir/completion"); verified=true; resource=retained
        fi
    elif _loom_native_identity_live "$_nn_dir/identity"; then
        verified=true; state=starting
        [[ ! -f $_nn_dir/exec-intent ]] || state=running
        [[ ! -f $_nn_dir/stop ]] || state=stop_requested
    fi
    if [[ -f $_nn_dir/identity ]] && ! jq -e --slurpfile c "$_nn_context" --slurpfile b "$_nn_binding" '
      .host_installation_id==$c[0].installation_id and .transport_identity==$c[0].transport_identity and
      .host_id==$b[0].target.host_id and .attempt_id==$b[0].target.attempt_id' "$_nn_dir/identity" >/dev/null; then
        state=unknown; verified=false; terminal=null; resource=unknown
    fi
    if [[ -f $_nn_dir/escaped ]]; then state=unknown; terminal=null; resource=unknown; fi
    if [[ -f $_nn_dir/released ]]; then
        resource=$(jq -r 'if .args.retention_policy=="retain" then "retained" else "released" end' "$_nn_dir/released")
    fi
    jq -cn --slurpfile b "$_nn_binding" --arg state "$state" --argjson identity "$identity" --argjson verified "$verified" --argjson terminal "$terminal" --arg resource "$resource" --arg ref "native:$_nn_id" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{binding:$b[0].target,state:$state,identity:$identity,identity_verified:$verified,terminal:$terminal,source:"native-spool",observed_at:$now,resources:[{ref:$ref,state:$resource}]}'
}

_loom_native_start() {
    local record digest prior workspace prompt executable nonce ops deadline data
    _loom_native_policy_check || { _loom_native_error policy_denied refused 'Pinned policy changed'; return; }
    jq -e --slurpfile b "$_nn_binding" --slurpfile p "$_nn_pin" '
      .args as $a | $b[0] as $b | $p[0] as $p |
      $a.workspace_id==$b.workspace_id and $a.profile_id==$p.profile.id and $a.profile_digest==$b.profile_digest and
      $a.profile_digest==$p.profile_digest and $a.argv==$p.argv and $a.prompt_ref==$b.prompt_ref and $a.model==$p.model and $a.effort==$p.effort and
      $a.manifest_digest==$b.manifest_digest and $a.limits==$b.limits' "$_nn_request" >/dev/null || { _loom_native_error policy_denied refused 'Launch differs from authorized binding'; return; }
    [[ $(jq -r .limits.stop_on_timeout "$_nn_binding") == false ]] || { _loom_native_error unsupported_capability refused 'Automatic runtime stop is not implemented'; return; }
    digest=$(_loom_native_request_digest "$_nn_request") || return 1
    record=$(loom_state_get host "$_nn_id" 2>/dev/null) || record=''
    if [[ -n $record ]]; then
        _nn_revision=$(jq -r .revision <<< "$record")
        prior=$(jq -r .data.request_digest <<< "$record")
        [[ $prior == "$digest" ]] || { _loom_native_error idempotency_conflict refused 'Attempt already has a different launch'; return; }
        _loom_native_start_result; return
    fi
    workspace=$(jq -r .workspace "$_nn_binding"); prompt=$(jq -r .prompt "$_nn_binding"); executable=$(jq -r '.argv[0]' "$_nn_pin")
    _loom_native_private "$workspace" dir && _loom_native_private "$prompt" || { _loom_native_error policy_denied refused 'Unsafe workspace or prompt'; return; }
    [[ $(loom_policy_digest "$prompt") == "$(jq -r .prompt_digest "$_nn_binding")" ]] || { _loom_native_error identity_mismatch refused 'Prompt artifact changed'; return; }
    [[ $workspace == "$(jq -r .host.workspace_root "$_nn_pin")/"* && -x $executable && ! -L $executable && $(realpath -e "$executable") == "$executable" && $(loom_policy_digest "$executable") == "$(jq -r .executable_digest "$_nn_binding")" ]] || { _loom_native_error identity_mismatch refused 'Workspace root or executable differs'; return; }
    mkdir -p "$_nn_root/native" || return 1
    _loom_native_private "$_nn_root/native" dir || return 2
    # flock only covers the short reservation/spawn boundary, never agent wait.
    exec 9> "$_nn_root/native/launch.lock"; flock -w 2 9 || return 1
    record=$(loom_state_get host "$_nn_id" 2>/dev/null) || record=''
    if [[ -n $record ]]; then
        flock -u 9
        [[ $(jq -r .data.request_digest <<< "$record") == "$digest" ]] || { _loom_native_error idempotency_conflict refused 'Concurrent launch conflicts'; return; }
        _loom_native_start_result; return
    fi
    nonce=$(cat /proc/sys/kernel/random/uuid)
    data=$(jq -cn --arg digest "$digest" --arg nonce "$nonce" --slurpfile b "$_nn_binding" --slurpfile p "$_nn_pin" --slurpfile q "$_nn_request" '{request_digest:$digest,nonce:$nonce,binding:$b[0],pin:$p[0],start_request:$q[0],phase:"reserved"}')
    _loom_native_commit "$_nn_request" native.reserved "$data" || { _loom_native_error outcome_unknown unknown 'Reservation was not acknowledged'; return; }
    mkdir -m 700 "$_nn_dir" || { _loom_native_error outcome_unknown unknown 'Reservation exists; spool unavailable'; return; }
    printf '%s\n' "$nonce" | loom_output_atomic "$_nn_dir/nonce" || return 1
    loom_output_atomic "$_nn_dir/context" < "$_nn_context" || return 1
    loom_output_atomic "$_nn_dir/binding" < "$_nn_binding" || return 1
    loom_output_atomic "$_nn_dir/pin" < "$_nn_pin" || return 1
    loom_output_atomic "$_nn_dir/request" < "$_nn_request" || return 1
    loom_output_atomic "$_nn_dir/prompt" < "$prompt" || return 1
    [[ $(loom_policy_digest "$_nn_dir/prompt") == "$(jq -r .prompt_digest "$_nn_binding")" ]] || return 1
    ops=$(loom_native_root)
    # All inherited stdio and launch-lock fds are closed. No terminal dependence.
    setsid -f bash "$ops/native-supervisor.sh" keeper "$_nn_context" "$_nn_dir" 9>&- </dev/null >/dev/null 2>&1
    flock -u 9
    if [[ ${LOOM_NATIVE_TEST_FAULT:-} == lost_launcher ]]; then kill -KILL "$BASHPID"; fi
    deadline=$(( $(date +%s%3N) + $(jq -r .timeout_ms "$_nn_request") ))
    while [[ ! -f $_nn_dir/identity && ! -f $_nn_dir/completion ]] && (( $(date +%s%3N)<deadline )); do sleep 0.02; done
    _loom_native_start_result
}

_loom_native_start_result() {
    local observation result
    observation=$(_loom_native_observe) || return 1
    if [[ $(jq -r .state <<< "$observation") == unknown ]]; then
        _loom_native_error outcome_unknown unknown 'Reserved launch requires reconciliation; never relaunch'; return
    fi
    result=$(jq -c '{binding,identity,start_evidence:[],prompt_acceptance:"unknown",resources}' <<< "$observation")
    _loom_native_response accepted "$result" true
}

_loom_native_handle() (
    umask 077
    local context=${1:-} request=${2:-} _nn_root _nn_store _nn_binding _nn_pin _nn_dir _nn_id _nn_context _nn_request _nn_revision=null
    local -a _np
    local temp rc=0 op observation result record
    _loom_native_load || return 2
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    _nn_request=$temp/request
    cp -- "$request" "$_nn_request" || return 2
    loom_protocol_check_request "$_nn_request" || return 2
    op=$(jq -r .op "$_nn_request")
    _loom_native_context "$context" "$op" || { _loom_native_error policy_denied refused 'Invalid trusted native context'; return; }
    _loom_native_probe || { _loom_native_error unsupported_capability refused 'Linux identity/session/flush primitives unavailable'; return; }
    op=$(jq -r .op "$_nn_request")
    if [[ -d $_nn_dir ]]; then
        local entry
        while IFS= read -r -d '' entry; do
            [[ ! -L $entry ]] || { _loom_native_error identity_mismatch refused 'Symlink in native spool'; return; }
            if [[ -p $entry && $entry == "$_nn_dir/pipe" ]]; then continue; fi
            if [[ -d $entry ]]; then _loom_native_private "$entry" dir
            else _loom_native_private "$entry"; fi || { [[ ! -e $entry ]] && continue; _loom_native_error identity_mismatch refused 'Unsafe native spool'; return; }
        done < <(find -P "$_nn_dir" -mindepth 1 -print0)
    fi
    if [[ $op == hello ]]; then
        _loom_native_policy_check || { _loom_native_error policy_denied refused 'Pinned policy changed'; return; }
        _loom_native_hello; return
    fi
    jq -e --slurpfile b "$_nn_binding" '.protocol=="loom.execution" and .actor==$b[0].actor and (.target==$b[0].target or (.op=="execution.list" and all(.target|to_entries[]; .value==null or .value==$b[0].target[.key])))' "$_nn_request" >/dev/null || { _loom_native_error owner_fenced refused 'Request does not match provisioned actor epoch and target'; return; }
    # Recheck context at every call; keeper compares current binding before signals.
    case $op in
        execution.start) _loom_native_start > "$temp/response" || rc=$? ;;
        execution.inspect|execution.reconcile|execution.list)
            record=$(loom_state_get host "$_nn_id" 2>/dev/null) || { _loom_native_error identity_mismatch refused 'Unknown attempt'; return; }
            _nn_revision=$(jq -r .revision <<< "$record")
            observation=$(_loom_native_observe) || return 1
            case $op in
                execution.inspect) result=$observation ;;
                execution.reconcile)
                    [[ $(jq -r .args.operation_id "$_nn_request") == "$(jq -r .data.start_request.operation_id <<< "$record")" || $(jq -r .args.operation_id "$_nn_request") == "$(jq -r .data.stop_request.operation_id <<< "$record")" ]] || { _loom_native_error identity_mismatch refused 'Unknown operation'; return; }
                    result=$(jq -cn --slurpfile q "$_nn_request" --argjson o "$observation" '{operation_id:$q[0].args.operation_id,observation:$o}') ;;
                execution.list)
                    [[ $(jq -r .args.run_id "$_nn_request") == "$(jq -r .actor.run_id "$_nn_binding")" ]] || { _loom_native_error owner_fenced refused 'Run does not match binding'; return; }
                    result=$(jq -cn --argjson o "$observation" '{items:[$o],next_cursor:null}') ;;
            esac
            _loom_native_response completed "$result" true > "$temp/response" ;;
        execution.read)
            [[ $(jq -r .args.source "$_nn_request") == combined.base64 ]] || { _loom_native_error identity_mismatch refused 'Unknown stream'; return; }
            result=$(loom_output_read "$_nn_dir/output" "$(jq -r '.args.cursor//""' "$_nn_request")" "$(jq -r .args.limit_bytes "$_nn_request")") || { _loom_native_error cursor_expired refused 'Output cursor unavailable or invalid'; return; }
            _loom_native_response completed "$result" false > "$temp/response" ;;
        execution.stop) _loom_native_stop > "$temp/response" || rc=$? ;;
        execution.release)
            _loom_native_policy_check || { _loom_native_error policy_denied refused 'Pinned policy changed'; return; }
            _loom_native_restore_control release_request "$_nn_dir/released" || return 1
            if [[ -f $_nn_dir/released ]]; then
                [[ $(_loom_native_request_digest "$_nn_dir/released") == "$(_loom_native_request_digest "$_nn_request")" ]] || { _loom_native_error idempotency_conflict refused 'Release already recorded'; return; }
            else
                record=$(loom_state_get host "$_nn_id") || return 1
                [[ $(jq -r .expected_revision "$_nn_request") == "$(jq -r .revision <<< "$record")" ]] || { _loom_native_error revision_conflict refused 'Stale release revision'; return; }
            fi
            observation=$(_loom_native_observe)
            [[ $(jq -r .release_authorized "$_nn_binding") == true && $(jq -r .state <<< "$observation") == exited && $(jq -r .eof "$_nn_dir/output/index") == true ]] || { _loom_native_error resource_busy refused 'Release requires settlement, drained output and authority collection approval'; return; }
            if [[ ! -f $_nn_dir/released ]]; then
                local release_data
                release_data=$(jq -c --slurpfile q "$_nn_request" '.data + {release_request:$q[0],phase:"released"}' <<< "$record")
                _loom_native_commit "$_nn_request" native.released "$release_data" "$(jq -r .revision <<< "$record")" || { _loom_native_error outcome_unknown unknown 'Release intent unacknowledged'; return; }
                loom_output_atomic "$_nn_dir/released" < "$_nn_request" || return 1
            fi
            result=$(jq -c --slurpfile q "$_nn_request" '{binding,resources:(.resources|map(.state=(if $q[0].args.retention_policy=="retain" then "retained" else "released" end)))}' <<< "$observation")
            _loom_native_response completed "$result" true > "$temp/response" ;;
        *) _loom_native_error unsupported_capability refused 'Operation not implemented by native process engine'; return ;;
    esac
    if ! loom_protocol_validate response "$temp/response" "$_nn_request"; then
        _loom_native_error outcome_unknown unknown 'Native response failed contract validation'; return
    fi
    cat "$temp/response"; return "$rc"
)

loom_native_handle() (
    umask 077
    local context=${1:-} request=${2:-} temp rc=0 seconds ops status
    _loom_native_load || return 2
    loom_protocol_check_request "$request" || return 2
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    cp -- "$request" "$temp/request" || return 2
    seconds=$(jq -r '.timeout_ms/1000' "$temp/request")
    ops=$(loom_native_root)
    timeout --kill-after=1 "$seconds" bash "$ops/native.sh" --internal "$context" "$temp/request" > "$temp/response" 2> >(loom_protocol_capture 1048576 "$temp/diagnostic") || rc=$?
    # Diagnostics are fixed labels; never return raw process/environment output.
    if ! loom_protocol_validate response "$temp/response" "$temp/request"; then
        status=failed
        if jq -e '.operation_id!=null' "$temp/request" >/dev/null; then status=unknown; fi
        loom_protocol_receipt "$temp/request" "$status" outcome_unknown 'Native deadline or invalid reply; reconcile original operation' > "$temp/response"
    fi
    rc=$(loom_protocol_exit "$temp/response")
    cat "$temp/response"
    return "$rc"
)

loom_native_serve() (
    local temp rc=0
    umask 077
    _loom_native_load || return 2
    temp=$(mktemp) || return 1
    trap 'rm -f -- "$temp"' EXIT
    loom_protocol_input "$temp" || { loom_protocol_receipt /dev/null refused invalid_request 'Input limit exceeded'; return 2; }
    loom_native_handle "$1" "$temp" || rc=$?
    return "$rc"
)

_loom_native_hello() {
    local capabilities result missing schema
    capabilities=$(jq -cn --slurpfile p "$_nn_pin" '["execution.start.v1","execution.inspect.v1","execution.list.v1","execution.read.v1","execution.reconcile.v1","execution.stop.group.v1","execution.release.v1"] + (if $p[0].profile.model!=null then ["model.select.v1"] else [] end) + (if $p[0].profile.effort!=null then ["effort.select.v1"] else [] end)|map({name:.,state:"supported",evidence:[],limits:{max_bytes:65536,max_items:1}})')
    missing=$(jq -r --argjson caps "$capabilities" '(.args.required_capabilities-($caps|map(.name)))[0]//empty' "$_nn_request")
    [[ -z $missing ]] || { loom_protocol_receipt "$_nn_request" refused unsupported_capability 'Native capability unavailable' "$missing"; return 2; }
    jq -e '.args.versions|index({major:1,minor:0})!=null' "$_nn_request" >/dev/null || { _loom_native_error protocol_mismatch refused 'No common version'; return; }
    schema=$(loom_protocol_digest "$(loom_protocol_root)/schemas/execution-v1/contract.json")
    result=$(jq -cn --argjson caps "$capabilities" --arg digest "$schema" '{selected_version:{major:1,minor:0},provider:{id:"native",version:"1"},capabilities:$caps,limits:{request_bytes:1048576,response_bytes:1048576,metadata_bytes:65536,message_bytes:65536,read_bytes:65536,list_rows:1,diagnostic_bytes:1048576},schema_digest:$digest}')
    _loom_native_response completed "$result"
}

_loom_native_group_empty() {
    local pgid=$1 path pid
    for path in /proc/[0-9]*/stat; do
        pid=${path#/proc/}; pid=${pid%/stat}
        _loom_native_proc "$pid" || { [[ ! -d /proc/$pid ]] && continue; return 2; }
        [[ ${_np[2]} != "$pgid" || ${_np[0]} == Z || ${_np[0]} == X ]] || return 1
    done
}

# Read-only identity observation may settle a recorded self-group KILL even
# when its original caller expired. Never signal a group from this path.
_loom_native_reconcile_kill() {
    local fact pid ticks result
    [[ -f $_nn_dir/identity && -f $_nn_dir/signals && ! -f $_nn_dir/escaped ]] || return 1
    jq -e '.==["TERM","KILL"]' "$_nn_dir/signals" >/dev/null || return 1
    fact=$(loom_state_operation "$(jq -r .actor.id "$_nn_binding")" native.fact "$_nn_id:identity") || return 1
    jq -e --argjson fact "$fact" --slurpfile c "$_nn_context" --slurpfile b "$_nn_binding" \
      --arg nonce "$(cat "$_nn_dir/nonce")" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" --argjson uid "$EUID" '
      .==$fact.outcome.result and .boot_id==$boot and .uid==$uid and .launch_nonce==$nonce and
      .host_installation_id==$c[0].installation_id and .transport_identity==$c[0].transport_identity and
      .host_id==$b[0].target.host_id and .attempt_id==$b[0].target.attempt_id and
      .pgid==.supervisor_pid and .sid==.pgid and (.pgid|type=="number" and .>1)' "$_nn_dir/identity" >/dev/null || return 1
    read -r pid ticks < <(jq -r '[.supervisor_pid,.supervisor_start_ticks]|@tsv' "$_nn_dir/identity")
    if _loom_native_proc "$pid"; then
        [[ ${_np[19]} != "$ticks" || ${_np[0]} == Z || ${_np[0]} == X ]] || return 1
    else
        [[ ! -d /proc/$pid ]] || return 1
    fi
    _loom_native_group_empty "$(jq -r .pgid "$_nn_dir/identity")" || return 1
    result=$(jq -cn --slurpfile id "$_nn_dir/identity" '{identity:$id[0],group_empty:true,escaped:false,terminal:{exit_code:null,signal:null,captured:false,evidence:[]}}') || return 1
    _loom_native_fact completion "$result" || return 1
    printf '%s\n' "$result" | loom_output_atomic "$_nn_dir/completion"
}

# Cache files are projections: reconstruct them from committed host history.
_loom_native_restore_control() {
    local field=$1 cache=$2 record saved
    [[ ! -e $cache ]] || return 0
    record=$(loom_state_get host "$_nn_id") || return 1
    saved=$(jq -c --arg field "$field" '.data[$field] // null' <<< "$record") || return 1
    [[ $saved != null ]] || return 0
    printf '%s\n' "$saved" | loom_output_atomic "$cache"
}

_loom_native_stop() {
    local observation digest saved deadline record data result signals='[]' verified=false confirmed=false group=unknown terminal=null
    _loom_native_policy_check || { _loom_native_error policy_denied refused 'Pinned policy changed'; return; }
    [[ $(jq -r .stop_authorized "$_nn_binding") == true ]] || { _loom_native_error policy_denied refused 'No explicit conductor stop authorization'; return; }
    # Per-request allow_kill is explicit authorization; runtime policy cannot add it.
    digest=$(_loom_native_request_digest "$_nn_request")
    [[ -d $_nn_dir && ! -L $_nn_dir ]] || { _loom_native_error identity_mismatch refused 'No reserved native attempt'; return; }
    exec 9> "$_nn_dir/control.lock"; flock -w 2 9 || return 1
    _loom_native_restore_control stop_request "$_nn_dir/stop" || return 1
    if [[ -f $_nn_dir/stop ]]; then
        saved=$(_loom_native_request_digest "$_nn_dir/stop")
        [[ $saved == "$digest" ]] || { _loom_native_error idempotency_conflict refused 'Stop already reserved; reconcile original operation'; return; }
    else
        observation=$(_loom_native_observe) || return 1
        if [[ $(jq -r .state <<< "$observation") != exited ]]; then
            _loom_native_identity_live "$_nn_dir/identity" || { _loom_native_error outcome_unknown unknown 'Keeper identity unavailable; no signal sent'; return; }
        fi
        record=$(loom_state_get host "$_nn_id") || return 1
        [[ $(jq -r .expected_revision "$_nn_request") == "$(jq -r .revision <<< "$record")" ]] || { _loom_native_error revision_conflict refused 'Stale stop revision'; return; }
        data=$(jq -c --slurpfile q "$_nn_request" '.data + {stop_request:$q[0],phase:"stop_requested"}' <<< "$record")
        _loom_native_commit "$_nn_request" native.stop_requested "$data" "$(jq -r .revision <<< "$record")" || { _loom_native_error outcome_unknown unknown 'Stop intent not acknowledged'; return; }
        loom_output_atomic "$_nn_dir/stop" < "$_nn_request" || return 1
    fi
    flock -u 9
    deadline=$(( $(date +%s%3N) + $(jq -r .timeout_ms "$_nn_request") ))
    while (( $(date +%s%3N)<deadline )); do
        observation=$(_loom_native_observe) || break
        if [[ ${LOOM_NATIVE_TEST_FAULT:-} == stop_observation ]]; then break; fi
        if [[ $(jq -r .state <<< "$observation") == exited ]]; then
            confirmed=true; verified=true; group=exited; terminal=$(jq -c .terminal <<< "$observation"); break
        fi
        # Observation owns post-KILL recovery, including calls made after this
        # caller expires. A missing keeper never grants an external signal.
        if ! _loom_native_identity_live "$_nn_dir/identity"; then break; fi
        verified=true; group=live
        sleep 0.05
    done
    if [[ $confirmed != true && ${LOOM_NATIVE_TEST_FAULT:-} != stop_observation ]]; then
        observation=$(_loom_native_observe) || return 1
        if [[ $(jq -r .state <<< "$observation") == exited ]]; then
            confirmed=true; verified=true; group=exited; terminal=$(jq -c .terminal <<< "$observation")
        fi
    fi
    [[ ! -f $_nn_dir/signals ]] || signals=$(cat "$_nn_dir/signals")
    if [[ $confirmed != true ]]; then
        _loom_native_error outcome_unknown unknown 'Stop requested; complete group termination not confirmed'; return
    fi
    result=$(jq -cn --slurpfile b "$_nn_binding" --argjson signals "$signals" --argjson verified "$verified" --arg group "$group" --argjson confirmed "$confirmed" --argjson terminal "$terminal" '{binding:$b[0].target,requested_signals:$signals,identity_verified:$verified,group_state:$group,confirmed_stopped:$confirmed,terminal:$terminal}')
    _loom_native_response completed "$result" true
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        --internal) _loom_native_handle "${2:-}" "${3:-}" ;;
        serve) loom_native_serve "${2:-}" ;;
        handle) loom_native_handle "${2:-}" "${3:-}" ;;
        *) printf 'native: use serve CONTEXT or handle CONTEXT REQUEST\n' >&2; exit 2 ;;
    esac
fi
