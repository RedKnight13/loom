#!/usr/bin/env bash
# Fixture-only policy/discovery plus optional real-store integration. No launches.
# shellcheck disable=SC1090,SC1091 # Source paths are explicit test arguments.
# shellcheck disable=SC2030,SC2031 # Source-aware analysis conflates module-local scratch with test scratch.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
umask 077
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok  %s\n' "$*"; }
deny() {
    local status=0
    "$@" > "$scratch/denied.out" 2> "$scratch/denied.err" || status=$?
    [[ $status == 2 ]] || fail "expected refusal 2, got $status: $*"
}
assert() { jq -e "$1" "$2" >/dev/null || fail "$1"; }
before=$(set +o; trap -p; pwd; umask; export -p)
source "$root/ops/policy.sh"
source "$root/ops/discover.sh"
after=$(set +o; trap -p; pwd; umask; export -p)
[[ $before == "$after" ]] || fail 'source modified shell state'
ok 'source-safe modules'

cat > "$scratch/config.json" <<'JSON'
{"schema":2,"repo":"example/project","execution":{"provider":"native","transport":"ssh","placement":{"allowed_hosts":["compute-primary"],"selection":"explicit","selected_host":"compute-primary","allow_local":false,"fallback":"deny"},"agent_profile":"fixture","model":"opaque-model","effort":null},"limits":{"workers":1,"operation_timeout_ms":30000},"ticket_provider":"github"}
JSON
cat > "$scratch/hosts.json" <<'JSON'
{"schema":2,"hosts":[{"id":"compute-primary","transport":"ssh","destination":"compute.example.invalid","workspace_root":"/srv/workspaces","identity":"pinned-host-key","helper":{"version":"1.0","digest":"git-blob-sha1-v1:1111111111111111111111111111111111111111"}}]}
JSON
cat > "$scratch/profiles.json" <<'JSON'
{"schema":2,"agents":[{"id":"fixture","executable":"/opt/fixture/agent","argv":["--batch","literal $(touch forbidden); `false`"],"prompt_ingress":"stdin","model":{"argv":["--model"],"values":["opaque-model","other-model"]},"effort":null}],"adapters":[{"id":"example-adapter","executable":"/opt/fixture/adapter","argv":["--json"]}]}
JSON
config=$scratch/config.json hosts=$scratch/hosts.json profiles=$scratch/profiles.json
resolve() { loom_policy_resolve "$config" "$hosts" "$profiles"; }
resolve > "$scratch/pin.json"
assert '.provider == "native" and .transport == "ssh" and .model == "opaque-model" and .effort == null and .argv[-2:] == ["--model","opaque-model"] and .adapter == null' "$scratch/pin.json"
loom_policy_check "$scratch/pin.json" "$config" "$hosts" "$profiles"
ok 'exact provider/host/profile/model/argv pinned'

for mutation in '.schema=3' '.unknown=true' '.execution.placement.fallback="local"' \
  '.execution.placement.selection="auto"' '.execution.placement.selected_host="unapproved"' \
  '.execution.model="unsupported"' '.execution.effort="high"' '.execution.provider="auto"' \
  '.execution.transport="process"' '.limits.workers=0' '.limits.operation_timeout_ms=300001' \
  '.execution.model="a\u0000b"'; do
    jq "$mutation" "$config" > "$scratch/bad.json"
    deny loom_policy_resolve "$scratch/bad.json" "$hosts" "$profiles"
done
# Environment overrides have no influence on explicit remote-only policy.
LOOM_ALLOW_LOCAL=1 LOOM_EXECUTOR=local LOOM_MODEL=other-model resolve > "$scratch/environment-pin.json"
cmp "$scratch/pin.json" "$scratch/environment-pin.json"
jq '.execution.transport="process"' "$config" > "$scratch/local.json"
jq '.hosts[0].transport="process" | .hosts[0].destination=null' "$hosts" > "$scratch/local-hosts.json"
deny loom_policy_resolve "$scratch/local.json" "$scratch/local-hosts.json" "$profiles"
jq '.execution.placement.allow_local=true' "$scratch/local.json" > "$scratch/allowed-local.json"
loom_policy_resolve "$scratch/allowed-local.json" "$scratch/local-hosts.json" "$profiles" > "$scratch/local-pin.json"
ok 'denied local/unapproved host/model/effort/provider; explicit local fixtures allowed'

for mutation in '.execution.provider="example-adapter"' '.execution.model="other-model"' \
  '.execution.model=null' '.execution.placement.allow_local=true'; do
    jq "$mutation" "$config" > "$scratch/changed.json"
    deny loom_policy_check "$scratch/pin.json" "$scratch/changed.json" "$hosts" "$profiles"
