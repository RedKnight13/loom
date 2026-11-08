#!/usr/bin/env bash
# Private per-attempt keeper, not a resident service. Safe to source.
# shellcheck disable=SC2030,SC2031,SC2015

_loom_native_fault() {
    [[ ${LOOM_NATIVE_TEST_FAULT:-} != "$1" ]] || exit 91
}

_loom_native_child() {
    local dir=$1 workspace prompt ingress executable arg
    local -a argv=()
    while [[ ! -f $dir/gate ]]; do
        # Lost keeper leaves child positively gated; child exits without exec.
        _loom_native_identity_live "$dir/identity" || return 90
        sleep 0.02
    done
    _loom_native_fault before_exec
    while IFS= read -r -d '' arg; do argv+=("$arg"); done < <(jq -j '.argv[]|.,"\u0000"' "$dir/pin")
    executable=${argv[0]}
    [[ $(loom_policy_digest "$executable") == "$(jq -r .executable_digest "$dir/binding")" ]] || return 90
    workspace=$(jq -r .workspace "$dir/binding"); prompt=$dir/prompt; ingress=$(jq -r .profile.prompt_ingress "$dir/pin")
    [[ $(loom_policy_digest "$prompt") == "$(jq -r .prompt_digest "$dir/binding")" ]] || return 90
    cd -- "$workspace" || return 90
    _loom_native_fact exec_intent '{}' || return 90
    printf '{}\n' | loom_output_atomic "$dir/exec-intent" || return 90
    _loom_native_fault after_exec_intent
    # Exec boundary is explicit, but this does not invent an agent readiness ack.
    if [[ $ingress == stdin ]]; then
        exec env -i PATH=/usr/bin:/bin LANG=C.UTF-8 HOME="$workspace" LOOM_BINDING_FILE="$dir/binding" "${argv[@]}" < "$prompt"
    else
        exec env -i PATH=/usr/bin:/bin LANG=C.UTF-8 HOME="$workspace" LOOM_BINDING_FILE="$dir/binding" LOOM_PROMPT_FILE="$prompt" "${argv[@]}" </dev/null
    fi
}

