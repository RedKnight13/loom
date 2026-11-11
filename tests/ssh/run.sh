#!/usr/bin/env bash
# Run only on explicitly approved compute. Creates synthetic workloads, no agents.
# shellcheck disable=SC2030,SC2031,SC2016 # Source-safe subshell APIs; literal attack fixtures.
set -euo pipefail
[[ ${LOOM_SSH_FIXTURES_APPROVED:-0} == 1 ]] || { echo 'Set LOOM_SSH_FIXTURES_APPROVED=1 on approved compute only' >&2; exit 2; }
ops=$(cd "${BASH_SOURCE[0]%/*}/../../ops" && pwd -P)
runtime=${LOOM_SSH_TEST_RUNTIME:-${ops%/ops}}
export LOOM_SSH_PROTOCOL_MODULE=$runtime/ops/protocol.sh
# shellcheck source=ops/transport-ssh.sh
source "$ops/transport-ssh.sh"
# shellcheck disable=SC1090,SC1091
source "$runtime/ops/native.sh"
_loom_native_load
umask 077
mkdir -p "${ops%/ops}/.loom"
scratch=$(mktemp -d "${ops%/ops}/.loom/ssh-fixture-XXXXXXXXXXXX")
sshd_pid=''
cleanup() {
    if [[ -n $sshd_pid ]]; then kill "$sshd_pid" 2>/dev/null || :; wait "$sshd_pid" 2>/dev/null || :; fi
    if [[ ${LOOM_SSH_KEEP_FIXTURES:-0} == 1 ]]; then echo "Retained: $scratch" >&2; else rm -rf "$scratch"; fi
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok $*"; }
call() {
    local expected=${2:-0} rc=0
    loom_ssh_handle "$dir/client" "$1" > "$dir/result" || rc=$?
    [[ $rc == "$expected" ]] || fail "$(jq -r .op "$1") exit=$rc expected=$expected $(cat "$dir/result")"
    if loom_protocol_validate request "$1"; then
        loom_protocol_validate response "$dir/result" "$1" || { cat "$dir/result" >&2; fail "invalid normalized response for $(jq -r .op "$1")"; }
    else
        loom_protocol_validate response "$dir/result" || { cat "$dir/result" >&2; fail 'invalid refusal response'; }
    fi
}
fixture() {
    dir=$scratch/$1
    mkdir -p "$dir/authority" "$dir/state" "$dir/workspaces" "$dir/installations" "$dir/source"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > args\ncat > prompt-copy\nprintf "fixture output\\n"\nprintf x >> launched\nexit 7\n' > "$dir/worker"
    if [[ $1 == real || $1 == stop ]]; then
        sed -i 's/^exit 7$/trap "exit 7" TERM; sleep 45; exit 7/' "$dir/worker"
    fi
    chmod 700 "$dir/worker"
    printf 'literal prompt: $(touch injected) `touch injected` "quote"\n' > "$dir/prompt"
    printf '{"schema":1,"workspace_id":"workspace"}\n' > "$dir/manifest"
    printf 'Synthetic fixture mandate\n' > "$dir/work"
    git init -q "$dir/source"
    printf 'hello\n' | git -C "$dir/source" hash-object -w --stdin > "$dir/blob"
    printf '%s blob %s\tREADME\n' "${LOOM_SSH_TEST_TREE_MODE:-100644}" "$(cat "$dir/blob")" | git -C "$dir/source" mktree > "$dir/tree"
    GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
      git -C "$dir/source" commit-tree "$(cat "$dir/tree")" -m fixture > "$dir/base"
    git -C "$dir/source" update-ref refs/heads/fixture "$(cat "$dir/base")"
    git -C "$dir/source" bundle create "$dir/input.bundle" refs/heads/fixture
    jq -cn --arg exe "$dir/worker" '{schema:2,agents:[{id:"fixture",executable:$exe,argv:["space value","quote\"value","$(touch injected)","`touch injected`","line\nvalue","-dash"],prompt_ingress:"stdin",model:null,effort:null}],adapters:[]}' > "$dir/profiles"
    jq -cn --arg root "$dir/workspaces" --arg helper "$(loom_protocol_digest "$ops/remote-helper.sh")" '{schema:2,hosts:[{id:"fixture-host",transport:"ssh",destination:"fixture-host",workspace_root:$root,identity:"fixture-transport",helper:{version:"1",digest:$helper}}]}' > "$dir/hosts"
    printf '%s\n' '{"schema":2,"repo":"example/project","execution":{"provider":"native","transport":"ssh","placement":{"allowed_hosts":["fixture-host"],"selection":"explicit","selected_host":"fixture-host","allow_local":false,"fallback":"deny"},"agent_profile":"fixture","model":null,"effort":null},"limits":{"workers":1,"operation_timeout_ms":30000},"ticket_provider":"github"}' > "$dir/config"
    loom_policy_resolve "$dir/config" "$dir/hosts" "$dir/profiles" > "$dir/pin"
    jq -cn --arg workspace "$dir/workspaces/worker" --arg prompt "$dir/prompt" --arg profile "$(jq -r .profile_digest "$dir/pin")" --arg executable "$(loom_policy_digest "$dir/worker")" --arg manifest "$(loom_protocol_digest "$dir/manifest")" --arg prompt_digest "$(loom_protocol_digest "$dir/prompt")" \
      '{schema:1,actor:{id:"owner",run_id:"run",epoch:0},target:{assignment_id:"assignment",attempt_id:"attempt",host_id:"fixture-host"},workspace_id:"workspace",workspace:$workspace,prompt_ref:"prompt",prompt:$prompt,prompt_digest:$prompt_digest,manifest_digest:$manifest,profile_digest:$profile,executable_digest:$executable,limits:{runtime_ms:null,stop_on_timeout:false,allow_kill:false,output_bytes:8192},stop_authorized:true,release_authorized:false}' > "$dir/binding"
    jq -cn --arg dir "$dir" '{schema:1,state_root:($dir+"/state"),store_id:"execution-spool",installation_id:"fixture-installation",transport_identity:"fixture-transport",config:($dir+"/config"),hosts:($dir+"/hosts"),profiles:($dir+"/profiles"),pin:($dir+"/pin"),binding:($dir+"/binding"),authorization:($dir+"/authorization"),authority_store_id:"fixture-authority"}' > "$dir/context"
    LOOM_STATE=$dir/state loom_state_init execution-spool >/dev/null
    LOOM_STATE=$dir/authority loom_state_init fixture-authority >/dev/null
    loom_policy_capacity_init_request fixture-authority owner > "$dir/cap-init"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/cap-init" >/dev/null
    printf '%s\n' '{"schema":2,"store_id":"fixture-authority","actor_id":"owner","operation_id":"capacity","idempotency_key":"capacity","run_id":"run","attempt_id":"attempt"}' > "$dir/reserve-context"
    LOOM_STATE=$dir/authority loom_policy_reserve_request "$dir/config" "$dir/hosts" "$dir/profiles" "$dir/reserve-context" > "$dir/reserve"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/reserve" > "$dir/cap-receipt"
    jq -cnS --slurpfile b "$dir/binding" --arg digest "$(jq -cS 'del(.stop_authorized,.release_authorized)' "$dir/binding" | loom_policy_scope)" \
      '{schema:2,store_id:"fixture-authority",operation_id:"authorize",idempotency_key:"authorize",op:"fixture.authorize",actor:$b[0].actor,target:$b[0].target,checks:[],changes:[{kind:"run",id:"run",expected_revision:null,run_id:"run",epoch:0,data:{owner_id:"owner"}},{kind:"attempt",id:"attempt",expected_revision:null,run_id:"run",epoch:0,data:{binding:$b[0]}}],events:[{type:"fixture.authorized",entity_ids:["run","attempt"],payload:{},observed_at:null}],result:{actor:$b[0].actor,target:$b[0].target,binding_digest:$digest}}' > "$dir/authorize"
    LOOM_STATE=$dir/authority loom_state_transact "$dir/authorize" > "$dir/launch-receipt"
    jq -cn --slurpfile c "$dir/cap-receipt" --slurpfile l "$dir/launch-receipt" '{capacity_receipt:$c[0],launch_receipt:$l[0]}' > "$dir/authorization"
    jq -cn --slurpfile b "$dir/binding" --slurpfile p "$dir/pin" '{protocol:"loom.execution",version:{major:1,minor:0},request_id:"request",operation_id:"start",idempotency_key:"start",op:"execution.start",actor:$b[0].actor,target:$b[0].target,expected_revision:null,timeout_ms:30000,args:{workspace_id:$b[0].workspace_id,profile_id:$p[0].profile.id,profile_digest:$b[0].profile_digest,argv:$p[0].argv,prompt_ref:$b[0].prompt_ref,model:null,effort:null,limits:$b[0].limits,manifest_digest:$b[0].manifest_digest},extensions:{}}' > "$dir/start"
    jq --arg base "$(cat "$dir/base")" --arg digest "$(loom_protocol_digest "$dir/input.bundle")" '.op="workspace.prepare"|.operation_id="prepare"|.idempotency_key="prepare"|.args={workspace_id:.args.workspace_id,base_sha:$base,bundle_ref:"bundle",bundle_digest:$digest,branch:"work/fixture",manifest_digest:.args.manifest_digest}' "$dir/start" > "$dir/prepare"
    jq -cn --arg runtime "$runtime" --arg dir "$dir" --argjson tree_bytes "${LOOM_SSH_TEST_TREE_BYTES:-1048576}" --slurpfile q "$dir/prepare" '{schema:1,runtime:$runtime,bundle_bytes:1048576,contexts:{fixture:{context:($dir+"/context"),prepare:{args:$q[0].args,max_files:100,max_worktree_bytes:$tree_bytes,manifest:($dir+"/manifest"),work:($dir+"/work")}}}}' > "$dir/install-config"
    bash "$ops/remote-helper.sh" install "$dir/install-config" "$dir/installations/v1" > /dev/null
    bash "$ops/remote-helper.sh" identity "$dir/installations/v1" fixture > "$dir/identity"
    jq -cn --arg dir "$dir" --slurpfile identity "$dir/identity" '{schema:1,destination:"fixture-host",port:22,helper_command:($dir+"/installations/v1/remote-helper.sh"),known_hosts:($dir+"/known_hosts"),identity_file:null,context_id:"fixture",identity:$identity[0],connect_timeout_s:2,timeout_ms:30000,bundle_bytes:1048576}' > "$dir/client"
    : > "$dir/known_hosts"
    jq '.op="execution.inspect"|.operation_id=null|.idempotency_key=null|.args={}' "$dir/start" > "$dir/inspect"
    jq '.op="execution.read"|.operation_id=null|.idempotency_key=null|.args={source:"combined.base64",limit_bytes:1024}' "$dir/start" > "$dir/read"
}
cat > "$scratch/fake-ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" > "${FAKE_ARGV:?}"
last=${!#}
case ${FAULT:-} in
    before) exit 255 ;;
    hang) sleep 10; exit 255 ;;
    oversize) head -c 1048578 /dev/zero; exit 0 ;;
    malformed) printf 'not-json\n'; exit 0 ;;
    after) "$last" >/dev/null; exit 255 ;;
    real-after) /usr/bin/ssh "$@" >/dev/null; exit 255 ;;
    exit) "$last"; exit 255 ;;
    *) exec "$last" ;;