done
jq '.hosts[0].identity="different-host-key"' "$hosts" > "$scratch/changed-hosts.json"
deny loom_policy_check "$scratch/pin.json" "$config" "$scratch/changed-hosts.json" "$profiles"
jq '.agents[0].argv += ["--different"]' "$profiles" > "$scratch/changed-profiles.json"
deny loom_policy_check "$scratch/pin.json" "$config" "$hosts" "$scratch/changed-profiles.json"
cat "$config" > "$scratch/changed.json"; printf '\n' >> "$scratch/changed.json"
deny loom_policy_check "$scratch/pin.json" "$scratch/changed.json" "$hosts" "$profiles"
ok 'binding and byte-level config/registry mutations refused'

# A config changed after its initial digest but during validation must refuse.
cp "$config" "$scratch/racing.json"
original_validate=$(declare -f loom_policy_validate)
eval "${original_validate/loom_policy_validate/fixture_policy_validate}"
loom_policy_validate() {
    fixture_policy_validate "$@" || return $?
    if [[ $1 == profiles ]]; then printf '\n' >> "$scratch/racing.json"; fi
}
deny loom_policy_resolve "$scratch/racing.json" "$hosts" "$profiles"
eval "$original_validate"
ok 'concurrent config edit is detected before pin return'

ln -s "$config" "$scratch/link.json"
deny loom_policy_resolve "$scratch/link.json" "$hosts" "$profiles"
ln -s "$scratch" "$scratch/link-dir"
deny loom_policy_resolve "$scratch/link-dir/config.json" "$hosts" "$profiles"
deny loom_policy_resolve "$scratch/../${scratch##*/}/config.json" "$hosts" "$profiles"
deny loom_policy_file "$scratch/line"$'\n'"/config.json"
cp "$config" "$scratch/writable.json"; chmod 666 "$scratch/writable.json"
deny loom_policy_resolve "$scratch/writable.json" "$hosts" "$profiles"
mkdir "$scratch/writable-parent"
cp "$config" "$scratch/writable-parent/config.json"
chmod 777 "$scratch/writable-parent"
deny loom_policy_resolve "$scratch/writable-parent/config.json" "$hosts" "$profiles"
cp "$config" "$scratch/hardlink-source.json"
ln "$scratch/hardlink-source.json" "$scratch/hardlink.json"
deny loom_policy_resolve "$scratch/hardlink.json" "$hosts" "$profiles"
printf '{"schema":2,"schema":2}\n' > "$scratch/duplicate.json"
deny loom_policy_json "$scratch/duplicate.json"
printf '{"a":{"x":1},"a":{"y":2}}\n' > "$scratch/duplicate.json"
deny loom_policy_json "$scratch/duplicate.json"
printf '{"a":1,"\\u0061":2}\n' > "$scratch/duplicate.json"
deny loom_policy_json "$scratch/duplicate.json"
printf '{"a":1e0}\n' > "$scratch/duplicate.json"
deny loom_policy_json "$scratch/duplicate.json"
printf '{"a":1.000000000000000001}\n' > "$scratch/duplicate.json"
deny loom_policy_json "$scratch/duplicate.json"
cat "$config" "$config" > "$scratch/two.json"
deny loom_policy_json "$scratch/two.json"
jq '.agents[0].executable="/opt/../agent"' "$profiles" > "$scratch/bad-profiles.json"
deny loom_policy_resolve "$config" "$hosts" "$scratch/bad-profiles.json"
ok 'traversal, links, writable config, duplicate keys, ambiguous numbers refused'

# Poison all launch/probe commands: passive discovery must never call them.
mkdir "$scratch/bin"
for tool in ssh orca codex claude fixture-agent; do
    printf '#!/usr/bin/env bash\nprintf "unexpected probe\\n" >> %q\nexit 97\n' "$scratch/probed" > "$scratch/bin/$tool"
    chmod +x "$scratch/bin/$tool"