# Scan from the keeper itself using builtins; no ps/grep child can be mistaken
# for an agent descendant. Previously seen identities detect observed escapes.
_loom_native_scan() {
    local path pid ticks
    _nk_live=0
    for path in /proc/[0-9]*/stat; do
        pid=${path#/proc/}; pid=${pid%/stat}
        [[ $pid != "$$" && $pid != "$BASHPID" ]] || continue
        _loom_native_proc "$pid" || continue
        [[ ${_np[0]} != Z && ${_np[0]} != X ]] || continue
        ticks=${_np[19]}
        if [[ ${_np[2]} == "$_nk_group" ]]; then
            _nk_known[$pid]=$ticks; _nk_live=$((_nk_live+1))
        elif [[ ${_nk_known[$pid]:-} == "$ticks" ]]; then
            printf '{}\n' | loom_output_atomic "$_nn_dir/escaped" || return 1
        fi
    done
}

_loom_native_guard() {
    # This command runs only in the keeper. Its PGID cannot be recycled between
    # comparison and a self-group signal while this very process is alive.
    [[ $$ == "$_nk_group" && $$ -gt 1 ]] || return 1
    _loom_native_identity_live "$_nn_dir/identity" || return 1
    jq -e --argjson expected "$identity" ' .==$expected' "$_nn_dir/identity" >/dev/null || return 1
    jq -e --argjson pid "$$" ' .supervisor_pid==$pid and .pgid==$pid and .sid==$pid' "$_nn_dir/identity" >/dev/null || return 1
    cmp -s <(jq -cS 'del(.stop_authorized,.release_authorized)' "$_nn_binding") <(jq -cS 'del(.stop_authorized,.release_authorized)' "$_nn_dir/binding") || return 1
    jq -e --slurpfile b "$_nn_binding" '.actor==$b[0].actor and .target==$b[0].target and $b[0].stop_authorized==true' "$_nn_dir/stop" >/dev/null
}

_loom_native_keeper() {
    local context=$1 dir=$2 ops child child_ticks own_ticks nonce identity rc=0 waited=false stopping=false kill_at=0 allow_kill=false output_pid
    local _nn_root _nn_store _nn_binding _nn_pin _nn_dir _nn_id _nn_context _nk_group _nk_live
    local -a _np
    local -A _nk_known=()
    _loom_native_context "$context" || return 2
    [[ $_nn_dir == "$dir" ]] || return 2
    exec 7> "$dir/keeper.lock"; flock -n 7 || return 2
    _loom_native_fault reserved
    _loom_native_proc "$$" || return 2
    _nk_group=${_np[2]}; own_ticks=${_np[19]}
    [[ $_nk_group == "$$" && ${_np[3]} == "$$" ]] || return 2
    trap ':' TERM HUP INT
    ops=$(loom_native_root); nonce=$(cat "$dir/nonce")
    mkfifo -m 600 "$dir/pipe" || return 2
    # Writer has its own SID/group, fd ownership and identity record. It retains
    # the FIFO read end while draining even after worker group KILL.
    setsid bash "$ops/native-supervisor.sh" writer "$context" "$dir" 7>&- </dev/null >/dev/null 2>&1 &
    output_pid=$!
    bash "$ops/native-supervisor.sh" child "$context" "$dir" 7>&- > "$dir/pipe" 2>&1 &
    child=$!
    _loom_native_proc "$child" || return 2
    child_ticks=${_np[19]}
    identity=$(jq -cn --slurpfile c "$context" --slurpfile b "$dir/binding" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" --argjson uid "$EUID" --argjson child "$child" --arg ticks "$child_ticks" --argjson keeper "$$" --arg own "$own_ticks" --arg nonce "$nonce" '{kind:"native",host_id:$b[0].target.host_id,transport_identity:$c[0].transport_identity,host_installation_id:$c[0].installation_id,boot_id:$boot,uid:$uid,pid:$child,start_ticks:$ticks,pgid:$keeper,sid:$keeper,supervisor_pid:$keeper,supervisor_start_ticks:$own,attempt_id:$b[0].target.attempt_id,launch_nonce:$nonce}')
    _loom_native_fact identity "$identity" || return 2
    printf '%s\n' "$identity" | loom_output_atomic "$dir/identity" || return 2
    _loom_native_fault identity
    _loom_native_policy_check || return 2
    printf '{}\n' | loom_output_atomic "$dir/gate" || return 2
    _loom_native_fault gate
    _nk_known[$child]=$child_ticks
    while :; do
        _loom_native_scan || return 1
        if [[ $waited == false ]] && { ! _loom_native_proc "$child" || [[ ${_np[19]} != "$child_ticks" || ${_np[0]} == Z ]]; }; then
            wait "$child" || rc=$?
            waited=true
            # Shell wait status is captured exactly. 128+n is not proof of a
            # signal versus an explicit exit of that value, so signal stays null.
            printf '{"exit_code":%s,"signal":null,"captured":true,"evidence":[]}\n' "$rc" | loom_output_atomic "$dir/child-exit" || return 1
        fi
        if [[ $waited == true && $_nk_live == 0 ]]; then break; fi
        if [[ -f $dir/stop && $stopping == false ]]; then
            _loom_native_guard || return 1
            _loom_native_fault before_term
            # Recheck after the deterministic race hook as well.
            _loom_native_guard || return 1
            printf '["TERM"]\n' | loom_output_atomic "$dir/signals" || return 1
            kill -TERM -- "-$_nk_group" || return 1
            stopping=true
            kill_at=$(( $(date +%s%3N) + $(jq -r .args.grace_ms "$dir/stop") ))
            allow_kill=$(jq -r .args.allow_kill "$dir/stop")
        fi
        if [[ $stopping == true && $allow_kill == true ]] && (( $(date +%s%3N)>=kill_at )); then
            _loom_native_scan || return 1
            if (( _nk_live>0 )); then
                _loom_native_guard || return 1
                printf '["TERM","KILL"]\n' | loom_output_atomic "$dir/signals" || return 1
                _loom_native_fault before_kill
                _loom_native_guard || return 1
                kill -KILL -- "-$_nk_group"
                return 1
            fi
        fi
        sleep 0.05
    done
    # Surviving children delay completion. Observed escapes keep it unresolved.
    [[ ! -f $dir/escaped ]] || return 1
    wait "$output_pid" || return 1
    local completion
    completion=$(jq -cn --argjson identity "$identity" --slurpfile terminal "$dir/child-exit" --slurpfile output "$dir/output/index" '{identity:$identity,group_empty:true,escaped:false,terminal:$terminal[0],final_output:$output[0]}') || return 1
    _loom_native_fact completion "$completion" || return 1
    printf '%s\n' "$completion" | loom_output_atomic "$dir/completion"
}

_loom_native_supervisor_main() {
    umask 077
    local mode=$1 context=$2 dir=$3 ops quota nonce fd path
    local _nn_root _nn_store _nn_binding _nn_pin _nn_dir _nn_id _nn_context
    local -a _np
    # Close caller-owned descriptors as well as stdio redirections at launch.
    # Bash keeps its script reader on 255 and closes that descriptor on exec.
    for path in /proc/self/fd/*; do
        fd=${path##*/}
        if (( fd>2 && fd!=255 )); then exec {fd}>&-; fi
    done
    ops=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
    # shellcheck source=ops/native.sh
    source "$ops/native.sh"
    _loom_native_load || return 2
    case $mode in
        keeper) _loom_native_keeper "$context" "$dir" ;;
        child)
            _loom_native_context "$context" || return 2
            # Identity is persisted by keeper before this gated child proceeds.
            for _ in {1..250}; do [[ ! -f $dir/identity ]] || break; sleep 0.02; done
            [[ -f $dir/identity ]] || return 90
            _loom_native_child "$dir" ;;
        writer)
            _loom_native_proc "$$" || return 2
            printf '{"pid":%s,"start_ticks":"%s","pgid":%s,"sid":%s}\n' "$$" "${_np[19]}" "${_np[2]}" "${_np[3]}" | loom_output_atomic "$dir/writer-identity" || return 1
            quota=$(jq -r .limits.output_bytes "$dir/binding"); nonce=$(cat "$dir/nonce")
            loom_output_drain "$dir/output" "$quota" "$nonce" < "$dir/pipe" ;;
        *) return 2 ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then _loom_native_supervisor_main "$@"; fi
