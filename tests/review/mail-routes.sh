#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2030,SC2031,SC2154 # actual fixture libraries provide shared state
# Component regression for actual S7 pump route selection. Store and network
# seams return deterministic empty receipts; no process/SSH/provider is launched.
set -euo pipefail
snapshot=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
evidence=$(mktemp -d)
umask 077
source "$snapshot/ops/mail.sh"
fixture_dir=$(mktemp -d "$evidence/pump-fixture.XXXXXXXX")
trap 'rm -rf "$evidence"' EXIT
export REVIEW_ROUTE_LOG="$evidence/pump-routes.calls"
: > "$REVIEW_ROUTE_LOG"
export LOOM_MAIL_SSH_MODULE="$fixture_dir/transport.sh"
cat > "$LOOM_MAIL_SSH_MODULE" <<'SH'
_loom_ssh_config() { return 0; }
loom_ssh_handle() {
    printf '%s\n' "${1##*/}" >> "$REVIEW_ROUTE_LOG"
    printf '{"extensions":{"loom.mail.exchange":{"receipts":[],"outbox":[]}}}\n'
}
SH
loom_policy_digest() { printf 'git-blob-sha1-v1:1111111111111111111111111111111111111111\n'; }
loom_state_get() {
    [[ -f $fixture_dir/cursor ]] || return 2
    jq '{data:.}' "$fixture_dir/cursor"
}
_loom_mail_change() { cp "$2" "$fixture_dir/cursor"; }
loom_state_list() { printf '{"items":[],"next_cursor":null}\n'; }
_lm_tmp="$fixture_dir/work"
mkdir "$_lm_tmp"
_lm_context="$fixture_dir/context"
_lm_request="$fixture_dir/request"
jq -cn '{role:"owner",routes:[]}' > "$_lm_context"
jq -cn '{id:"run",revision:1,epoch:0,data:{tasks:{},attempts:{}}}' > "$_lm_tmp/run"
for n in {1..80}; do
    aid="attempt-$n"
    cfg="$fixture_dir/route-$n"
    jq -cn --arg a "$aid" '{context_id:$a,identity:{transport_identity:"fixture-identity"}}' > "$cfg"
    jq --arg a "$aid" --arg c "$cfg" '.routes += [{attempt_id:$a,config:$c}]' "$_lm_context" > "$fixture_dir/new"
    mv "$fixture_dir/new" "$_lm_context"
    jq --arg a "$aid" '.data.attempts[$a]={attempt_id:$a,task_id:"task",launch_authorized:true,binding:{actor:{id:"owner",run_id:"run",epoch:0},target:{assignment_id:"assignment",attempt_id:$a,host_id:"fixture"}},policy_pin:{host:{identity:"fixture-identity"}}}' "$_lm_tmp/run" > "$fixture_dir/new"
    mv "$fixture_dir/new" "$_lm_tmp/run"
done
for round in 1 2 3 4; do
    jq -cn --arg id "pump-$round" '{actor:{id:"owner",run_id:"run",epoch:0},operation_id:$id,expected_revision:1,timeout_ms:300000,args:{run_id:"run",deadline_ms:300000}}' > "$_lm_request"
    : > "$_lm_tmp/change-lines"
    started=$EPOCHREALTIME
    rc=0; _loom_mail_pump || rc=$?
    jq -cn --argjson round "$round" --argjson rc "$rc" --arg start "$started" --arg end "$EPOCHREALTIME" --slurpfile result "$_lm_tmp/result" '{round:$round,exit:$rc,wall_s:(($end|tonumber)-($start|tonumber)),result:$result[0]}' >> "$evidence/pump-routes.jsonl"
done
[[ $(wc -l < "$REVIEW_ROUTE_LOG") == 80 ]]
[[ $(sort -u "$REVIEW_ROUTE_LOG" | wc -l) == 80 ]]
grep -qx 'route-80' "$REVIEW_ROUTE_LOG"
printf 'PASS: four bounded pumps service all 80 routes\n'
