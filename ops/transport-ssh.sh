#!/usr/bin/env bash
# Source-safe SSH transport. No provisioning, fallback or policy selection here.

_loom_ssh_root() ( cd -- "${BASH_SOURCE[0]%/*}" && pwd -P; )
_loom_ssh_load() {
    # shellcheck disable=SC1090,SC1091
    source "${LOOM_SSH_PROTOCOL_MODULE:-$(_loom_ssh_root)/protocol.sh}"
}
_loom_ssh_private() {
    local path=$1 kind=${2:-file} part current='' owner mode
    local -a parts
    [[ $path == /* && $path != */ && $path != *//* && $path != *$'\n'* ]] || return 2
    IFS=/ read -r -a parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [[ -n $part && $part != . && $part != .. ]] || return 2
        current+=/$part
        [[ ! -L $current && -e $current ]] || return 2
        read -r owner mode < <(stat -c '%u %a' -- "$current")
        [[ $owner == "$EUID" || $owner == 0 ]] || return 2
        if (( (8#$mode & 0022)!=0 )); then
            [[ $owner == 0 ]] && (( (8#$mode & 01000)!=0 )) || return 2
        fi
    done
    [[ -O $path ]] && (( (8#$mode & 0077)==0 )) || return 2
    if [[ $kind == dir ]]; then [[ -d $path ]]
    else [[ -f $path && $(stat -c %h -- "$path") == 1 ]]; fi
}
_loom_ssh_digest() { printf 'sha256:'; sha256sum -- "$1" | cut -d ' ' -f1; }
_loom_ssh_config() {
    _loom_ssh_private "$1" && loom_protocol_lex "$1" || return 2
    jq -e '
      keys==(["schema","destination","port","helper_command","known_hosts","identity_file","context_id","identity","connect_timeout_s","timeout_ms","bundle_bytes"]|sort) and .schema==1 and
      (.destination|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9_.@:-]{0,254}$")) and
      (.helper_command|type=="string" and test("^/([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$") and (contains("/../")|not) and (contains("/./")|not) and (endswith("/..")|not) and (endswith("/.")|not)) and
      (.context_id|type=="string" and test("^[A-Za-z0-9_-]{1,128}$")) and
      (.port|type=="number" and floor==. and .>=1 and .<=65535) and
      (.connect_timeout_s|type=="number" and floor==. and .>=1 and .<=30) and
      (.timeout_ms|type=="number" and floor==. and .>=1 and .<=300000) and
      (.bundle_bytes|type=="number" and floor==. and .>=1 and .<=1073741824) and
      (.identity|type=="object" and keys==["boot_id","context_digest","helper_digest","installation_id","transport_identity"] and all(.[];type=="string" and length>0 and length<=256)) and
      (.known_hosts|type=="string") and (.identity_file==null or (.identity_file|type=="string"))' "$1" >/dev/null || return 2
    # OpenSSH expands token/path lists in UserKnownHostsFile. Require a literal
    # safe path so a whitespace or percent token cannot select another file.
    jq -e '.known_hosts|test("^/[A-Za-z0-9_./-]+$")' "$1" >/dev/null || return 2
    _loom_ssh_private "$(jq -r .known_hosts "$1")" || return 2
    [[ $(jq -r .identity_file "$1") == null ]] || _loom_ssh_private "$(jq -r .identity_file "$1")" || return 2
}

# Internal bounded process runner. S1 owns pipe draining, timeout group safety,
# diagnostics capture and the actual child exit. All request bytes remain stdin.
_loom_ssh_exchange() {
    local config=$1 dir=$2 timeout_ms=$3 executable=${LOOM_SSH_EXECUTABLE:-/usr/bin/ssh} duration rc=0
    local -a argv
    argv=(-T -a -x -o BatchMode=yes -o StrictHostKeyChecking=yes -o UpdateHostKeys=no
          -o ConnectionAttempts=1 -o ClearAllForwardings=yes -o PermitLocalCommand=no
          -o RequestTTY=no -o RemoteCommand=none -o ControlMaster=no -o ControlPath=none
          -o "ConnectTimeout=$(jq -r .connect_timeout_s "$config")"
          -o "UserKnownHostsFile=$(jq -r .known_hosts "$config")" -o GlobalKnownHostsFile=/dev/null
          -p "$(jq -r .port "$config")")
    if [[ $(jq -r .identity_file "$config") != null ]]; then
        argv+=(-o IdentitiesOnly=yes -i "$(jq -r .identity_file "$config")")
    fi
    argv+=(-- "$(jq -r .destination "$config")" "$(jq -r .helper_command "$config")")
    duration=$(awk -v n="$timeout_ms" 'BEGIN {printf "%.3f",n/1000}')
    { timeout --signal=TERM --kill-after=0.2 "$duration" /bin/bash "${LOOM_SSH_PROTOCOL_MODULE:-$(_loom_ssh_root)/protocol.sh}" \
        _call "$dir" 1048576 1048576 "$executable" "${argv[@]}" > "$dir/runner-out" 2> "$dir/runner-err"; } 2> "$dir/launcher-err" || rc=$?
    printf '%s\n' "$rc" > "$dir/transport-exit"
    return 0
}
_loom_ssh_frame() {
    jq -cn --slurpfile c "$1" --arg kind "$2" --slurpfile request "${3:-/dev/null}" \
      '{schema:1,kind:$kind,context_id:$c[0].context_id,identity:$c[0].identity,request:($request[0]//null)}'
}

loom_ssh_handle() (
    umask 077
    local config=$1 request=$2 dir rc reason='' expected deadline
    _loom_ssh_load || return 2
    loom_protocol_check_request "$request" || return 2
    _loom_ssh_config "$config" || { loom_protocol_receipt "$request" refused policy_denied 'Invalid private SSH configuration'; return 2; }
    dir=$(mktemp -d) || return 1
    trap 'rm -rf -- "$dir"' EXIT
    _loom_ssh_frame "$config" call "$request" > "$dir/request" || return 2
    deadline=$(jq -nr --slurpfile q "$request" --slurpfile c "$config" '[$q[0].timeout_ms,$c[0].timeout_ms]|min')
    _loom_ssh_exchange "$config" "$dir" "$deadline"
    rc=$(cat "$dir/transport-exit")
    if [[ ! -f $dir/stdout || $(wc -c < "$dir/stdout") -gt 1048576 ]]; then reason=response_overflow
    elif ! loom_protocol_validate response "$dir/stdout" "$request"; then reason=invalid_response
    elif ! jq -e --slurpfile c "$config" '.extensions["loom.ssh"].identity==$c[0].identity' "$dir/stdout" >/dev/null; then reason=identity_mismatch
    else
        expected=$(loom_protocol_exit "$dir/stdout")
        [[ $rc == "$expected" ]] || reason=exit_mismatch
    fi
    if [[ -n $reason ]]; then
        loom_protocol_receipt "$request" unknown outcome_unknown 'SSH outcome unverified; reconcile the same operation on its pinned host' > "$dir/response"
    else cp "$dir/stdout" "$dir/response"; fi
    jq -c --argjson exit_code "$rc" --arg reason "$reason" \
      --argjson truncated "$(if [[ -f $dir/stderr && $(wc -c < "$dir/stderr") -gt 1048576 ]]; then echo true; else echo false; fi)" \
      '.extensions["loom.ssh.transport"]={exit_code:$exit_code,reason:$reason,diagnostic_truncated:$truncated}' "$dir/response" > "$dir/final"
    local response_limit=1048576
    [[ $(jq -r .op "$request") != hello ]] || response_limit=65536
    if (( $(wc -c < "$dir/final") > response_limit )); then
        loom_protocol_receipt "$request" unknown outcome_unknown 'Normalized response exceeds transport quota' |
          jq -c --argjson rc "$rc" '.extensions["loom.ssh.transport"]={exit_code:$rc,reason:"normalized_overflow",diagnostic_truncated:false}' > "$dir/final"
    fi
    cat "$dir/final"
    return "$(loom_protocol_exit "$dir/final")"
)
loom_ssh_serve() (
    umask 077
    local dir
    _loom_ssh_load || return 2
    dir=$(mktemp -d) || return 1
    trap 'rm -rf -- "$dir"' EXIT
    loom_protocol_input "$dir/input" || { loom_protocol_receipt /dev/null refused quota_exceeded 'Request exceeds transport quota'; return 2; }
    loom_ssh_handle "$1" "$dir/input"
)

# Control API uses small JSON headers. Upload payload is a separate raw stream,
# never JSON/base64; only an explicitly provisioned context may receive it.
_loom_ssh_control() (
    umask 077
    local config=$1 kind=$2 bundle=${3:-} digest=${4:-} dir rc bytes=0
    _loom_ssh_load && _loom_ssh_config "$config" || return 2
    dir=$(mktemp -d) || return 1
    trap 'rm -rf -- "$dir"' EXIT
    if [[ $kind == upload ]]; then
        [[ -f $bundle && ! -L $bundle ]] || return 2
        bytes=$(stat -c %s -- "$bundle")
        (( bytes <= $(jq -r .bundle_bytes "$config") )) || return 2
        [[ $digest == "$(loom_protocol_digest "$bundle")" ]] || return 2
    fi
    _loom_ssh_frame "$config" "$kind" | jq -c --arg digest "$digest" --argjson bytes "$bytes" '. + {bundle:{bytes:$bytes,digest:$digest}}' > "$dir/request"
    [[ $kind != upload ]] || cat -- "$bundle" >> "$dir/request"
    _loom_ssh_exchange "$config" "$dir" "$(jq -r .timeout_ms "$config")"
    rc=$(cat "$dir/transport-exit")
    if [[ -f $dir/stdout && $(wc -c < "$dir/stdout") -le 65536 ]] && loom_protocol_lex "$dir/stdout" &&
       jq -e --slurpfile c "$config" 'keys==["error","identity","ok","schema","status"] and .schema==1 and .identity==$c[0].identity and (.ok|type=="boolean") and (if .ok then .status=="completed" and .error==null else .status=="refused" and (.error|type=="string") end)' "$dir/stdout" >/dev/null &&
       [[ $rc == "$(jq -r 'if .ok then 0 else 2 end' "$dir/stdout")" ]]; then
        cat "$dir/stdout"; return "$rc"
    fi
    jq -cn --argjson rc "$rc" '{schema:1,ok:false,status:"unknown",error:"unverified_transport",transport_exit:$rc}'
    return 1
)
loom_ssh_preflight() { _loom_ssh_control "$1" preflight; }
loom_ssh_upload() { _loom_ssh_control "$1" upload "$2" "$3"; }

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        handle) loom_ssh_handle "${2:-}" "${3:-}" ;;
        serve) loom_ssh_serve "${2:-}" ;;
        preflight) loom_ssh_preflight "${2:-}" ;;
        upload) loom_ssh_upload "${2:-}" "${3:-}" "${4:-}" ;;
        *) printf 'ssh: use handle CONFIG REQUEST, serve CONFIG, preflight CONFIG, upload CONFIG BUNDLE DIGEST\n' >&2; exit 2 ;;
    esac
fi
