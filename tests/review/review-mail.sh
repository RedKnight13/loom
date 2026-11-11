#!/usr/bin/env bash
# Deterministic authority/spool regressions; no network, agents or model calls.
# shellcheck disable=SC1090,SC1091,SC2016,SC2030,SC2031,SC2154
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
# The installed helper requires private deployment permissions, unlike a clone.
if [[ ${REVIEW_MAIL_PRIVATE:-0} != 1 ]]; then
    private=$(mktemp -d)
    trap 'rm -rf -- "$private"' EXIT
    cp -R "$root/ops" "$root/schemas" "$root/tests" "$root/VERSION" "$private/"
    chmod -R go-rwx "$private"
    REVIEW_MAIL_PRIVATE=1 bash "$private/tests/review/review-mail.sh" "${1:-all}"
    exit $?
fi
mode=${1:-all}
if [[ $mode == all ]]; then
    for section in claim state replay expiry outbox selection cache; do bash "${BASH_SOURCE[0]}" "$section"; done
    exit 0
fi
if [[ $mode == claim ]]; then
    # Existing review fixture also checks ordinary stale-owner mutations.
    source "$root/tests/review/coordination.sh"
    context=$scratch/replacement; actor=replacement; run='run-one'; epoch=0
    # Recover the original successful claim request from the journal.
    jq -c '.request|select(.op=="run.claim")' "$LOOM_STATE/v2/journal/"*.json > "$scratch/claim-tx"
    jq -cn --slurpfile tx "$scratch/claim-tx" '{protocol:"loom.coordination",version:{major:1,minor:0},request_id:"retry",operation_id:$tx[0].operation_id,idempotency_key:$tx[0].idempotency_key,op:"run.claim",actor:$tx[0].actor,target:$tx[0].target,expected_revision:2,timeout_ms:30000,args:{run_id:"run-one",expected_owner:"owner",reason:"fixture takeover"},extensions:{}}' > "$scratch/request"
    ok
    jq -e '.result.epoch==1 and .result.owner_id=="replacement"' "$scratch/response" >/dev/null
    cp "$scratch/request" "$scratch/claim-retry"
    # Later writes in the same ownership epoch do not revoke replay.
    epoch=1; task '[]'
    cp "$scratch/claim-retry" "$scratch/request"; ok
    revision=$(rev run "$run")
    jq --argjson rev "$revision" '.actor_id="successor"|.claims=[{run_id:"run-one",expected_owner:"replacement",expected_revision:$rev,epoch:1,reason:"next takeover"}]' "$context" > "$scratch/successor"
    context=$scratch/successor; actor=successor
    request run.claim '{"run_id":"run-one","expected_owner":"replacement","reason":"next takeover"}' "$revision"; ok
    context=$scratch/replacement; cp "$scratch/claim-retry" "$scratch/request"; deny
    # Same actor returning in a newer epoch still cannot replay an old claim.
    revision=$(rev run "$run"); epoch=2; actor=replacement
    jq --argjson rev "$revision" '.claims=[{run_id:"run-one",expected_owner:"successor",expected_revision:$rev,epoch:2,reason:"return takeover"}]' "$context" > "$scratch/return"
    context=$scratch/return
    request run.claim '{"run_id":"run-one","expected_owner":"successor","reason":"return takeover"}' "$revision"; ok
    cp "$scratch/claim-retry" "$scratch/request"; deny
    printf 'PASS claim replay uses resulting ownership epoch and fences superseded claims\n'
    exit 0
