#!/usr/bin/env bash
# Real authority/helper fixture, no network or models; bounded offline retries.
# shellcheck disable=SC1090,SC1091,SC2016,SC2154
set -euo pipefail
here=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
MAIL_SSH_LIBRARY=1 source "$here/ssh.sh"
send_message offline attempt:attempt
did=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
for n in 1 2 3 4 5; do
    MAIL_FAULT=before pump
    LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/offline-state"
    [[ $(jq .data.tries "$dir/offline-state") == "$n" ]] || fail 'retry count'
    if (( n<5 )); then
        planned=$(jq .data.next_attempt_ms "$dir/offline-state")
        now=$(date +%s%3N)
        if (( planned>now )); then sleep "$(awk -v ms="$((planned-now))" 'BEGIN{print ms/1000}')"; fi
    fi
done
jq -e '.data.delivery.state=="dead_letter" and .data.delivery.reason=="retry_exhausted"' "$dir/offline-state" >/dev/null || fail 'retry ceiling'
cp "$dir/offline-state" "$dir/dead-letter"
request mail.poll '{"mailbox":"attempt:attempt","after_cursor":null,"limit":100}' null worker
mail_call worker; mail_call worker
LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/no-runner"
cmp "$dir/dead-letter" "$dir/no-runner" || fail 'poll retried dead letter'
request mail.retry "$(jq -cn --arg id "$did" '{delivery_id:$id}')" "$(jq .revision "$dir/dead-letter")"
mail_call
pump
LOOM_STATE=$dir/authority loom_state_get delivery "$did" > "$dir/retried"
jq -e '.data.facts.delivered and .data.tries==0' "$dir/retried" >/dev/null || fail 'explicit retry'
pass 'offline backoff ceiling, inspectable dead letter, passive poll and explicit retry'
send_message deadline attempt:attempt
# A separate immutable expired message tests expiry without rewriting history.
request mail.send '{"message_id":"past-deadline","from":"owner","to":["attempt:attempt"],"kind":"guidance","subject":"","body":"expired","thread_id":null,"in_reply_to":null,"expires_at":"2020-01-01T00:00:00Z"}'
mail_call
deadline_id=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
pump
LOOM_STATE=$dir/authority loom_state_get delivery "$deadline_id" > "$dir/deadline"
jq -e '.data.delivery.state=="dead_letter" and .data.delivery.reason=="deadline_expired"' "$dir/deadline" >/dev/null || fail 'deadline'
pass 'deadline expiry is explicit pump work and preserves message history'
printf 'PASS bounded retry/dead-letter fixtures; deterministic transport only\n'
