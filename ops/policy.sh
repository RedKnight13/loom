#!/usr/bin/env bash
# Isolated schema-2 policy. Source-safe: no env, cwd, options or trap changes.
# shellcheck disable=SC2015 # Every chained guard intentionally rejects any failed condition.

loom_policy_error() { printf 'loom policy: %s\n' "$*" >&2; return 2; }

loom_policy_root() (
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)

# Reject links in every existing component, not only the final file. Input
# filenames must be canonical absolute paths; IDs never become filenames.
loom_policy_file() {
    local file=${1-} part current='' mode owner
    local -a parts
    [[ $file == /* && $file != */ && $file != *//* && ! $file =~ [[:cntrl:]] ]] || return 2
    IFS=/ read -r -a parts <<< "$file"
    for part in "${parts[@]:1}"; do
        [[ -n $part && $part != . && $part != .. ]] || return 2
        current+="/$part"
        [[ ! -L $current ]] || return 2
        if [[ $current != "$file" ]]; then
            [[ -d $current ]] || return 2
            owner=$(stat -c %u -- "$current") || return 2
            mode=$(stat -c %a -- "$current") || return 2
            [[ $owner == "$EUID" || $owner == 0 ]] || return 2
            if (( (8#$mode & 0022) != 0 )); then
                [[ $owner == 0 ]] && (( (8#$mode & 01000) != 0 )) || return 2
            fi
        fi
    done
    [[ -f $file && -r $file && -O $file ]] || return 2
    mode=$(stat -c %a -- "$file") || return 2
    (( (8#$mode & 0022) == 0 )) || return 2
    [[ $(stat -c %h -- "$file") == 1 ]] || return 2
    [[ $(stat -c %s -- "$file") -le 1048576 ]] || return 2
}

loom_policy_digest() {
    local digest
    digest=$(git hash-object --no-filters -- "$1") || return 2
    printf 'git-blob-sha1-v1:%s\n' "$digest"
}

# Comparing input event streams with the parsed object's stream catches duplicate
# keys, including escaped aliases and repeated objects with disjoint children.
# No schema-2 file accepts fractional/exponent numeric tokens.
loom_policy_json() {
    [[ $# == 1 ]] || return 2
    loom_policy_file "$1" || { loom_policy_error 'unsafe input file'; return 2; }
    LC_ALL=C iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1 || return 2
    LC_ALL=C awk '{s=s $0 "\n"} END {
      gsub(/"([^"\\]|\\.)*"/, "\"\"", s)
      gsub(/true|false|null|[{}\[\]:,[:space:]"0-9]/, "", s)
      if (length(s)) exit 1
    }' "$1" || return 2
    jq -e -s 'length == 1 and (.[0] | type == "object")' "$1" >/dev/null 2>&1 || return 2
    local stream parsed
    stream=$(jq -c --stream -s . "$1") || return 2
    parsed=$(jq -c '[tostream]' "$1") || return 2
    [[ $stream == "$parsed" ]] || { loom_policy_error 'duplicate JSON keys'; return 2; }
    jq -e 'all(.. | strings; contains("\u0000") | not)' "$1" >/dev/null || return 2
}

loom_policy_validate() {
    [[ $# == 2 ]] || return 2
    local root
    root=$(loom_policy_root) || return 2
    loom_policy_json "$2" || return 2
    jq -e --arg kind "$1" -f "$root/schemas/config-v2/validate.jq" "$2" >/dev/null 2>&1 || {
        loom_policy_error "invalid closed v2 $1 schema"; return 2;
    }
}

# Output is a pin, never a launch. Registry paths are supplied by the operator,
# not taken from untrusted config or environment overrides.
loom_policy_resolve() (
    [[ $# == 3 ]] || { loom_policy_error 'resolve needs CONFIG HOSTS PROFILES'; return 2; }
    local config=$1 hosts=$2 profiles=$3 cdigest hdigest pdigest pin profile_digest adapter_digest
    loom_policy_file "$config" && loom_policy_file "$hosts" && loom_policy_file "$profiles" || {
        loom_policy_error 'unsafe input file'; return 2;
    }
    cdigest=$(loom_policy_digest "$config") || return 2
    hdigest=$(loom_policy_digest "$hosts") || return 2
    pdigest=$(loom_policy_digest "$profiles") || return 2
    loom_policy_validate config "$config" && loom_policy_validate hosts "$hosts" &&
        loom_policy_validate profiles "$profiles" || return 2
    pin=$(jq -cn --slurpfile c "$config" --slurpfile h "$hosts" --slurpfile p "$profiles" \
      --arg cd "$cdigest" --arg hd "$hdigest" --arg pd "$pdigest" '
      $c[0] as $c | $c.execution as $e |
      ($h[0].hosts | map(select(.id == $e.placement.selected_host)) | .[0]) as $h |
      ($p[0].agents | map(select(.id == $e.agent_profile)) | .[0]) as $a |
      ($p[0].adapters | map(select(.id == $e.provider)) | .[0]) as $adapter |
      if $h == null or $a == null or $h.transport != $e.transport or
        ($e.transport == "process" and ($e.placement.allow_local | not)) or
        ($e.provider != "native" and $adapter == null) or
        ($e.model != null and ($a.model == null or ($a.model.values | index($e.model)) == null)) or
        ($e.effort != null and ($a.effort == null or ($a.effort.values | index($e.effort)) == null))
      then error("policy_denied") else
        {schema:2, config_digest:$cd, hosts_digest:$hd, profiles_digest:$pd,
         repo:$c.repo, ticket_provider:$c.ticket_provider, provider:$e.provider,
         transport:$e.transport, placement:$e.placement, host:$h, profile:$a,
         adapter:(if $e.provider == "native" then null else $adapter end),
         model:$e.model, effort:$e.effort, limits:$c.limits,
         argv:([$a.executable] + $a.argv +
           (if $e.model == null then [] else $a.model.argv + [$e.model] end) +
           (if $e.effort == null then [] else $a.effort.argv + [$e.effort] end))}
      end | if (.argv | length) > 256 then error("argv too large") else . end') || {
        loom_policy_error 'selection denied; no fallback'; return 2;
    }
    # Detect edits between validation, resolution and the return boundary.
    loom_policy_file "$config" && loom_policy_file "$hosts" && loom_policy_file "$profiles" || return 2
    [[ $(loom_policy_digest "$config") == "$cdigest" &&
       $(loom_policy_digest "$hosts") == "$hdigest" &&
       $(loom_policy_digest "$profiles") == "$pdigest" ]] || {
        loom_policy_error 'configuration changed while resolving'; return 2;
    }
    profile_digest=$(jq .profile <<< "$pin" | loom_policy_scope) || return 2
    adapter_digest=$(jq .adapter <<< "$pin" | loom_policy_scope) || return 2
    jq -c --arg profile_digest "$profile_digest" --arg adapter_digest "$adapter_digest" '
      . + {profile_digest:$profile_digest,
        adapter_digest:(if .adapter == null then null else $adapter_digest end)}' <<< "$pin"
)

# Canonical policy scope, compatible with S1 digest spelling. No file locations
# or timestamps enter this digest; config/registry content revisions do.
loom_policy_scope() (
    set -o pipefail
    local digest
    digest=$(jq -cS . | git hash-object --stdin) || return 2
    printf 'git-blob-sha1-v1:%s\n' "$digest"
)

# Re-resolve and compare the complete pin before intent/retry. Existing attempts
# keep their stored pin; editing config never authorizes retargeting an attempt.
loom_policy_check() {
    [[ $# == 4 ]] || return 2
    local pin=$1 resolved
    loom_policy_json "$pin" || return 2
    resolved=$(loom_policy_resolve "$2" "$3" "$4") || return 2
    [[ $(jq -cS . "$pin") == "$(jq -cS . <<< "$resolved")" ]] || {
        loom_policy_error 'pinned policy changed'; return 2;
    }
}

# Capacity helpers emit canonical S2 requests. The caller MUST retain the exact
# request and pass it to loom_state_transact; request generation reserves nothing.
# One global ledger prevents different runs/hosts from racing separate counters.
loom_policy_capacity_init_request() {
    [[ $# == 2 ]] || return 2
    jq -cenS --arg store "$1" --arg actor "$2" '
      def id: utf8bytelength > 0 and utf8bytelength <= 128 and (contains("\u0000") | not);
      if ($store | id) and ($actor | id) then
      {schema:2,store_id:$store,operation_id:"loom.policy.capacity.init",
       idempotency_key:"loom.policy.capacity.init",op:"policy.capacity.init",
       actor:{id:$actor,run_id:null,epoch:0},target:{id:"loom.policy.capacity"},checks:[],
       changes:[{kind:"config",id:"loom.policy.capacity",expected_revision:null,
         run_id:null,epoch:0,data:{schema:2,slots:[]}}],
       events:[{type:"policy.capacity.initialized",entity_ids:["loom.policy.capacity"],
         payload:{},observed_at:null}],result:{capacity_id:"loom.policy.capacity"}}
      else error("invalid identity") end' || return 2
}

loom_policy_capacity_ledger() (
    declare -F loom_state_get >/dev/null || { loom_policy_error 'source the S2 store API first'; return 2; }
    [[ -n ${LOOM_STATE:-} ]] || { loom_policy_error 'explicit LOOM_STATE required'; return 2; }
    local scratch
    umask 077
    scratch=$(mktemp -d) || return 2
    trap 'rm -rf -- "$scratch"' EXIT
    loom_state_get config loom.policy.capacity > "$scratch/ledger" || return $?
    loom_policy_validate ledger "$scratch/ledger" || return 2
    cat "$scratch/ledger"
)

loom_policy_capacity() {
    [[ $# == 3 ]] || return 2
    local pin ledger
    pin=$(loom_policy_resolve "$1" "$2" "$3") || return 2
    ledger=$(loom_policy_capacity_ledger) || return $?
    jq -cn --argjson p "$pin" --argjson l "$ledger" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      ($l.data.slots | map(select(.state != "settled")) | length) as $used |
      {schema:2,configured:$p.limits.workers,occupied:$used,
       reserved:([$l.data.slots[] | select(.state == "reserved")] | length),
       live:([$l.data.slots[] | select(.state == "running")] | length),
       unknown:([$l.data.slots[] | select(.state == "unknown")] | length),
       available:([$p.limits.workers - $used,0] | max),
       revision:$l.revision,observed_at:$at,observed_constraints:[],
       reason:"Declared concurrency and authoritative reservations; not CPU or model capacity"}'
}

loom_policy_reserve_request() {
    [[ $# == 4 ]] || return 2
    local pin ledger scope
    loom_policy_validate context "$4" || return 2
    pin=$(loom_policy_resolve "$1" "$2" "$3") || return 2
    scope=$(loom_policy_scope <<< "$pin") || return 2
    ledger=$(loom_policy_capacity_ledger) || return $?
    jq -cenS --argjson p "$pin" --argjson l "$ledger" --arg scope "$scope" --slurpfile q "$4" '
      $q[0] as $q |
      if any($l.data.slots[]; .attempt_id == $q.attempt_id) then error("attempt already reserved; replay original transaction")
      elif ([$l.data.slots[] | select(.state != "settled")] | length) >= $p.limits.workers
      then error("capacity_exhausted") else
      {schema:2,store_id:$q.store_id,operation_id:$q.operation_id,idempotency_key:$q.idempotency_key,
       op:"policy.capacity.reserve",actor:{id:$q.actor_id,run_id:null,epoch:0},
       target:{attempt_id:$q.attempt_id,scope_digest:$scope},checks:[],
       changes:[{kind:"config",id:$l.id,expected_revision:$l.revision,run_id:null,epoch:0,
         data:($l.data | .slots += [{attempt_id:$q.attempt_id,run_id:$q.run_id,scope_digest:$scope,state:"reserved"}])}],
       events:[{type:"policy.capacity.reserved",entity_ids:[$q.attempt_id],
         payload:{scope_digest:$scope},observed_at:null}],
       result:{attempt_id:$q.attempt_id,scope_digest:$scope,policy_pin:$p}}
      end' || return 2
}

# A caller-owned normalized observation, never a raw provider response. Core must
# verify stop/start-failure proof before setting confirmed_stopped. Silence,
# abandon, retained workspace and a successful stop command are NOT that proof.
loom_policy_observe_request() {
    [[ $# == 2 ]] || return 2
    local ledger
    loom_policy_validate context "$1" && loom_policy_validate observation "$2" || return 2
    ledger=$(loom_policy_capacity_ledger) || return $?
    jq -cenS --argjson l "$ledger" --slurpfile q "$1" --slurpfile o "$2" '
      $q[0] as $q | $o[0] as $o |
      ([$l.data.slots[] | select(.attempt_id == $q.attempt_id)] | first) as $slot |
      if $slot == null or $slot.run_id != $q.run_id or $slot.scope_digest != $o.scope_digest or $slot.state == "settled"
      then error("identity_mismatch or already settled") else
      {schema:2,store_id:$q.store_id,operation_id:$q.operation_id,idempotency_key:$q.idempotency_key,
       op:"policy.capacity.observe",actor:{id:$q.actor_id,run_id:null,epoch:0},
       target:{attempt_id:$q.attempt_id,scope_digest:$o.scope_digest},checks:[],
       changes:[{kind:"config",id:$l.id,expected_revision:$l.revision,run_id:null,epoch:0,
         data:($l.data | .slots |= map(if .attempt_id == $q.attempt_id then .state=$o.state else . end))}],
       events:[{type:"policy.capacity.observed",entity_ids:[$q.attempt_id],payload:$o,observed_at:null}],
       result:{attempt_id:$q.attempt_id,state:$o.state}}
      end' || return 2
}
