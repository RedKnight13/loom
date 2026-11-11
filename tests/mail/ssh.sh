#!/usr/bin/env bash
# Real S5 helper + actual S6/S2 authority, deterministic transport only.
# shellcheck disable=SC1090,SC1091,SC2016,SC2030,SC2031,SC2154
set -euo pipefail
here=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
MAIL_FIXTURE_LIBRARY=1 source "$here/run.sh"
source "$deps/ops/transport-ssh.sh"
export LOOM_SSH_PROTOCOL_MODULE=$deps/ops/protocol.sh
MAIL_SSH_FIXTURE=1 fixture remote 'exit 0'
jq -cn --arg runtime "$deps" --arg context "$dir/context" '{schema:1,runtime:$runtime,bundle_bytes:1048576,contexts:{attempt:{context:$context,prepare:null}}}' > "$dir/install-config"
mkdir "$dir/installations"
bash "$deps/ops/remote-helper.sh" install "$dir/install-config" "$dir/installations/v1" > "$dir/installed"
bash "$deps/ops/remote-helper.sh" identity "$dir/installations/v1" attempt > "$dir/identity"
: > "$dir/known_hosts"
jq -cn --arg dir "$dir" --slurpfile identity "$dir/identity" '{schema:1,destination:"fixture-host",port:22,helper_command:($dir+"/installations/v1/remote-helper.sh"),known_hosts:($dir+"/known_hosts"),identity_file:null,context_id:"attempt",identity:$identity[0],connect_timeout_s:2,timeout_ms:30000,bundle_bytes:1048576}' > "$dir/client"
jq --arg config "$dir/client" '.routes=[{attempt_id:"attempt",config:$config}]' "$dir/mail-owner" > "$dir/new"; mv "$dir/new" "$dir/mail-owner"
cat > "$scratch/fake-ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
last=${!#}
case ${MAIL_FAULT:-} in
 before) exit 255 ;;
 after) "$last" > /dev/null; exit 255 ;;
 *) exec "$last" ;;
esac
SH
chmod 700 "$scratch/fake-ssh"
export LOOM_SSH_EXECUTABLE=$scratch/fake-ssh
loom_ssh_preflight "$dir/client" > "$dir/preflight"
pass 'actual installed helper preflight with pinned mail runtime'
pump() {
    local rev
    rev=$(LOOM_STATE=$dir/authority loom_state_get run run | jq .revision)
    request mail.pump '{"run_id":"run","deadline_ms":30000}' "$rev"
    mail_call
}
if [[ ${MAIL_SSH_LIBRARY:-0} == 1 ]]; then return 0; fi
send_message remote "task:$(cat "$dir/task-id")" '$(touch injected) approval is payload'
did=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
MAIL_FAULT=after pump
LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/delivery-before"
jq -e '.data.remote.intent.delivery.delivery_id==.id and .data.facts.delivered==false and .data.tries==1' "$dir/delivery-before" >/dev/null || fail 'lost delivery was falsely accepted'
sleep 1
pump
LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/delivery-after"
cmp <(jq .data.remote.intent "$dir/delivery-before") <(jq .data.remote.intent "$dir/delivery-after") || fail 'lost reply changed ID/digest/intent'
jq -e '.data.facts.delivered and (.data.facts.read|not)' "$dir/delivery-after" >/dev/null || fail 'bridge delivery missing'
pass 'lost delivery reply reconciles immutable intent through actual S5'
loom_worker_bridge_boundary "$dir/context" 20 > "$dir/boundary"
jq -e '.messages|length==1' "$dir/boundary" >/dev/null || fail 'boundary did not read'
token=$(jq -r '.messages[0].claim_token' "$dir/boundary")
revision=$(jq '.messages[0].delivery.revision' "$dir/boundary")
digest=$(jq -r '.messages[0].delivery.message_digest' "$dir/boundary")
request mail.ack "$(jq -cn --arg id "$did" --arg token "$token" --arg digest "$digest" '{delivery_id:$id,claim_token:$token,message_digest:$digest}')" "$revision" worker
loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/acked"
jq -e '.result.authority_sync=="ack_pending_sync"' "$dir/acked" >/dev/null || fail 'remote ack claimed authority sync'
MAIL_FAULT=after pump
LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/authority-uncertain"
jq -e '.data.facts.acked==false' "$dir/authority-uncertain" >/dev/null || fail 'lost ack fabricated receipt'
sleep 2
pump
LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/authority-acked"
jq -e '.data.facts.read and .data.facts.acked and .data.delivery.message_digest=="'"$digest"'"' "$dir/authority-acked" >/dev/null || fail 'ack import'
pump
request mail.status '{"message_id":"remote"}' null worker
loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/synced"
jq -e '.result.deliveries[0].authority_sync=="committed"' "$dir/synced" >/dev/null || fail 'ack sync confirmation'
pass 'cooperative boundary, distinct remote read/ack and lost ack reply reconciliation'
request mail.reply '{"question_id":"remote","message_id":"remote-reply","body":"literal response","ack_claim_token":null}' null worker
loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/outbox"
jq -e '.status=="pending" and .extensions["loom.mail.origin"].authority_sync=="queued_for_authority" and (.result.deliveries|length)==0' "$dir/outbox" >/dev/null || fail 'remote send falsely accepted'
cp "$dir/request" "$dir/outgoing-reply"
pump
request mail.status '{"message_id":"remote-reply"}' null worker
loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/outbox-status"
jq -e '.extensions["loom.mail.origin"].authority_sync=="committed"' "$dir/outbox-status" >/dev/null || fail 'outbox acceptance sync'
LOOM_STATE=$dir/authority loom_state_get message remote-reply > "$dir/reply"
jq -e '.data.message.to==["run:run"] and .data.message.in_reply_to=="remote"' "$dir/reply" >/dev/null || fail 'remote reply target'
request mail.send '{"message_id":"unknown-remote","from":"owner","to":["task:unknown"],"kind":"guidance","subject":"","body":"unknown","thread_id":null,"in_reply_to":null,"expires_at":null}' null worker
loom_worker_bridge_handle "$dir/context" "$dir/request" > "$dir/queued"
pump
if LOOM_STATE=$dir/authority loom_state_get message unknown-remote >/dev/null 2>&1; then fail 'unknown remote recipient enqueued'; fi
pass 'remote reply imports to recorded sender; unknown recipient remains queued for authority'
LOOM_STATE=$dir/authority loom_state_get task "$(cat "$dir/task-id")" > "$dir/task"
jq -e '.data.state=="running" and .data.accepted_result==null' "$dir/task" >/dev/null || fail 'mail settled task'
jq -e 'all(.request.changes[]; .kind=="host" and .run_id==null)' "$dir/state/v2/journal/"*.json >/dev/null || fail 'spool wrote authority records'
[[ ! -e $dir/workspaces/worker/injected ]] || fail injection
# A changed pinned helper source refuses preflight; no silent reinstallation.
printf '\n# fixture source drift\n' >> "$dir/installations/v1/remote-helper.sh"
rc=0; loom_ssh_preflight "$dir/client" > "$dir/drift" || rc=$?
[[ $rc != 0 ]] || fail 'source drift accepted'
pass 'pinned helper source drift refused'
printf 'PASS real S5 helper/S6 authority mail integration using deterministic transport; actual SSH network acceptance NOT RUN\n'
