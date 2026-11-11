#!/usr/bin/env bash
# Actual S6-authorized S4 process, two explicit cooperative tool boundaries.
# shellcheck disable=SC1090,SC1091,SC2016,SC2154
set -euo pipefail
here=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
MAIL_FIXTURE_LIBRARY=1 source "$here/run.sh"
printf -v bridge '%q' "$mail_root/ops/worker-bridge.sh"
script="bash $bridge boundary \"\$HOME/.loom/mail-context\" 20 > \"\$HOME/startup.json\" || exit 21
printf ready > \"\$HOME/ready\"
for _ in {1..1200}; do
    if [[ -f \"\$HOME/next-turn\" ]]; then
        bash $bridge boundary \"\$HOME/.loom/mail-context\" 20 > \"\$HOME/turn.json\" || exit 22
        exit 0
    fi
    sleep 0.05
done
exit 23"
fixture cooperative "$script"
mkdir "$dir/workspaces/worker/.loom"
cp "$dir/mail-worker" "$dir/workspaces/worker/.loom/mail-context"
send_message startup "task:$(cat "$dir/task-id")" 'quoted $(touch injected) startup'
call "$dir/start"
for _ in {1..600}; do [[ ! -f $dir/workspaces/worker/ready ]] || break; sleep 0.05; done
[[ -f $dir/workspaces/worker/ready ]] || fail 'startup boundary did not finish'
jq -e 'any(.messages[];.message.message_id=="startup" and .delivery.state=="read")' "$dir/workspaces/worker/startup.json" >/dev/null || fail 'startup presentation'
send_message busy "task:$(cat "$dir/task-id")" 'busy worker waits for boundary'
busy_delivery=$(jq -r '.result.deliveries[0].delivery_id' "$dir/result")
LOOM_STATE=$dir/authority loom_state_get delivery "$busy_delivery" > "$dir/busy"
jq -e '.data.delivery.state=="pending" and (.data.facts.read|not)' "$dir/busy" >/dev/null || fail 'send fabricated live read'
[[ ! -e $dir/workspaces/worker/turn.json ]] || fail 'hidden wake'
touch "$dir/workspaces/worker/next-turn"
settled
jq -e '.result.terminal.captured and .result.terminal.exit_code==0' "$dir/result" >/dev/null || fail 'cooperative worker captured exit'
jq -e 'any(.messages[];.message.message_id=="busy" and .delivery.state=="read")' "$dir/workspaces/worker/turn.json" >/dev/null || fail 'turn boundary presentation'
[[ ! -e $dir/workspaces/worker/injected ]] || fail 'message evaluation'
LOOM_STATE=$dir/authority loom_state_get task "$(cat "$dir/task-id")" > "$dir/task"
jq -e '.data.state=="running" and .data.accepted_result==null' "$dir/task" >/dev/null || fail 'worker boundary completed authority task'
printf 'PASS actual S6/S4 cooperative startup and turn delivery, busy pending, captured exit, no implicit task acceptance\n'
