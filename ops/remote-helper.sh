#!/usr/bin/env bash
# Fixed-command, explicitly installed SSH endpoint. No request-supplied paths.
# shellcheck disable=SC2154 # S4 context loader supplies _nn_* state.

_loom_remote_root() ( cd -- "${BASH_SOURCE[0]%/*}" && pwd -P; )
_loom_remote_load() {
    local root=$1
    # shellcheck disable=SC1090,SC1091
    source "$root/transport-ssh.sh" || return 2
    _loom_ssh_private "$root" dir && _loom_ssh_private "$root/installation.json" || return 2
    _rh_config=$root/installation.json
    # Strict lexical checking is performed once the trusted S1 module is loaded.
    jq -e 'keys==["bundle_bytes","contexts","runtime","schema"] and .schema==1 and
      (.runtime|type=="string") and (.bundle_bytes|type=="number" and floor==. and .>=1 and .<=1073741824) and
      (.contexts|type=="object" and length>0 and length<=100 and all(to_entries[];
        (.key|test("^[A-Za-z0-9_-]{1,128}$")) and (.value|keys==["context","prepare"])))' "$_rh_config" >/dev/null || return 2
    _rh_runtime=$(jq -r .runtime "$_rh_config")
    _loom_ssh_private "$_rh_runtime" dir || return 2
    local file
    [[ -d $_rh_runtime/schemas && ! -L $_rh_runtime/schemas ]] || return 2
    [[ -z $(find "$_rh_runtime/schemas" ! -type f ! -type d -print -quit) ]] || return 2
    for file in native.sh native-supervisor.sh output.sh protocol.sh policy.sh state.sh; do
        _loom_ssh_private "$_rh_runtime/ops/$file" || return 2
    done
    unset LOOM_NATIVE_PROTOCOL_MODULE LOOM_NATIVE_STATE_MODULE LOOM_NATIVE_POLICY_MODULE LOOM_NATIVE_TEST_FAULT
    # shellcheck disable=SC1090,SC1091
    source "$_rh_runtime/ops/native.sh" || return 2
    _loom_native_load && loom_protocol_lex "$_rh_config"
}
_loom_remote_identity() {
    local root=$1 id=$2 file context plan
    context=$(jq -er --arg id "$id" '.contexts[$id].context' "$_rh_config") || return 2
    _loom_native_context "$context" || return 2
    [[ $(jq -r .transport "$_nn_pin") == ssh && $(jq -r .host.helper.version "$_nn_pin") == 1 &&
       $(jq -r .host.helper.digest "$_nn_pin") == "$(loom_protocol_digest "$root/remote-helper.sh")" ]] || return 2
    _rh_context=$context
    plan=$(jq -c --arg id "$id" '.contexts[$id].prepare' "$_rh_config")
    _rh_plan=$plan
    # Hash exact installed code, schemas and context inputs, including copied
    # authority receipts. A modified helper/context/boot never inherits a pin.
    local helper_digest context_digest
    helper_digest=$({
        sha256sum "$root/remote-helper.sh" "$root/transport-ssh.sh" "$_rh_config"
        for file in native.sh native-supervisor.sh output.sh protocol.sh policy.sh state.sh; do sha256sum "$_rh_runtime/ops/$file"; done
        while IFS= read -r -d '' file; do
            _loom_ssh_private "$file" || return 2
            sha256sum "$file"
        done < <(find "$_rh_runtime/schemas" -type f -print0 | sort -z)
    } | sha256sum | cut -d ' ' -f1) || return 2
    context_digest=$({
        sha256sum "$context"
        for file in config hosts profiles pin binding authorization; do sha256sum "$(jq -r --arg key "$file" '.[$key]' "$context")"; done
        _loom_ssh_private "$(jq -r .prompt "$_nn_binding")" || return 2
        sha256sum "$(jq -r .prompt "$_nn_binding")"
        if [[ $plan != null ]]; then
            for file in manifest work; do
                file=$(jq -r --arg key "$file" '.[$key]' <<< "$plan")
                _loom_ssh_private "$file" || return 2
                sha256sum "$file"
            done
        fi
    } | sha256sum | cut -d ' ' -f1) || return 2
    _rh_identity=$(jq -cn --slurpfile c "$context" --arg helper "sha256:$helper_digest" --arg context "sha256:$context_digest" --arg boot "$(cat /proc/sys/kernel/random/boot_id)" \
      '{installation_id:$c[0].installation_id,transport_identity:$c[0].transport_identity,helper_digest:$helper,context_digest:$context,boot_id:$boot}')
    _rh_spool=$_nn_root/ssh/$(printf '%s' "$id" | sha256sum | cut -d ' ' -f1)
    [[ ! -L $_nn_root/ssh && ! -L $_rh_spool ]] || return 2
    mkdir -p -- "$_rh_spool" || return 2
    _loom_ssh_private "$_rh_spool" dir || return 2
    while IFS= read -r -d '' file; do
        _loom_ssh_private "$file" || return 2
    done < <(find "$_rh_spool" -mindepth 1 -maxdepth 1 -print0)
}

