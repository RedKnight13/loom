#!/usr/bin/env bash
# Source-safe S6 authority. All state/policy dependencies are loaded inside calls.
# shellcheck disable=SC2015 # Guards intentionally refuse either failed condition.

_loom_coord_modules() {
    local ops
    ops=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 2
    # shellcheck source=/dev/null
    source "${LOOM_COORDINATION_PROTOCOL_MODULE:-$ops/protocol.sh}" || return 2
    # shellcheck source=/dev/null
    source "${LOOM_COORDINATION_STATE_MODULE:-$ops/state.sh}" || return 2
    # shellcheck source=/dev/null
    source "${LOOM_COORDINATION_POLICY_MODULE:-$ops/policy.sh}" || return 2
}

_loom_coord_context() {
    loom_policy_json "$1" || return 2
    [[ $(stat -c %a -- "$1") == 600 ]] || return 2
    jq -e '
      def id: type=="string" and utf8bytelength>0 and utf8bytelength<=128;
      keys==["actor_id","claims","config","create_runs","hosts","profiles","proofs","runs","schema","state_root","store_id"] and
      .schema==1 and (.actor_id|id) and (.store_id|id) and
      (.state_root|type=="string") and (.create_runs|type=="boolean") and
      (.runs|type=="array" and all(.[];id)) and (.claims|type=="array") and
      (.proofs|type=="array") and all(.config,.hosts,.profiles;type=="string")
    ' "$1" >/dev/null || return 2
    export LOOM_STATE
    LOOM_STATE=$(jq -r .state_root "$1")
    # Identity comes from this installed context, never from body or extensions.
    loom_state_replay > "$_cq_tmp/store" || return $?
    [[ $(jq -r .store_id "$_cq_tmp/store") == "$(jq -r .store_id "$1")" ]] || return 2
}

_loom_coord_key() {
    jq -cS '[.actor.id,.op,.idempotency_key]' "$1" | git hash-object --stdin
}

_loom_coord_digest() {
    jq -cS 'del(.request_id,.timeout_ms)' "$1" | loom_policy_scope
}