esac
SH
chmod 700 "$scratch/fake-ssh"
export LOOM_SSH_EXECUTABLE=$scratch/fake-ssh FAKE_ARGV=$scratch/argv
if [[ ${LOOM_SSH_FIXTURE_LIBRARY:-0} == 1 ]]; then return 0; fi
fixture fake
baseline_dir=$dir
loom_ssh_preflight "$dir/client" > "$dir/preflight"
jq '.op="hello"|.operation_id=null|.idempotency_key=null|.args={versions:[{major:1,minor:0}],required_capabilities:["workspace.prepare.v1","execution.start.v1"]}' "$dir/start" > "$dir/hello"
call "$dir/hello"
pass 'pinned helper preflight and workspace/lifecycle capability negotiation using actual S1-S4 modules'
loom_ssh_upload "$dir/client" "$dir/input.bundle" "$(loom_protocol_digest "$dir/input.bundle")" >/dev/null
FAULT=after call "$dir/prepare" 1; call "$dir/prepare"
[[ $(jq -r .result.disposition "$dir/result") == existing ]] || fail 'prepare replay'
[[ -z $(git -C "$dir/workspaces/worker" remote) ]] || fail 'origin retained'
pass 'bounded verified bundle, private workspace, exact prepare replay'
FAULT=before call "$dir/start" 1
[[ ! -e $dir/workspaces/worker/launched ]] || fail 'before launch executed'
FAULT=after call "$dir/start" 1
[[ $(jq -r '.extensions["loom.ssh.transport"].exit_code' "$dir/result") == 255 ]] || fail 'transport exit erased'
call "$dir/start"
jq '.op="execution.reconcile"|.operation_id=null|.idempotency_key=null|.args={operation_id:"start"}' "$dir/start" > "$dir/reconcile"
call "$dir/reconcile"
for _ in {1..20}; do call "$dir/inspect"; [[ $(jq -r .result.state "$dir/result") != exited ]] || break; sleep 0.1; done
[[ $(cat "$dir/workspaces/worker/launched") == x ]] || fail 'duplicate launch'
jq -e '.result.terminal.exit_code==7 and .result.terminal.captured' "$dir/result" >/dev/null || fail 'captured exit'
jq -r '.argv[1:][]' "$dir/pin" > "$dir/expected-args"
cmp "$dir/expected-args" "$dir/workspaces/worker/args"
cmp "$dir/prompt" "$dir/workspaces/worker/prompt-copy"
[[ ! -e $dir/workspaces/worker/injected ]] || fail injection
call "$dir/read"
jq -e 'all(.request.changes[]; .kind=="host" and .run_id==null) and .request.actor.run_id==null' "$dir/state/v2/journal/"*.json >/dev/null || fail 'remote authority mutation'
pass 'lost reply keeps same-operation fence; literal argv/prompt; captured remote exit/read; spool-only journal facts'
for fault in malformed oversize exit; do FAULT=$fault call "$dir/inspect" 1; done
jq '.timeout_ms=200' "$dir/inspect" > "$dir/short"
FAULT=hang call "$dir/short" 1
pass 'malformed, oversized, exit mismatch and bounded timeout become unknown'
cp "$dir/client" "$dir/good-client"
for key in boot_id helper_digest context_digest installation_id; do
    jq --arg key "$key" '.identity[$key]="replaced"' "$dir/good-client" > "$dir/client"
    call "$dir/start" 1
    [[ $(cat "$dir/workspaces/worker/launched") == x ]] || fail 'replacement relaunched'
