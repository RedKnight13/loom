#!/usr/bin/env bash
# Protocol 1.0 validation and bounded command boundary. Safe to source.
# No core state, runtime routing, agent launch, environment or trap mutation on source.

loom_protocol_root() (
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P
)

loom_protocol_digest() {
    printf 'git-blob-sha1-v1:%s\n' "$(git hash-object --no-filters -- "$1")"
}

# Parse lexical structure before jq: duplicate names compare decoded Unicode,
# including escape aliases/surrogate pairs. Input was byte-bounded by the caller.
loom_protocol_lex() {
    LC_ALL=C iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1 || return 2
    LC_ALL=C awk '
    function bad() { failed=1; exit 2 }
    function ws() { while (substr(s,p,1) ~ /^[ \t\r\n]$/) p++ }
    function hex4(  i,c,n) {
      n=0
      for(i=0;i<4;i++) {
        c=index("0123456789abcdef",tolower(substr(s,p++,1)))-1
        if(c<0) bad()
        n=n*16+c
      }
      return n
    }
    function utf(n) {
      if(n==0) bad()
      if(n<128) return sprintf("%c",n)
      if(n<2048) return sprintf("%c%c",192+int(n/64),128+n%64)
      if(n<65536) return sprintf("%c%c%c",224+int(n/4096),128+int(n/64)%64,128+n%64)
      return sprintf("%c%c%c%c",240+int(n/262144),128+int(n/4096)%64,128+int(n/64)%64,128+n%64)
    }
    function str(  out,c,n,lo) {
      if(substr(s,p++,1)!="\"") bad()
      out=""
      while(p<=length(s)) {
        c=substr(s,p++,1)
        if(c=="\"") return out
        if(c ~ /^[[:cntrl:]]$/ && c!=sprintf("%c",127)) bad()
        if(c=="\\") {
          c=substr(s,p++,1)
          if(c=="u") {
            n=hex4()
            if(n>=55296 && n<=56319) {
              if(substr(s,p,2)!="\\u") bad()
              p+=2; lo=hex4()
              if(lo<56320 || lo>57343) bad()
              n=65536+(n-55296)*1024+lo-56320
            } else if(n>=56320 && n<=57343) bad()
            c=utf(n)
          } else if(c=="b") c=sprintf("%c",8)
          else if(c=="f") c=sprintf("%c",12)
          else if(c=="n") c="\n"
          else if(c=="r") c="\r"
          else if(c=="t") c="\t"
          else if(c!="\"" && c!="\\" && c!="/") bad()
        }
        out=out c
      }
      bad()
    }
    # jq can round a large fractional JSON number to an integer. Reject that
    # loss before a schema integer test can accidentally accept it.
    function precise(t,  mant,exponent,pos,digits,frac,a) {
      mant=t; sub(/^-/,"",mant); exponent=0
      if(mant ~ /[eE]/) {
        split(mant,a,/[eE]/); mant=a[1]; exponent=a[2]+0
        if(exponent>308 || exponent< -308) bad()
      }
      pos=index(mant,".")
      if(pos) pos--; else pos=length(mant)
      digits=mant; gsub(/\./,"",digits); pos+=exponent
      frac=(pos<0 ? digits : substr(digits,pos+1))
      if(frac ~ /[1-9]/ && (t+0)==(sprintf("%.0f",t+0)+0)) bad()
    }
    function value(depth,  c,id,k,t,start) {
      if(depth>64 || ++nodes>50000) bad()
      ws(); c=substr(s,p,1)
      if(c=="{") {
        id=++serial; p++; ws()
        if(substr(s,p,1)=="}") { p++; return }
        while(1) {
          ws(); k=str()
          # Length prefix avoids ambiguity even when keys contain SUBSEP.
          t=id ":" length(k) ":" k
          if(t in seen) bad()
          seen[t]=1; ws()
          if(substr(s,p++,1)!=":") bad()
          value(depth+1); ws(); c=substr(s,p++,1)
          if(c=="}") return
          if(c!=",") bad()
        }
      } else if(c=="[") {
        p++; ws()
        if(substr(s,p,1)=="]") { p++; return }
        while(1) {
          value(depth+1); ws(); c=substr(s,p++,1)
          if(c=="]") return
          if(c!=",") bad()
        }
      } else if(c=="\"") k=str()
      else {
        start=p
        while(p<=length(s) && substr(s,p,1)!~/^[ \t\r\n,}\]]$/) p++
        t=substr(s,start,p-start)
        if(t!="null" && t!="true" && t!="false") {
          if(t!~/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) bad()
          precise(t)
        }
      }
    }
    { s=s $0 "\n" }
    END {
      if(failed) exit 2
      p=1; ws(); if(substr(s,p,1)!="{") bad()
      value(0); ws(); if(p<=length(s)) bad()
    }' "$1"
}

