#!/usr/bin/env bash
# Narrow S5 dispatch regression: workers cannot tunnel authority mail commands.
# shellcheck disable=SC1090,SC1091,SC2016,SC2154
set -euo pipefail
here=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
MAIL_SSH_LIBRARY=1 source "$here/ssh.sh"
request mail.status '{"message_id":"unknown"}' null worker
rc=0; loom_ssh_handle "$dir/client" "$dir/request" > "$dir/refused" || rc=$?
[[ $rc == 2 ]] || fail 'helper accepted authority status operation'
loom_protocol_validate response "$dir/refused" "$dir/request" || fail 'helper refusal envelope'
jq -e '.error.code=="unsupported_capability" and (.effects|length)==0' "$dir/refused" >/dev/null || fail 'helper dispatch refusal'
request mail.send '{"message_id":"bypass","from":"owner","to":["run:run"],"kind":"guidance","subject":"","body":"must use outbox","thread_id":null,"in_reply_to":null,"expires_at":null}' null worker
rc=0; loom_ssh_handle "$dir/client" "$dir/request" > "$dir/refused-send" || rc=$?
[[ $rc == 2 ]] || fail 'helper accepted direct send bypass'
if LOOM_STATE=$dir/authority loom_state_get message bypass >/dev/null 2>&1; then fail 'helper wrote authority'; fi
printf 'PASS narrow helper routes only authenticated mail.pump exchange; other coordination operations refused\n'