done
PATH="$scratch/bin:$PATH" loom_discover "$config" "$hosts" "$profiles" > "$scratch/discovery.json"
[[ ! -e $scratch/probed ]] || fail 'unexpected command probe'
assert '.profiles[0].configured.value == true and .profiles[0].installed.value == null and .profiles[0].launch_verified.value == null and .host.reachable.value == null and .authentication.value == null' "$scratch/discovery.json"
scope=$(jq -r .scope_digest "$scratch/discovery.json")
jq -cn --arg scope "$scope" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{schema:2,scope_digest:$scope,observations:[{dimension:"installed",value:true,source:"bounded_version_probe",observed_at:$now,evidence_ref:"evidence/version",attempt_id:null},{dimension:"reachable",value:false,source:"transport_probe",observed_at:$now,evidence_ref:"evidence/transport",attempt_id:null}]}' > "$scratch/evidence.json"
loom_discover "$config" "$hosts" "$profiles" "$scratch/evidence.json" > "$scratch/discovery.json"
assert '.profiles[0].installed.value == true and .host.reachable.value == false and .profiles[0].launch_verified.value == null and .profiles[0].model == "opaque-model" and .authentication.value == null' "$scratch/discovery.json"
jq '.observations[0].dimension="launch_verified"' "$scratch/evidence.json" > "$scratch/bad-evidence.json"
deny loom_discover "$config" "$hosts" "$profiles" "$scratch/bad-evidence.json"
jq '.observations[0].observed_at="2000-01-01T00:00:00Z"' "$scratch/evidence.json" > "$scratch/stale.json"
loom_discover "$config" "$hosts" "$profiles" "$scratch/stale.json" > "$scratch/discovery.json"
assert '.profiles[0].installed.value == null and .profiles[0].installed.source == "stale_or_future"' "$scratch/discovery.json"
jq '.scope_digest="git-blob-sha1-v1:2222222222222222222222222222222222222222"' "$scratch/evidence.json" > "$scratch/stale.json"
loom_discover "$config" "$hosts" "$profiles" "$scratch/stale.json" > "$scratch/discovery.json"
assert '.profiles[0].installed.value == null and .host.reachable.value == null' "$scratch/discovery.json"
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.observations += [{dimension:"launch_verified",value:true,source:"authorized_attempt",observed_at:$now,evidence_ref:"evidence/startup",attempt_id:"prior-attempt"}]' "$scratch/evidence.json" > "$scratch/launch-evidence.json"
loom_discover "$config" "$hosts" "$profiles" "$scratch/launch-evidence.json" > "$scratch/discovery.json"
assert '.profiles[0].launch_verified.value == true and .host.reachable.value == false and .authentication.value == null' "$scratch/discovery.json"
jq '.observations[0].value=false | .observations[0].source="missing_executable"' "$scratch/evidence.json" > "$scratch/missing-evidence.json"
loom_discover "$config" "$hosts" "$profiles" "$scratch/missing-evidence.json" > "$scratch/discovery.json"
assert '.profiles[0].installed.value == false and .profiles[0].launch_verified.value == null' "$scratch/discovery.json"
jq '.execution.provider="example-adapter"' "$config" > "$scratch/adapter-config.json"
PATH="$scratch/bin:$PATH" loom_discover "$scratch/adapter-config.json" "$hosts" "$profiles" > "$scratch/discovery.json"
assert '.provider.id == "example-adapter" and .profiles[0].installed.value == null and .host.reachable.value == null' "$scratch/discovery.json"
[[ ! -e $scratch/probed ]] || fail 'provider fallback or implicit probe'
ok 'unavailable and stale discovery stay unknown; install never proves model/launch/auth'

# Guard the file-read boundary: all inspected files must be the explicit inputs.
# An unknown credential path field is rejected without ever reading its target.
mkfifo "$scratch/credential-never-read"
jq --arg path "$scratch/credential-never-read" '.agents[0].credential_file=$path' "$profiles" > "$scratch/credential-profile.json"
deny loom_policy_resolve "$config" "$hosts" "$scratch/credential-profile.json"
original_file=$(declare -f loom_policy_file)
eval "${original_file/loom_policy_file/fixture_policy_file}"
loom_policy_file() {
    case $1 in "$config"|"$hosts"|"$profiles") fixture_policy_file "$1";; *) fail "unexpected read: $1";; esac
}
loom_discover "$config" "$hosts" "$profiles" > "$scratch/discovery.json"
eval "$original_file"
ok 'no credential path expansion or implicit files; discovery is passive'