done
cp "$dir/good-client" "$dir/client"
pass 'boot/helper/context/installation changes stay unknown without effects'
for field in destination helper_command context_id; do
    jq --arg field "$field" '.[$field]="$(touch injected)"' "$dir/good-client" > "$dir/client"
    call "$dir/inspect" 2
done
cp "$dir/good-client" "$dir/client"
rc=0; loom_ssh_upload "$dir/client" "$dir/input.bundle" 'git-blob-sha1-v1:0000000000000000000000000000000000000000' >/dev/null || rc=$?
[[ $rc == 2 ]] || fail digest
jq '.bundle_bytes=1' "$dir/good-client" > "$dir/client"
rc=0; loom_ssh_upload "$dir/client" "$dir/input.bundle" "$(loom_protocol_digest "$dir/input.bundle")" >/dev/null || rc=$?
[[ $rc == 2 ]] || fail quota
cp "$dir/good-client" "$dir/client"
pass 'shell-bearing destinations/commands/context IDs and bundle digest/quota rejected'
# Check the fixed SSH argv without relying on shell text parsing.
tr '\0' '\n' < "$scratch/argv" > "$dir/argv-lines"
for option in BatchMode=yes StrictHostKeyChecking=yes ClearAllForwardings=yes PermitLocalCommand=no RequestTTY=no ControlPath=none; do
    rg -Fx -- "$option" "$dir/argv-lines" >/dev/null || fail "missing SSH option $option"