fi
if [[ $mode == state ]]; then
    source "$root/ops/state.sh"
    umask 077
    scratch=$(mktemp -d); trap 'rm -rf -- "$scratch"' EXIT
    export LOOM_STATE=$scratch/store
    for fault in lock metadata journal snapshot; do
        for boundary in before_write after_write after_file_flush after_rename after_directory_flush; do
            rm -rf "$LOOM_STATE"
            loom_state_init fixture >/dev/null
            jq -cnS '{schema:2,store_id:"fixture",operation_id:"put",idempotency_key:"put",op:"config.put",actor:{id:"owner",run_id:null,epoch:0},target:{},checks:[],changes:[{kind:"config",id:"item",expected_revision:null,run_id:null,epoch:0,data:{value:1}}],events:[{type:"put",entity_ids:["item"],payload:{},observed_at:null}],result:{value:1}}' > "$scratch/tx"
            command=(transact "$scratch/tx")
            if [[ $fault == metadata ]]; then rm -rf "$LOOM_STATE"; command=(init fixture); fi
            rc=0
            LOOM_STATE_TESTING=1 LOOM_STATE_TEST_FAIL=$fault.$boundary bash "$root/ops/state.sh" "${command[@]}" > "$scratch/out" 2> "$scratch/err" || rc=$?
            expected=1; [[ $fault != snapshot ]] || expected=0
            [[ $rc == "$expected" ]]
            [[ -z $(find "$LOOM_STATE" -name '.tmp.*' -o -name '.work.*') ]]
        done
    done
    # SIGKILL leaves both a work directory and an incomplete atomic write.
    rm -rf "$LOOM_STATE"; loom_state_init fixture >/dev/null
    rc=0
    LOOM_STATE_TESTING=1 LOOM_STATE_TEST_CRASH=journal.after_write bash "$root/ops/state.sh" transact "$scratch/tx" > "$scratch/out" 2> "$scratch/err" || rc=$?
    [[ $rc == 137 ]]
    [[ -n $(find "$LOOM_STATE" -name '.tmp.*') && -n $(find "$LOOM_STATE" -name '.work.*') ]]
    loom_state_transact "$scratch/tx" > "$scratch/committed"
    [[ -z $(find "$LOOM_STATE" -name '.tmp.*' -o -name '.work.*') ]]
    # Post-rename failure must not remove committed history.
    rm -rf "$LOOM_STATE"; loom_state_init fixture >/dev/null
    rc=0
    LOOM_STATE_TESTING=1 LOOM_STATE_TEST_FAIL=journal.after_rename bash "$root/ops/state.sh" transact "$scratch/tx" > "$scratch/out" 2> "$scratch/err" || rc=$?
    [[ $rc == 1 && -f $LOOM_STATE/v2/journal/0000000000000001.json ]]
    before=$(git hash-object "$LOOM_STATE/v2/journal/0000000000000001.json")
    loom_state_transact "$scratch/tx" > "$scratch/replayed"
    [[ $before == "$(git hash-object "$LOOM_STATE/v2/journal/0000000000000001.json")" ]]
    jq -e '.sequence==1 and .durable' "$scratch/replayed" >/dev/null
    printf 'PASS ordinary failures clean scratch; crash recovery reclaims scratch and preserves committed journals\n'
    exit 0
fi
MAIL_SSH_LIBRARY=1 source "$root/tests/mail/ssh.sh"
export REVIEW_MAIL_FIXTURE=$dir REVIEW_MAIL_ROOT=$root
if [[ $mode == replay ]]; then
    pump
    request mail.send '{"message_id":"outbound-one","from":"owner","to":["run:run"],"kind":"guidance","subject":"","body":"fixture","thread_id":null,"in_reply_to":null,"expires_at":null}' null worker
    loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/outbound-one"
    send_message replay-one attempt:attempt
    did=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
    # Fail the final authority commit after transport and receipt import succeed.
    cat > "$dir/interrupted-state.sh" <<'HOOK'