# Operator-only local installation. Run on the chosen execution host using the
# already reviewed deployment. Updates install into a new versioned directory.
loom_remote_install() (
    set -euo pipefail
    umask 077
    local config=$1 destination=$2 root parent temp id
    root=$(_loom_remote_root)
    # shellcheck disable=SC1090,SC1091
    source "$root/transport-ssh.sh"
    _loom_ssh_private "$config"
    [[ $destination =~ ^/([A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$ && $destination != */../* && $destination != */./* && $destination != */.. && $destination != */. && ! -e $destination && ! -L $destination ]]
    parent=${destination%/*}; _loom_ssh_private "$parent" dir
    temp=$(mktemp -d "$parent/.helper.XXXXXXXXXXXX")
    trap 'rm -rf -- "$temp"' EXIT
    cp -- "$root/remote-helper.sh" "$root/transport-ssh.sh" "$temp/"
    chmod 700 "$temp/remote-helper.sh" "$temp/transport-ssh.sh"
    cp -- "$config" "$temp/installation.json"
    chmod 600 "$temp/installation.json"
    _loom_remote_load "$temp"
    while IFS= read -r id; do _loom_remote_identity "$temp" "$id"; done < <(jq -r '.contexts|keys[]' "$config")
    sync -f "$temp/installation.json"; sync -f "$temp"
    mv -T -- "$temp" "$destination"; sync -f "$parent"
    printf '{"schema":1,"installed":true}\n'
)
_loom_remote_control_reply() {
    jq -cn --argjson identity "$_rh_identity" --argjson ok "$1" --arg error "${2:-}" \
      '{schema:1,ok:$ok,status:(if $ok then "completed" else "refused" end),identity:$identity,error:(if $error=="" then null else $error end)}'
}
_loom_remote_git() { env -i PATH=/usr/bin:/bin LANG=C.UTF-8 HOME=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -c core.hooksPath=/dev/null "$@"; }
_loom_remote_prepare() (
    set -euo pipefail
    local request=$1 plan=$_rh_plan workspace root bundle base branch digest record max_files max_bytes entry metadata name mode type _object size count=0 bytes=0 tmp
    [[ $plan != null ]] || { loom_protocol_receipt "$request" refused unsupported_capability 'Workspace preparation is not provisioned'; return 2; }
    jq -e 'keys==(["args","max_files","max_worktree_bytes","manifest","work"]|sort) and
      (.max_files|type=="number" and floor==. and .>0 and .<=100000) and
      (.max_worktree_bytes|type=="number" and floor==. and .>0 and .<=1073741824)' <<< "$plan" >/dev/null
    jq -e --argjson plan "$plan" --slurpfile b "$_nn_binding" '.args==$plan.args and .actor==$b[0].actor and .target==$b[0].target and .args.workspace_id==$b[0].workspace_id and .args.manifest_digest==$b[0].manifest_digest' "$request" >/dev/null || {
        loom_protocol_receipt "$request" refused policy_denied 'Workspace request differs from provisioned authority binding'; return 2;
    }
    workspace=$(jq -r .workspace "$_nn_binding"); root=$(jq -r .host.workspace_root "$_nn_pin")
    _loom_ssh_private "$root" dir
    [[ $workspace == "$root/"* && ${workspace#"$root/"} != */* && $workspace != "$root/." && $workspace != "$root/.." ]]
    digest=$(jq -cS 'del(.request_id,.timeout_ms)' "$request" | sha256sum | cut -d ' ' -f1)
    record=$_rh_spool/prepared
    exec 9> "$_rh_spool/prepare.lock"; flock -x -w "$(jq -r ' .timeout_ms/1000' "$request")" 9
    if [[ -e $record ]]; then
        [[ $(cat "$record") == "$digest" ]] || { loom_protocol_receipt "$request" refused idempotency_conflict 'Workspace operation conflicts'; return 2; }
        _loom_ssh_private "$workspace" dir
        disposition=existing
    else
        # A directory without its durable receipt is unknown, never overwritten.
        [[ ! -e $workspace && ! -L $workspace ]] || { loom_protocol_receipt "$request" unknown outcome_unknown 'Workspace exists without preparation receipt'; return 1; }
        bundle=$_rh_spool/bundle
        _loom_ssh_private "$bundle"
        [[ $(loom_protocol_digest "$bundle") == "$(jq -r .args.bundle_digest <<< "$plan")" ]]
        [[ $(loom_protocol_digest "$(jq -r .manifest <<< "$plan")") == "$(jq -r .args.manifest_digest <<< "$plan")" ]]
        base=$(jq -r .args.base_sha <<< "$plan"); branch=$(jq -r .args.branch <<< "$plan")
        _loom_remote_git check-ref-format --branch "$branch" >/dev/null
        tmp=$(mktemp -d "$root/.prepare.XXXXXXXXXXXX")
        trap 'rm -rf -- "$tmp"' EXIT
        _loom_remote_git init --bare "$tmp/objects" >/dev/null
        _loom_remote_git -C "$tmp/objects" bundle verify "$bundle" >/dev/null 2>&1
        # Pack retained as pack; do not unpack arbitrary archive members.
        _loom_remote_git -C "$tmp/objects" -c fetch.unpackLimit=1 fetch --no-tags "$bundle" '+refs/*:refs/*' >/dev/null 2>&1
        [[ $(_loom_remote_git -C "$tmp/objects" rev-parse "$base^{commit}") == "$base" ]]
        max_files=$(jq -r .max_files <<< "$plan"); max_bytes=$(jq -r .max_worktree_bytes <<< "$plan")
        # Stream tree metadata; a tiny pack with many entries must not create an
        # unbounded listing file before the quota check. pipefail checks Git too.
        _loom_remote_git -C "$tmp/objects" ls-tree -rzl "$base" | while IFS= read -r -d '' entry; do
            metadata=${entry%%$'\t'*}; name=${entry#*$'\t'}
            read -r mode type _object size <<< "$metadata"
            [[ ( $mode == 100644 || $mode == 100755 ) && $type == blob && $size =~ ^[0-9]+$ && $name != /* && $name != ../* && $name != */../* && $name != .loom && $name != .loom/* ]] || {
                loom_protocol_receipt "$request" refused policy_denied 'Bundle contains links, special entries or reserved paths'; return 2;
            }
            count=$((count+1)); bytes=$((bytes+size))
            if (( count > max_files || bytes > max_bytes )); then
                loom_protocol_receipt "$request" refused quota_exceeded 'Workspace exceeds file or byte quota'; return 2
            fi
        done || return $?
        _loom_remote_git clone --no-checkout --no-hardlinks "$tmp/objects" "$tmp/workspace" >/dev/null 2>&1
        _loom_remote_git -C "$tmp/workspace" checkout -b "$branch" "$base" >/dev/null 2>&1
        _loom_remote_git -C "$tmp/workspace" remote remove origin
        cp -- "$(jq -r .work <<< "$plan")" "$tmp/workspace/WORK.md"
        mkdir -p "$tmp/workspace/.loom"
        cp -- "$(jq -r .manifest <<< "$plan")" "$tmp/workspace/.loom/binding.json"
        printf '\n.loom/\nREPORT.md\nWORK.md\n' >> "$tmp/workspace/.git/info/exclude"
        sync -f "$tmp/workspace"
        mv -T -- "$tmp/workspace" "$workspace"; sync -f "$root"
        printf '%s\n' "$digest" > "$_rh_spool/.prepared"
        sync -f "$_rh_spool/.prepared"; mv -T "$_rh_spool/.prepared" "$record"; sync -f "$_rh_spool"
        disposition=created
    fi
    jq -cn --slurpfile q "$request" --arg disposition "$disposition" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      $q[0]|{protocol,version,request_id,operation_id,op,target}+
      {ok:true,status:"completed",revision:null,durable:true,result:{workspace_id:.args.workspace_id,host_id:.target.host_id,base_sha:.args.base_sha,manifest_digest:.args.manifest_digest,disposition:$disposition},error:null,effects:[],evidence:[],observed_at:$at,extensions:{}}'
)

loom_remote_serve() (
    set -uo pipefail
    umask 077
    local root=$1 temp limit header_size total kind rc=0 bytes digest
    _loom_remote_load "$root" || return 2
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    limit=$(jq -r '[.bundle_bytes+65536,1052672]|max' "$_rh_config")
    head -c "$((limit+1))" > "$temp/wire"
    total=$(stat -c %s "$temp/wire")
    (( total<=limit )) || return 2
    head -c 1052673 "$temp/wire" > "$temp/header-prefix"
    head -n1 "$temp/header-prefix" > "$temp/header"
    header_size=$(stat -c %s "$temp/header")
    (( header_size<=1052672 )) && loom_protocol_lex "$temp/header" || return 2
    jq -e 'keys==(["schema","kind","context_id","identity","request"]|sort) or keys==(["schema","kind","context_id","identity","request","bundle"]|sort)' "$temp/header" >/dev/null || return 2
    jq -e '.schema==1 and (.context_id|type=="string" and test("^[A-Za-z0-9_-]{1,128}$")) and (.kind=="call" or .kind=="preflight" or .kind=="upload")' "$temp/header" >/dev/null || return 2
    _loom_remote_identity "$root" "$(jq -r .context_id "$temp/header")" || return 2
    kind=$(jq -r .kind "$temp/header")
    if ! jq -e --argjson identity "$_rh_identity" '.identity==$identity' "$temp/header" >/dev/null; then
        if [[ $kind == call ]]; then
            jq -c .request "$temp/header" > "$temp/request"
            loom_protocol_receipt "$temp/request" unknown identity_mismatch 'Boot, installation, helper or context pin changed' | jq -c --argjson identity "$_rh_identity" '.extensions["loom.ssh"]={identity:$identity}'
            return 1
        fi
        _loom_remote_control_reply false identity_mismatch; return 2
    fi
    case $kind in
        preflight)
            (( total==header_size )) || return 2
            _loom_native_probe || { _loom_remote_control_reply false unsupported_capability; return 2; }
            _loom_remote_control_reply true ;;
        upload)
            (( header_size<=65536 )) || return 2
            jq -e --argjson quota "$(jq -r .bundle_bytes "$_rh_config")" '.request==null and (.bundle|keys==["bytes","digest"]) and (.bundle.bytes|type=="number" and floor==. and .>=0 and .<=$quota) and (.bundle.digest|test("^git-blob-sha1-v1:[0-9a-f]{40}$"))' "$temp/header" >/dev/null || return 2
            bytes=$(jq -r .bundle.bytes "$temp/header"); digest=$(jq -r .bundle.digest "$temp/header")
            (( total-header_size==bytes )) || { _loom_remote_control_reply false truncated_bundle; return 2; }
            tail -c "+$((header_size+1))" "$temp/wire" > "$temp/bundle"
            [[ $(loom_protocol_digest "$temp/bundle") == "$digest" && $(jq -r .args.bundle_digest <<< "$_rh_plan") == "$digest" ]] || { _loom_remote_control_reply false digest_mismatch; return 2; }
            exec 9> "$_rh_spool/upload.lock"; flock -x -w 30 9 || return 1
            if [[ -e $_rh_spool/bundle ]]; then
                [[ $(loom_protocol_digest "$_rh_spool/bundle") == "$digest" ]] || { _loom_remote_control_reply false idempotency_conflict; return 2; }
            else
                cp "$temp/bundle" "$_rh_spool/.bundle" && sync -f "$_rh_spool/.bundle" && mv -T "$_rh_spool/.bundle" "$_rh_spool/bundle" && sync -f "$_rh_spool" || return 1
            fi
            _loom_remote_control_reply true ;;
        call)
            (( total==header_size )) || return 2
            jq -c .request "$temp/header" > "$temp/request"
            loom_protocol_check_request "$temp/request" > "$temp/response" || rc=$?
            if (( rc==0 )); then
                if [[ $(jq -r .op "$temp/request") == workspace.prepare ]]; then
                    /bin/bash "$root/remote-helper.sh" _prepare "$root" "$(jq -r .context_id "$temp/header")" "$temp/request" > "$temp/response" || rc=$?
                elif [[ $(jq -r .op "$temp/request") == hello && $_rh_plan != null ]]; then
                    jq '.args.required_capabilities -= ["workspace.prepare.v1"]' "$temp/request" > "$temp/native-request"
                    loom_native_handle "$_rh_context" "$temp/native-request" > "$temp/native-response" || rc=$?
                    jq 'if .ok then .result.capabilities += [{name:"workspace.prepare.v1",state:"supported",evidence:[],limits:{max_bytes:65536,max_items:1}}] else . end' "$temp/native-response" > "$temp/response"
                else
                    loom_native_handle "$_rh_context" "$temp/request" > "$temp/response" || rc=$?
                fi
            fi
            jq -c --argjson identity "$_rh_identity" '.extensions["loom.ssh"]={identity:$identity}' "$temp/response"
            return "$rc" ;;
    esac
)
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-serve} in
        serve) loom_remote_serve "$(_loom_remote_root)" ;;
        install) loom_remote_install "${2:-}" "${3:-}" ;;
        _prepare)
            _loom_remote_load "${2:-}" || exit 2
            _loom_remote_identity "${2:-}" "${3:-}" || exit 2
            _loom_remote_prepare "${4:-}" ;;
        identity)
            set -o pipefail
            _loom_remote_load "${2:-}" && _loom_remote_identity "${2:-}" "${3:-}" && printf '%s\n' "$_rh_identity" ;;
        *) printf 'helper: use install CONFIG NEW_DIRECTORY or identity DIRECTORY CONTEXT_ID\n' >&2; exit 2 ;;
    esac
fi