_loom_coord_response() {
    local request=$1 result=$2 durable=$3
    jq -cn --slurpfile q "$request" --slurpfile r "$result" --argjson durable "$durable" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      $q[0] as $q | {protocol:"loom.coordination",version:{major:1,minor:0},request_id:$q.request_id,
       operation_id:$q.operation_id,op:$q.op,target:$q.target,ok:true,status:"completed",
       revision:($r[0].revision//$r[0].gate.revision//null),durable:$durable,result:$r[0],error:null,
       effects:[],evidence:[],observed_at:$at,extensions:{}}'
}

# One aggregate per run is the graph authority. Task/gate/attempt entities are
# atomically updated projections for mail/workflow consumers. Every mutation
# changes the run revision, fencing graph reads and ownership under S2's lock.
_loom_coord_program() {
    cat <<'JQ'
def need($yes;$why): if $yes then . else error($why) end;
def viewrun($d): $d.run;
def allowed($c;$r): ($c.runs|index($r))!=null;
def active($a): $a.execution_state|IN("reserved","starting","running","stop_requested","unknown");
def ready($d;$t):
  all($t.deps[]; . as $dep | $d.tasks[$dep.task_id] as $p |
    $p!=null and $p.state=="succeeded" and $p.accepted_result!=null) and
  all($t.gates[]; $d.gates[.].state=="approved");
def graph($d):
  # Kahn reduction bounds work even for dense DAGs with many shared ancestors.
  def acyclic($nodes):
    if ($nodes|length)==0 then true else
      [$nodes|to_entries[] | select(all(.value.deps[];.task_id as $id | $nodes[$id]==null)) | .key] as $roots |
      if ($roots|length)==0 then error("dependency_cycle")
      else acyclic($nodes|delpaths($roots|map([.]))) end
    end;
  need(all($d.tasks[];. as $t | all($t.deps[];$d.tasks[.task_id]!=null));"missing_or_cross_run_dependency") |
  need(all($d.tasks[];. as $t | all($t.gates[];$d.gates[.]!=null and $d.gates[.].task_id==$t.task_id));"missing_or_cross_task_gate") |
  acyclic($d.tasks);
def refresh:
  . as $d | .tasks |= with_entries(
    if (.value.state|IN("pending","ready")) then
      .value.state=(if ready($d;.value) then "ready" else "pending" end)
    else . end);
def checkrev($q;$e): need($e!=null and $q.expected_revision==$e.revision;"revision_conflict");
def proof($c;$q;$t;$kind):
  [$c.proofs[] | select(.kind==$kind and .run_id==$q.actor.run_id and
    .task_id==$t.task_id and .revision==$t.revision and .epoch==$q.actor.epoch and
    .attempt_id==$t.attempt_ids[-1] and (.evidence_ref as $ref | $q.args.evidence_refs|index($ref))!=null)] | first;
def projection($kind;$id;$value;$old;$q):
  {kind:$kind,id:$id,expected_revision:($old.revision//null),run_id:$q.actor.run_id,epoch:$q.actor.epoch,data:$value};
$c[0] as $c | $q[0] as $q | $s[0] as $s | ($s.data//null) as $old |
need($q.actor.id==$c.actor_id;"actor_mismatch") |
need($q.target=={assignment_id:null,attempt_id:null,host_id:null};"unexpected_target") |
need(($q.extensions|length)==0;"unsupported_extension") |
if $q.op=="run.create" then
  need($c.create_runs and $q.actor.run_id!=null and $q.actor.epoch==0 and $q.args.owner_id==$c.actor_id and $q.args.parent_run_id==null and $s==null;"creation_denied") |
  {owner_id:$c.actor_id,run:{run_id:$q.actor.run_id,objective:$q.args.objective,owner_id:$c.actor_id,
    epoch:0,state:"open",revision:1,parent_run_id:null},tasks:{},gates:{},attempts:{},assignments:{},preparations:{}} as $d |
  {data:$d,result:$d.run}
else
  need($s!=null and allowed($c;$q.actor.run_id) and $s.run_id==$q.actor.run_id;"run_denied") |
  need($s.epoch==$q.actor.epoch;"owner_fenced") |
  need($q.args.run_id==null or $q.args.run_id==$s.run_id;"cross_run_reference") |
  need($q.op=="run.claim" or $q.op=="gate.resolve" or ($q.op|IN("run.show","run.use","task.show","task.list","gate.list")) or $old.owner_id==$c.actor_id;"owner_denied") |
  if $q.op=="run.claim" then
    checkrev($q;$old.run) |
    need($q.args.expected_owner==$old.owner_id and ($q.args.reason|length)>0;"claim_denied") |
    need(any($c.claims[]; .run_id==$s.run_id and .expected_owner==$old.owner_id and .expected_revision==$s.revision and .epoch==$s.epoch and .reason==$q.args.reason);"claim_not_authorized") |
    need(all($old.attempts[];active(.)|not) and (($old.preparations//{})|length)==0;"host_fence_unproven") |
    ($old | .owner_id=$c.actor_id | .run.owner_id=$c.actor_id | .run.epoch+=1) as $d |
    {data:$d,result:$d.run}
  elif $q.op=="task.create" then
    need(($old.tasks|length)<80;"graph_limit") |
    ($old | .tasks[$id]={task_id:$id,run_id:$s.run_id,spec_ref:$q.args.spec_ref,spec_digest:$q.args.spec_digest,
      deps:$q.args.deps,gates:$q.args.gates,state:"pending",revision:1,attempt_ids:[],accepted_result:null}) as $d |
    need(graph($d);"invalid_graph") | ($d|refresh) as $d | {data:$d,result:$d.tasks[$id]}
  elif $q.op=="gate.create" then
    $old.tasks[$q.args.task_id] as $t | need($t!=null;"missing_task") |
    need(($t.state|IN("succeeded","failed","cancelled"))|not;"terminal_task") |
    need(($old.gates|length)<80 and all($q.args.options[];IN("approved","rejected","cancelled"));"unsupported_gate_option") |
    ($old | .gates[$id]={gate_id:$id,task_id:$t.task_id,question:$q.args.question,resolver_id:$q.args.resolver_id,
      options:$q.args.options,state:"open",revision:1,decision:null,evidence_ref:null} |
      .tasks[$t.task_id].gates+=[$id] |
      if $t.state=="running" then .tasks[$t.task_id].state="waiting" |
        .attempts[$t.attempt_ids[-1]].stop_requested=true else . end | refresh) as $d |
    {data:$d,result:$d.gates[$id]}
  elif $q.op=="gate.resolve" then
    $old.gates[$q.args.gate_id] as $g | checkrev($q;$g) |
    need($g.resolver_id==$c.actor_id or $old.owner_id==$c.actor_id;"resolver_denied") |
    need($g.state=="open" and ($g.options|index($q.args.decision))!=null;"gate_conflict") |
    ($old | .gates[$g.gate_id].state=$q.args.decision | .gates[$g.gate_id].decision=$q.args.decision |
      .gates[$g.gate_id].evidence_ref=$q.args.evidence_ref | refresh) as $d |
    {data:$d,result:{gate:$d.gates[$g.gate_id],ready_task_ids:[$d.tasks[]|select(.state=="ready" and $old.tasks[.task_id].state!="ready")|.task_id]}}
  elif $q.op=="task.update" then
    $old.tasks[$q.args.task_id] as $t | checkrev($q;$t) |
    $q.args.transition as $to |
    need($t.state!="succeeded" and ($t.state!="cancelled" or $to=="cancelled");"terminal_task") |
    need($to!="running";"launch_authorization_required") |
    if $to=="ready" then
      need(($t.state|IN("pending","ready")) and ready($old;$t);"prerequisites_unmet")
    elif $to=="review" then
      proof($c;$q;$t;"harvest") as $p |
      need(($t.state|IN("running","waiting")) and ($t.attempt_ids|length)>0 and $p!=null and $p.confirmed_stopped==true and $p.quiescent==true and $p.current_report==true and $p.report_state=="ready" and $p.report_digest!=null and $p.exit_code==0;"harvest_proof_required")
    elif $to=="succeeded" then
      proof($c;$q;$t;"accept") as $p |
      need($t.state=="review" and $p!=null and $p.reviewed==true and $p.check_exit==0 and
        ($p.checked_sha|type)=="string" and ($p.checked_sha|test("^[0-9a-f]{40}$")) and
        $p.checked_sha==$p.collected_sha and $p.checked_sha==$p.current_sha and
        $p.config_digest==$old.attempts[$t.attempt_ids[-1]].policy_pin.config_digest and
        $p.manifest_digest==$old.attempts[$t.attempt_ids[-1]].binding.manifest_digest;"acceptance_proof_required")
    elif $to=="failed" then
      proof($c;$q;$t;"settlement") as $p |
      need(($t.state|IN("running","waiting","review")) and ($t.attempt_ids|length)>0 and $p!=null and $p.confirmed_stopped==true and $p.quiescent==true;"settlement_proof_required")
    elif $t.state=="cancelled" then
      proof($c;$q;$t;"settlement") as $p |
      need(($t.attempt_ids|length)>0 and $p!=null and $p.confirmed_stopped==true and $p.quiescent==true;"settlement_proof_required")
    else need($to=="waiting" or $to=="cancelled";"invalid_transition") end |
    ($old | .tasks[$t.task_id].state=$to |
      if $to=="succeeded" then .tasks[$t.task_id].accepted_result=proof($c;$q;$t;"accept").evidence_ref else . end |
      if $to=="review" or $to=="failed" or ($t.state=="cancelled" and $to=="cancelled") then
        .attempts[$t.attempt_ids[-1]].execution_state="exited" |
        .attempts[$t.attempt_ids[-1]].confirmed_stopped=true else . end | refresh) as $d |
    {data:$d,result:$d.tasks[$t.task_id]}
  elif $q.op=="task.continue" then
    $old.tasks[$q.args.task_id] as $t | checkrev($q;$t) |
    $old.attempts[$q.args.parent_attempt_id] as $a |
    need($a!=null and $t.attempt_ids[-1]==$q.args.parent_attempt_id and $a.task_id==$t.task_id and
      $a.confirmed_stopped==true and (active($a)|not) and ($q.args.reason|length)>0 and
      ($t.state|IN("failed","review","waiting")) and $q.args.placement_digest==$a.placement_digest and
      ($q.args.message_ids|length)==0;"continuation_denied") |
    need(ready($old;$t) and ($t.attempt_ids|length)<100;"prerequisites_unmet") |
    ($old | .attempts[$id]={attempt_id:$id,task_id:$t.task_id,assignment_id:$a.assignment_id,
      ordinal:($a.ordinal+1),parent_attempt_id:$a.attempt_id,epoch:$q.actor.epoch,
      execution_state:"reserved",resource_state:"unknown",confirmed_stopped:false,launch_authorized:false,
      binding:null,placement_digest:$a.placement_digest,policy_pin:$a.policy_pin,
      capacity_operation_id:null,launch_operation:null,revision:1} |
      .tasks[$t.task_id].attempt_ids+=[$id] | .tasks[$t.task_id].state="ready" |
      .tasks[$t.task_id].accepted_result=null) as $d |
    {data:$d,result:{task_id:$t.task_id,parent_attempt_id:$a.attempt_id,attempt_id:$id,revision:($t.revision+1)}}
  else error("unsupported_operation") end
end |
# Bump only changed entity projections; the run revision changes for all writes.
.data |= (. as $d | .tasks |= with_entries(if $old.tasks[.key]!=null and .value!=$old.tasks[.key] then .value.revision+=1 else . end) |
  .gates |= with_entries(if $old.gates[.key]!=null and .value!=$old.gates[.key] then .value.revision+=1 else . end) |
  .attempts |= with_entries(if $old.attempts[.key]!=null and .value!=$old.attempts[.key] then .value.revision+=1 else . end) |
  .run.revision=(($s.revision//0)+1)) |
.data as $d |
.result=(if $q.op|startswith("run.") then $d.run
  elif $q.op=="task.create" then $d.tasks[$id]
  elif $q.op=="task.update" then $d.tasks[$q.args.task_id]
  elif $q.op=="gate.create" then $d.gates[$id]
  elif $q.op=="gate.resolve" then .result|.gate=$d.gates[$q.args.gate_id] else .result end) |
{schema:2,store_id:$c.store_id,operation_id:$q.operation_id,idempotency_key:$q.idempotency_key,op:$q.op,
 actor:$q.actor,target:$q.target,checks:[],
 changes:([{kind:"run",id:$q.actor.run_id,expected_revision:($s.revision//null),run_id:$q.actor.run_id,epoch:$d.run.epoch,data:$d}] +
  [$d.tasks|to_entries[]|select(.value!=$old.tasks[.key])|projection("task";.key;.value;$old.tasks[.key];$q)] +
  [$d.gates|to_entries[]|select(.value!=$old.gates[.key])|projection("gate";.key;.value;$old.gates[.key];$q)] +
  [$d.attempts|to_entries[]|select(.value!=$old.attempts[.key])|projection("attempt";.key;.value;$old.attempts[.key];$q)]),
 events:[{type:$q.op,entity_ids:[$q.actor.run_id],payload:{wire_digest:$digest,
   verified_proof:(if $q.op=="run.claim" then
     [$c.claims[] | select(.run_id==$q.actor.run_id and .expected_owner==$q.args.expected_owner and
       .expected_revision==$q.expected_revision and .epoch==$q.actor.epoch and .reason==$q.args.reason)] | first
   elif $q.op=="task.update" then
     ($q.args.transition | if .=="review" then "harvest" elif .=="succeeded" then "accept" elif .=="failed" then "settlement" else "none" end) as $kind |
     proof($c;$q;$old.tasks[$q.args.task_id];$kind) else null end)},observed_at:null}],
 result:{wire_digest:$digest,response:.result}}
JQ
}

# A historical outcome never grants a former owner current mutation authority.
_loom_coord_replay_authorized() {
    local context=$1 request=$2 current
    current=$(loom_state_get run "$(jq -r .actor.run_id "$request")") || return 2
    jq -e --slurpfile c "$context" --slurpfile q "$request" '
      .epoch==$q[0].actor.epoch and
      (.data.owner_id==$c[0].actor_id or
       ($q[0].op=="gate.resolve" and .data.gates[$q[0].args.gate_id].resolver_id==$c[0].actor_id))
    ' <<< "$current" >/dev/null || { printf 'owner_fenced\n' >&2; return 2; }
}

_loom_coord_mutate() {
    local context=$1 request=$2 prior rc=0 key digest run op actor
    key=$(_loom_coord_key "$request") || return 2
    digest=$(_loom_coord_digest "$request") || return 2
    run=$(jq -r .actor.run_id "$request"); op=$(jq -r .op "$request"); actor=$(jq -r .actor.id "$request")
    jq -e --arg run "$run" --arg op "$op" 'if $op=="run.create" then .create_runs else (.runs|index($run))!=null end' "$context" >/dev/null || return 2
    # Read failures are not absence: replay already verified the store. A missing
    # dedupe entry alone can proceed, while corrupt/unavailable stores fail later.
    if prior=$(loom_state_operation "$actor" "$op" "$(jq -r .idempotency_key "$request")" 2>"$_cq_tmp/lookup-error"); then
        [[ $(jq -r .outcome.result.wire_digest <<< "$prior") == "$digest" ]] || { printf 'idempotency_conflict\n' >&2; return 2; }
        _loom_coord_replay_authorized "$context" "$request" || return 2
        jq -cS .outcome.result.response <<< "$prior" > "$_cq_tmp/result"
        return 0
    fi
    if [[ $op == run.create ]]; then printf 'null\n' > "$_cq_tmp/run"
    else loom_state_get run "$run" > "$_cq_tmp/run" || return $?; fi
    _loom_coord_program > "$_cq_tmp/program.jq"
    jq -cnS --slurpfile c "$context" --slurpfile q "$request" --slurpfile s "$_cq_tmp/run" \
      --arg id "coord-$key" --arg digest "$digest" -f "$_cq_tmp/program.jq" > "$_cq_tmp/transaction" || return 2
    loom_state_transact "$_cq_tmp/transaction" > "$_cq_tmp/outcome" || rc=$?
    (( rc==0 )) || return "$rc"
    jq -cS .result.response "$_cq_tmp/outcome" > "$_cq_tmp/result"
}

_loom_coord_read() {
    local context=$1 request=$2 op run kind
    op=$(jq -r .op "$request"); run=$(jq -r .actor.run_id "$request")
    if [[ $op == hello ]]; then
        local schema
        schema=$(loom_protocol_digest "$(loom_protocol_root)/schemas/coordination-v1/contract.json") || return 2
        jq -cen --slurpfile q "$request" --arg digest "$schema" '
          ["run.create.v1","run.claim.v1","run.show.v1","run.use.v1","run.list.v1","task.create.v1","task.update.v1","task.show.v1","task.list.v1","task.continue.v1","gate.create.v1","gate.resolve.v1","gate.list.v1"] as $names |
          if ($q[0].args.required_capabilities-$names|length)>0 then error("unsupported_capability") else
          {selected_version:{major:1,minor:0},provider:{id:"native-coordination",version:"1"},
           capabilities:[$names[]|{name:.,state:"supported",evidence:[],limits:{max_bytes:1048576,max_items:80}}],
           limits:{request_bytes:1048576,response_bytes:1048576,metadata_bytes:65536,message_bytes:65536,read_bytes:65536,list_rows:100,diagnostic_bytes:1048576},schema_digest:$digest} end' > "$_cq_tmp/result"
        return $?
    fi
    if [[ $op == run.list ]]; then
        loom_state_list run "$(jq -r '.args.cursor//""' "$request")" "$(jq -r .args.limit "$request")" > "$_cq_tmp/list" || return $?
        jq -c --slurpfile c "$context" '.items |= map(select(.id as $id | $c[0].runs|index($id))|.data.run)' "$_cq_tmp/list" > "$_cq_tmp/result"
        return $?
    fi
    loom_state_get run "$run" > "$_cq_tmp/run" || return $?
    kind=${op%%.*}
    jq -ce --slurpfile c "$context" --slurpfile q "$request" --arg kind "$kind" '
      $c[0] as $c | $q[0] as $q | .data as $d | .run_id as $run |
      if ($c.runs|index($run))==null then error("run_denied") else . end |
      if $q.args.run_id!=null and $q.args.run_id!=.run_id then error("cross_run_reference") else . end |
      if $q.op=="run.show" or $q.op=="run.use" then $d.run
      elif $q.op=="task.show" then $d.tasks[$q.args.task_id]//error("missing_task")
      else [$d[($kind+"s")][] | select(.[($kind+"_id")]>($q.args.cursor//""))] |
        sort_by(.[($kind+"_id")]) | .[:$q.args.limit] |
        {items:.,next_cursor:(if length==$q.args.limit then .[-1][($kind+"_id")] else null end)} end
    ' "$_cq_tmp/run" > "$_cq_tmp/result"
}

_loom_coord_handle() (
    umask 077
    local context=$1 request=$2 _cq_tmp rc=0 op durable=false prior
    _cq_tmp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$_cq_tmp"' EXIT
    _loom_coord_modules || return 2
    loom_protocol_validate request "$request" || { loom_protocol_receipt "$request" refused invalid_request 'Invalid coordination request'; return 2; }
    [[ $(jq -r .protocol "$request") == loom.coordination ]] || return 2
    cp -- "$request" "$_cq_tmp/request" || return 1
    request=$_cq_tmp/request
    _loom_coord_context "$context" &&
      [[ $(jq -r .actor.id "$request") == "$(jq -r .actor_id "$context")" ]] || {
        loom_protocol_receipt "$request" refused actor_denied 'Trusted context or actor mismatch'; return 2;
    }
    op=$(jq -r .op "$request")
    case $op in
        hello|run.show|run.use|run.list|task.show|task.list|gate.list)
            _loom_coord_read "$context" "$request" 2>"$_cq_tmp/error" || rc=$? ;;
        run.create|run.claim|task.create|task.update|task.continue|gate.create|gate.resolve)
            durable=true
            _loom_coord_mutate "$context" "$request" 2>"$_cq_tmp/error" || rc=$? ;;
        *) loom_protocol_receipt "$request" refused unsupported_capability 'Operation belongs to another coordination module' "$op"; return 2 ;;
    esac
    # Another identical caller may have committed after our first lookup but
    # before validation/CAS. Reconcile its durable semantic result, never retry
    # a newly generated transaction or execute a second effect.
    if (( rc!=0 )) && [[ $durable == true ]] &&
      jq -e --slurpfile q "$request" 'if $q[0].op=="run.create" then .create_runs else (.runs|index($q[0].actor.run_id))!=null end' "$context" >/dev/null; then
        if prior=$(loom_state_operation "$(jq -r .actor.id "$request")" "$op" "$(jq -r .idempotency_key "$request")" 2>/dev/null) &&
          [[ $(jq -r .outcome.result.wire_digest <<< "$prior") == "$(_loom_coord_digest "$request")" ]] &&
          _loom_coord_replay_authorized "$context" "$request"; then
            jq -cS .outcome.result.response <<< "$prior" > "$_cq_tmp/result"
            rc=0
        fi
    fi
    if (( rc!=0 )); then
        cat "$_cq_tmp/error" >&2
        if (( rc==2 )); then loom_protocol_receipt "$request" refused coordination_denied 'Authority, revision or domain precondition refused'; return 2
        else loom_protocol_receipt "$request" unknown outcome_unknown 'Reconcile the identical operation; retain capacity'; return 1; fi
    fi
    _loom_coord_response "$request" "$_cq_tmp/result" "$durable" > "$_cq_tmp/response" || return 1
    loom_protocol_validate response "$_cq_tmp/response" "$request" || {
        loom_protocol_receipt "$request" unknown outcome_unknown 'Response validation failed; reconcile identical operation'; return 1;
    }
    cat "$_cq_tmp/response"
)

loom_coordination_handle() (
    [[ $# == 2 ]] || return 2
    umask 077
    local temp rc=0 seconds ops
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    _loom_coord_modules || return 2
    loom_protocol_validate request "$2" || { loom_protocol_receipt "$2" refused invalid_request 'Invalid request'; return 2; }
    cp -- "$2" "$temp/request" || return 1
    seconds=$(jq -r '.timeout_ms/1000' "$temp/request")
    ops=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 2
    timeout --kill-after=1 "$seconds" bash "$ops/coordination.sh" --internal "$1" "$temp/request" > "$temp/response" || rc=$?
    if (( rc==124 || rc==137 )); then
        loom_protocol_receipt "$temp/request" unknown outcome_unknown 'Deadline exceeded; reconcile identical operation'; return 1
    fi
    cat "$temp/response"
    return "$rc"
)

loom_coordination_serve() (
    [[ $# == 1 ]] || return 2
    umask 077
    local temp
    temp=$(mktemp) || return 1
    trap 'rm -f -- "$temp"' EXIT
    head -c 1048577 > "$temp" || return 2
    [[ $(stat -c %s "$temp") -le 1048576 ]] || return 2
    loom_coordination_handle "$1" "$temp"
)

_loom_coord_fault() {
    if [[ ${LOOM_COORDINATION_TESTING:-} == 1 ]]; then
        if [[ ${LOOM_COORDINATION_TEST_CRASH:-} == "$1" ]]; then kill -KILL "$BASHPID"; fi
        if [[ ${LOOM_COORDINATION_TEST_FAIL:-} == "$1" ]]; then return 1; fi
    fi
    return 0
}

# PLAN is data, not authority. A matching trusted launch proof in CONTEXT pins
# calibrated policy, capability evidence and the prepared workspace/binding.
_loom_coord_authorize() (
    umask 077
    local context=$1 plan=$2 _cq_tmp key digest run actor pin scope binding_digest prep rc=0
    _cq_tmp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$_cq_tmp"' EXIT
    _loom_coord_modules && _loom_coord_context "$context" || return 2
    loom_policy_json "$plan" || return 2
    cp -- "$plan" "$_cq_tmp/plan" || return 1
    plan=$_cq_tmp/plan
    jq -e '
      def id: type=="string" and utf8bytelength>0 and utf8bytelength<=128;
      def digest: type=="string" and test("^git-blob-sha1-v1:[0-9a-f]{40}$");
      keys==["actor","binding","expected_revision","idempotency_key","operation_id","placement_digest","schema","task_id"] and
      .schema==1 and all(.task_id,.operation_id,.idempotency_key;id) and (.placement_digest|digest) and
      (.expected_revision|type=="number" and .==floor and .>=1) and
      (.actor|keys==["epoch","id","run_id"] and (.id|id) and (.run_id|id) and (.epoch|type=="number" and .==floor and .>=0)) and
      (.binding|keys==["actor","executable_digest","limits","manifest_digest","profile_digest","prompt","prompt_digest","prompt_ref","release_authorized","schema","stop_authorized","target","workspace","workspace_id"] and
        .schema==1 and (.target|keys==["assignment_id","attempt_id","host_id"] and all(.[];id)) and
        all(.workspace_id,.prompt_ref;id) and all(.workspace,.prompt;type=="string" and startswith("/")) and
        all(.manifest_digest,.profile_digest,.prompt_digest,.executable_digest;digest) and
        all(.stop_authorized,.release_authorized;type=="boolean") and
        (.limits|keys==["allow_kill","output_bytes","runtime_ms","stop_on_timeout"] and
          all(.allow_kill,.stop_on_timeout;type=="boolean") and
          (.output_bytes|type=="number" and .==floor and .>=4096 and .<=67108864) and
          (.runtime_ms==null or (.runtime_ms|type=="number" and .==floor and .>=1)))) and .actor==.binding.actor
    ' "$plan" >/dev/null || return 2
    actor=$(jq -r .actor.id "$plan"); run=$(jq -r .actor.run_id "$plan")
    [[ $actor == "$(jq -r .actor_id "$context")" ]] || return 2
    pin=$(loom_policy_resolve "$(jq -r .config "$context")" "$(jq -r .hosts "$context")" "$(jq -r .profiles "$context")") || return 2
    scope=$(loom_policy_scope <<< "$pin") || return 2
    binding_digest=$(jq 'del(.stop_authorized,.release_authorized)' < <(jq .binding "$plan") | loom_policy_scope) || return 2
    digest=$(loom_policy_scope < "$plan") || return 2
    key=$(jq -cS '[.actor.id,.idempotency_key]' "$plan" | git hash-object --stdin) || return 2
    prep=launch-$key
    printf '%s\n' "$pin" > "$_cq_tmp/pin"
    loom_state_get run "$run" > "$_cq_tmp/run" || return $?
    jq -e --slurpfile c "$context" --slurpfile p "$plan" --arg scope "$scope" --arg bd "$binding_digest" --argjson pin "$pin" '
      $p[0] as $p | $c[0] as $c | .data as $d |
      .epoch==$p.actor.epoch and $d.owner_id==$c.actor_id and ($c.runs|index($p.actor.run_id))!=null and
      $pin.provider=="native" and $pin.host.id==$p.binding.target.host_id and $scope==$p.placement_digest and
      $pin.profile_digest==$p.binding.profile_digest and
      any($c.proofs[];.kind=="launch" and .run_id==$p.actor.run_id and .task_id==$p.task_id and
        .revision==$p.expected_revision and .epoch==$p.actor.epoch and .binding_digest==$bd and
        .placement_digest==$scope and .calibration_verified==true and .capabilities_verified==true and .workspace_verified==true and
        .stop_authorized==$p.binding.stop_authorized and $p.binding.release_authorized==false)
    ' "$_cq_tmp/run" >/dev/null || { printf 'launch_authority_denied\n' >&2; return 2; }
    if loom_state_get operation "$prep" > "$_cq_tmp/prepared" 2>"$_cq_tmp/lookup-error"; then
        jq -e --arg digest "$digest" --arg run "$run" '.run_id==$run and .data.plan_digest==$digest' "$_cq_tmp/prepared" >/dev/null || return 2
    else
        jq -cnS --slurpfile c "$context" --slurpfile p "$plan" --arg key "capacity-$key" '
          {schema:2,store_id:$c[0].store_id,actor_id:$c[0].actor_id,operation_id:$key,idempotency_key:$key,
           run_id:$p[0].actor.run_id,attempt_id:$p[0].binding.target.attempt_id}' > "$_cq_tmp/cap-context"
        loom_policy_reserve_request "$(jq -r .config "$context")" "$(jq -r .hosts "$context")" \
          "$(jq -r .profiles "$context")" "$_cq_tmp/cap-context" > "$_cq_tmp/cap-request" || return $?
        jq -cnS --slurpfile c "$context" --slurpfile p "$plan" --slurpfile s "$_cq_tmp/run" \
          --slurpfile cap "$_cq_tmp/cap-request" --arg id "$prep" --arg digest "$digest" --arg bd "$binding_digest" '
          $p[0] as $p | $s[0] as $s | $s.data as $d | $d.tasks[$p.task_id] as $t |
          if $t==null or $t.revision!=$p.expected_revision or $d.preparations[$p.task_id]!=null or
            ($t.state|IN("ready","pending")|not) or
            (($t.attempt_ids|length)>=100 and ($t.attempt_ids|index($p.binding.target.attempt_id))==null) or
            any($t.deps[];$d.tasks[.task_id].state!="succeeded" or $d.tasks[.task_id].accepted_result==null) or
            any($t.gates[];$d.gates[.].state!="approved") or
            any($t.attempt_ids[]; . as $aid | $d.attempts[$aid] as $a |
              $a.confirmed_stopped!=true and ($aid!=$p.binding.target.attempt_id or $a.binding!=null)) or
            ($d.attempts[$p.binding.target.attempt_id]!=null and
              ($d.attempts[$p.binding.target.attempt_id].task_id!=$t.task_id or
               $d.attempts[$p.binding.target.attempt_id].assignment_id!=$p.binding.target.assignment_id or
               $d.attempts[$p.binding.target.attempt_id].placement_digest!=$p.placement_digest))
          then error("attempt_not_ready") else
          {schema:2,store_id:$c[0].store_id,operation_id:($id+"-prepare"),idempotency_key:($id+"-prepare"),
           op:"coordination.prepare",actor:$p.actor,target:$p.binding.target,checks:[],
           changes:[{kind:"run",id:$s.id,expected_revision:$s.revision,run_id:$s.id,epoch:$s.epoch,
             data:($d | .run.revision+=1 | .preparations[$p.task_id]=$id)},
             {kind:"operation",id:$id,expected_revision:null,run_id:$s.id,epoch:$s.epoch,
              data:{plan_digest:$digest,plan:$p,binding_digest:$bd,capacity_request:$cap[0],stage:"prepared",
                verified_proof:([$c[0].proofs[]|select(.kind=="launch" and .run_id==$p.actor.run_id and .task_id==$p.task_id and
                  .revision==$p.expected_revision and .epoch==$p.actor.epoch and .binding_digest==$bd and .placement_digest==$p.placement_digest and
                  .calibration_verified==true and .capabilities_verified==true and .workspace_verified==true and .stop_authorized==$p.binding.stop_authorized)]|first)}}],
           events:[{type:"coordination.prepared",entity_ids:[$id,$t.task_id],payload:{},observed_at:null}],result:{operation_id:$id}}
          end' > "$_cq_tmp/prepare-request" || return 2
        loom_state_transact "$_cq_tmp/prepare-request" > "$_cq_tmp/prepare-receipt" || return $?
        loom_state_get operation "$prep" > "$_cq_tmp/prepared" || return $?
        _loom_coord_fault after_prepare || return 1
    fi
    # The exact S3 transaction is durable before use. Lost replies/crashes replay
    # these bytes, never regenerate a reservation from a newer ledger revision.
    jq -cS .data.capacity_request "$_cq_tmp/prepared" > "$_cq_tmp/cap-request"
    jq -e --slurpfile pin "$_cq_tmp/pin" --slurpfile p "$plan" --arg scope "$scope" '
      .result.policy_pin==$pin[0] and .result.scope_digest==$scope and
      .result.attempt_id==$p[0].binding.target.attempt_id and
      .changes[0].data.slots[-1].run_id==$p[0].actor.run_id
    ' "$_cq_tmp/cap-request" >/dev/null || return 2
    loom_state_transact "$_cq_tmp/cap-request" > "$_cq_tmp/capacity" || return $?
    _loom_coord_fault after_capacity || return 1
    # Durable authorization is replay-only once committed. It is not a new launch.
    if [[ $(jq -r .data.stage "$_cq_tmp/prepared") == authorized ]]; then
        loom_state_operation "$actor" coordination.launch "$prep" > "$_cq_tmp/launch-operation" || return $?
        jq .outcome "$_cq_tmp/launch-operation" > "$_cq_tmp/launch"
    else
        loom_state_get run "$run" > "$_cq_tmp/run" || return $?
        # Recheck exact pin at the final authorization boundary.
        loom_policy_check "$_cq_tmp/pin" "$(jq -r .config "$context")" "$(jq -r .hosts "$context")" "$(jq -r .profiles "$context")" || return 2
        jq -cnS --slurpfile c "$context" --slurpfile p "$plan" --slurpfile s "$_cq_tmp/run" \
          --slurpfile prep "$_cq_tmp/prepared" --slurpfile cap "$_cq_tmp/capacity" --arg id "$prep" --arg scope "$scope" --arg bd "$binding_digest" '
          $p[0] as $p | $s[0] as $s | $s.data as $old | $old.tasks[$p.task_id] as $t |
          $p.binding.target.attempt_id as $aid | $p.binding.target.assignment_id as $assignment |
          if $s.epoch!=$p.actor.epoch or $old.owner_id!=$p.actor.id or $t.revision!=$p.expected_revision or
            $old.preparations[$t.task_id]!=$id or ($t.state|IN("pending","ready")|not) or
            any($t.deps[];$old.tasks[.task_id].state!="succeeded" or $old.tasks[.task_id].accepted_result==null) or
            any($t.gates[];$old.gates[.].state!="approved") or
            ($old.assignments[$assignment]!=null and $old.assignments[$assignment].task_id!=$t.task_id)
          then error("launch_preconditions_changed") else
          ($old | .run.revision+=1 | .tasks[$t.task_id].state="running" | .tasks[$t.task_id].revision+=1 |
            .tasks[$t.task_id].attempt_ids |= (if index($aid)==null then .+[$aid] else . end) |
            del(.preparations[$t.task_id]) |
            .attempts[$aid]={attempt_id:$aid,task_id:$t.task_id,assignment_id:$assignment,
              ordinal:($t.attempt_ids|length)+(if $old.attempts[$aid]==null then 1 else 0 end),
              parent_attempt_id:($old.attempts[$aid].parent_attempt_id//null),epoch:$p.actor.epoch,
              execution_state:"reserved",resource_state:"owned",confirmed_stopped:false,launch_authorized:true,
              binding:$p.binding,placement_digest:$scope,policy_pin:$cap[0].result.policy_pin,
              capacity_operation_id:$cap[0].operation_id,launch_operation:$id,revision:(($old.attempts[$aid].revision//0)+1)} |
            .assignments[$assignment]=($old.assignments[$assignment]//{assignment_id:$assignment,task_id:$t.task_id,binding:$p.binding,revision:1})) as $d |
          {schema:2,store_id:$c[0].store_id,operation_id:($id+"-authorize"),idempotency_key:$id,op:"coordination.launch",
           actor:$p.actor,target:$p.binding.target,checks:[],
           changes:([{kind:"run",id:$s.id,expected_revision:$s.revision,run_id:$s.id,epoch:$s.epoch,data:$d},
             {kind:"task",id:$t.task_id,expected_revision:$t.revision,run_id:$s.id,epoch:$s.epoch,data:$d.tasks[$t.task_id]},
             {kind:"attempt",id:$aid,expected_revision:($old.attempts[$aid].revision//null),run_id:$s.id,epoch:$s.epoch,data:$d.attempts[$aid]},
             {kind:"operation",id:$id,expected_revision:$prep[0].revision,run_id:$s.id,epoch:$s.epoch,data:($prep[0].data|.stage="authorized")}] +
             if $old.assignments[$assignment]==null then [{kind:"assignment",id:$assignment,expected_revision:null,run_id:$s.id,epoch:$s.epoch,data:$d.assignments[$assignment]}] else [] end),
           events:[{type:"coordination.launch_authorized",entity_ids:[$aid,$t.task_id],payload:{binding_digest:$bd},observed_at:null}],
           result:{actor:$p.actor,target:$p.binding.target,binding_digest:$bd}}
          end' > "$_cq_tmp/launch-request" || return 2
        loom_state_transact "$_cq_tmp/launch-request" > "$_cq_tmp/launch" || rc=$?
        (( rc==0 )) || return "$rc"
    fi
    _loom_coord_fault after_authorize || return 1
    jq -cn --slurpfile c "$_cq_tmp/capacity" --slurpfile l "$_cq_tmp/launch" '{capacity_receipt:$c[0],launch_receipt:$l[0]}'
)

loom_coordination_authorize() (
    [[ $# == 2 ]] || return 2
    local ops
    ops=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 2
    timeout --kill-after=1 30 bash "$ops/coordination.sh" --authorize-internal "$@"
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        handle) shift; loom_coordination_handle "$@" ;;
        serve) shift; loom_coordination_serve "$@" ;;
        authorize) shift; loom_coordination_authorize "$@" ;;
        --internal) shift; _loom_coord_handle "$@" ;;
        --authorize-internal) shift; _loom_coord_authorize "$@" ;;
        *) printf 'usage: coordination.sh handle CONTEXT REQUEST | serve CONTEXT | authorize CONTEXT PLAN\n' >&2; exit 2 ;;
    esac
fi