done
[[ $(tail -n1 "$dir/argv-lines") == "$dir/installations/v1/remote-helper.sh" ]] || fail 'nonfixed command'
pass 'fixed SSH options and exactly one trusted remote command'

# Data validation failures do not reach exec or rewrite authority.
jq '.args.argv += ["changed"]' "$dir/start" > "$dir/changed"
call "$dir/changed" 2
jq '.actor.epoch=1' "$dir/start" > "$dir/changed"
call "$dir/changed" 2
jq '.args.argv += ["nul\\u0000"]' "$dir/start" > "$dir/changed"
# A literal JSON NUL escape must be rejected before any transport call.
sed 's/nul\\\\u0000/nul\\u0000/' "$dir/changed" > "$dir/nul"
rc=0; loom_ssh_handle "$dir/client" "$dir/nul" > "$dir/result" || rc=$?
[[ $rc == 2 ]] || fail 'NUL not refused'
jq -e '.status=="refused"' "$dir/result" >/dev/null || fail 'NUL not refused'
[[ $(cat "$dir/workspaces/worker/launched") == x ]] || fail 'invalid request launched'
pass 'changed argv/owner and NUL rejected without another launch'
LOOM_SSH_TEST_TREE_BYTES=1 fixture tree_quota
loom_ssh_upload "$dir/client" "$dir/input.bundle" "$(loom_protocol_digest "$dir/input.bundle")" >/dev/null
call "$dir/prepare" 2
jq -e '.error.code=="quota_exceeded"' "$dir/result" >/dev/null || fail 'remote tree quota'
[[ ! -e $dir/workspaces/worker ]] || fail 'quota published workspace'
LOOM_SSH_TEST_TREE_MODE=120000 fixture symlink
loom_ssh_upload "$dir/client" "$dir/input.bundle" "$(loom_protocol_digest "$dir/input.bundle")" >/dev/null
call "$dir/prepare" 2
[[ ! -e $dir/workspaces/worker ]] || fail 'link published workspace'
pass 'remote worktree byte quota and Git symlink rejected before checkout'

