#!/usr/bin/env bash
# Source-safe durable storage API. No global side effects on source.
# shellcheck disable=SC2015 # All A && B || refusal guards intentionally reject either failure.

loom_state_init() { _loom_state_call init "$@"; }
loom_state_transact() { _loom_state_call transact "$@"; }
loom_state_get() { _loom_state_call get "$@"; }
loom_state_list() { _loom_state_call list "$@"; }
loom_state_operation() { _loom_state_call operation "$@"; }
loom_state_replay() { _loom_state_call replay "$@"; }
loom_state_legacy_get() { _loom_state_call legacy-get "$@"; }

_loom_state_call() (
    local ms=${LOOM_STATE_TIMEOUT_MS:-30000} seconds
    [[ $ms =~ ^[0-9]{1,6}$ ]] && (( 10#$ms >= 1 && 10#$ms <= 300000 )) || { printf '%s\n' 'loom-state: invalid timeout' >&2; return 2; }
    seconds=$(awk -v ms="$ms" 'BEGIN {printf "%.3f",ms/1000}')
    command -v timeout >/dev/null || { printf '%s\n' 'loom-state: unsupported_capability: timeout' >&2; return 2; }
    # shellcheck disable=SC2016 # Arguments are positional in the bounded child.
    timeout --kill-after=1 "$seconds" bash -c 'source "$1"; shift; _loom_state_main "$@"' _ "${BASH_SOURCE[0]}" "$@"
)

_loom_state_error() { printf 'loom-state: %s\n' "$*" >&2; return 2; }
_loom_state_digest() {
    local h
    h=$(git hash-object --stdin) || return 1
    [[ $h =~ ^[0-9a-f]{40}$ ]] || return 2
    printf 'git-blob-sha1-v1:%s\n' "$h"
}
_loom_state_kind() {
    case $1 in run|task|assignment|attempt|message|delivery|gate|operation|config|host|profile) return 0 ;; *) return 2 ;; esac
}
_loom_state_id() { jq -en --arg id "$1" '$id|utf8bytelength>0 and utf8bytelength<=128 and (contains("\u0000")|not)' >/dev/null; }