if [[ $# == 0 ]]; then
    source "$root/tests/policy/fake-store.sh"
    expected_durable=false
    printf 'store backend: synthetic CAS (no persistence claim)\n'
elif [[ $# == 2 && $1 == --state-api && -f $2 ]]; then
    source "$2"
    expected_durable=true
    printf 'store backend: real S2\n'
else fail 'usage: run.sh [--state-api /absolute/path/to/ops/state.sh]'; fi
export LOOM_STATE="$scratch/state"
loom_state_init fixture-store > "$scratch/init.out"
loom_policy_capacity_init_request fixture-store fixture-owner > "$scratch/init-request.json"
loom_state_transact "$scratch/init-request.json" > "$scratch/init-receipt.json"
assert ".durable == $expected_durable" "$scratch/init-receipt.json"
loom_policy_capacity "$config" "$hosts" "$profiles" > "$scratch/capacity.json"
assert '.configured == 1 and .available == 1' "$scratch/capacity.json"
context() {
    jq -cn --arg id "$1" '{schema:2,store_id:"fixture-store",actor_id:"fixture-owner",operation_id:$id,idempotency_key:$id,run_id:"fixture-run",attempt_id:$id}'
}
context attempt-a > "$scratch/a.json"
context attempt-b | jq '.run_id="other-fixture-run"' > "$scratch/b.json"
loom_policy_reserve_request "$config" "$hosts" "$profiles" "$scratch/a.json" > "$scratch/reserve-a.json"
loom_policy_reserve_request "$config" "$hosts" "$profiles" "$scratch/b.json" > "$scratch/reserve-b.json"
for id in a b; do
    (set +e; loom_state_transact "$scratch/reserve-$id.json" > "$scratch/receipt-$id.json" 2> "$scratch/error-$id"; printf '%s\n' "$?" > "$scratch/exit-$id") &
done
wait
a=$(cat "$scratch/exit-a") b=$(cat "$scratch/exit-b")
[[ $a:$b == 0:2 || $a:$b == 2:0 ]] || fail "CAS race exits $a:$b"
if [[ $a == 0 ]]; then winner=a; else winner=b; fi
assert ".durable == $expected_durable" "$scratch/receipt-$winner.json"
loom_state_transact "$scratch/reserve-$winner.json" > "$scratch/replay.json"
cmp "$scratch/receipt-$winner.json" "$scratch/replay.json"
jq -cS '.result.scope_digest="git-blob-sha1-v1:4444444444444444444444444444444444444444"' "$scratch/reserve-$winner.json" > "$scratch/conflicting-retry.json"
deny loom_state_transact "$scratch/conflicting-retry.json"
loom_policy_capacity "$config" "$hosts" "$profiles" > "$scratch/capacity.json"
assert '.occupied == 1 and .reserved == 1 and .available == 0' "$scratch/capacity.json"
deny loom_policy_reserve_request "$config" "$hosts" "$profiles" "$scratch/a.json"
deny loom_policy_reserve_request "$config" "$hosts" "$profiles" "$scratch/b.json"
ok 'one of two simultaneous CAS reservations wins; exact replay does not add a slot'

jq '.operation_id="observe-unknown" | .idempotency_key="observe-unknown"' "$scratch/$winner.json" > "$scratch/observe-context.json"
jq -cn --arg scope "$scope" '{schema:2,scope_digest:$scope,state:"unknown",evidence_ref:"evidence/lost-contact",confirmed_stopped:false}' > "$scratch/observation.json"
loom_policy_observe_request "$scratch/observe-context.json" "$scratch/observation.json" > "$scratch/observe-request.json"
loom_state_transact "$scratch/observe-request.json" > "$scratch/observe-receipt.json"
loom_policy_capacity "$config" "$hosts" "$profiles" > "$scratch/capacity.json"
assert '.occupied == 1 and .unknown == 1 and .available == 0' "$scratch/capacity.json"
context attempt-c > "$scratch/c.json"
deny loom_policy_reserve_request "$config" "$hosts" "$profiles" "$scratch/c.json"
jq '.state="settled"' "$scratch/observation.json" > "$scratch/unproven-stop.json"
deny loom_policy_observe_request "$scratch/observe-context.json" "$scratch/unproven-stop.json"
jq '.scope_digest="git-blob-sha1-v1:3333333333333333333333333333333333333333"' "$scratch/observation.json" > "$scratch/wrong-scope.json"
deny loom_policy_observe_request "$scratch/observe-context.json" "$scratch/wrong-scope.json"
ok 'unknown attempts occupy capacity; unconfirmed stop and wrong-scope evidence refused'

jq '.operation_id="settle" | .idempotency_key="settle"' "$scratch/observe-context.json" > "$scratch/settle-context.json"
jq '.state="settled" | .confirmed_stopped=true | .evidence_ref="evidence/confirmed-exit"' "$scratch/observation.json" > "$scratch/settle.json"
loom_policy_observe_request "$scratch/settle-context.json" "$scratch/settle.json" > "$scratch/settle-request.json"
loom_state_transact "$scratch/settle-request.json" > "$scratch/settle-receipt.json"
loom_policy_reserve_request "$config" "$hosts" "$profiles" "$scratch/c.json" > "$scratch/reserve-c.json"
loom_state_transact "$scratch/reserve-c.json" > "$scratch/receipt-c.json"
loom_policy_capacity "$config" "$hosts" "$profiles" > "$scratch/capacity.json"
assert '.occupied == 1 and .reserved == 1 and .unknown == 0' "$scratch/capacity.json"
ok 'only core-confirmed settlement frees a slot for a new attempt'
LOOM_STATE="$scratch/missing-store" deny loom_policy_capacity "$config" "$hosts" "$profiles"
[[ ! -e $scratch/missing-store ]] || fail 'implicit store creation'
ok 'missing store fails closed without initialization or legacy fallback'
printf 'policy suite passed\n'