fixture stop
loom_ssh_upload "$dir/client" "$dir/input.bundle" "$(loom_protocol_digest "$dir/input.bundle")" >/dev/null
call "$dir/prepare"; call "$dir/start"
jq '.op="execution.stop"|.operation_id="stop"|.idempotency_key="stop"|.expected_revision=1|.args={reason:"fixture stop",grace_ms:500,allow_kill:false}' "$dir/start" > "$dir/stop"
FAULT=after call "$dir/stop" 1
call "$dir/stop"
jq -e '.result.confirmed_stopped and .result.identity_verified and .result.requested_signals==["TERM"]' "$dir/result" >/dev/null || fail 'guarded stop not confirmed'
[[ $(cat "$dir/workspaces/worker/launched") == x ]] || fail 'stop replay relaunched'
pass 'actual S4 guarded stop and lost stop-reply reconciliation'
# Separate normal fake-path samples; never label these SSH/network latency.
dir=$baseline_dir
for op in preflight inspect read; do
    for sample in 1 2 3; do
        before=$(date +%s%3N)
        if [[ $op == preflight ]]; then loom_ssh_preflight "$dir/client" >/dev/null; else call "$dir/$op"; fi
        after=$(date +%s%3N)
        printf 'latency_fake_ms %s %s %s\n' "$op" "$sample" "$((after-before))"
    done