# Validate a bounded file. Optional request file adds exact response correlation.
# Return 0/2; silent stdout. Byte limits and lexical rules are wire assertions.
loom_protocol_validate() (
    local kind=${1-} file=${2-} request=${3-} root protocol schema bytes
    [[ $kind == request || $kind == response || $kind == adapter_config ]] || return 2
    [[ -f $file ]] || return 2
    bytes=$(wc -c < "$file")
    (( bytes > 0 && bytes <= 1048576 )) || return 2
    [[ $(tail -c 1 -- "$file" | od -An -tu1) =~ 10[[:space:]]*$ ]] || return 2
    loom_protocol_lex "$file" || return 2
    root=$(loom_protocol_root) || return 2
    if [[ $kind == adapter_config ]]; then protocol=execution
    else protocol=$(jq -er '.protocol | select(.=="loom.execution" or .=="loom.coordination") | split(".")[1]' "$file" 2>/dev/null) || return 2
    fi
    schema="$root/schemas/$protocol-v1/contract.json"
    jq -e --slurpfile schema "$schema" --arg kind "$kind" -f "$root/schemas/execution-v1/validate.jq" "$file" >/dev/null 2>&1 || return 2
    if jq -e '.op=="hello"' "$file" >/dev/null; then (( bytes <= 65536 )) || return 2; fi
    if [[ $kind == response && -n $request ]]; then
        loom_protocol_validate request "$request" || return 2
        jq -e --slurpfile req "$request" '
          . as $r | $req[0] as $q |
          all(["protocol","version","request_id","operation_id","op","target"][]; . as $k | $r[$k]==$q[$k]) and
          (if $r.ok then
             all(["workspace_id","base_sha","manifest_digest","profile_id","operation_id","run_id","task_id","parent_attempt_id","message_id","delivery_id","gate_id","owner_id","sha","message_digest"][];
               . as $k | if ($q.args|has($k)) and ($r.result|has($k)) then $r.result[$k]==$q.args[$k] else true end)
           else true end) and
          (if $r.ok and $q.op=="workspace.prepare" then $r.result.host_id==$q.target.host_id else true end) and
          (if $r.ok and $q.op=="workspace.export" then $r.result.bytes<=$q.args.limit_bytes else true end) and
          (if $r.ok and $q.op=="execution.stop" then $q.args.allow_kill or ($r.result.requested_signals|index("KILL")==null) else true end) and
          (if $r.ok and ($q.op=="mail.read" or $q.op=="mail.claim") then $r.result.delivery.delivery_id==$q.args.delivery_id else true end) and
          (if $r.ok and $q.op=="mail.claim" then
             $r.result.delivery.recipient==$q.args.mailbox or $q.args.mailbox==("attempt:"+($r.result.delivery.attempt_id//"")) else true end) and
          (if $r.ok and $q.op=="mail.send" then all($r.result.deliveries[];.recipient as $recipient|$q.args.to|index($recipient)!=null) else true end) and
          (if $r.ok and $q.op=="gate.resolve" then $r.result.gate.gate_id==$q.args.gate_id and $r.result.gate.decision==$q.args.decision else true end) and
          (if $r.ok and $q.op=="execution.reconcile" then $r.result.operation_id==$q.args.operation_id else true end) and
          (if $r.ok and $q.op=="execution.prompt" then $r.result.message_id==$q.args.message_id and $r.result.delivery_id==$q.args.delivery_id else true end) and
          (if $r.ok and $q.op=="agents.discover" then all($r.result.profiles[]; .host_id==$q.args.host_id and (.profile_id as $id | $q.args.profile_ids|index($id)!=null)) else true end) and
          (if $r.ok and $q.op=="hello" then
             ($r.result.capabilities|map(select(.state=="supported")|.name)) as $supported |
             (($q.args.versions|index($r.result.selected_version))!=null and (($q.args.required_capabilities-$supported)|length)==0) else true end) and
          (if $r.ok and ($q.op=="execution.read" or $q.op=="workspace.read") then ($r.result.data|utf8bytelength)<=$q.args.limit_bytes else true end) and
          (if $r.ok and ($q.args|has("limit")) then (($r.result.items//$r.result.events//$r.result.profiles//[])|length)<=$q.args.limit else true end)
        ' "$file" >/dev/null 2>&1 || return 2
    fi
)

# Always produce a schema-valid receipt, even for an unparseable request.
# Only lexically valid bounded envelopes supply correlation fields.
loom_protocol_receipt() {
    local file=$1 status=$2 code=$3 message=$4 missing=${5-} safe=/dev/null
    if [[ -f $file ]] && loom_protocol_lex "$file" 2>/dev/null; then safe=$file; fi
    jq -cn --slurpfile input "$safe" --arg status "$status" --arg code "$code" --arg message "$message" --arg missing "$missing" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      def id: if type=="string" and length>0 and utf8bytelength<=128 and (contains("\u0000")|not) then . else null end;
      ($input[0]//{}) as $q | ($q.target|if type=="object" then . else {} end) as $t |
      {protocol:(if $q.protocol=="loom.coordination" then $q.protocol else "loom.execution" end),version:{major:1,minor:0},
       request_id:(($q.request_id|id)//"invalid-request"),operation_id:($q.operation_id|id),op:(($q.op|id)//"invalid"),
       target:{assignment_id:($t.assignment_id|id),attempt_id:($t.attempt_id|id),host_id:($t.host_id|id)},
       ok:false,status:$status,revision:null,durable:false,result:(if $missing!="" then {missing_capability:$missing} else null end),
       error:{code:$code,message:$message,retry:(if $status=="unknown" then "after_reconcile" else "never" end)},effects:[],evidence:[],observed_at:$now,extensions:{}}'

}

loom_protocol_exit() {
    jq -er 'if .ok then 0 elif .status=="refused" then 2 else 1 end' "$1"
}

# Validate input before classification; unsupported versions/operations are refusals.
loom_protocol_check_request() {
    local file=$1 root protocol op
    if loom_protocol_validate request "$file"; then return 0; fi
    if ! loom_protocol_lex "$file" 2>/dev/null; then
        loom_protocol_receipt /dev/null refused invalid_request 'Invalid JSON framing or duplicate keys'
    elif ! jq -e '.version=={major:1,minor:0}' "$file" >/dev/null 2>&1; then
        loom_protocol_receipt "$file" refused protocol_mismatch 'Only protocol 1.0 is supported'
    else
        root=$(loom_protocol_root)
        protocol=$(jq -r '.protocol|select(type=="string" and length<128)' "$file")
        op=$(jq -r '.op|select(type=="string" and length<128)' "$file")
        if [[ $protocol == loom.execution || $protocol == loom.coordination ]] &&
           ! jq -e --arg op "$op" '.["x-loom-operations"]|has($op)' "$root/schemas/${protocol#loom.}-v1/contract.json" >/dev/null; then
            loom_protocol_receipt "$file" refused unsupported_operation 'Operation is not registered'
        else
            loom_protocol_receipt "$file" refused invalid_request 'Request violates protocol schema or bounds'
        fi
    fi
    return 2
}

# Bounded read: the extra byte detects overflow. Never parse truncated JSON.
loom_protocol_input() {
    head -c 1048577 > "$1"
    [[ $(wc -c < "$1") -le 1048576 ]]
}

loom_protocol_hello() {
    local file=$1 root protocol digest missing
    root=$(loom_protocol_root)
    protocol=$(jq -r '.protocol|select(type=="string" and length<128)' "$file")
    digest=$(loom_protocol_digest "$root/schemas/${protocol#loom.}-v1/contract.json")
    if ! jq -e '.args.versions|index({major:1,minor:0})!=null' "$file" >/dev/null; then
        loom_protocol_receipt "$file" refused protocol_mismatch 'No common exact protocol version'; return 2
    fi
    missing=$(jq -r '.args.required_capabilities[0]//empty' "$file")
    if [[ -n $missing ]]; then
        loom_protocol_receipt "$file" refused unsupported_capability 'The standalone validator provides no runtime capabilities' "$missing"; return 2
    fi
    jq -c --arg digest "$digest" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      {protocol,version,request_id,operation_id,op,target,ok:true,status:"completed",revision:null,durable:false,
       result:{selected_version:{major:1,minor:0},provider:{id:"loom-contract",version:"1.0"},capabilities:[],
       limits:{request_bytes:1048576,response_bytes:1048576,metadata_bytes:65536,message_bytes:65536,read_bytes:65536,list_rows:100,diagnostic_bytes:1048576},schema_digest:$digest},
       error:null,effects:[],evidence:[],observed_at:$now,extensions:{}}' "$file"
}

_loom_protocol_serve() (
    local temp rc=0
    umask 077
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    if ! loom_protocol_input "$temp/request"; then
        loom_protocol_receipt /dev/null refused invalid_request 'Request exceeds 1 MiB'; return 2
    fi
    loom_protocol_check_request "$temp/request" || return 2
    if [[ $(jq -r .op "$temp/request") == hello ]]; then
        loom_protocol_hello "$temp/request" || rc=$?
    else
        loom_protocol_receipt "$temp/request" refused unsupported_operation 'Runtime routing is not implemented by this contract module'
        rc=2
    fi
    return "$rc"
)

# A bounded draining writer stores at most limit+1 bytes. The sentinel byte is
# never parsed; descendants cannot block by keeping a full pipe open.
loom_protocol_capture() {
    local limit=$1 output=$2
    head -c "$((limit + 1))" > "$output"
    cat >/dev/null
}

# Internal helper, run ONLY below GNU timeout (its process-group identity anchor).
# Keep the helper alive until both pipes close, even if the adapter leader exits.
loom_protocol_call_child() {
    local dir=$1 out_limit=$2 err_limit=$3 pgid sid ticks pid=$BASHPID rc=0
    local out_pid err_pid adapter_pid
    shift 3
    # Remain timeout's direct child after TERM. Otherwise timeout may reap a
    # dead wrapper and cancel KILL while an adapter descendant ignores TERM.
    # The anchor itself issues KILL to its still-owned group after 100 ms.
    trap 'while :; do sleep 1; done' TERM
    pgid=$(ps -o pgid= -p "$pid" | tr -d ' ')
    sid=$(ps -o sid= -p "$pid" | tr -d ' ')
    # timeout creates its own group and signals from inside that group. Refuse
    # an unanchored helper; never issue external kill(-PGID) based on a stale PID.
    [[ $pgid == "$PPID" && $pgid -gt 1 && -r /proc/$pgid/stat ]] || return 125
    ticks=$(sed 's/.*) //' "/proc/$pgid/stat" | awk '{print $20}')
    jq -cn --argjson pid "$pgid" --argjson pgid "$pgid" --argjson sid "$sid" --arg ticks "$ticks" \
        --arg boot "$(cat /proc/sys/kernel/random/boot_id)" \
        '{pid:$pid,pgid:$pgid,sid:$sid,start_ticks:$ticks,boot_id:$boot}' > "$dir/adapter-group.json"
    mkfifo "$dir/stdout.pipe" "$dir/stderr.pipe" || return 125
    loom_protocol_capture "$out_limit" "$dir/stdout" < "$dir/stdout.pipe" & out_pid=$!
    loom_protocol_capture "$err_limit" "$dir/stderr" < "$dir/stderr.pipe" & err_pid=$!
    # argv is passed as individual parameters, including empty/newline arguments.
    "$@" < "$dir/request" > "$dir/stdout.pipe" 2> "$dir/stderr.pipe" & adapter_pid=$!
    wait "$adapter_pid" || rc=$?
    printf '%s\n' "$rc" > "$dir/adapter-exit"
    wait "$out_pid" || return 125
    wait "$err_pid" || return 125
    return "$rc"
}

# Return a normalized response in dir/response; raw bounded diagnostics stay
# private in dir/stderr. All status codes here are captured transport outcomes.
loom_protocol_millis() {
    awk '{printf "%.0f\n", $1 * 1000}' /proc/uptime
}

loom_protocol_exchange() (
    local config=$1 request=$2 dir=$3 config_digest=$4 capability_digest=${5-null} deadline_end=${6-}
    local root executable digest duration deadline out_limit err_limit transport_exit=0 adapter_exit=null
    local expected_exit response_exit=0 reason=ok mutation=false out_truncated=false err_truncated=false
    local -a argv=()
    root=$(loom_protocol_root)
    mkdir -m 700 -- "$dir" || return 1
    cp -- "$request" "$dir/request" || return 1
    if ! loom_protocol_request_limits "$request" "$config"; then
        loom_protocol_receipt "$request" refused quota_exceeded 'Request exceeds adapter call limits' > "$dir/response"; return 2
    fi
    executable=$(jq -r .executable "$config")
    digest=$(jq -r .executable_digest "$config")
    mapfile -d '' -t argv < <(jq -j '.argv[] | ., "\u0000"' "$config")
    deadline=$(jq -r .timeout_ms "$request")
    if [[ -n $deadline_end ]]; then deadline=$((deadline_end - $(loom_protocol_millis))); fi
    if (( deadline <= 0 )); then
        loom_protocol_receipt "$request" refused deadline_exceeded 'Call deadline expired before invocation' > "$dir/response"
        return 2
    fi
    printf -v duration '%d.%03d' "$((deadline / 1000))" "$((deadline % 1000))"
    out_limit=$(jq -r .limits.response_bytes "$config")
    if [[ $(jq -r .op "$request") == hello ]]; then
        out_limit=$(jq -r '[.limits.response_bytes,.limits.metadata_bytes,65536]|min' "$config")
    fi
    err_limit=$(jq -r .limits.diagnostic_bytes "$config")
    if [[ $(loom_protocol_digest "$executable") != "$digest" ]]; then
        loom_protocol_receipt "$request" refused identity_mismatch 'Configured executable digest changed' > "$dir/response"
        return 2
    fi
    # Fixed allowlist only. HOME/TMPDIR are an empty private operation directory;
    # no ambient token, SSH agent, model selector, shell hook or credentials pass.
    { env -i PATH=/usr/bin:/bin LC_ALL=C.UTF-8 LANG=C.UTF-8 HOME="$dir" TMPDIR="$dir" \
        /usr/bin/timeout --signal=TERM --kill-after=0.1s "${duration}s" \
        /bin/bash "$root/ops/protocol.sh" _call "$dir" "$out_limit" "$err_limit" \
        "$executable" "${argv[@]}" > "$dir/helper-stdout" 2> "$dir/helper-stderr"; } 2> "$dir/launcher-stderr" || transport_exit=$?
    if [[ -f $dir/adapter-exit ]]; then adapter_exit=$(cat "$dir/adapter-exit"); fi
    [[ -f $dir/stdout ]] || : > "$dir/stdout"
    [[ -f $dir/stderr ]] || : > "$dir/stderr"
    if (( $(wc -c < "$dir/stdout") > out_limit )); then out_truncated=true; reason=stdout_overflow; fi
    if (( $(wc -c < "$dir/stderr") > err_limit )); then err_truncated=true; reason=stderr_overflow; fi
    if (( transport_exit == 124 || transport_exit == 137 )); then reason=timeout; fi
    if [[ $reason == ok ]]; then
        if ! loom_protocol_validate response "$dir/stdout" "$request"; then reason=invalid_receipt
        else
            expected_exit=$(loom_protocol_exit "$dir/stdout")
            if (( transport_exit != expected_exit )); then reason=exit_mismatch; fi
        fi
    fi
    if [[ $(loom_protocol_digest "$executable") != "$digest" ]]; then reason=executable_changed; fi
    if [[ $reason == ok ]]; then cp -- "$dir/stdout" "$dir/response"
    else
        if jq -e '.operation_id!=null' "$request" >/dev/null; then mutation=true; fi
        # A mutation may already have crossed its effect boundary. Neither a
        # timeout, missing response nor invalid receipt establishes safe retry.
        if [[ $mutation == true ]]; then
            loom_protocol_receipt "$request" unknown outcome_unknown 'Adapter outcome requires reconciliation' > "$dir/response"
            jq '.effects=[{kind:"adapter_invocation",resource:.operation_id,disposition:"unknown"}]' "$dir/response" > "$dir/patched"
            mv -- "$dir/patched" "$dir/response"
        else
            loom_protocol_receipt "$request" failed invalid_receipt 'Adapter response or transport failed validation' > "$dir/response"
        fi
    fi
    if [[ $reason != ok ]] && loom_protocol_lex "$dir/stdout" 2>/dev/null; then
        jq -c --slurpfile raw "$dir/stdout" '
          [$raw[0].effects[]? | select(type=="object") |
            select((.kind|type)=="string" and (.resource|type)=="string") |
            select((.kind|utf8bytelength)<=128 and (.resource|utf8bytelength)<=128) |
            {kind,resource,disposition:"unknown"}][:100] as $reported |
          if ($reported|length)>0 then .extensions["loom.invalid_receipt"]={reported_effects:$reported} else . end
        ' "$dir/response" > "$dir/patched" && mv -- "$dir/patched" "$dir/response"
    fi
    local identity=null invocation_digest request_digest
    [[ ! -f $dir/adapter-group.json ]] || identity=$(cat "$dir/adapter-group.json")
    request_digest=$(loom_protocol_digest "$request")
    jq -c '{executable,executable_digest,argv}' "$config" > "$dir/invocation"
    invocation_digest=$(loom_protocol_digest "$dir/invocation")
    jq -c --argjson exit_code "$transport_exit" --argjson adapter_exit "$adapter_exit" \
        --arg config_digest "$config_digest" --arg executable_digest "$digest" --arg request_digest "$request_digest" \
        --arg capability_digest "$capability_digest" --arg invocation_digest "$invocation_digest" \
        --argjson stdout_truncated "$out_truncated" --argjson stderr_truncated "$err_truncated" \
        --arg reason "$reason" --argjson identity "$identity" '
        .extensions["loom.transport"]={exit_code:$exit_code,adapter_exit:$adapter_exit,
          config_digest:$config_digest,executable_digest:$executable_digest,request_digest:$request_digest,
          capability_digest:(if $capability_digest=="null" then null else $capability_digest end),invocation_digest:$invocation_digest,
          stdout_truncated:$stdout_truncated,stderr_truncated:$stderr_truncated,reason:$reason,adapter_group:$identity}
        ' "$dir/response" > "$dir/patched" && mv -- "$dir/patched" "$dir/response"
    local response_bound=1048576
    [[ $(jq -r .op "$request") != hello ]] || response_bound=65536
    if (( $(wc -c < "$dir/response") > response_bound )); then
        cp -- "$dir/response" "$dir/oversize-response"
        if jq -e '.operation_id!=null' "$request" >/dev/null; then
            loom_protocol_receipt "$request" unknown outcome_unknown 'Normalized adapter response exceeds envelope limit' > "$dir/response"
        else
            loom_protocol_receipt "$request" failed invalid_receipt 'Normalized adapter response exceeds envelope limit' > "$dir/response"
        fi
        jq -c --slurpfile old "$dir/oversize-response" '
          .extensions["loom.transport"]=$old[0].extensions["loom.transport"] |
          .extensions["loom.transport"].reason="normalized_overflow" |
          .extensions["loom.transport"].stdout_truncated=true |
          if .status=="unknown" then .effects=[{kind:"adapter_invocation",resource:.operation_id,disposition:"unknown"}] else . end
        ' "$dir/response" > "$dir/patched" && mv -- "$dir/patched" "$dir/response"
    fi
    response_exit=$(loom_protocol_exit "$dir/response")
    return "$response_exit"
)

loom_protocol_cap_limits() {
    local config=$1 caps=$2 hello=${3-/dev/null}
    jq --argjson caps "$caps" --slurpfile hello "$hello" '
      [.capabilities[], $hello[0].result.capabilities[]? | select(.name as $name | $caps|index($name)!=null)] as $selected |
      .limits.request_bytes=([.limits.request_bytes,($selected[].limits.max_bytes//empty)]|min) |
      .limits.response_bytes=([.limits.response_bytes,($selected[].limits.max_bytes//empty)]|min) |
      .limits.list_rows=([.limits.list_rows,($selected[].limits.max_items//empty)]|min)
    ' "$config"
}

loom_protocol_request_limits() {
    local request=$1 config=$2
    jq -e --slurpfile c "$config" --argjson bytes "$(wc -c < "$request")" '
      $c[0].limits as $limits |
      $bytes<=$limits.request_bytes and
      (if .op=="hello" then $bytes<=$limits.metadata_bytes else true end) and
      (if .args|has("limit") then .args.limit<=$limits.list_rows else true end) and
      (if .op=="agents.discover" then (.args.profile_ids|length)<=$limits.list_rows else true end) and
      (if .op=="execution.read" or .op=="workspace.read" then .args.limit_bytes<=$limits.read_bytes else true end)
    ' "$request" >/dev/null
}

_loom_protocol_invoke() (
    local config=${1-} expected_digest=${2-} temp root op cap missing executable actual_digest rc=0
    local caps digest protocol negotiated_request_limit started_ms deadline_end
    started_ms=$(loom_protocol_millis)
    umask 077
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    root=$(loom_protocol_root)
    if ! loom_protocol_input "$temp/request"; then
        loom_protocol_receipt /dev/null refused invalid_request 'Request exceeds 1 MiB'; return 2
    fi
    loom_protocol_check_request "$temp/request" || return 2
    deadline_end=$((started_ms + $(jq -r .timeout_ms "$temp/request")))
    protocol=$(jq -r .protocol "$temp/request")
    if [[ $protocol != loom.execution ]]; then
        loom_protocol_receipt "$temp/request" refused unsupported_operation 'Coordination operations are never delegated to executors'; return 2
    fi
    if [[ ! $expected_digest =~ ^git-blob-sha1-v1:[0-9a-f]{40}$ || ! -f $config || -L $config ]] ||
       ! loom_protocol_validate adapter_config "$config"; then
        loom_protocol_receipt "$temp/request" refused invalid_config 'Invalid adapter config or digest'; return 2
    fi
    # Snapshot once, verify the snapshot against the caller-pinned exact bytes.
    cp -- "$config" "$temp/config" || return 1
    actual_digest=$(loom_protocol_digest "$temp/config")
    if [[ $actual_digest != "$expected_digest" ]]; then
        loom_protocol_receipt "$temp/request" refused identity_mismatch 'Adapter config digest changed'; return 2
    fi
    config="$temp/config"
    if ! loom_protocol_validate adapter_config "$config"; then
        loom_protocol_receipt "$temp/request" refused invalid_config 'Pinned config snapshot is invalid'; return 2
    fi
    executable=$(jq -r .executable "$config")
    if [[ ! -f $executable || ! -x $executable || -L $executable || $(realpath -e -- "$executable" 2>/dev/null) != "$executable" ]]; then
        loom_protocol_receipt "$temp/request" refused invalid_config 'Executable must be a canonical absolute regular executable'; return 2
    fi
    if [[ $(loom_protocol_digest "$executable") != "$(jq -r .executable_digest "$config")" ]]; then
        loom_protocol_receipt "$temp/request" refused identity_mismatch 'Executable digest mismatch'; return 2
    fi
    if (( $(wc -c < "$temp/request") > $(jq -r .limits.request_bytes "$config") )); then
        loom_protocol_receipt "$temp/request" refused quota_exceeded 'Request exceeds pinned adapter limit'; return 2
    fi
    if ! loom_protocol_request_limits "$temp/request" "$config"; then
        loom_protocol_receipt "$temp/request" refused quota_exceeded 'Request exceeds pinned field limits'; return 2
    fi
    op=$(jq -r .op "$temp/request")
    cap=$(jq -r --arg op "$op" '.["x-loom-operations"][$op].capability//empty' "$root/schemas/execution-v1/contract.json")
    if [[ $op == execution.prompt ]]; then cap="prompt.$(jq -r .args.mode "$temp/request").v1"; fi
    caps=$(jq -cn --arg cap "$cap" --slurpfile req "$temp/request" '
      (if $cap=="" then $req[0].args.required_capabilities else [$cap] end) +
      (if $req[0].op=="execution.start" and $req[0].args.model!=null then ["model.select.v1"] else [] end) +
      (if $req[0].op=="execution.start" and $req[0].args.effort!=null then ["effort.select.v1"] else [] end) | unique')
    missing=$(jq -r --argjson caps "$caps" '.capabilities|map(select(.state=="supported")|.name) as $supported | ($caps-$supported)[0]//empty' "$config")
    if [[ -n $missing ]]; then
        loom_protocol_receipt "$temp/request" refused unsupported_capability 'Required capability is not pinned as supported' "$missing"; return 2
    fi
    if [[ $op != hello ]]; then
        loom_protocol_cap_limits "$config" "$caps" > "$temp/cap-config"
        if ! loom_protocol_request_limits "$temp/request" "$temp/cap-config"; then
            loom_protocol_receipt "$temp/request" refused quota_exceeded 'Request exceeds pinned capability limits'; return 2
        fi
        jq -c --argjson caps "$caps" '.op="hello" | .operation_id=null | .idempotency_key=null | .expected_revision=null |
          .target={assignment_id:null,attempt_id:null,host_id:null} | .args={versions:[{major:1,minor:0}],required_capabilities:$caps}' "$temp/request" > "$temp/hello-request"
        loom_protocol_exchange "$config" "$temp/hello-request" "$temp/hello" "$actual_digest" null "$deadline_end" || rc=$?
        if (( rc != 0 )); then
            loom_protocol_receipt "$temp/request" refused negotiation_failed 'Adapter negotiation failed before the requested operation' > "$temp/response"
            jq -c --slurpfile hello "$temp/hello/response" '.extensions["loom.negotiation"]={status:$hello[0].status,error:$hello[0].error,transport:$hello[0].extensions["loom.transport"],reported_effects:($hello[0].extensions["loom.invalid_receipt"].reported_effects//[])}' "$temp/response"
            return 2
        fi
        # Exact-version intersection; absent/unknown capabilities never support.
        if ! jq -e '.result.selected_version=={major:1,minor:0}' "$temp/hello/response" >/dev/null; then
            loom_protocol_receipt "$temp/request" refused protocol_mismatch 'Adapter selected an unoffered version'; return 2
        fi
        missing=$(jq -r --argjson caps "$caps" '.result.capabilities|map(select(.state=="supported")|.name) as $supported | ($caps-$supported)[0]//empty' "$temp/hello/response")
        if [[ -n $missing ]]; then
            loom_protocol_receipt "$temp/request" refused unsupported_capability 'Negotiated capability is absent or not supported' "$missing"; return 2
        fi
        jq -cS .result.capabilities "$temp/hello/response" > "$temp/capabilities"
        digest=$(loom_protocol_digest "$temp/capabilities")
        # Pin the most restrictive advertised/configured limits for this call.
        jq --slurpfile hello "$temp/hello/response" '.limits |= with_entries(.key as $k | .value=([.value,$hello[0].result.limits[$k]]|min))' "$config" > "$temp/negotiated-config"
        negotiated_request_limit=$(jq -r .limits.request_bytes "$temp/negotiated-config")
        if (( $(wc -c < "$temp/request") > negotiated_request_limit )); then
            loom_protocol_receipt "$temp/request" refused quota_exceeded 'Request exceeds negotiated limit'; return 2
        fi
        loom_protocol_cap_limits "$temp/negotiated-config" "$caps" "$temp/hello/response" > "$temp/effective-config"
        config="$temp/effective-config"
        if ! loom_protocol_request_limits "$temp/request" "$config"; then
            loom_protocol_receipt "$temp/request" refused quota_exceeded 'Request exceeds negotiated field limits'; return 2
        fi
    else digest=null
    fi
    rc=0
    loom_protocol_exchange "$config" "$temp/request" "$temp/call" "$actual_digest" "$digest" "$deadline_end" || rc=$?
    # Raw stderr is deliberately not relayed: it could contain secrets even with
    # a clean environment. Expose only fixed, bounded diagnostic labels.
    if [[ -s $temp/call/stderr ]]; then printf 'loom protocol: adapter emitted diagnostics (content withheld)\n' >&2; fi
    cat -- "$temp/call/response"
    return "$rc"
)

# Final validation is mandatory after adding wrapper evidence. A valid adapter
# response can otherwise exceed extension/depth/byte limits when normalized.
loom_protocol_endpoint() (
    local action=$1 temp rc=0 status=failed
    shift
    umask 077
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    if ! loom_protocol_input "$temp/request"; then
        loom_protocol_receipt /dev/null refused invalid_request 'Request exceeds 1 MiB' > "$temp/response"
    else
        case $action in
            serve) _loom_protocol_serve < "$temp/request" > "$temp/response" || rc=$? ;;
            invoke) _loom_protocol_invoke "$@" < "$temp/request" > "$temp/response" || rc=$? ;;
        esac
    fi
    if ! loom_protocol_validate response "$temp/response"; then
        if loom_protocol_validate request "$temp/request" && jq -e '.operation_id!=null' "$temp/request" >/dev/null; then status=unknown; fi
        loom_protocol_receipt "$temp/request" "$status" outcome_unknown 'Normalized response failed validation' > "$temp/fallback"
        if [[ $status == unknown ]]; then
            jq '.effects=[{kind:"adapter_invocation",resource:.operation_id,disposition:"unknown"}]' "$temp/fallback" > "$temp/patched"
            mv -- "$temp/patched" "$temp/fallback"
        fi
        # Transport evidence is our own bounded shape. Ignore adapter extensions.
        if loom_protocol_lex "$temp/response" 2>/dev/null; then
            jq -c --slurpfile old "$temp/response" --argjson code "$rc" '
              .extensions["loom.normalization"]={implementation_exit:$code} |
              if $old[0].extensions["loom.transport"] then .extensions["loom.transport"]=$old[0].extensions["loom.transport"] else . end
            ' "$temp/fallback" > "$temp/patched" && mv -- "$temp/patched" "$temp/fallback"
        fi
        if ! loom_protocol_validate response "$temp/fallback"; then
            # No unvalidated optional value can escape even on internal failure.
            loom_protocol_receipt "$temp/request" "$status" outcome_unknown 'Normalized response failed validation' > "$temp/fallback"
        fi
        mv -- "$temp/fallback" "$temp/response"
    fi
    rc=$(loom_protocol_exit "$temp/response")
    cat -- "$temp/response"
    return "$rc"
)

loom_protocol_serve() { loom_protocol_endpoint serve; }
loom_protocol_invoke() { loom_protocol_endpoint invoke "$@"; }

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1-serve} in
        serve) loom_protocol_serve ;;
        invoke) loom_protocol_invoke "${2-}" "${3-}" ;;
        _call) shift; loom_protocol_call_child "$@" ;;
        validate) loom_protocol_validate "${2-}" "${3-}" "${4-}" ;;
        *) printf 'loom protocol: unsupported CLI mode\n' >&2; exit 2 ;;
    esac
fi