source "$REVIEW_MAIL_ROOT/ops/state.sh"
loom_state_transact() {
    if [[ $(jq -r .op "$1") == mail.pump && ! -e $REVIEW_MAIL_FIXTURE/interrupted ]]; then
        touch "$REVIEW_MAIL_FIXTURE/interrupted"
        return 1
    fi
    _loom_state_call transact "$@" || return $?
    if [[ $(jq -r .op "$1") == mail.transport && ! -e $REVIEW_MAIL_FIXTURE/transport-uncertain ]]; then
        touch "$REVIEW_MAIL_FIXTURE/transport-uncertain"
        return 1
    fi
}
HOOK
    export LOOM_MAIL_STATE_MODULE=$dir/interrupted-state.sh
    rev=$(LOOM_STATE=$dir/authority loom_state_get run run | jq .revision)
    request mail.pump '{"run_id":"run","deadline_ms":30000}' "$rev"
    cp "$dir/request" "$dir/retry-pump"
    mail_call owner 1
    [[ -f $dir/interrupted && -f $dir/transport-uncertain ]]
    LOOM_STATE=$dir/authority loom_state_get delivery "$did" | jq -e '.data.facts.delivered' >/dev/null
    LOOM_STATE=$dir/authority loom_state_list operation '' 100 > "$dir/prepared"
    exchange=$(jq -r --arg mid replay-one '.items[]|select(.data.request.extensions["loom.mail.exchange"].deliveries[0].message.message_id==$mid)|.id' "$dir/prepared")
    [[ -n $exchange ]]
    jq -e --arg id "$exchange-confirm" 'any(.items[];.id==$id and (.data.request.extensions["loom.mail.exchange"].outbox_confirm|length)==1)' "$dir/prepared" >/dev/null
    jq '.args.deadline_ms=29000' "$dir/retry-pump" > "$dir/request"; mail_call owner 2
    # Another message is now eligible, but this retry must retain the first intent.
    send_message replay-two attempt:attempt
    request mail.send '{"message_id":"outbound-two","from":"owner","to":["run:run"],"kind":"guidance","subject":"","body":"fixture","thread_id":null,"in_reply_to":null,"expires_at":null}' null worker
    loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/outbound-two"
    cp "$dir/retry-pump" "$dir/request"; mail_call
    LOOM_STATE=$dir/state loom_state_operation owner mail.pump.spool "$exchange" > "$dir/exchange-result"
    LOOM_STATE=$dir/authority loom_state_list delivery '' 100 | jq -e 'all(.items[]|select(.data.delivery.message_id=="replay-two");.data.facts.delivered==false)' >/dev/null
    if LOOM_STATE=$dir/authority loom_state_get message outbound-two >/dev/null 2>&1; then fail 'retry selected a different outbound'; fi
    # Timeout-only transport retries must preserve the semantic digest.
    jq '.items[]|select(.id=="'"$exchange"'")|.data.request|.timeout_ms=29000' "$dir/prepared" > "$dir/exchange-retry"
    loom_ssh_handle "$dir/client" "$dir/exchange-retry" > "$dir/exchange-reply"
    printf 'PASS interrupted pump retains exact exchange intent and permits timeout-only retry\n'
elif [[ $mode == expiry ]]; then
    # Real acknowledgment is committed after list snapshot but before fresh get.
    request mail.send "$(jq -cn --arg expiry "$(date -u -d '+5 minutes' +%Y-%m-%dT%H:%M:%SZ)" '{message_id:"expiry-race",from:"owner",to:["run:run"],kind:"guidance",subject:"",body:"fixture",thread_id:null,in_reply_to:null,expires_at:$expiry}')"
    mail_call
    did=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
    request mail.claim "$(jq -cn --arg id "$did" '{mailbox:"run:run",delivery_id:$id,lease_ms:30000,claim_token:null}')" 1
    mail_call
    token=$(jq -r .result.claim_token "$dir/result")
    request mail.ack "$(jq -cn --arg id "$did" --arg token "$token" --arg digest "$(jq -r .result.delivery.message_digest "$dir/result")" '{delivery_id:$id,claim_token:$token,message_digest:$digest}')" 2
    cp "$dir/request" "$dir/ack-request"
    # Advance only the pump clock; the concurrent ack uses real time and the
    # immutable message bytes/digest are never rewritten by the fixture.
    cat > "$dir/race-state.sh" <<'HOOK'
source "$REVIEW_MAIL_ROOT/ops/state.sh"
loom_state_list() {
    _loom_state_call list "$@" || return $?
    if [[ $1 == delivery && ! -e $REVIEW_MAIL_FIXTURE/raced ]]; then
        touch "$REVIEW_MAIL_FIXTURE/raced"
        LOOM_MAIL_STATE_MODULE=$REVIEW_MAIL_ROOT/ops/state.sh bash "$REVIEW_MAIL_ROOT/ops/mail.sh" handle "$REVIEW_MAIL_FIXTURE/mail-owner" "$REVIEW_MAIL_FIXTURE/ack-request" > "$REVIEW_MAIL_FIXTURE/ack-result" || return $?
    fi
}
_loom_mail_now() { printf '%s\n' "$(( $(date +%s%3N)+600000 ))"; }
HOOK
    export LOOM_MAIL_STATE_MODULE=$dir/race-state.sh
    pump
    jq -e '.ok and .result.state=="acked"' "$dir/ack-result" >/dev/null
    LOOM_STATE=$dir/authority loom_state_get delivery "$did" | jq -e '.data.facts.acked and .data.delivery.state=="acked" and .data.delivery.next_action=="none"' >/dev/null
    printf 'PASS expiry rechecks freshly acknowledged state after stale list snapshot\n'