done
if [[ ${LOOM_SSH_REAL_FIXTURE:-0} != 1 ]]; then echo 'real SSH and latency: not_run (set LOOM_SSH_REAL_FIXTURE=1 on approved compute)'; echo PASS; exit 0; fi
unset LOOM_SSH_EXECUTABLE
fixture real
ssh-keygen -q -t ed25519 -N '' -f "$scratch/client-key"
ssh-keygen -q -t ed25519 -N '' -f "$scratch/host-key"
cp "$scratch/client-key.pub" "$scratch/authorized_keys"
port=${LOOM_SSH_TEST_PORT:-22347}
cat > "$scratch/sshd_config" <<CONFIG
Port $port
ListenAddress 127.0.0.1
HostKey $scratch/host-key
PidFile $scratch/sshd.pid
AuthorizedKeysFile $scratch/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes yes
PermitUserEnvironment no
AllowUsers $(id -un)
LogLevel ERROR
CONFIG
sshd=$(command -v sshd)
"$sshd" -t -f "$scratch/sshd_config"
"$sshd" -D -e -f "$scratch/sshd_config" > "$scratch/sshd.log" 2>&1 & sshd_pid=$!
read -r keytype keydata _ < "$scratch/host-key.pub"
printf '[127.0.0.1]:%s %s %s\n' "$port" "$keytype" "$keydata" > "$dir/known_hosts"
jq --arg user "$(id -un)@127.0.0.1" --arg key "$scratch/client-key" --argjson port "$port" '.destination=$user|.identity_file=$key|.port=$port' "$dir/client" > "$dir/new"
mv "$dir/new" "$dir/client"
sleep 0.2
loom_ssh_preflight "$dir/client" > "$dir/preflight" || { cat "$scratch/sshd.log" >&2; fail 'actual ssh preflight'; }
loom_ssh_upload "$dir/client" "$dir/input.bundle" "$(loom_protocol_digest "$dir/input.bundle")" >/dev/null
call "$dir/prepare"
LOOM_SSH_EXECUTABLE=$scratch/fake-ssh FAULT=real-after call "$dir/start" 1
call "$dir/start"
call "$dir/inspect"
jq '.op="execution.stop"|.operation_id="stop"|.idempotency_key="stop"|.expected_revision=1|.args={reason:"fixture stop",grace_ms:500,allow_kill:false}' "$dir/start" > "$dir/stop"
LOOM_SSH_EXECUTABLE=$scratch/fake-ssh FAULT=real-after call "$dir/stop" 1
call "$dir/stop"
jq -e '.result.confirmed_stopped and .result.identity_verified' "$dir/result" >/dev/null || fail 'actual remote stop not confirmed'
[[ $(cat "$dir/workspaces/worker/launched") == x ]] || fail 'actual duplicate launch'
for _ in {1..20}; do call "$dir/inspect"; [[ $(jq -r .result.state "$dir/result") != exited ]] || break; sleep 0.1; done
jq -e '.result.terminal.exit_code==7 and .result.terminal.captured' "$dir/result" >/dev/null || fail 'actual S4 terminal receipt'
call "$dir/read"
pass 'actual OpenSSH to S4 prepare/start/stop/inspect/read; lost start/stop replies reconcile without duplicate effects'
# Normal operation samples are separate from fault-suite duration. No warm SSH
# multiplexing; include validation, connect, remote helper and reply validation.
for op in preflight inspect read; do
    for sample in 1 2 3; do
        before=$(date +%s%3N)
        if [[ $op == preflight ]]; then loom_ssh_preflight "$dir/client" >/dev/null; else call "$dir/$op"; fi
        after=$(date +%s%3N)
        printf 'latency_ms %s %s %s\n' "$op" "$sample" "$((after-before))"
    done
done
# Wrong host key must fail closed; no new launch or alternate connection.
: > "$dir/known_hosts"
call "$dir/inspect" 1
pass 'actual unknown host key refused with no fallback'
echo PASS
