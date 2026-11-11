#!/usr/bin/env bash
# Cooperative boundary only. No stdin injection, wake loop, reverse connection,
# policy mutation or task completion. All presentation is escaped JSON data.
# shellcheck disable=SC2015,SC2016,SC2154 # Native loader supplies _nn_* context.
_loom_bridge_modules() {
    local ops
    ops=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P) || return 2
    # shellcheck source=/dev/null
    source "$ops/mail.sh" || return 2
    _loom_mail_modules || return 2
    # shellcheck source=/dev/null
    source "${LOOM_MAIL_NATIVE_MODULE:-$ops/native.sh}" || return 2
    _loom_native_load
}
_loom_bridge_context() {
    _loom_native_context "$1" && _loom_native_policy_check || return 2
    _wb_id=mail-$(jq -cS '{actor,target}' "$_nn_binding" | git hash-object --stdin)
    loom_state_replay > "$_wb_tmp/store" || return $?
    [[ $(jq -r .store_id "$_wb_tmp/store") == "$_nn_store" ]] || return 2
    if ! loom_state_get host "$_wb_id" > "$_wb_tmp/old" 2>/dev/null; then
        printf 'null\n' > "$_wb_tmp/old"
        jq -cn --slurpfile b "$_nn_binding" '{schema:1,binding:$b[0],directory:null,deliveries:{},outbox:{}}' > "$_wb_tmp/data"
    else jq -c .data "$_wb_tmp/old" > "$_wb_tmp/data"; fi
    jq -e --slurpfile b "$_nn_binding" '(.binding|del(.stop_authorized,.release_authorized))==($b[0]|del(.stop_authorized,.release_authorized))' "$_wb_tmp/data" >/dev/null
}
_loom_bridge_commit() {
    local request=$1 digest=$2 opid
    opid=bridge-$(jq -cS '[.actor,.target,.operation_id]' "$request" | git hash-object --stdin)
    # One bounded host aggregate serializes competing consumers. It never writes
    # an authority run, task, gate, or assignment entity.
    (( $(wc -c < "$_wb_tmp/data")<=524288 )) || return 2
    jq -cnS --slurpfile q "$request" --slurpfile old "$_wb_tmp/old" --slurpfile data "$_wb_tmp/data" \
      --slurpfile result "$_wb_tmp/result" --arg store "$_nn_store" --arg id "$_wb_id" --arg digest "$digest" --arg opid "$opid" '
      $q[0] as $q | {schema:2,store_id:$store,operation_id:$opid,idempotency_key:$q.idempotency_key,op:($q.op+".spool"),
      actor:{id:$q.actor.id,run_id:null,epoch:0},target:$q.target,checks:[],
      changes:[{kind:"host",id:$id,expected_revision:($old[0].revision//null),run_id:null,epoch:0,data:$data[0]}],
      events:[{type:($q.op+".spool"),entity_ids:[$id],payload:{wire_digest:$digest},observed_at:null}],result:{wire_digest:$digest,response:$result[0]}}' > "$_wb_tmp/tx" || return 2
    loom_state_transact "$_wb_tmp/tx" > "$_wb_tmp/outcome"
}
_loom_bridge_wire_digest() { jq -cS 'del(.request_id,.timeout_ms)' "$1" | loom_policy_scope; }
_loom_bridge_response() {
    _loom_mail_response "$1" "$_wb_tmp/result" true |
      jq -c --slurpfile d "$_wb_tmp/data" '
        ($d[0].outbox[.result.message_id//""]//null) as $out |
        if $out!=null then
          .status=(if $out.authority_sync=="committed" then "completed" else "pending" end) |
          .extensions["loom.mail.origin"]={authority_sync:$out.authority_sync,
            next_action:(if $out.authority_sync=="committed" then "none" else "pump" end),
            directory_revision:($d[0].directory.revision//null)}
        else . end'
}
_loom_bridge_handle() (
    umask 077
    local context=$1 request=$2 _wb_tmp _wb_id op digest prior rc=0 now token id expiry
    _wb_tmp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$_wb_tmp"' EXIT
    _loom_bridge_modules || return 2
    loom_protocol_check_request "$request" || return 2
    _loom_bridge_context "$context" || { loom_protocol_receipt "$request" refused identity_mismatch 'Native spool binding refused'; return 2; }
    jq -e --slurpfile b "$_nn_binding" '.protocol=="loom.coordination" and .actor==$b[0].actor and .target==$b[0].target and (.extensions|length)==0' "$request" >/dev/null || { loom_protocol_receipt "$request" refused actor_denied 'Bridge requires exact attempt binding'; return 2; }
    op=$(jq -r .op "$request"); digest=$(_loom_bridge_wire_digest "$request")
    if [[ $op != mail.poll && $op != mail.status ]]; then
        if prior=$(loom_state_operation "$(jq -r .actor.id "$request")" "$op.spool" "$(jq -r .idempotency_key "$request")" 2>/dev/null); then
            [[ $(jq -r .outcome.result.wire_digest <<< "$prior") == "$digest" ]] || { loom_protocol_receipt "$request" refused idempotency_conflict 'Same key has different content'; return 2; }
            jq -c .outcome.result.response <<< "$prior" > "$_wb_tmp/result"
            _loom_bridge_response "$request"
            return 0
        fi
    fi
    now=$(_loom_mail_now)
    token=$(cat /proc/sys/kernel/random/uuid)
    expiry=$(date -u -d "@$(( (now+$(jq '.args.lease_ms//30000' "$request")+999)/1000 ))" +%Y-%m-%dT%H:%M:%SZ)
    jq -c --slurpfile q "$request" --argjson now "$now" --arg token "$token" --arg expiry "$expiry" '
      def need($p;$e): if $p then . else error($e) end;
      def scope($r;$d): $r==("attempt:"+$d.binding.target.attempt_id) or ($d.directory!=null and $r==("task:"+$d.directory.task_id));
      $q[0] as $q | . as $d | $q.args.delivery_id as $id |
      if $q.op=="mail.poll" then
        need(scope($q.args.mailbox;$d);"mailbox_denied") |
        [.deliveries[]|.delivery|select(.recipient==$q.args.mailbox or $q.args.mailbox==("attempt:"+.attempt_id))|select(.delivery_id>($q.args.after_cursor//""))]|sort_by(.delivery_id)|.[:$q.args.limit] |
        {data:$d,result:{items:.,next_cursor:(if length==$q.args.limit then .[-1].delivery_id else null end)}}
      elif $q.op=="mail.status" then
        {data:$d,result:{message_id:$q.args.message_id,deliveries:[$d.deliveries[]|.delivery|select(.message_id==$q.args.message_id)]}}
      elif $q.op=="mail.send" or $q.op=="mail.reply" then
        need($q.op!="mail.send" or ($q.args.from==$d.binding.actor.id and $q.args.in_reply_to==null);"actor_mismatch") |
        need($q.op!="mail.reply" or any(.deliveries[];.message.message_id==$q.args.question_id and .message.kind=="question");"unknown_question") |
        # Remote send never asserts recipient acceptance, even for snapshot entries.
        ($q.args.message_id) as $mid |
        need(.outbox[$mid]==null or (.outbox[$mid].request.args==($q.args|if $q.op=="mail.reply" then .ack_claim_token=null else . end) and .outbox[$mid].request.op==$q.op);"idempotency_conflict") |
        if $q.op=="mail.reply" and $q.args.ack_claim_token!=null then
          [.deliveries|to_entries[]|select(.value.message.message_id==$q.args.question_id and .value.claim.token==$q.args.ack_claim_token and .value.claim.until_ms>$now)] as $claims |
          need(($claims|length)==1;"claim_expired") |
          $claims[0].key as $cid | .deliveries[$cid].facts.acked=true |
          .deliveries[$cid].delivery.revision+=1 | .deliveries[$cid].delivery.state="acked" |
          .deliveries[$cid].delivery.authority_sync="ack_pending_sync" | .deliveries[$cid].delivery.next_action="reconcile"
        else . end |
        if .outbox[$mid]==null then .outbox[$mid]={request:($q|if .op=="mail.reply" then .args.ack_claim_token=null else . end),authority_sync:"queued_for_authority"} else . end |
        {data:.,result:{message_id:$mid,deliveries:[]}}
      elif ($q.op|IN("mail.claim","mail.read","mail.ack")) then
        .deliveries[$id] as $entry | need($entry!=null;"unknown_delivery") |
        need($entry.delivery.revision==$q.expected_revision;"revision_conflict") |
        need($entry.delivery.attempt_id==$d.binding.target.attempt_id;"identity_mismatch") |
        need($entry.message.expires_at==null or ($entry.message.expires_at|fromdateiso8601)*1000>$now;"message_expired") |
        if $q.op=="mail.claim" then
          need(scope($q.args.mailbox;$d) and ($entry.delivery.recipient==$q.args.mailbox or $q.args.mailbox==("attempt:"+$entry.delivery.attempt_id));"mailbox_denied") |
          need(($entry.delivery.state|IN("acked","dead_letter")|not);"settled_delivery") |
          need(if $q.args.claim_token==null then ($entry.claim.until_ms//0)<=$now else $entry.claim.token==$q.args.claim_token and $entry.claim.until_ms>$now end;"claim_busy") |
          .deliveries[$id].claim={token:($q.args.claim_token//$token),until_ms:($now+$q.args.lease_ms)} |
          .deliveries[$id].delivery.revision+=1 | .deliveries[$id].delivery.next_action="read" |
          {data:.,result:{delivery:.deliveries[$id].delivery,claim_token:.deliveries[$id].claim.token,expires_at:$expiry}}
        else
          need($entry.claim!=null and $entry.claim.token==$q.args.claim_token and $entry.claim.until_ms>$now;"claim_expired") |
          need($q.op!="mail.ack" or $q.args.message_digest==$entry.delivery.message_digest;"digest_mismatch") |
          need($q.op!="mail.read" or $entry.delivery.state!="acked";"already_acked") |
          .deliveries[$id].delivery.revision+=1 |
          if $q.op=="mail.read" then
            .deliveries[$id].delivery.state="read" | .deliveries[$id].delivery.next_action="ack" |
            .deliveries[$id].delivery.authority_sync="queued_for_authority" |
            .deliveries[$id].facts.read=true |
            {data:.,result:{delivery:.deliveries[$id].delivery,message:$entry.message}}
          else
            .deliveries[$id].delivery.state="acked" | .deliveries[$id].delivery.authority_sync="ack_pending_sync" |
            .deliveries[$id].delivery.next_action="reconcile" | .deliveries[$id].facts.acked=true |
            {data:.,result:.deliveries[$id].delivery}
          end
        end
      else error("unsupported_operation") end' "$_wb_tmp/data" > "$_wb_tmp/plan" || rc=2
    if (( rc==2 )); then
        loom_protocol_receipt "$request" refused mail_refused 'Bridge claim, revision or message precondition refused'; return 2
    fi
    if (( rc==0 )); then
        jq .data "$_wb_tmp/plan" > "$_wb_tmp/data"; jq .result "$_wb_tmp/plan" > "$_wb_tmp/result"
        if [[ $op == mail.send || $op == mail.reply ]]; then
            id=$(jq -r .args.message_id "$request")
            jq --arg id "$id" '.outbox[$id].request' "$_wb_tmp/data" > "$_wb_tmp/outbound"
            jq --arg id "$id" --arg digest "$(_loom_bridge_wire_digest "$_wb_tmp/outbound")" '.outbox[$id].request_digest=$digest' "$_wb_tmp/data" > "$_wb_tmp/hashed"
            mv "$_wb_tmp/hashed" "$_wb_tmp/data"
        fi
        if [[ $op != mail.poll && $op != mail.status ]]; then _loom_bridge_commit "$request" "$digest" || rc=$?; fi
    fi
    if (( rc!=0 )); then
        loom_protocol_receipt "$request" unknown outcome_unknown 'Spool conflict or uncertain write; reconcile identical operation'; return 1
    fi
    _loom_bridge_response "$request" > "$_wb_tmp/response"
    loom_protocol_validate response "$_wb_tmp/response" "$request" || return 1
    cat "$_wb_tmp/response"
)

# Authenticated S5 helper calls this only after its installation/context pin check.
# The worker-facing handler above never accepts this extension/import path.
loom_worker_bridge_exchange() (
    umask 077
    local context=$1 request=$2 _wb_tmp _wb_id digest prior rc=0
    _wb_tmp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$_wb_tmp"' EXIT
    _loom_bridge_modules || return 2
    loom_protocol_check_request "$request" || return 2
    _loom_bridge_context "$context" || return 2
    jq -e --slurpfile b "$_nn_binding" '
      .protocol=="loom.coordination" and .op=="mail.pump" and .actor==$b[0].actor and .target==$b[0].target and .args.run_id==.actor.run_id and
      (.extensions|keys)==["loom.mail.exchange"] and
      (.extensions["loom.mail.exchange"]|keys==["confirm","deliveries","directory","outbox_confirm"] and
        (.deliveries|type=="array" and length<=1) and
        (.confirm|type=="array" and length<=100 and all(.[];keys==["acked","delivery_id","message_digest"] and (.acked|type=="boolean"))) and
        (.outbox_confirm|type=="array" and length<=100 and all(.[];keys==["authority_sync","message_id","request_digest"] and .authority_sync=="committed" and (.request_digest|test("^git-blob-sha1-v1:[0-9a-f]{40}$")))) and
        (.directory|keys==["addresses","epoch","revision","task_id"] and (.addresses|type=="array" and length<=200 and all(.[];type=="string" and test("^(run|task|attempt):.+$"))) and
          (.task_id|type=="string" and length>0 and utf8bytelength<=128) and all(.epoch,.revision;type=="number" and .==floor and .>=0)))' "$request" >/dev/null || return 2
    digest=$(_loom_bridge_wire_digest "$request")
    if prior=$(loom_state_operation "$(jq -r .actor.id "$request")" mail.pump.spool "$(jq -r .idempotency_key "$request")" 2>/dev/null); then
        [[ $(jq -r .outcome.result.wire_digest <<< "$prior") == "$digest" ]] || return 2
        # Replay never rotates again or reimports; facts can still advance.
        jq -c '.outcome.result.response' <<< "$prior" > "$_wb_tmp/result"
    else
        # Full message shape is validated as an S1 mail.send request below.
        jq -c '.extensions["loom.mail.exchange"].deliveries[]' "$request" > "$_wb_tmp/intents"
        while IFS= read -r intent; do
            jq -cn --slurpfile q "$request" --argjson intent "$intent" '$q[0] | .op="mail.send" | .expected_revision=null | .args=$intent.message | .extensions={}' > "$_wb_tmp/message-request"
            loom_protocol_validate request "$_wb_tmp/message-request" || return 2
            jq -cn --argjson intent "$intent" '{deliveries:[$intent.delivery],next_cursor:null,deadline_reached:false}' > "$_wb_tmp/intake-result"
            _loom_mail_response "$request" "$_wb_tmp/intake-result" true > "$_wb_tmp/intake-response"
            loom_protocol_validate response "$_wb_tmp/intake-response" "$request" || return 2
            [[ $(jq -cS .message <<< "$intent" | loom_policy_scope) == "$(jq -r .delivery.message_digest <<< "$intent")" ]] || return 2
            jq -e --slurpfile b "$_nn_binding" 'keys==["delivery","message","return_address"] and (.return_address|type=="string" and test("^(run|attempt):.+$")) and .delivery.attempt_id==$b[0].target.attempt_id and .delivery.message_id==.message.message_id and (.delivery.recipient as $r | .message.to|index($r))!=null' <<< "$intent" >/dev/null || return 2
        done < "$_wb_tmp/intents"
        jq -c --slurpfile q "$request" '
          def need($p;$e): if $p then . else error($e) end;
          $q[0].extensions["loom.mail.exchange"] as $x |
          need($x.directory.epoch==.binding.actor.epoch;"epoch_mismatch") |
          need(.directory==null or $x.directory.revision>=.directory.revision;"directory_stale") |
          .directory=$x.directory |
          reduce $x.deliveries[] as $i (.;
            $i.delivery.delivery_id as $id |
            need(($i.delivery|keys)==["attempt_id","authority_sync","delivery_id","message_digest","message_id","next_action","reason","recipient","revision","state"];"invalid_delivery") |
            need($i.delivery.recipient==("attempt:"+.binding.target.attempt_id) or $i.delivery.recipient==("task:"+.directory.task_id);"recipient_mismatch") |
            need(.deliveries[$id]==null or .deliveries[$id].intent==$i;"idempotency_conflict") |
            if .deliveries[$id]==null then .deliveries[$id]={intent:$i,message:$i.message,return_address:$i.return_address,delivery:($i.delivery|.state="delivered"|.next_action="claim"|.authority_sync="queued_for_authority"),claim:null,facts:{delivered:true,read:false,acked:false}} else . end) |
          reduce $x.confirm[] as $c (.;
            need(.deliveries[$c.delivery_id].delivery.message_digest==$c.message_digest;"digest_mismatch") |
            if .deliveries[$c.delivery_id].facts.acked and $c.acked then .deliveries[$c.delivery_id].delivery.authority_sync="committed" | .deliveries[$c.delivery_id].delivery.next_action="none" else . end) |
          reduce $x.outbox_confirm[] as $c (.;
            need(.outbox[$c.message_id]!=null and .outbox[$c.message_id].request_digest==$c.request_digest;"outbox_digest_mismatch") |
            .outbox[$c.message_id].authority_sync=$c.authority_sync)
        ' "$_wb_tmp/data" > "$_wb_tmp/new" || return 2
        mv "$_wb_tmp/new" "$_wb_tmp/data"
        jq -e '(.deliveries|length)<=100 and (.outbox|length)<=100' "$_wb_tmp/data" >/dev/null || return 2
        # Rotate only for a new durable exchange. Rejected entries remain queued
        # as evidence, but cannot monopolize the one-entry transport window.
        jq -c '
          .outbox_after as $after |
          [.outbox|to_entries[]|select(.value.authority_sync=="queued_for_authority")]|sort_by(.key) |
          (map(select(.key>($after//"")))+map(select(.key<=($after//""))))|.[:1] |
          {outbox:map(.value|{request,request_digest}),outbox_after:(.[0].key//$after)}
        ' "$_wb_tmp/data" > "$_wb_tmp/result" || return 2
        jq --slurpfile r "$_wb_tmp/result" '.outbox_after=$r[0].outbox_after' "$_wb_tmp/data" > "$_wb_tmp/new" || return 2
        mv "$_wb_tmp/new" "$_wb_tmp/data"
        _loom_bridge_commit "$request" "$digest" || rc=$?
        if (( rc!=0 )); then loom_protocol_receipt "$request" unknown outcome_unknown 'Spool CAS or write uncertain; replay same exchange'; return 1; fi
    fi
    cp "$_wb_tmp/result" "$_wb_tmp/selection"
    jq -c '{deliveries:[.deliveries[]|.delivery],next_cursor:null,deadline_reached:false}' "$_wb_tmp/data" > "$_wb_tmp/result"
    _loom_mail_response "$request" "$_wb_tmp/result" true |
      jq -c --slurpfile d "$_wb_tmp/data" --slurpfile selected "$_wb_tmp/selection" '.extensions["loom.mail.exchange"]={receipts:[$d[0].deliveries[]|{delivery_id:.delivery.delivery_id,message_digest:.delivery.message_digest,attempt_id:.delivery.attempt_id,facts}],outbox:($selected[0].outbox//[])}'
)

loom_worker_bridge_handle() (
    [[ $# == 2 ]] || return 2
    _loom_bridge_modules || return 2
    loom_policy_json "$1" || return 2
    if [[ $(jq -r '.role//""' "$1") == worker ]]; then loom_mail_handle "$@"
    else
        local ops temp rc=0
        umask 077
        loom_protocol_check_request "$2" || return 2
        ops=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
        temp=$(mktemp -d) || return 1
        trap 'rm -rf -- "$temp"' EXIT
        timeout --kill-after=1 "$(jq '.timeout_ms/1000' "$2")" bash "$ops/worker-bridge.sh" --internal "$1" "$2" > "$temp/response" || rc=$?
        if (( rc==124 || rc==137 )); then loom_protocol_receipt "$2" unknown outcome_unknown 'Bridge deadline; replay identical operation'; return 1; fi
        cat "$temp/response"; return "$rc"
    fi
)
_loom_bridge_request() {
    local op=$1 args=$2 revision=$3 binding=$4 id
    id=boundary-$(cat /proc/sys/kernel/random/uuid)
    jq -cn --arg op "$op" --argjson args "$args" --argjson revision "$revision" --slurpfile b "$binding" --arg id "$id" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:$id,operation_id:(if $op=="mail.poll" then null else $id end),idempotency_key:(if $op=="mail.poll" then null else $id end),op:$op,actor:$b[0].actor,target:$b[0].target,expected_revision:$revision,timeout_ms:30000,args:$args,extensions:{}}'
}
loom_worker_bridge_boundary() (
    [[ $# == 2 && $2 =~ ^[0-9]+$ ]] && (( $2>=1 && $2<=20 )) || return 2
    umask 077
    local context=$1 limit=$2 temp binding mailbox id revision count=0 task cursor pages=0
    _loom_bridge_modules || return 2
    loom_policy_json "$context" || return 2
    binding=$(jq -r .binding "$context")
    loom_policy_json "$binding" || return 2
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    : > "$temp/messages"
    mailbox=attempt:$(jq -r .target.attempt_id "$binding")
    # Task mail is polled separately on authority deployments. Remote intake has
    # already assigned task deliveries to the exact attempt under the store CAS.
    printf '%s\n' "$mailbox" > "$temp/mailboxes"
    if [[ $(jq -r '.role//""' "$context") == worker ]]; then
        LOOM_STATE=$(jq -r .state_root "$context") loom_state_get run "$(jq -r .actor.run_id "$binding")" > "$temp/run" || return $?
        task=$(jq -r --slurpfile b "$binding" '.data.attempts[$b[0].target.attempt_id].task_id' "$temp/run")
        printf 'task:%s\n' "$task" >> "$temp/mailboxes"
    fi
    while IFS= read -r mailbox; do
        cursor=''
        while (( count<limit && pages<41 )); do
        pages=$((pages+1))
        _loom_bridge_request mail.poll "$(jq -cn --arg m "$mailbox" --arg cursor "$cursor" '{mailbox:$m,after_cursor:(if $cursor=="" then null else $cursor end),limit:100}')" null "$binding" > "$temp/poll"
        loom_worker_bridge_handle "$context" "$temp/poll" > "$temp/polled" || return $?
        while IFS= read -r id; do
            (( count<limit )) || break
            revision=$(jq --arg id "$id" '.result.items[]|select(.delivery_id==$id)|.revision' "$temp/polled")
            _loom_bridge_request mail.claim "$(jq -cn --arg m "$mailbox" --arg id "$id" '{mailbox:$m,delivery_id:$id,lease_ms:30000,claim_token:null}')" "$revision" "$binding" > "$temp/claim"
            if ! loom_worker_bridge_handle "$context" "$temp/claim" > "$temp/claimed"; then continue; fi
            _loom_bridge_request mail.read "$(jq -c '{delivery_id:.result.delivery.delivery_id,claim_token:.result.claim_token}' "$temp/claimed")" "$(jq .result.delivery.revision "$temp/claimed")" "$binding" > "$temp/read"
            loom_worker_bridge_handle "$context" "$temp/read" > "$temp/read-result" || return $?
            jq -c --slurpfile c "$temp/claimed" '{external:true,delivery:.result.delivery,message:.result.message,claim_token:$c[0].result.claim_token}' "$temp/read-result" >> "$temp/messages"
            count=$((count+1))
        done < <(jq -r '.result.items[]|select(.state!="acked" and .state!="dead_letter")|.delivery_id' "$temp/polled")
        cursor=$(jq -r '.result.next_cursor//""' "$temp/polled")
        [[ -n $cursor ]] || break
        done
    done < "$temp/mailboxes"
    jq -cn --slurpfile messages "$temp/messages" '{delivery_mode:"next_boundary",wake:"unsupported",messages:$messages}'
)
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        handle) shift; loom_worker_bridge_handle "$@" ;;
        boundary) shift; loom_worker_bridge_boundary "$@" ;;
        exchange) shift; loom_worker_bridge_exchange "$@" ;;
        --internal) shift; _loom_bridge_handle "$@" ;;
        *) printf 'usage: worker-bridge.sh handle CONTEXT REQUEST | boundary CONTEXT LIMIT | exchange NATIVE_CONTEXT REQUEST\n' >&2; exit 2 ;;
    esac
fi
