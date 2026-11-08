#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2030,SC2031,SC2016,SC1091 # literal fixture scripts and dynamic module source paths
# Synthetic processes only; no agents, model clients, network or credentials.
set -euo pipefail
ops=$(cd "${BASH_SOURCE[0]%/*}/../../ops" && pwd -P)
export LOOM_NATIVE_PROTOCOL_MODULE=${LOOM_NATIVE_PROTOCOL_MODULE:-$ops/protocol.sh}
export LOOM_NATIVE_STATE_MODULE=${LOOM_NATIVE_STATE_MODULE:-$ops/state.sh}
export LOOM_NATIVE_POLICY_MODULE=${LOOM_NATIVE_POLICY_MODULE:-$ops/policy.sh}
for module in "$LOOM_NATIVE_PROTOCOL_MODULE" "$LOOM_NATIVE_STATE_MODULE" "$LOOM_NATIVE_POLICY_MODULE"; do [[ -f $module ]] || { printf 'Missing dependency: %s\n' "$module" >&2; exit 2; }; done
# shellcheck source=ops/native.sh
source "$ops/native.sh"
_loom_native_load
umask 077
scratch=$(mktemp -d)
cleanup() {
    local file pid ticks
    # Only fixture identities, never names or arbitrary PGIDs.
    for file in "$scratch"/*/state/native/*/identity; do
        [[ -f $file ]] || continue
        pid=$(jq -r .supervisor_pid "$file"); ticks=$(jq -r .supervisor_start_ticks "$file")
        if _loom_native_proc "$pid" && [[ ${_np[19]} == "$ticks" ]]; then kill -TERM "$pid" 2>/dev/null || :; fi
    done
    if [[ ${NATIVE_KEEP_FIXTURES:-0} == 1 ]]; then printf 'fixtures retained: %s\n' "$scratch" >&2
    else rm -rf "$scratch"; fi
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok %s\n' "$*"; }
fixture() {
    local name=$1 script=$2
    dir=$scratch/$name
    mkdir -p "$dir/authority" "$dir/state" "$dir/workspaces/worker"
    printf '#!/usr/bin/env bash\n%s\n' "$script" > "$dir/worker"
    chmod 700 "$dir/worker"
    printf 'prompt\n' > "$dir/prompt"
    jq -cn --arg exe "$dir/worker" '{schema:2,agents:[{id:"fixture",executable:$exe,argv:[],prompt_ingress:"stdin",model:null,effort:null}],adapters:[]}' > "$dir/profiles"
    jq -cn --arg root "$dir/workspaces" '{schema:2,hosts:[{id:"fixture-host",transport:"process",destination:null,workspace_root:$root,identity:"fixture-transport",helper:{version:"1",digest:"git-blob-sha1-v1:1111111111111111111111111111111111111111"}}]}' > "$dir/hosts"
    printf '%s\n' '{"schema":2,"repo":"example/project","execution":{"provider":"native","transport":"process","placement":{"allowed_hosts":["fixture-host"],"selection":"explicit","selected_host":"fixture-host","allow_local":true,"fallback":"deny"},"agent_profile":"fixture","model":null,"effort":null},"limits":{"workers":1,"operation_timeout_ms":10000},"ticket_provider":"github"}' > "$dir/config"
    loom_policy_resolve "$dir/config" "$dir/hosts" "$dir/profiles" > "$dir/pin"
    jq -cn --arg workspace "$dir/workspaces/worker" --arg prompt "$dir/prompt" --arg prompt_digest "$(loom_policy_digest "$dir/prompt")" --arg profile_digest "$(jq -r .profile_digest "$dir/pin")" --arg executable_digest "$(loom_policy_digest "$dir/worker")" '{schema:1,actor:{id:"owner",run_id:"run",epoch:0},target:{assignment_id:"assignment",attempt_id:"attempt",host_id:"fixture-host"},workspace_id:"workspace",workspace:$workspace,prompt_ref:"prompt",prompt:$prompt,manifest_digest:"git-blob-sha1-v1:1111111111111111111111111111111111111111",profile_digest:$profile_digest,limits:{runtime_ms:null,stop_on_timeout:false,allow_kill:false,output_bytes:8192},stop_authorized:true,release_authorized:false,executable_digest:$executable_digest,prompt_digest:$prompt_digest}' > "$dir/binding"
    jq -cn --arg dir "$dir" '{schema:1,state_root:($dir+"/state"),store_id:"native-spool",installation_id:"fixture-installation",transport_identity:"fixture-transport",config:($dir+"/config"),hosts:($dir+"/hosts"),profiles:($dir+"/profiles"),pin:($dir+"/pin"),binding:($dir+"/binding"),authorization:($dir+"/authorization"),authority_store_id:"fixture-authority"}' > "$dir/context"
    LOOM_STATE=$dir/state loom_state_init native-spool >/dev/null
    authorize
    jq -cn --slurpfile b "$dir/binding" --slurpfile p "$dir/pin" '{protocol:"loom.execution",version:{major:1,minor:0},request_id:"request",operation_id:"start",idempotency_key:"start",op:"execution.start",actor:$b[0].actor,target:$b[0].target,expected_revision:null,timeout_ms:10000,args:{workspace_id:$b[0].workspace_id,profile_id:$p[0].profile.id,profile_digest:$b[0].profile_digest,argv:$p[0].argv,prompt_ref:$b[0].prompt_ref,model:null,effort:null,limits:$b[0].limits,manifest_digest:$b[0].manifest_digest},extensions:{}}' > "$dir/start"
    spool=$dir/state/native/$(printf 'attempt\n' | git hash-object --stdin)
}
authorize() {
    LOOM_STATE=$dir/authority loom_state_init fixture-authority >/dev/null
    loom_policy_capacity_init_request fixture-authority owner > "$dir/cap-init"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/cap-init" > /dev/null
    printf '%s\n' '{"schema":2,"store_id":"fixture-authority","actor_id":"owner","operation_id":"capacity","idempotency_key":"capacity","run_id":"run","attempt_id":"attempt"}' > "$dir/reserve-context"
    LOOM_STATE=$dir/authority loom_policy_reserve_request "$dir/config" "$dir/hosts" "$dir/profiles" "$dir/reserve-context" > "$dir/cap-reserve"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/cap-reserve" > "$dir/cap-receipt"
    jq -cnS --slurpfile b "$dir/binding" --arg digest "$(jq -cS 'del(.stop_authorized,.release_authorized)' "$dir/binding" | loom_policy_scope)" '{schema:2,store_id:"fixture-authority",operation_id:"authorize",idempotency_key:"authorize",op:"fixture.authorize",actor:$b[0].actor,target:$b[0].target,checks:[],changes:[{kind:"run",id:"run",expected_revision:null,run_id:"run",epoch:0,data:{owner_id:"owner"}},{kind:"attempt",id:"attempt",expected_revision:null,run_id:"run",epoch:0,data:{binding:$b[0]}}],events:[{type:"fixture.authorized",entity_ids:["run","attempt"],payload:{},observed_at:null}],result:{actor:$b[0].actor,target:$b[0].target,binding_digest:$digest}}' > "$dir/launch-authorize"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/launch-authorize" > "$dir/launch-receipt"
    jq -cn --slurpfile c "$dir/cap-receipt" --slurpfile l "$dir/launch-receipt" '{capacity_receipt:$c[0],launch_receipt:$l[0]}' > "$dir/authorization"
}

call() {
    local req=$1 expected=${2:-0} rc=0
    loom_native_handle "$dir/context" "$req" > "$dir/result" || rc=$?
    [[ $rc == "$expected" ]] || fail "call $(jq -r .op "$req") exit $rc wanted $expected: $(cat "$dir/result")"
    loom_protocol_validate response "$dir/result" "$req" || fail 'invalid response'
}
inspect_request() {
    jq '.op="execution.inspect"|.operation_id=null|.idempotency_key=null|.expected_revision=null|.args={}' "$dir/start" > "$dir/inspect"
}
settled() {
    inspect_request
    for _ in {1..60}; do
        call "$dir/inspect"
        [[ $(jq -r .result.state "$dir/result") != exited ]] || return 0
        sleep 0.05
    done
    fail "did not settle: $(cat "$dir/result")"
}
stop_request() {
    jq --argjson kill "$1" --argjson timeout "${2:-10000}" '.op="execution.stop"|.operation_id="stop"|.idempotency_key="stop"|.expected_revision=1|.timeout_ms=$timeout|.args={reason:"fixture stop",grace_ms:100,allow_kill:$kill}' "$dir/start" > "$dir/stop"
}
if [[ ${LOOM_NATIVE_FIXTURE_LIBRARY:-0} == 1 ]]; then return 0; fi

fixture nonzero 'printf "hello\\n"; exit 7'
jq '.op="hello"|.operation_id=null|.idempotency_key=null|.target={assignment_id:null,attempt_id:null,host_id:null}|.args={versions:[{major:1,minor:0}],required_capabilities:["execution.stop.group.v1"]}' "$dir/start" > "$dir/hello"
mv "$dir/authorization" "$dir/authorization-held"
call "$dir/hello"
call "$dir/start" 2
[[ ! -d $dir/state/native ]] || fail 'preflight created native effects'
mv "$dir/authorization-held" "$dir/authorization"
pass 'S1 hello negotiation and supported capability result'
call "$dir/start"
settled
jq -e '.result.terminal.exit_code==7 and .result.terminal.captured==true' "$dir/result" >/dev/null || fail 'captured exit'
call "$dir/start"
[[ $(jq -r 'select(.request.op=="execution.start")|.sequence' "$dir/state/v2/journal/"*.json | wc -l) == 1 ]] || fail 'duplicate launch'
pass 'captured nonzero exit and same-operation replay'

# Journal receipts survive loss of rebuildable files; capacity remains authority-owned.
rm "$spool/completion"
inspect_request; call "$dir/inspect"
jq -e '.result.terminal.exit_code==7' "$dir/result" >/dev/null || fail 'journal completion recovery'
LOOM_STATE=$dir/authority loom_policy_capacity "$dir/config" "$dir/hosts" "$dir/profiles" > "$dir/capacity"
jq -e '.reserved==1 and .available==0' "$dir/capacity" >/dev/null || fail 'host freed authority slot'
jq '.args.argv += ["different"]' "$dir/start" > "$dir/conflict"
call "$dir/conflict" 2
jq '.actor.epoch=1' "$dir/start" > "$dir/fenced"; call "$dir/fenced" 2
pass 'receipt recovery, authority-owned capacity, conflicting launch and epoch refusal'
# Explicit collection approval only changes a provisioned permission, not binding identity.
jq '.release_authorized=true' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
jq '.op="execution.release"|.operation_id="release"|.idempotency_key="release"|.expected_revision=1|.args={retention_policy:"release"}' "$dir/start" > "$dir/release"
call "$dir/release"; call "$dir/release"
[[ -d $dir/workspaces/worker && -f $spool/output/index ]] || fail 'release deleted evidence/workspace'
pass 'release requires authority approval and preserves evidence/tombstones'

# Preserve metacharacters literally through pin, JSON, NUL decoder and exec.
fixture argv 'printf "%s\n" "$@" > args; printf "%s\n" "${UNDECLARED_SECRET-unset}" > env; if [[ -e /proc/self/fd/19 ]]; then printf leaked >&19; fi'
# A separate fresh fixture policy revision is authorized before reservation.
jq '.agents[0].argv=["space value","quote\"value","$HOME","`touch injected`","line\nvalue"]' "$dir/profiles" > "$dir/new"; mv "$dir/new" "$dir/profiles"
loom_policy_resolve "$dir/config" "$dir/hosts" "$dir/profiles" > "$dir/pin"
jq --arg digest "$(jq -r .profile_digest "$dir/pin")" '.profile_digest=$digest' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
rm -rf "$dir/authority"; mkdir "$dir/authority"; authorize
jq --slurpfile p "$dir/pin" '.args.argv=$p[0].argv|.args.profile_digest=$p[0].profile_digest' "$dir/start" > "$dir/new"; mv "$dir/new" "$dir/start"
exec 19> "$dir/leaked-fd"
UNDECLARED_SECRET=fixture call "$dir/start"; settled
exec 19>&-
[[ ! -s $dir/leaked-fd ]] || fail 'inherited descriptor leaked'
jq -r '.argv[1:][]' "$dir/pin" > "$dir/expected"
cmp "$dir/expected" "$dir/workspaces/worker/args" || fail 'argv changed'
[[ $(cat "$dir/workspaces/worker/env") == unset && ! -e $dir/workspaces/worker/injected ]] || fail 'environment or shell injection'
pass 'literal argv and explicit environment allowlist'

fixture output 'head -c 262144 /dev/zero; exit 9'
call "$dir/start"; settled
jq -e '.result.terminal.exit_code==9' "$dir/result" >/dev/null || fail 'output blocked workload'
[[ $(jq -r .end "$spool/output/index") == 262144 && $(jq -r .eof "$spool/output/index") == true ]] || fail 'output not drained'
bytes=$(find "$spool/output" -name '*.chunk' -printf '%s\n' | awk '{s+=$1} END {print s}')
(( bytes<=8192 )) || fail 'output quota'
jq '.op="execution.read"|.operation_id=null|.idempotency_key=null|.args={source:"combined.base64",limit_bytes:8192}' "$dir/start" > "$dir/read"
call "$dir/read"
jq -e '.result.gap.from_byte==0 and .result.gap.to_byte==253952 and .result.truncated==true and (.result.data|length)<=8192' "$dir/result" >/dev/null || fail 'gap or read bound'
cursor=$(jq -r .result.next_cursor "$dir/result")
jq --arg cursor "$cursor" '.args.cursor=$cursor' "$dir/read" > "$dir/next"; call "$dir/next"
jq -e '.result.eof==true and .result.gap==null' "$dir/result" >/dev/null || fail 'cursor continuation'
jq '.args.cursor="other-generation:0"' "$dir/read" > "$dir/bad"; call "$dir/bad" 2
pass 'binary output quota, continued draining, exact gaps and generation cursor'

fixture term 'trap "exit 0" TERM; touch started; while :; do sleep 1; done'
call "$dir/start"
for _ in {1..100}; do [[ ! -f $dir/workspaces/worker/started ]] || break; sleep 0.02; done
stop_request false; call "$dir/stop"
jq -e '.result.confirmed_stopped==true and .result.requested_signals==["TERM"]' "$dir/result" >/dev/null || fail 'TERM confirmation'
call "$dir/stop"
pass 'durable guarded TERM, captured exit and stop replay'

fixture kill 'trap "" TERM; touch started; sleep 4'
call "$dir/start"
for _ in {1..100}; do [[ ! -f $dir/workspaces/worker/started ]] || break; sleep 0.02; done
stop_request true; call "$dir/stop"
jq -e '.result.confirmed_stopped==true and .result.requested_signals==["TERM","KILL"] and .result.terminal.captured==false and .result.terminal.exit_code==null' "$dir/result" >/dev/null || fail 'KILL observer invented exit'
pass 'authorized self-group KILL with independent empty-group observation'

fixture no_kill 'trap "" TERM; touch started; sleep 8'
call "$dir/start"
for _ in {1..100}; do [[ ! -f $dir/workspaces/worker/started ]] || break; sleep 0.02; done
stop_request false 1800; call "$dir/stop" 1
[[ $(cat "$spool/signals") == '["TERM"]' ]] || fail 'unauthorized KILL'
settled
pass 'no KILL without authorization; timeout stays unknown'

fixture lost_observation 'trap "exit 0" TERM; touch started; sleep 4'
call "$dir/start"
for _ in {1..100}; do [[ ! -f $dir/workspaces/worker/started ]] || break; sleep 0.02; done
stop_request false
LOOM_NATIVE_TEST_FAULT=stop_observation call "$dir/stop" 1
settled
call "$dir/stop"
jq -e '.result.confirmed_stopped' "$dir/result" >/dev/null || fail 'lost stop receipt not reconciled'
pass 'lost stop observation stays unknown until exact later receipt'

fixture survivor 'sleep 2 & printf child > started; exit 5'
call "$dir/start"
for _ in {1..100}; do [[ ! -f $spool/child-exit ]] || break; sleep 0.02; done
inspect_request; call "$dir/inspect"
[[ $(jq -r .result.state "$dir/result") != exited ]] || fail 'surviving child declared stopped'
settled
jq -e '.result.terminal.exit_code==5' "$dir/result" >/dev/null || fail 'leader exit lost'
pass 'surviving child delays completion and preserves leader wait status'

# Corrupt exact identity never authorizes signaling an unrelated process/group.
fixture reuse 'touch started; sleep 6'
call "$dir/start"
jq '.stop_authorized=false' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
stop_request true; call "$dir/stop" 2
[[ ! -f $spool/signals ]] || fail 'stop without authority permission'
jq '.stop_authorized=true' "$dir/binding" > "$dir/new"; mv "$dir/new" "$dir/binding"
cp "$spool/identity" "$dir/original-identity"
jq '.supervisor_start_ticks="0"' "$spool/identity" > "$dir/new"; mv "$dir/new" "$spool/identity"
stop_request true; call "$dir/stop" 1
[[ ! -f $spool/signals ]] || fail 'PID reuse signaled'
cp "$dir/original-identity" "$spool/identity"
call "$dir/stop"
pass 'start-token mismatch refuses signaling before group stop'

fixture unrelated 'touch started; sleep 4'
setsid bash -c 'trap "exit 99" TERM; sleep 10' & unrelated=$!
unrelated_ticks=$(_loom_state_ticks "$unrelated")
call "$dir/start"
for _ in {1..100}; do [[ ! -f $dir/workspaces/worker/started ]] || break; sleep 0.02; done
cp "$spool/identity" "$dir/original-identity"
jq --argjson pgid "$unrelated" '.pgid=$pgid|.sid=$pgid' "$spool/identity" > "$dir/new"; mv "$dir/new" "$spool/identity"
stop_request true; call "$dir/stop" 1
_loom_native_proc "$unrelated" && [[ ${_np[19]} == "$unrelated_ticks" && ${_np[0]} != Z ]] || fail 'unrelated process was signaled'
cp "$dir/original-identity" "$spool/identity"
call "$dir/stop"
_loom_native_proc "$unrelated" && [[ ${_np[19]} == "$unrelated_ticks" && ${_np[0]} != Z ]] || fail 'owned stop reached unrelated group'
wait "$unrelated" || fail 'unrelated fixture received TERM'
pass 'group reuse refused and unrelated process survives owned TERM/KILL'

# Inject keeper death after identity check but before TERM. No external helper
# is allowed to substitute a PGID kill after this race.
fixture signal_race 'touch started; sleep 2'
LOOM_NATIVE_TEST_FAULT=before_term call "$dir/start"
stop_request true; call "$dir/stop" 1
[[ ! -f $spool/signals ]] || fail 'signal after lost keeper guard'
sleep 2.1
inspect_request; call "$dir/inspect"
[[ $(jq -r .result.state "$dir/result") == unknown ]] || fail 'lost supervisor fabricated terminal exit'
pass 'identity-check/signal race has no external signal fallback'

# Reservation/gate/exec crashes all retain one operation and never relaunch.
for boundary in reserved identity gate before_exec after_exec_intent; do
    fixture "crash-$boundary" 'printf x >> ran; exit 0'
    jq '.timeout_ms=2000' "$dir/start" > "$dir/new"; mv "$dir/new" "$dir/start"
    rc=0; LOOM_NATIVE_TEST_FAULT=$boundary loom_native_handle "$dir/context" "$dir/start" > "$dir/result" || rc=$?
    [[ $rc == 0 || $rc == 1 ]] || fail "crash boundary exit $rc"
    # The original gated child may still cross exec after its keeper dies.
    # Observe that exact child finish before attributing a later marker to replay.
    if [[ -f $spool/identity ]]; then
        child_pid=$(jq -r .pid "$spool/identity")
        child_ticks=$(jq -r .start_ticks "$spool/identity")
        for _ in {1..100}; do
            if ! _loom_native_proc "$child_pid" || [[ ${_np[19]} != "$child_ticks" || ${_np[0]} == Z ]]; then break; fi
            sleep 0.05
        done
        if _loom_native_proc "$child_pid" && [[ ${_np[19]} == "$child_ticks" && ${_np[0]} != Z ]]; then fail 'crash fixture child did not settle'; fi
    fi
    before=0; [[ ! -f $dir/workspaces/worker/ran ]] || before=$(stat -c %s "$dir/workspaces/worker/ran")
    rc=0; loom_native_handle "$dir/context" "$dir/start" > "$dir/result" || rc=$?
    [[ $rc == 0 || $rc == 1 ]] || fail "replay boundary exit $rc"
    after=0; [[ ! -f $dir/workspaces/worker/ran ]] || after=$(stat -c %s "$dir/workspaces/worker/ran")
    [[ $before == "$after" && $after -le 1 ]] || fail 'replay relaunched'
    [[ $(jq -r 'select(.request.op=="execution.start")|.sequence' "$dir/state/v2/journal/"*.json | wc -l) == 1 ]] || fail 'duplicate intent'
    if [[ $boundary == reserved || $boundary == identity || $boundary == before_exec || $boundary == after_exec_intent ]]; then [[ $after == 0 ]] || fail 'gated child ran'; fi
    pass "crash $boundary and replay dedupe"
done

fixture launcher 'sleep 1; printf done > finished; exit 4'
LOOM_NATIVE_TEST_FAULT=lost_launcher bash "$ops/native.sh" handle "$dir/context" "$dir/start" > "$dir/lost-response" 2>/dev/null & launcher=$!
rc=0; wait "$launcher" || rc=$?
[[ $rc != 0 ]] || fail 'launcher crash not injected'
settled
jq -e '.result.terminal.exit_code==4' "$dir/result" >/dev/null || fail 'detached launch did not survive'
[[ -f $dir/workspaces/worker/finished ]] || fail 'lost launcher killed worker'
pass 'lost launcher leaves detached keeper and writer running'

# Source safety is observable even under strict caller shell options.
before=$(set +o; trap -p; pwd; umask)
source "$ops/native.sh"; source "$ops/output.sh"; source "$ops/native-supervisor.sh"
after=$(set +o; trap -p; pwd; umask)
[[ $before == "$after" ]] || fail 'source modified caller state'
pass 'source-safe modules'
printf 'PASS native process fixtures with actual S1/S2/S3\n'