# Ancestors may be shared only when root-owned sticky directories (e.g. /tmp).
_loom_state_ancestors() {
    local path=$1 part current='' mode owner
    [[ $path == /* && $path != / && $path != *//* && $path != */ && $path != *$'\n'* ]] || return 2
    local -a parts
    IFS=/ read -r -a parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [[ $part != . && $part != .. && -n $part ]] || return 2
        current="$current/$part"
        [[ ! -L $current ]] || return 2
        if [[ -e $current ]]; then
            [[ -d $current ]] || return 2
            owner=$(stat -c %u -- "$current") || return 2
            mode=$(stat -c %a -- "$current") || return 2
            [[ $owner == "$EUID" || $owner == 0 ]] || return 2
            if (( (8#$mode & 0022) != 0 )); then
                [[ $owner == 0 ]] && (( (8#$mode & 01000) != 0 )) || return 2
            fi
        fi
    done
}

_loom_state_private() {
    local path=$1 want=$2 mode owner links details
    [[ ! -L $path ]] || return 2
    if [[ $want == dir ]]; then [[ -d $path ]] || return 2
    else [[ -f $path ]] || return 2; fi
    details=$(stat -c '%u %a %h' -- "$path") || return 2
    read -r owner mode links <<< "$details"
    [[ $owner == "$EUID" && $mode =~ ^[0-7]{1,4}$ ]] && (( (8#$mode & 0077) == 0 )) || return 2
    if [[ $want == dir ]]; then (( (8#$mode & 0500) == 0500 )) || return 2
    else [[ $links == 1 ]] && (( (8#$mode & 0400) != 0 )) || return 2; fi
}

_loom_state_validate() {
    local kind=$1 file=$2 max=${3:-1048576} bytes canonical
    [[ -f $file && ! -L $file ]] || return 2
    bytes=$(stat -c %s -- "$file") || return 2
    (( bytes>0 && bytes<=max )) || return 2
    LC_ALL=C iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1 || return 2
    # The storage format is deliberately canonical. Comparison rejects duplicate
    # members, trailing documents, lossy numbers, noncanonical escapes and NULs.
    canonical=$(jq -scSe 'if length==1 and (.[0]|type=="object") then .[0] else error("one object required") end' "$file" 2>/dev/null) || return 2
    cmp -s "$file" <(printf '%s\n' "$canonical") || return 2
    jq -e --arg kind "$kind" -f "$_ls_code/schemas/state-v2/validate.jq" "$file" >/dev/null 2>&1
}

_loom_state_ticks() {
    local pid=$1 raw
    [[ $pid =~ ^[0-9]+$ ]] || return 2
    raw=$(cat "/proc/$pid/stat" 2>/dev/null) || return 2
    raw=${raw##*) }
    local -a fields
    read -r -a fields <<< "$raw"
    [[ ${fields[19]:-} =~ ^[0-9]+$ ]] || return 2
    printf '%s\n' "${fields[19]}"
}

_loom_state_probe() {
    local tool
    [[ $(uname -s) == Linux ]] || return 2
    for tool in jq git sync setsid flock stat mktemp timeout iconv find sort cmp date readlink; do command -v "$tool" >/dev/null || return 2; done
    [[ -r /etc/machine-id && -r /proc/sys/kernel/random/boot_id && -r /proc/sys/kernel/random/uuid ]] || return 2
    _ls_host=$(_loom_state_digest < /etc/machine-id) || return 2
    _ls_boot=$(cat /proc/sys/kernel/random/boot_id) || return 2
    _ls_namespace=$(readlink /proc/self/ns/pid) || return 2
    _ls_pid=$BASHPID
    _ls_ticks=$(_loom_state_ticks "$_ls_pid") || return 2
    setsid --wait true || return 2
    sync -f -- "$_ls_root" || return 2
}

_loom_state_fault() {
    # Explicit test-only injection. Never inferred from agent or provider output.
    if [[ ${LOOM_STATE_TESTING:-} == 1 && ${LOOM_STATE_TEST_CRASH:-} == "$1" ]]; then kill -KILL "$BASHPID"; fi
    if [[ ${LOOM_STATE_TESTING:-} == 1 && ${LOOM_STATE_TEST_FAIL:-} == "$1" ]]; then return 1; fi
}

_loom_state_atomic() {
    local dest=$1 content=$2 label=$3 tmp rc=0
    tmp=$(mktemp "${dest%/*}/.tmp.XXXXXXXXXXXX") || return 1
    # Every ordinary failure removes only the scratch name, never the destination
    # (a rename may already have committed a journal whose reply was lost).
    _loom_state_fault "$label.before_write" &&
        printf '%s\n' "$content" > "$tmp" &&
        _loom_state_fault "$label.after_write" &&
        sync -f -- "$tmp" &&
        _loom_state_fault "$label.after_file_flush" &&
        mv -T -- "$tmp" "$dest" &&
        _loom_state_fault "$label.after_rename" &&
        sync -f -- "${dest%/*}" &&
        _loom_state_fault "$label.after_directory_flush" || rc=1
    rm -f -- "$tmp" || return 1
    return "$rc"
}

_loom_state_unlock() {
    local nonce
    if [[ -n ${_ls_nonce:-} && -f $_ls_v2/lock.json && ! -L $_ls_v2/lock.json ]]; then
        nonce=$(jq -r '.nonce' "$_ls_v2/lock.json" 2>/dev/null) || return
        if [[ $nonce == "$_ls_nonce" ]]; then rm -f -- "$_ls_v2/lock.json"; fi
    fi
    [[ -z ${_ls_work:-} ]] || rm -rf -- "$_ls_work"
    # guard is a permanent inode, never unlinked; closing fd releases flock.
}

_loom_state_lock() {
    local owner current old_nonce lock
    if [[ ! -e $_ls_v2/guard ]]; then
        (set -o noclobber; : > "$_ls_v2/guard") 2>/dev/null || :
    fi
    _loom_state_private "$_ls_v2/guard" file || return 2
    exec 9<>"$_ls_v2/guard" || return 2
    flock -x -w 5 9 || { _loom_state_error resource_busy; return 2; }
    if [[ -e $_ls_v2/lock.json || -L $_ls_v2/lock.json ]]; then
        _loom_state_private "$_ls_v2/lock.json" file && _loom_state_validate lock "$_ls_v2/lock.json" || return 2
        owner=$(cat "$_ls_v2/lock.json")
        jq -e --arg host "$_ls_host" --arg boot "$_ls_boot" --arg ns "$_ls_namespace" '.host_id==$host and .boot_id==$boot and .pid_namespace==$ns' <<< "$owner" >/dev/null || { _loom_state_error 'resource_busy: foreign or ambiguous lock'; return 2; }
        current=$(jq -r .pid <<< "$owner")
        if [[ -e /proc/$current ]]; then
            lock=$(_loom_state_ticks "$current") || { _loom_state_error 'resource_busy: unverifiable owner'; return 2; }
            [[ $lock != "$(jq -r .start_ticks <<< "$owner")" ]] || { _loom_state_error 'resource_busy: exact owner still exists'; return 2; }
        elif kill -0 "$current" 2>/dev/null; then
            _loom_state_error 'resource_busy: unverifiable owner'; return 2
        fi
        old_nonce=$(jq -r .nonce <<< "$owner")
        [[ $(jq -r .nonce "$_ls_v2/lock.json") == "$old_nonce" ]] || return 2
    fi
    _ls_nonce=$(cat /proc/sys/kernel/random/uuid) || return 2
    lock=$(jq -cnS --arg host "$_ls_host" --arg boot "$_ls_boot" --arg ns "$_ls_namespace" --argjson pid "$_ls_pid" --arg ticks "$_ls_ticks" --arg nonce "$_ls_nonce" '{schema:2,host_id:$host,boot_id:$boot,pid_namespace:$ns,pid:$pid,start_ticks:$ticks,nonce:$nonce}') || return 2
    # Install the trap before publication. Unknown/partial lock files fail closed.
    trap _loom_state_unlock EXIT
    _loom_state_atomic "$_ls_v2/lock.json" "$lock" lock || return 1
}

_loom_state_layout() {
    local path
    _ls_root=${LOOM_STATE:-}
    [[ -n $_ls_root ]] && _loom_state_ancestors "$_ls_root" || { _loom_state_error unsafe_path; return 2; }
    if [[ $1 == init ]]; then mkdir -p -- "$_ls_root" || return 1; fi
    _loom_state_private "$_ls_root" dir || { _loom_state_error unsafe_path; return 2; }
    _loom_state_probe || { _loom_state_error unsupported_capability; return 2; }
    [[ $1 != legacy-get ]] || return 0
    _ls_v2=$_ls_root/v2
    if [[ $1 == init ]]; then mkdir -p -- "$_ls_v2" || return 1; fi
    _loom_state_private "$_ls_v2" dir || { _loom_state_error unsafe_path; return 2; }
    _loom_state_lock || return "$?"
    _ls_work=$(mktemp -d "$_ls_v2/.work.XXXXXXXXXXXX") || return 1
    find -P "$_ls_v2" -mindepth 1 -print0 > "$_ls_work/paths" || { _loom_state_error unsafe_path; return 2; }
    # Refuse links (including nested links), special files and hardlinks before
    # reading metadata/projections. The lock paths were checked before opening.
    # Account peers are trusted, not sandboxed.
    while IFS= read -r -d '' path; do
        if [[ -d $path && ! -L $path ]]; then _loom_state_private "$path" dir || return 2
        else _loom_state_private "$path" file || { _loom_state_error unsafe_path; return 2; }; fi
    done < "$_ls_work/paths"
    # The exclusive guard proves no writer still owns these scratch paths.
    # Validate the entire tree first; only exact reserved names are reclaimable.
    while IFS= read -r -d '' path; do
        case $path in
            "$_ls_v2"/.work.*)
                if [[ ${path#"$_ls_v2/"} =~ ^\.work\.[a-zA-Z0-9]{12}$ && $path != "$_ls_work" ]]; then
                    rm -rf -- "$path" || return 1
                fi ;;
            "$_ls_v2"/.tmp.*|"$_ls_v2/journal"/.tmp.*)
                if [[ ${path##*/} =~ ^\.tmp\.[a-zA-Z0-9]{12}$ ]]; then rm -f -- "$path" || return 1; fi ;;
        esac
    done < "$_ls_work/paths"
}

_loom_state_metadata() {
    _loom_state_private "$_ls_v2/store.json" file && _loom_state_validate metadata "$_ls_v2/store.json" || { _loom_state_error corrupt_metadata; return 2; }
    _ls_store=$(jq -r .store_id "$_ls_v2/store.json") || return 2
    _loom_state_private "$_ls_v2/journal" dir || { _loom_state_error unsafe_path; return 2; }
}

_loom_state_prepare() {
    local request=$1 digest=$2
    jq -cS --slurpfile q "$request" --arg digest "$digest" -f "$_ls_code/schemas/state-v2/apply.jq" "$_ls_work/state.json" > "$_ls_work/prepared.json" 2> "$_ls_work/error" || {
        cat "$_ls_work/error" >&2; return 2;
    }
}

_loom_state_build() {
    local request=$1 digest=$2 sequence=$3 txid=$4 at=$5
    jq -cnS --slurpfile q "$request" --slurpfile p "$_ls_work/prepared.json" --arg digest "$digest" --argjson seq "$sequence" --arg txid "$txid" --arg at "$at" '
      $q[0] as $q | $p[0].state as $s |
      {schema:2,store_id:$s.store_id,sequence:$seq,transaction_id:$txid,previous_digest:$s.last_digest,recorded_at:$at,request:$q,request_digest:$digest,
       events:[$q.events|to_entries[] | .key as $i | .value as $e |
         {schema:2,sequence:($s.event_sequence+$i+1),event_id:($txid+":"+($i|tostring)),transaction_id:$txid,actor:$q.actor,
          entity_ids:$e.entity_ids,previous_revisions:($q.checks+[$q.changes[]|{kind,id,revision:.expected_revision}]),type:$e.type,payload:$e.payload,recorded_at:$at,observed_at:$e.observed_at}],
       outcome:{schema:2,store_id:$s.store_id,sequence:$seq,transaction_id:$txid,operation_id:$q.operation_id,durable:true,
         revisions:[$q.changes[] | . as $c | $s.entities[$c.kind][$c.id]|{kind,id,revision}],result:$q.result}}'
}

_loom_state_fold() {
    local tx=$1 digest=$2
    jq -cS --slurpfile t "$tx" --slurpfile p "$_ls_work/prepared.json" --arg digest "$digest" '
      $t[0] as $t | $p[0].state |
      .sequence=$t.sequence | .event_sequence=($t.events[-1].sequence) | .last_digest=$digest |
      .operations += [{actor_id:$t.request.actor.id,op:$t.request.op,key:$t.request.idempotency_key,operation_id:$t.request.operation_id,digest:$t.request_digest,outcome:$t.outcome}] |
      .events += $t.events' "$_ls_work/state.json" > "$_ls_work/next.json" || return 1
    mv -T "$_ls_work/next.json" "$_ls_work/state.json"
}

_loom_state_load() {
    local file name expected=1 total=0 count=0 digest request_digest seq txid at canonical actual
    _loom_state_metadata || return "$?"
    jq -cnS --arg store "$_ls_store" '{schema:2,store_id:$store,sequence:0,event_sequence:0,last_digest:null,entities:{},operations:[],events:[]}' > "$_ls_work/state.json" || return 1
    find "$_ls_v2/journal" -mindepth 1 -maxdepth 1 -print0 > "$_ls_work/journal-list" || { _loom_state_error unsafe_path; return 2; }
    LC_ALL=C sort -z "$_ls_work/journal-list" > "$_ls_work/journal-sorted" || return 1
    while IFS= read -r -d '' file; do
        name=${file##*/}
        if [[ $name =~ ^\.tmp\.[a-zA-Z0-9]{12}$ ]]; then
            _loom_state_private "$file" file || { _loom_state_error unsafe_path; return 2; }
            continue
        fi
        [[ $name =~ ^[0-9]{16}\.json$ ]] || { _loom_state_error corrupt_journal; return 2; }
        printf -v actual '%016d.json' "$expected"
        [[ $name == "$actual" ]] || { _loom_state_error journal_gap; return 2; }
        _loom_state_private "$file" file && _loom_state_validate transaction "$file" 4194304 || { _loom_state_error corrupt_journal; return 2; }
        total=$((total + $(stat -c %s -- "$file"))); count=$((count+1))
        (( total<=67108864 && count<=4096 )) || { _loom_state_error quota_exceeded; return 2; }
        jq -cS .request "$file" > "$_ls_work/request.json" || return 2
        request_digest=$(_loom_state_digest < "$_ls_work/request.json") || return 1
        _loom_state_prepare "$_ls_work/request.json" "$request_digest" || { _loom_state_error corrupt_journal; return 2; }
        jq -e '.replay==null' "$_ls_work/prepared.json" >/dev/null || { _loom_state_error conflicting_transaction; return 2; }
        seq=$(jq -r .sequence "$file"); txid=$(jq -r .transaction_id "$file"); at=$(jq -r .recorded_at "$file")
        [[ $seq == "$expected" ]] || { _loom_state_error journal_gap; return 2; }
        canonical=$(_loom_state_build "$_ls_work/request.json" "$request_digest" "$seq" "$txid" "$at") || return 2
        cmp -s "$file" <(printf '%s\n' "$canonical") || { _loom_state_error conflicting_transaction; return 2; }
        digest=$(_loom_state_digest < "$file") || return 1
        _loom_state_fold "$file" "$digest" || return 1
        expected=$((expected+1))
    done < "$_ls_work/journal-sorted"
    _ls_bytes=$total
    # A recognizable snapshot ahead of the journal is evidence of missing
    # committed history. Never silently acknowledge a truncated journal.
    if [[ -f $_ls_v2/snapshot.json ]] && jq -e --arg store "$_ls_store" --argjson count "$count" '
        type=="object" and .schema==2 and .store_id==$store and
        (.sequence|type=="number" and .==floor and .>=0 and .<=9007199254740991) and
        .sequence>$count' "$_ls_v2/snapshot.json" >/dev/null 2>&1; then
        _loom_state_error journal_gap; return 2
    fi
    # A previous unacknowledged rename becomes durable before any read/retry says
    # durable:true. This also covers recovery after directory flush failure.
    sync -f -- "$_ls_v2/journal" || { _loom_state_error storage_failure; return 1; }
}

_loom_state_snapshot() {
    local content
    content=$(cat "$_ls_work/state.json") || return 1
    _loom_state_atomic "$_ls_v2/snapshot.json" "$content" snapshot
}

_loom_state_transact_internal() {
    local request=$1 digest sequence txid at tx path size outcome
    _loom_state_validate request "$request" || { _loom_state_error invalid_request; return 2; }
    # Copy once before validation/use to bind a stable request, not a mutable path.
    cp -- "$request" "$_ls_work/input.json" || return 1
    request=$_ls_work/input.json
    _loom_state_validate request "$request" || { _loom_state_error invalid_request; return 2; }
    _loom_state_load || return "$?"
    digest=$(_loom_state_digest < "$request") || return 1
    _loom_state_prepare "$request" "$digest" || return "$?"
    if jq -e '.replay!=null' "$_ls_work/prepared.json" >/dev/null; then jq -cS .replay "$_ls_work/prepared.json"; return; fi
    sequence=$(jq '.sequence+1' "$_ls_work/state.json")
    (( sequence<=4096 )) || { _loom_state_error quota_exceeded; return 2; }
    txid=$(cat /proc/sys/kernel/random/uuid); at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    tx=$(_loom_state_build "$request" "$digest" "$sequence" "$txid" "$at") || return 1
    size=$(LC_ALL=C printf '%s\n' "$tx" | wc -c)
    (( size<=4194304 && _ls_bytes+size<=67108864 )) || { _loom_state_error quota_exceeded; return 2; }
    printf -v path '%s/journal/%016d.json' "$_ls_v2" "$sequence"
    [[ ! -e $path && ! -L $path ]] || { _loom_state_error conflicting_transaction; return 2; }
    if ! _loom_state_atomic "$path" "$tx" journal; then _loom_state_error 'outcome_unknown: storage_failure; retry identical operation'; return 1; fi
    digest=$(_loom_state_digest < "$path") || return 1
    _loom_state_fold "$path" "$digest" || return 1
    outcome=$(jq -cS .outcome "$path") || return 1
    # Snapshot failure cannot revoke a durable journal commit; readers replay it.
    _loom_state_snapshot || printf '%s\n' 'loom-state: snapshot lag; journal committed' >&2
    printf '%s\n' "$outcome"
}

_loom_state_main() (
    umask 077
    local cmd=${1:-} _ls_root _ls_v2 _ls_code _ls_store _ls_host _ls_boot _ls_namespace _ls_pid _ls_ticks _ls_nonce='' _ls_work='' _ls_bytes=0
    local id content kind after limit file
    shift || return 2
    _ls_code=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P) || return 1
    case $cmd in
        init|get|operation) [[ $# == 1 && $cmd == init || $# == 2 && $cmd == get || $# == 3 && $cmd == operation ]] || return 2 ;;
        transact|legacy-get) [[ $# == 1 ]] || return 2 ;;
        replay) [[ $# == 0 ]] || return 2 ;;
        list) (( $#>=1 && $#<=3 )) || return 2 ;;
        events) [[ $# == 2 ]] || return 2 ;;
        *) _loom_state_error 'usage: init|transact|get|list|operation|replay|legacy-get|events'; return 2 ;;
    esac
    if [[ $cmd == get || $cmd == list ]]; then _loom_state_kind "$1" || { _loom_state_error invalid_request; return 2; }; fi
    _loom_state_layout "$cmd" || return "$?"
    if [[ $cmd == init ]]; then
        id=$1; _loom_state_id "$id" || return 2
        if [[ -e $_ls_v2/store.json ]]; then
            _loom_state_load || return "$?"
            [[ $_ls_store == "$id" ]] || { _loom_state_error identity_mismatch; return 2; }
        else
            # Never manufacture a new identity for orphaned committed history.
            if [[ -e $_ls_v2/snapshot.json ]] || { [[ -e $_ls_v2/journal ]] && [[ -n $(find "$_ls_v2/journal" -mindepth 1 -print -quit) ]]; }; then _loom_state_error corrupt_metadata; return 2; fi
            mkdir -p -- "$_ls_v2/journal" || return 1
            content=$(jq -cnS --arg id "$id" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{schema:2,store_id:$id,created_at:$at}') || return 1
            _loom_state_atomic "$_ls_v2/store.json" "$content" metadata || return 1
        fi
        cat "$_ls_v2/store.json"; return
    fi
    if [[ $cmd == legacy-get ]]; then
        id=$1
        [[ $id =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && $id != *..* ]] || return 2
        file=$_ls_root/$id.json
        _loom_state_private "$file" file || { _loom_state_error unsafe_path; return 2; }
        (( $(stat -c %s -- "$file") <= 1048576 )) || return 2
        # Reuse the established legacy validator in an isolated subshell only;
        # sourcing lib.sh here cannot change the API caller or migrate its data.
        (
            # shellcheck source=ops/lib.sh
            source "$_ls_code/ops/lib.sh"
            loom_validate "$file"
        ) || return 2
        # shellcheck disable=SC2031 # Legacy source is isolated; retain parent id/file.
        jq -ceS --arg id "$id" 'select(type=="object" and (.schema==null or .schema==1) and (.ticket|type=="number") and (.reports|type=="array")) |
          {schema:1,read_only:true,id:$id,origin_provider:(.executor.kind//"local"),identity:"unknown",record:.}' "$file" || return 2
        return
    fi
    if [[ $cmd == transact ]]; then _loom_state_transact_internal "$1"; return "$?"; fi
    _loom_state_load || return "$?"
    case $cmd in
        replay) _loom_state_snapshot || return 1; jq -cS '{schema,store_id,sequence,event_sequence,last_digest}' "$_ls_work/state.json" ;;
        get) kind=$1; id=$2; jq -ceS --arg kind "$kind" --arg id "$id" '.entities[$kind][$id] // empty' "$_ls_work/state.json" || { _loom_state_error not_found; return 2; } ;;
        list)
            kind=$1; after=${2:-}; limit=${3:-100}
            [[ $limit =~ ^[0-9]{1,3}$ ]] && (( 10#$limit>=1 && 10#$limit<=100 )) || return 2
            jq -cS --arg kind "$kind" --arg after "$after" --argjson limit "$((10#$limit))" '
              [(.entities[$kind]//{})[] | select(.id>$after)] | sort_by(.id) | .[:$limit] |
              {items:.,next_cursor:(if length==$limit then .[-1].id else null end)}' "$_ls_work/state.json" ;;
        operation) jq -ceS --arg actor "$1" --arg op "$2" --arg key "$3" '[.operations[]|select(.actor_id==$actor and .op==$op and .key==$key)]|first//empty' "$_ls_work/state.json" || { _loom_state_error not_found; return 2; } ;;
        events)
            after=$1; limit=$2
            [[ $after =~ ^[0-9]{1,15}$ && $limit =~ ^[0-9]{1,3}$ ]] && (( 10#$limit>=1 && 10#$limit<=100 )) || return 2
            jq -ceS --argjson after "$((10#$after))" --argjson limit "$((10#$limit))" '
              if $after>.event_sequence then error("cursor_expired") else
              [.events[]|select(.sequence>$after)]|.[:$limit]|{events:.,next_sequence:(.[-1].sequence//$after)} end' "$_ls_work/state.json" || return 2 ;;
    esac
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    _loom_state_call "$@"
fi
