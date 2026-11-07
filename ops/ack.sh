#!/usr/bin/env bash
# ack.sh <assignment-id> "<why>"
#
# A person has dealt with this assignment. Keep the history. Drop it from
# status. Not a fifth report state: workers cannot emit it. A second ack is
# refused so the first fact cannot be quietly rewritten (gap #31).
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
[[ $# == 2 ]] || loom_error 'usage: ack.sh <assignment-id> "<why>"'
loom_id "$1"
[[ -n $2 ]] || loom_error 'fact must not be empty'
[[ $2 != *$'\n'* ]] || loom_error 'fact is one line'
[[ $2 != *'## '* ]] || loom_error 'fact may not contain a markdown heading'
loom_init
loom_lock
file=$(loom_record "$1")
! loom_alive "$file" || loom_error 'worker is still live; ack after it settles'
jq -e 'has("acked") | not' "$file" >/dev/null || loom_error 'assignment already acked'
# shellcheck disable=SC2016
loom_write "$file" '.acked = {at: (now | todateiso8601), fact: $fact}' --arg fact "$2"
printf '%s acked\n' "$1"
