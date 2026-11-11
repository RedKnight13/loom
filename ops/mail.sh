#!/usr/bin/env bash
# Source-safe native authority. Dependencies are loaded only inside API calls.
# shellcheck disable=SC2015,SC2016,SC2030,SC2031 # Deliberate guards and literal jq programs.

_loom_mail_modules() {
    local ops
    ops=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P) || return 2
    # shellcheck source=/dev/null
    source "${LOOM_MAIL_PROTOCOL_MODULE:-$ops/protocol.sh}" || return 2
    # shellcheck source=/dev/null
    source "${LOOM_MAIL_STATE_MODULE:-$ops/state.sh}" || return 2
    # shellcheck source=/dev/null
    source "${LOOM_MAIL_POLICY_MODULE:-$ops/policy.sh}" || return 2
}
_loom_mail_error() { _lm_code=$1; printf '%s\n' "$1" >&2; return 2; }
_loom_mail_hash() { git hash-object --stdin; }
_loom_mail_now() { date +%s%3N; }
_loom_mail_context() {
    local context=$1 request=$2
    loom_policy_json "$context" && [[ $(stat -c %a "$context") == 600 ]] || return 2
    jq -e '
      def id: type=="string" and utf8bytelength>0 and utf8bytelength<=128;
      keys==["actor","binding","commands","role","routes","schema","state_root","store_id"] and
      .schema==1 and (.store_id|id) and (.state_root|type=="string") and
      (.role|IN("owner","worker")) and (.actor|keys==["epoch","id","run_id"] and (.id|id) and (.run_id|id)) and
      (.commands|type=="array" and all(.[];type=="string" and startswith("mail."))) and
      (.routes|type=="array" and length<=80 and all(.[];keys==["attempt_id","config"] and (.attempt_id|id) and (.config|type=="string"))) and
      (if .role=="owner" then .binding==null else (.binding|type=="string") end)
    ' "$context" >/dev/null || return 2
    export LOOM_STATE
    LOOM_STATE=$(jq -r .state_root "$context")
    loom_state_replay > "$_lm_tmp/store" || return $?
    [[ $(jq -r .store_id "$_lm_tmp/store") == "$(jq -r .store_id "$context")" ]] || return 2
    loom_state_get run "$(jq -r .actor.run_id "$context")" > "$_lm_tmp/run" || return $?
    printf 'null\n' > "$_lm_tmp/binding"
    if [[ $(jq -r .role "$context") == worker ]]; then
        loom_policy_json "$(jq -r .binding "$context")" || return 2
        cp -- "$(jq -r .binding "$context")" "$_lm_tmp/binding" || return 1
    fi
    jq -e --slurpfile c "$context" --slurpfile b "$_lm_tmp/binding" --slurpfile q "$request" '
      $c[0] as $c | $q[0] as $q | $b[0] as $b |
      .epoch==$c.actor.epoch and .run_id==$c.actor.run_id and .data.run.run_id==.run_id and
      $q.actor==$c.actor and ($c.commands|index($q.op))!=null and
      (if $c.role=="owner" then .data.owner_id==$c.actor.id and $q.target=={assignment_id:null,attempt_id:null,host_id:null}
       else .data.attempts[$b.target.attempt_id] as $a |
        $a!=null and $a.launch_authorized==true and $a.epoch==.epoch and
        ($a.binding|del(.stop_authorized,.release_authorized))==($b|del(.stop_authorized,.release_authorized)) and
        $b.actor==$c.actor and $q.target==$b.target end)
    ' "$_lm_tmp/run" >/dev/null || _loom_mail_error owner_fenced
}
_loom_mail_observation() {
    jq -c --argjson now "$(_loom_mail_now)" '.data | {delivery_id:.delivery.delivery_id,
      age_ms:([$now-(.created_ms//$now),0]|max),expires_at:(.expires_at//null),
      next_attempt_ms:(.next_attempt_ms//null),failed_attempts:(.tries//0),
      claim_expires_ms:(.claim.until_ms//null)}' "$1" >> "$_lm_tmp/observations"
}
_loom_mail_view() {
    _loom_mail_observation "$1" || return 2
    jq -c '.data.delivery | {delivery_id,message_id,message_digest,recipient,attempt_id,revision,state,authority_sync,next_action,reason}' "$1"
}
_loom_mail_response() {
    jq -cn --slurpfile q "$1" --slurpfile r "$2" --argjson durable "$3" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      $q[0] as $q | {protocol:$q.protocol,version:$q.version,request_id:$q.request_id,operation_id:$q.operation_id,
      op:$q.op,target:$q.target,ok:true,status:(if $q.op=="mail.send" or $q.op=="mail.reply" then "accepted" else "completed" end),
      revision:($r[0].revision//$r[0].delivery.revision//null),durable:$durable,result:$r[0],error:null,effects:[],evidence:[],observed_at:$now,
      extensions:{"loom.mail.delivery":{delivery_mode:"next_boundary",wake:"unsupported"}}}'
}
_loom_mail_digest() {
    jq -cS --slurpfile c "$_lm_context" '{request:del(.request_id,.timeout_ms),role:$c[0].role}' "$1" | loom_policy_scope
}
_loom_mail_replay() {
    local prior
    prior=$(loom_state_operation "$(jq -r .actor.id "$_lm_request")" "$(jq -r .op "$_lm_request")" "$_lm_key" 2>/dev/null) || return 3
    [[ $(jq -r .outcome.result.wire_digest <<< "$prior") == "$_lm_digest" ]] || { _loom_mail_error idempotency_conflict; return 2; }
    jq -c .outcome.result.response <<< "$prior" > "$_lm_tmp/result"
}
# Every write checks the S6 aggregate revision under the real S2 lock. Mail does
# not replace graph projections or derive task/gate transitions from a payload.
_loom_mail_commit() {
    jq -cnS --slurpfile c "$_lm_context" --slurpfile q "$_lm_request" --slurpfile run "$_lm_tmp/run" \
      --slurpfile changes "$_lm_tmp/changes" --slurpfile result "$_lm_tmp/result" --arg key "$_lm_key" --arg digest "$_lm_digest" '
      $q[0] as $q | {schema:2,store_id:$c[0].store_id,operation_id:$q.operation_id,idempotency_key:$key,op:$q.op,
        actor:$q.actor,target:$q.target,checks:[{kind:"run",id:$run[0].id,revision:$run[0].revision}],changes:$changes[0],
        events:[{type:$q.op,entity_ids:[$changes[0][].id],payload:{wire_digest:$digest},observed_at:null}],
        result:{wire_digest:$digest,response:$result[0]}}' > "$_lm_tmp/transaction" || return 2
    loom_state_transact "$_lm_tmp/transaction" > "$_lm_tmp/outcome" || return $?
    jq -c .result.response "$_lm_tmp/outcome" > "$_lm_tmp/result"
}
_loom_mail_change() {
    jq -cn --slurpfile q "$_lm_request" --slurpfile old "$1" --slurpfile data "$2" --arg kind "$3" --arg id "$4" '
      {kind:$kind,id:$id,expected_revision:($old[0].revision//null),run_id:$q[0].actor.run_id,epoch:$q[0].actor.epoch,data:$data[0]}' >> "$_lm_tmp/change-lines"
}
_loom_mail_known() {
    jq -e --arg addr "$1" '
      ($addr|index(":")) as $n | ($addr[:$n]) as $kind | ($addr[$n+1:]) as $id |
      if $kind=="run" then .id==$id elif $kind=="task" then .data.tasks[$id]!=null
      elif $kind=="attempt" then .data.attempts[$id]!=null else false end' "$_lm_tmp/run" >/dev/null || _loom_mail_error unknown_recipient
}
_loom_mail_scope() {
    # A worker may inspect its exact attempt and its task, never a previous or
    # sibling attempt. Task claiming additionally requires the latest attempt.
    local recipient=$1 attempt=${2:-null}
    [[ $(jq -r .role "$_lm_context") != worker ]] ||
      jq -e --slurpfile b "$_lm_tmp/binding" --arg addr "$recipient" --arg attempt "$attempt" '
        $b[0].target.attempt_id as $id | .data.attempts[$id] as $a |
        ($addr==("attempt:"+$id) or ($addr==("task:"+$a.task_id) and .data.tasks[$a.task_id].attempt_ids[-1]==$id)) and
        ($attempt=="null" or $attempt==$id)
      ' "$_lm_tmp/run" >/dev/null || _loom_mail_error mailbox_denied
}
_loom_mail_status() {
    local message=$1 id
    loom_state_get message "$message" > "$_lm_tmp/message-record" || return $?
    [[ $(jq -r .run_id "$_lm_tmp/message-record") == "$(jq -r .actor.run_id "$_lm_request")" ]] || return 2
    : > "$_lm_tmp/views"
    while IFS= read -r id; do
        loom_state_get delivery "$id" > "$_lm_tmp/d" || return $?
        if _loom_mail_scope "$(jq -r .data.delivery.recipient "$_lm_tmp/d")" "$(jq -r .data.delivery.attempt_id "$_lm_tmp/d")" 2>/dev/null ||
          [[ $(jq -r .data.return_address "$_lm_tmp/message-record") == "attempt:$(jq -r .target.attempt_id "$_lm_tmp/binding")" ]]; then
            _loom_mail_view "$_lm_tmp/d" >> "$_lm_tmp/views"
        fi
    done < <(jq -r '.data.delivery_ids[]' "$_lm_tmp/message-record")
    jq -cn --arg id "$message" --slurpfile ds "$_lm_tmp/views" '{message_id:$id,deliveries:$ds}' > "$_lm_tmp/result"
}
_loom_mail_send() {
    local recipient id mid digest return_address existing=false
    if [[ $(jq -r .op "$_lm_request") == mail.reply ]]; then
        loom_state_get message "$(jq -r .args.question_id "$_lm_request")" > "$_lm_tmp/question" || return $?
        [[ $(jq -r .data.message.kind "$_lm_tmp/question") == question && $(jq -r .run_id "$_lm_tmp/question") == "$(jq -r .actor.run_id "$_lm_request")" ]] || return 2
        local received=false
        while IFS= read -r recipient; do
            if _loom_mail_scope "$recipient" 2>/dev/null; then received=true; fi
        done < <(jq -r '.data.message.to[]' "$_lm_tmp/question")
        [[ $received == true ]] || return 2
        jq -cn --slurpfile q "$_lm_request" --slurpfile m "$_lm_tmp/question" '{message_id:$q[0].args.message_id,from:$q[0].actor.id,to:[$m[0].data.return_address],kind:"reply",subject:$m[0].data.message.subject,body:$q[0].args.body,thread_id:($m[0].data.message.thread_id//$m[0].id),in_reply_to:$m[0].id,expires_at:null}' > "$_lm_tmp/message"
    else
        jq -c .args "$_lm_request" > "$_lm_tmp/message"
        [[ $(jq -r .from "$_lm_tmp/message") == "$(jq -r .actor.id "$_lm_request")" ]] || { _loom_mail_error actor_mismatch; return 2; }
        [[ $(jq -r .in_reply_to "$_lm_tmp/message") == null ]] || { _loom_mail_error use_reply; return 2; }
    fi
    while IFS= read -r recipient; do _loom_mail_known "$recipient" || return $?; done < <(jq -r '.to[]' "$_lm_tmp/message")
    mid=$(jq -r .message_id "$_lm_tmp/message")
    digest=$(jq -cS . "$_lm_tmp/message" | loom_policy_scope)
    if [[ $(jq -r .role "$_lm_context") == owner ]]; then return_address=run:$(jq -r .actor.run_id "$_lm_request")
    else return_address=attempt:$(jq -r .target.attempt_id "$_lm_tmp/binding"); fi
    printf 'null\n' > "$_lm_tmp/old"
    if loom_state_get message "$mid" > "$_lm_tmp/existing" 2>/dev/null; then
        jq -e --arg digest "$digest" --arg address "$return_address" --slurpfile q "$_lm_request" '.run_id==$q[0].actor.run_id and .data.digest==$digest and .data.return_address==$address' "$_lm_tmp/existing" >/dev/null || { _loom_mail_error idempotency_conflict; return 2; }
        existing=true
        _loom_mail_status "$mid" || return $?
    else
        # S2 has a 100-change bound; reserve space for the message and optional ack.
        (( $(jq '.to|length' "$_lm_tmp/message")<=98 )) || { _loom_mail_error quota_exceeded; return 2; }
        : > "$_lm_tmp/views"
        while IFS= read -r recipient; do
            id=delivery-$(jq -cn --arg run "$(jq -r .actor.run_id "$_lm_request")" --arg mid "$mid" --arg to "$recipient" '[$run,$mid,$to]' | _loom_mail_hash)
            jq -cn --arg id "$id" --arg mid "$mid" --arg digest "$digest" --arg to "$recipient" --argjson now "$(_loom_mail_now)" --slurpfile m "$_lm_tmp/message" '{expires_at:$m[0].expires_at,delivery:{delivery_id:$id,message_id:$mid,message_digest:$digest,recipient:$to,attempt_id:(if $to|startswith("attempt:") then $to[8:] else null end),revision:1,state:"pending",authority_sync:"committed",next_action:"claim",reason:null},claim:null,facts:{delivered:false,read:false,acked:false},tries:0,next_attempt_ms:$now,created_ms:$now,remote:null}' > "$_lm_tmp/data"
            _loom_mail_change "$_lm_tmp/old" "$_lm_tmp/data" delivery "$id" || return $?
            jq -c .delivery "$_lm_tmp/data" >> "$_lm_tmp/views"
        done < <(jq -r '.to[]' "$_lm_tmp/message")
        jq -cn --slurpfile m "$_lm_tmp/message" --slurpfile ds "$_lm_tmp/views" --arg digest "$digest" --arg address "$return_address" '{message:$m[0],digest:$digest,return_address:$address,delivery_ids:[$ds[].delivery_id]}' > "$_lm_tmp/data"
        _loom_mail_change "$_lm_tmp/old" "$_lm_tmp/data" message "$mid" || return $?
        jq -cn --arg mid "$mid" --slurpfile ds "$_lm_tmp/views" '{message_id:$mid,deliveries:$ds}' > "$_lm_tmp/result"
    fi
    # Optional question ack is a distinct fact in the same atomic transaction.
    if [[ $(jq -r '.args.ack_claim_token//""' "$_lm_request") != '' ]]; then
        local token did
        token=$(jq -r .args.ack_claim_token "$_lm_request")
        did=''
        while IFS= read -r id; do
            loom_state_get delivery "$id" > "$_lm_tmp/d" || return $?
            if [[ $(jq -r '.data.claim.token//""' "$_lm_tmp/d") == "$token" ]]; then did=$id; break; fi
        done < <(jq -r '.data.delivery_ids[]' "$_lm_tmp/question")
        [[ -n $did ]] || return 2
        _loom_mail_check_claim "$_lm_tmp/d" "$token" || return $?
        jq '.data | .delivery.revision+=1 | .delivery.state="acked" | .delivery.next_action="none" | .facts.acked=true' "$_lm_tmp/d" > "$_lm_tmp/data"
        _loom_mail_change "$_lm_tmp/d" "$_lm_tmp/data" delivery "$did" || return $?
    fi
    [[ $existing == false ]] || :
}
_loom_mail_poll() {
    local mailbox cursor limit
    mailbox=$(jq -r .args.mailbox "$_lm_request")
    cursor=$(jq -r '.args.after_cursor//""' "$_lm_request")
    limit=$(jq -r .args.limit "$_lm_request")
    _loom_mail_known "$mailbox" && _loom_mail_scope "$mailbox" || return 2
    # Cursor is exclusive over the durable store, including filtered records.
    loom_state_list delivery "$cursor" "$limit" > "$_lm_tmp/list" || return $?
    jq -c --arg mailbox "$mailbox" --argjson now "$(_loom_mail_now)" --slurpfile q "$_lm_request" --slurpfile b "$_lm_tmp/binding" '
      {items:[.items[]|select(.run_id==$q[0].actor.run_id)|
        select($b[0]==null or .data.delivery.attempt_id==null or .data.delivery.attempt_id==$b[0].target.attempt_id or
          ((.data.delivery.recipient|startswith("task:")) and .data.remote==null and (.data.claim.until_ms//0)<=$now))|
        .data.delivery|select(.recipient==$mailbox or ($mailbox==("attempt:"+(.attempt_id//""))))],next_cursor:.next_cursor}' "$_lm_tmp/list" > "$_lm_tmp/result"
    jq -c --slurpfile r "$_lm_tmp/result" --argjson now "$(_loom_mail_now)" '.items[]|
      select(.id as $id|any($r[0].items[];.delivery_id==$id))|.data|
      {delivery_id:.delivery.delivery_id,age_ms:([$now-.created_ms,0]|max),expires_at:(.expires_at//null),
      next_attempt_ms:.next_attempt_ms,failed_attempts:.tries,claim_expires_ms:(.claim.until_ms//null)}' "$_lm_tmp/list" >> "$_lm_tmp/observations"
}
_loom_mail_check_claim() {
    local record=$1 token=$2
    _loom_mail_scope "$(jq -r .data.delivery.recipient "$record")" "$(jq -r .data.delivery.attempt_id "$record")" || return 2
    jq -e --arg token "$token" --argjson now "$(_loom_mail_now)" --slurpfile q "$_lm_request" --slurpfile c "$_lm_context" '
      .data.claim as $claim | $claim!=null and $claim.token==$token and $claim.actor==$q[0].actor and
      $claim.target==$q[0].target and $claim.role==$c[0].role and $claim.until_ms>$now' "$record" >/dev/null || _loom_mail_error claim_expired
}
_loom_mail_delivery() {
    local id op now token until attempt recipient scoped_attempt
    id=$(jq -r .args.delivery_id "$_lm_request"); op=$(jq -r .op "$_lm_request")
    loom_state_get delivery "$id" > "$_lm_tmp/d" || return $?
    jq -e --slurpfile q "$_lm_request" '.run_id==$q[0].actor.run_id and .revision==$q[0].expected_revision' "$_lm_tmp/d" >/dev/null || { _loom_mail_error revision_conflict; return 2; }
    recipient=$(jq -r .data.delivery.recipient "$_lm_tmp/d")
    scoped_attempt=$(jq -r .data.delivery.attempt_id "$_lm_tmp/d")
    if [[ $op == mail.claim && $recipient == task:* ]] && (( $(jq '.data.claim.until_ms//0' "$_lm_tmp/d")<=$(_loom_mail_now) )); then scoped_attempt=null; fi
    _loom_mail_scope "$recipient" "$scoped_attempt" || return 2
    loom_state_get message "$(jq -r .data.delivery.message_id "$_lm_tmp/d")" > "$_lm_tmp/message-record" || return $?
    now=$(_loom_mail_now)
    [[ $op == mail.retry || $(jq -r .data.remote "$_lm_tmp/d") == null ]] || { _loom_mail_error remote_claim_owned; return 2; }
    jq -c .data "$_lm_tmp/d" > "$_lm_tmp/data"
    if [[ $op != mail.retry && $(jq -r .data.message.expires_at "$_lm_tmp/message-record") != null ]] &&
       (( now >= $(date -u -d "$(jq -r .data.message.expires_at "$_lm_tmp/message-record")" +%s) * 1000 )); then
        _loom_mail_error message_expired; return 2
    fi
    case $op in
        mail.claim)
            [[ $(jq -r .data.delivery.state "$_lm_tmp/d") != acked && $(jq -r .data.delivery.state "$_lm_tmp/d") != dead_letter ]] || return 2
            jq -e --slurpfile q "$_lm_request" '.data.delivery.recipient==$q[0].args.mailbox or $q[0].args.mailbox==("attempt:"+(.data.delivery.attempt_id//""))' "$_lm_tmp/d" >/dev/null || return 2
            token=$(jq -r '.args.claim_token//""' "$_lm_request")
            if [[ -n $token ]]; then _loom_mail_check_claim "$_lm_tmp/d" "$token" || return $?
            else
                (( $(jq '.data.claim.until_ms//0' "$_lm_tmp/d")<=now )) || { _loom_mail_error resource_busy; return 2; }
                token=$(cat /proc/sys/kernel/random/uuid)
            fi
            until=$((now+$(jq .args.lease_ms "$_lm_request")))
            attempt=$(jq -r '.target.attempt_id//""' "$_lm_tmp/binding")
            jq --arg token "$token" --arg attempt "$attempt" --argjson until "$until" --slurpfile q "$_lm_request" --slurpfile c "$_lm_context" '
              .data | .delivery.revision+=1 | .delivery.state=(if .facts.read then "read" else "delivered" end) |
              .delivery.next_action="read" | .facts.delivered=true |
              (if $attempt!="" then .delivery.attempt_id=$attempt else . end) |
              .claim={token:$token,until_ms:$until,actor:$q[0].actor,target:$q[0].target,role:$c[0].role}' "$_lm_tmp/d" > "$_lm_tmp/data"
            jq -cn --slurpfile d "$_lm_tmp/data" --arg token "$token" --arg expiry "$(date -u -d "@$(( (until+999)/1000 ))" +%Y-%m-%dT%H:%M:%SZ)" '{delivery:$d[0].delivery,claim_token:$token,expires_at:$expiry}' > "$_lm_tmp/result" ;;
        mail.read|mail.ack)
            _loom_mail_check_claim "$_lm_tmp/d" "$(jq -r .args.claim_token "$_lm_request")" || return $?
            if [[ $op == mail.ack ]]; then
                [[ $(jq -r .args.message_digest "$_lm_request") == "$(jq -r .data.delivery.message_digest "$_lm_tmp/d")" ]] || return 2
                jq '.data | .delivery.revision+=1 | .delivery.state="acked" | .delivery.next_action="none" | .facts.acked=true' "$_lm_tmp/d" > "$_lm_tmp/data"
                jq .delivery "$_lm_tmp/data" > "$_lm_tmp/result"
            else
                [[ $(jq -r .data.delivery.state "$_lm_tmp/d") != acked ]] || return 2
                jq '.data | .delivery.revision+=1 | .delivery.state="read" | .delivery.next_action="ack" | .facts.read=true' "$_lm_tmp/d" > "$_lm_tmp/data"
                jq -cn --slurpfile d "$_lm_tmp/data" --slurpfile m "$_lm_tmp/message-record" '{delivery:$d[0].delivery,message:$m[0].data.message}' > "$_lm_tmp/result"
            fi ;;
        mail.retry)
            [[ $(jq -r .role "$_lm_context") == owner && $(jq -r .data.delivery.state "$_lm_tmp/d") == dead_letter ]] || return 2
            jq --argjson now "$now" '.data | .delivery.revision+=1 | .delivery.state="pending" | .delivery.reason=null | .delivery.next_action="pump" | .tries=0 | .next_attempt_ms=$now | .claim=null' "$_lm_tmp/d" > "$_lm_tmp/data"
            jq .delivery "$_lm_tmp/data" > "$_lm_tmp/result" ;;
    esac
    _loom_mail_change "$_lm_tmp/d" "$_lm_tmp/data" delivery "$id"
}

_loom_mail_handle() (
    umask 077
    local _lm_context=$1 _lm_request=$2 _lm_tmp _lm_key _lm_digest _lm_code=mail_refused rc=0 op durable=false
    _lm_tmp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$_lm_tmp"' EXIT
    _loom_mail_modules || return 2
    loom_protocol_check_request "$_lm_request" || return 2
    [[ $(jq -r .protocol "$_lm_request") == loom.coordination ]] || return 2
    jq -e 'all([.actor.id,.actor.run_id,.request_id,.operation_id,.idempotency_key,.target[],.args.message_id,.args.delivery_id,.args.question_id,.args.from,.args.mailbox,(.args.to//[])[]][]|select(.!=null); test("[\u0000-\u001f\u007f]")|not)' "$_lm_request" >/dev/null || {
        loom_protocol_receipt "$_lm_request" refused invalid_request 'Control characters in routing identifiers are refused'; return 2;
    }
    cp "$_lm_request" "$_lm_tmp/request"; _lm_request=$_lm_tmp/request
    _loom_mail_context "$_lm_context" "$_lm_request" || { loom_protocol_receipt "$_lm_request" refused actor_denied 'Provisioned actor, epoch or binding mismatch'; return 2; }
    [[ $(jq '.extensions|length' "$_lm_request") == 0 ]] || { loom_protocol_receipt "$_lm_request" refused invalid_request 'Authority mail takes no extensions'; return 2; }
    op=$(jq -r .op "$_lm_request")
    _lm_key=$(jq -cS --slurpfile c "$_lm_context" '[.idempotency_key,.target,$c[0].role]' "$_lm_request" | _loom_mail_hash)
    _lm_digest=$(_loom_mail_digest "$_lm_request")
    : > "$_lm_tmp/change-lines"
    : > "$_lm_tmp/observations"
    case $op in
        mail.poll) _loom_mail_poll || rc=$? ;;
        mail.status) _loom_mail_status "$(jq -r .args.message_id "$_lm_request")" || rc=$? ;;
        mail.send|mail.reply|mail.claim|mail.read|mail.ack|mail.retry|mail.pump)
            durable=true
            _loom_mail_replay || rc=$?
            if (( rc==3 )); then
                rc=0
                case $op in
                    mail.send|mail.reply) _loom_mail_send || rc=$? ;;
                    mail.pump) _loom_mail_pump || rc=$? ;;
                    *) _loom_mail_delivery || rc=$? ;;
                esac
                if (( rc==0 )); then
                    jq -s . "$_lm_tmp/change-lines" > "$_lm_tmp/changes"
                    _loom_mail_commit || rc=$?
                fi
                # A concurrent identical caller can have won the CAS.
                if (( rc!=0 )); then _loom_mail_replay && rc=0; fi
            fi ;;
        *) _lm_code=unsupported_operation; rc=2 ;;
    esac
    if (( rc!=0 )); then
        if (( rc==2 || rc==3 )); then loom_protocol_receipt "$_lm_request" refused "$_lm_code" 'Mail authority or revision precondition refused'; return 2
        else loom_protocol_receipt "$_lm_request" unknown outcome_unknown 'Reconcile the identical operation'; return 1; fi
    fi
    _loom_mail_response "$_lm_request" "$_lm_tmp/result" "$durable" > "$_lm_tmp/response"
    jq --slurpfile observations "$_lm_tmp/observations" '.extensions["loom.mail.observations"]={deliveries:($observations|unique_by(.delivery_id))}' "$_lm_tmp/response" > "$_lm_tmp/observed-response"
    mv "$_lm_tmp/observed-response" "$_lm_tmp/response"
    loom_protocol_validate response "$_lm_tmp/response" "$_lm_request" || { loom_protocol_receipt "$_lm_request" unknown outcome_unknown 'Response failed validation; reconcile identical operation'; return 1; }
    cat "$_lm_tmp/response"
)
loom_mail_handle() (
    [[ $# == 2 ]] || return 2
    umask 077
    local temp rc=0 ops
    _loom_mail_modules || return 2
    loom_protocol_check_request "$2" || return 2
    temp=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temp"' EXIT
    cp "$2" "$temp/request" || return 1
    ops=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P) || return 2
    timeout --kill-after=1 "$(jq '.timeout_ms/1000' "$temp/request")" bash "$ops/mail.sh" --internal "$1" "$temp/request" > "$temp/response" || rc=$?
    if (( rc==124 || rc==137 )); then loom_protocol_receipt "$temp/request" unknown outcome_unknown 'Deadline exceeded; reconcile identical operation'; return 1; fi
    cat "$temp/response"
    return "$rc"
)
loom_mail_serve() (
    [[ $# == 1 ]] || return 2
    umask 077
    local tmp
    tmp=$(mktemp) || return 1
    trap 'rm -f -- "$tmp"' EXIT
    head -c 1048577 > "$tmp"
    [[ $(stat -c %s "$tmp") -le 1048576 ]] || return 2
    loom_mail_handle "$1" "$tmp"
)

# Pump subtransactions persist exact outbound intent before SSH. Keys bind the
# original pump operation and phase; lost replies never allocate a new message.
_loom_mail_pump_store() {
    local old=$1 data=$2 phase=$3 key prior
    key=pump-$(jq -cn --arg op "$(jq -r .operation_id "$_lm_request")" --arg id "$(jq -r .id "$old")" --arg phase "$phase" '[$op,$id,$phase]' | _loom_mail_hash)
    if prior=$(loom_state_operation "$(jq -r .actor.id "$_lm_request")" mail.transport "$key" 2>/dev/null); then
        jq -c .outcome.result <<< "$prior" > "$_lm_tmp/pump-record"; return 0
    fi
    jq -cnS --slurpfile c "$_lm_context" --slurpfile q "$_lm_request" --slurpfile old "$old" --slurpfile data "$data" --slurpfile run "$_lm_tmp/run" --arg key "$key" '
      $old[0] as $o | $q[0] as $q | ($o|.revision+=1|.data=$data[0]|.data.delivery.revision=.revision) as $new |
      {schema:2,store_id:$c[0].store_id,operation_id:$key,idempotency_key:$key,op:"mail.transport",actor:$q.actor,target:$q.target,
      checks:[{kind:"run",id:$run[0].id,revision:$run[0].revision}],changes:[{kind:"delivery",id:$o.id,expected_revision:$o.revision,run_id:$o.run_id,epoch:$q.actor.epoch,data:$new.data}],
      events:[{type:"mail.transport",entity_ids:[$o.id],payload:{},observed_at:null}],result:$new}' > "$_lm_tmp/pump-tx" || return 2
    loom_state_transact "$_lm_tmp/pump-tx" > "$_lm_tmp/pump-outcome" || return $?
    jq .result "$_lm_tmp/pump-outcome" > "$_lm_tmp/pump-record"
}
_loom_mail_pump() {
    local ops route aid config now deadline id rc request_id directory attempt expected config_digest count=0 cursor='' route_after='' cursor_id
    [[ $(jq -r .role "$_lm_context") == owner ]] || return 2
    jq -e --slurpfile r "$_lm_tmp/run" '.args.run_id==.actor.run_id and .expected_revision==$r[0].revision' "$_lm_request" >/dev/null || { _loom_mail_error revision_conflict; return 2; }
    ops=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
    # shellcheck source=/dev/null
    source "${LOOM_MAIL_SSH_MODULE:-$ops/transport-ssh.sh}" || return 2
    deadline=$(( $(_loom_mail_now)+$(jq '[.args.deadline_ms,.timeout_ms]|min' "$_lm_request") ))
    : > "$_lm_tmp/pump-views"
    cursor_id=mail-cursor-$(jq -r .actor.run_id "$_lm_request" | _loom_mail_hash)
    if loom_state_get operation "$cursor_id" > "$_lm_tmp/cursor-old" 2>/dev/null; then cursor=$(jq -r '.data.cursor//""' "$_lm_tmp/cursor-old"); route_after=$(jq -r '.data.route_after//""' "$_lm_tmp/cursor-old")
    else printf 'null\n' > "$_lm_tmp/cursor-old"; fi
    loom_state_list delivery "$cursor" 100 > "$_lm_tmp/pump-list" || return $?
    # Expiry is an explicit pump action; ordinary observers do not mutate mail.
    while IFS= read -r id; do
        (( $(_loom_mail_now)<deadline )) || break
        loom_state_get delivery "$id" > "$_lm_tmp/pump-d" || return $?
        loom_state_get message "$(jq -r .data.delivery.message_id "$_lm_tmp/pump-d")" > "$_lm_tmp/pump-m" || return $?
        expected=$(jq -r .data.message.expires_at "$_lm_tmp/pump-m")
        if [[ $expected != null ]] && (( $(date -u -d "$expected" +%s)*1000<=$(_loom_mail_now) )); then
            jq '.data|.delivery.state="dead_letter"|.delivery.reason="deadline_expired"|.delivery.next_action="retry"' "$_lm_tmp/pump-d" > "$_lm_tmp/pump-data"
            _loom_mail_pump_store "$_lm_tmp/pump-d" "$_lm_tmp/pump-data" expire || return $?
            _loom_mail_view "$_lm_tmp/pump-record" >> "$_lm_tmp/pump-views"
        fi
    done < <(jq -r --slurpfile q "$_lm_request" '.items[]|select(.run_id==$q[0].actor.run_id and (.data.delivery.state|IN("acked","dead_letter")|not))|.id' "$_lm_tmp/pump-list")
    while IFS= read -r route; do
        (( $(_loom_mail_now)<deadline && count<20 )) || break
        count=$((count+1))
        aid=$(jq -r .attempt_id <<< "$route"); route_after=$aid; config=$(jq -r .config <<< "$route")
        _loom_ssh_config "$config" || return 2
        config_digest=$(loom_policy_digest "$config")
        attempt=$(jq -ce --arg aid "$aid" '.data.attempts[$aid]|select(.launch_authorized==true and .binding!=null)' "$_lm_tmp/run") || return 2
        jq -e --argjson a "$attempt" '.context_id==$a.attempt_id and .identity.transport_identity==$a.policy_pin.host.identity' "$config" >/dev/null || return 2
        jq -c --argjson a "$attempt" '{epoch:.epoch,revision:.revision,task_id:$a.task_id,addresses:(["run:"+.id]+[.data.tasks|keys[]|"task:"+.]+[.data.attempts|keys[]|"attempt:"+.])}' "$_lm_tmp/run" > "$_lm_tmp/directory"
        directory=$(cat "$_lm_tmp/directory")
        printf '[]\n' > "$_lm_tmp/intents"
        id=''
        # Use fresh state after expiry, and pin exactly one intent per exchange.
        loom_state_list delivery "$cursor" 100 > "$_lm_tmp/current" || return $?
        now=$(_loom_mail_now)
        id=$(jq -r --argjson a "$attempt" --argjson now "$now" --slurpfile run "$_lm_tmp/run" '
          [.items[]|select(.run_id==$run[0].id)|select(.data.delivery.state|IN("acked","dead_letter")|not)|
           select(.data.facts.delivered!=true)|
           select(.data.next_attempt_ms<=$now and (.data.claim.until_ms//0)<=$now)|
           select(.data.delivery.recipient==("attempt:"+$a.attempt_id) or
             (.data.delivery.recipient==("task:"+$a.task_id) and $run[0].data.tasks[$a.task_id].attempt_ids[-1]==$a.attempt_id))|
           select(.data.remote==null or .data.remote.attempt_id==$a.attempt_id)]|first|.id//""' "$_lm_tmp/current")
        if [[ -n $id ]]; then
            loom_state_get delivery "$id" > "$_lm_tmp/pump-d" || return $?
            loom_state_get message "$(jq -r .data.delivery.message_id "$_lm_tmp/pump-d")" > "$_lm_tmp/pump-m" || return $?
            if [[ $(jq -r .data.remote "$_lm_tmp/pump-d") == null ]]; then
                jq --arg aid "$aid" --arg config "$config_digest" --argjson dir "$directory" --slurpfile m "$_lm_tmp/pump-m" '
                  .data|.delivery.attempt_id=$aid | .remote={attempt_id:$aid,config_digest:$config,directory:$dir,
                    intent:{delivery:.delivery,message:$m[0].data.message,return_address:$m[0].data.return_address}}' "$_lm_tmp/pump-d" > "$_lm_tmp/pump-data"
                _loom_mail_pump_store "$_lm_tmp/pump-d" "$_lm_tmp/pump-data" prepare || return $?
                cp "$_lm_tmp/pump-record" "$_lm_tmp/pump-d"
            fi
            [[ $(jq -r .data.remote.config_digest "$_lm_tmp/pump-d") == "$config_digest" ]] || { _loom_mail_error identity_mismatch; return 2; }
            jq '[.data.remote.intent]' "$_lm_tmp/pump-d" > "$_lm_tmp/intents"
        fi
        # Each exchange has a unique pump ID; intake dedupes immutable delivery
        # intent independently. A lost transport reply keeps its original digest.
        request_id=exchange-$(jq -cn --arg op "$(jq -r .operation_id "$_lm_request")" --arg aid "$aid" '[$op,$aid]' | _loom_mail_hash)
        jq -cn --slurpfile q "$_lm_request" --argjson a "$attempt" --argjson directory "$directory" --slurpfile ds "$_lm_tmp/intents" --slurpfile list "$_lm_tmp/current" --arg id "$request_id" --argjson remaining "$((deadline-$(_loom_mail_now)))" '
          $q[0] | .actor=$a.binding.actor | .target=$a.binding.target | .operation_id=$id | .idempotency_key=$id | .request_id=$id |
          .timeout_ms=([$remaining,300000]|min) | .args.deadline_ms=.timeout_ms | .expected_revision=0 |
          .extensions={"loom.mail.exchange":{directory:$directory,deliveries:$ds[0],
          confirm:[$list[0].items[]|select(.data.remote.attempt_id==$a.attempt_id and .data.facts.acked)|{delivery_id:.id,message_digest:.data.delivery.message_digest,acked:true}],outbox_confirm:[]}}' > "$_lm_tmp/exchange" || return 2
        (( $(jq .timeout_ms "$_lm_tmp/exchange")>0 )) || break
        rc=0; loom_ssh_handle "$config" "$_lm_tmp/exchange" > "$_lm_tmp/exchanged" || rc=$?
        if (( rc!=0 )); then
            if [[ -n $id ]]; then
                jq --argjson now "$(_loom_mail_now)" '.data|.tries+=1|.next_attempt_ms=($now+([1000,2000,4000,8000,16000][([.tries-1,4]|min)]))|
                  .delivery.reason="host_unreachable_or_unknown"|.delivery.next_action="pump"|
                  if .tries>=5 then .delivery.state="dead_letter"|.delivery.reason="retry_exhausted"|.delivery.next_action="retry" else . end' "$_lm_tmp/pump-d" > "$_lm_tmp/pump-data"
                _loom_mail_pump_store "$_lm_tmp/pump-d" "$_lm_tmp/pump-data" failure || return $?
                _loom_mail_view "$_lm_tmp/pump-record" >> "$_lm_tmp/pump-views"
            fi
            continue
        fi
        # Exact receipt identity and monotonic facts are mandatory before import.
        while IFS= read -r receipt; do
            local did
            did=$(jq -r .delivery_id <<< "$receipt")
            loom_state_get delivery "$did" > "$_lm_tmp/received" || return $?
            jq -e --argjson r "$receipt" --arg aid "$aid" '($r|keys)==["attempt_id","delivery_id","facts","message_digest"] and .data.remote.attempt_id==$aid and .data.delivery.message_digest==$r.message_digest and $r.attempt_id==$aid and ($r.facts|keys==["acked","delivered","read"] and all(.[];type=="boolean"))' "$_lm_tmp/received" >/dev/null || return 2
            jq --argjson r "$receipt" '.data | .facts.delivered=(.facts.delivered or $r.facts.delivered)|.facts.read=(.facts.read or $r.facts.read)|.facts.acked=(.facts.acked or $r.facts.acked)|
              .delivery.state=(if .delivery.state=="dead_letter" then .delivery.state elif .facts.acked then "acked" elif .facts.read then "read" elif .facts.delivered then "delivered" else .delivery.state end)|
              .delivery.next_action=(if .facts.acked then "none" else "pump" end)|.delivery.reason=null' "$_lm_tmp/received" > "$_lm_tmp/pump-data"
            if ! jq -e --slurpfile d "$_lm_tmp/pump-data" '.data==$d[0]' "$_lm_tmp/received" >/dev/null; then
                _loom_mail_pump_store "$_lm_tmp/received" "$_lm_tmp/pump-data" receipt || return $?
                _loom_mail_view "$_lm_tmp/pump-record" >> "$_lm_tmp/pump-views"
            fi
        done < <(jq -c '.extensions["loom.mail.exchange"].receipts[]' "$_lm_tmp/exchanged")
        # Outbound requests remain queued on the host until exact authority
        # acceptance. Repeated import uses the original operation/message IDs.
        : > "$_lm_tmp/outbox-confirm"
        while IFS= read -r outgoing; do
            jq -c .request <<< "$outgoing" > "$_lm_tmp/outgoing"
            [[ $(jq -cS 'del(.request_id,.timeout_ms)' "$_lm_tmp/outgoing" | loom_policy_scope) == "$(jq -r .request_digest <<< "$outgoing")" ]] || return 2
            jq --argjson a "$attempt" '.role="worker"|.actor=$a.binding.actor|.binding="PLACEHOLDER"|.routes=[]|.commands=["mail.send","mail.reply"]' "$_lm_context" > "$_lm_tmp/worker-context-template"
            jq -c .binding <<< "$attempt" > "$_lm_tmp/worker-binding"
            jq --arg binding "$_lm_tmp/worker-binding" '.binding=$binding' "$_lm_tmp/worker-context-template" > "$_lm_tmp/worker-context"
            if loom_mail_handle "$_lm_tmp/worker-context" "$_lm_tmp/outgoing" > "$_lm_tmp/imported"; then
                jq -c --arg digest "$(jq -r .request_digest <<< "$outgoing")" '{message_id:.result.message_id,request_digest:$digest,authority_sync:"committed"}' "$_lm_tmp/imported" >> "$_lm_tmp/outbox-confirm"
            fi
        done < <(jq -c '.extensions["loom.mail.exchange"].outbox[]' "$_lm_tmp/exchanged")
        if [[ -s $_lm_tmp/outbox-confirm ]] && (( $(_loom_mail_now)<deadline )); then
            jq --slurpfile confirms "$_lm_tmp/outbox-confirm" '.operation_id+="-confirm"|.idempotency_key+="-confirm"|.request_id+="-confirm"|.extensions["loom.mail.exchange"].deliveries=[]|.extensions["loom.mail.exchange"].outbox_confirm=$confirms' "$_lm_tmp/exchange" > "$_lm_tmp/confirm"
            loom_ssh_handle "$config" "$_lm_tmp/confirm" > "$_lm_tmp/confirmed" || :
        fi
    done < <(jq -c --arg after "$route_after" '.routes | (map(.attempt_id)|index($after)) as $i | if $i==null then .[] else (.[$i+1:]+.[:$i+1])[] end' "$_lm_context")
    jq --arg route_after "$route_after" '{cursor:.next_cursor,route_after:$route_after}' "$_lm_tmp/pump-list" > "$_lm_tmp/cursor-data"
    _loom_mail_change "$_lm_tmp/cursor-old" "$_lm_tmp/cursor-data" operation "$cursor_id" || return $?
    jq -cn --slurpfile ds "$_lm_tmp/pump-views" --argjson deadline "$deadline" --argjson now "$(_loom_mail_now)" --slurpfile list "$_lm_tmp/pump-list" '{deliveries:($ds|unique_by(.delivery_id)),next_cursor:$list[0].next_cursor,deadline_reached:($now>=$deadline)}' > "$_lm_tmp/result"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case ${1:-} in
        handle) shift; loom_mail_handle "$@" ;;
        serve) shift; loom_mail_serve "$@" ;;
        --internal) shift; _loom_mail_handle "$@" ;;
        *) printf 'usage: mail.sh handle CONTEXT REQUEST | serve CONTEXT\n' >&2; exit 2 ;;
    esac
fi