elif [[ $mode == outbox ]]; then
    pump
    for entry in a-rejected z-valid; do
        to=task:missing; [[ $entry != z-valid ]] || to=run:run
        request mail.send "$(jq -cn --arg id "$entry" --arg to "$to" '{message_id:$id,from:"owner",to:[$to],kind:"guidance",subject:"",body:"fixture",thread_id:null,in_reply_to:null,expires_at:null}')" null worker
        loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/queued"
    done
    pump; pump
    LOOM_STATE=$dir/authority loom_state_get message z-valid > "$dir/accepted"
    if LOOM_STATE=$dir/authority loom_state_get message a-rejected > /dev/null 2>&1; then fail 'rejected outbound imported'; fi
    LOOM_STATE=$dir/state loom_state_list host '' 100 | jq -e '.items[0].data.outbox | .["a-rejected"].authority_sync=="queued_for_authority" and .["a-rejected"].request.args.to==["task:missing"] and .["z-valid"].authority_sync=="committed"' >/dev/null
    printf 'PASS authority-rejected outbound retained while later valid mail progresses\n'
elif [[ $mode == selection ]]; then
    send_message selected attempt:attempt
    did=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
    request mail.claim "$(jq -cn --arg id "$did" '{mailbox:"attempt:attempt",delivery_id:$id,lease_ms:30000,claim_token:null}')" 1 worker
    cp "$dir/request" "$dir/claim-request"
    cat > "$dir/selection-state.sh" <<'HOOK'
source "$REVIEW_MAIL_ROOT/ops/state.sh"
loom_state_list() {
    _loom_state_call list "$@" || return $?
    if [[ $1 == delivery ]]; then
        if [[ ! -e $REVIEW_MAIL_FIXTURE/listed ]]; then touch "$REVIEW_MAIL_FIXTURE/listed"
        elif [[ ! -e $REVIEW_MAIL_FIXTURE/claimed ]]; then
            touch "$REVIEW_MAIL_FIXTURE/claimed"
            LOOM_MAIL_STATE_MODULE=$REVIEW_MAIL_ROOT/ops/state.sh bash "$REVIEW_MAIL_ROOT/ops/mail.sh" handle "$REVIEW_MAIL_FIXTURE/mail-worker" "$REVIEW_MAIL_FIXTURE/claim-request" > "$REVIEW_MAIL_FIXTURE/claim-result" || return $?
            _loom_state_call get delivery "$(jq -r .args.delivery_id "$REVIEW_MAIL_FIXTURE/claim-request")" > "$REVIEW_MAIL_FIXTURE/claim-state" || return $?
        fi
    fi
}
HOOK
    export LOOM_MAIL_STATE_MODULE=$dir/selection-state.sh
    rev=$(LOOM_STATE=$dir/authority loom_state_get run run | jq .revision)
    request mail.pump '{"run_id":"run","deadline_ms":30000}' "$rev"
    mail_call owner 2
    jq -e '.ok' "$dir/claim-result" >/dev/null
    LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/selection-final"
    jq -e --slurpfile c "$dir/claim-state" --slurpfile r "$dir/claim-result" --slurpfile q "$dir/claim-request" '
      .data.delivery.state=="delivered" and .data.facts.delivered and .data.remote==null and .revision==2 and
      .data.claim==$c[0].data.claim and .data.claim.token==$r[0].result.claim_token and
      .data.claim.actor==$q[0].actor and .data.claim.target==$q[0].target and
      .data.claim.role=="worker" and .data.claim.until_ms>0
    ' "$dir/selection-final" >/dev/null
    printf 'PASS stale selected-list revision cannot overwrite concurrent claim\n'
elif [[ $mode == cache ]]; then
    send_message cache-message attempt:attempt
    did=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
    _lm_tmp=$dir/cache; mkdir "$_lm_tmp"
    export LOOM_STATE=$dir/authority
    loom_state_get delivery "$did" > "$_lm_tmp/delivery"
    _loom_mail_pump_message "$_lm_tmp/delivery"
    cached=$_lm_tmp/message-$(printf '%s\n' cache-message | _loom_mail_hash)
    jq '.data.message.body="mismatched cache"' "$cached" > "$_lm_tmp/tampered"
    mv "$_lm_tmp/tampered" "$cached"
    rc=0; _loom_mail_pump_message "$_lm_tmp/delivery" || rc=$?
    [[ $rc == 2 ]]
    loom_state_get message cache-message | jq -e '.data.message.body=="fixture"' >/dev/null
    printf 'PASS cached message digest mismatch refuses without changing authority\n'
else
    fail "unknown review-mail section: $mode"
fi
