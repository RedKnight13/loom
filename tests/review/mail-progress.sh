#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2030,SC2031,SC2154 # actual fixture libraries provide shared state
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
MAIL_SSH_LIBRARY=1 source "$root/tests/mail/ssh.sh"
send_message first attempt:attempt
send_message second attempt:attempt
pump
LOOM_STATE=$dir/authority loom_state_list delivery '' 100 | jq -c '[.items[]|{id:.data.delivery.message_id,state:.data.delivery.state,delivered:.data.facts.delivered}]'
pump
pump
LOOM_STATE=$dir/authority loom_state_list delivery '' 100 > "$dir/final"
printf 'after three successful pumps without an ack: '
jq -c '[.items[]|{id:.data.delivery.message_id,state:.data.delivery.state,delivered:.data.facts.delivered}]' "$dir/final"
jq -e '[.items[]|select(.data.facts.delivered)]|length==2' "$dir/final" >/dev/null
printf 'PASS unacknowledged first delivery does not starve second delivery\n'
# Verify direct authority polling remains passive and refuses forged worker identity.
request mail.poll '{"mailbox":"attempt:attempt","after_cursor":null,"limit":20}' null worker
mail_call worker; cp "$dir/result" "$dir/poll-one"
mail_call worker
cmp <(jq .result "$dir/poll-one") <(jq .result "$dir/result")
jq '.actor.id="forged"' "$dir/request" > "$dir/forged"
rc=0; loom_mail_handle "$dir/mail-worker" "$dir/forged" > "$dir/refused" || rc=$?
[[ $rc == 2 ]]
printf 'PASS passive poll and forged worker refusal\n'
