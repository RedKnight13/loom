#!/usr/bin/env bash
# Offline contract fixtures only; no agent or provider launch.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
jq -e -f tests/contract/schema-audit.jq schemas/execution-v1/contract.json schemas/coordination-v1/contract.json >/dev/null
printf 'contract: source has no side effects\n'
bash -c 'set -euo pipefail; before=$(set +o); old_umask=$(umask); source ops/protocol.sh; [[ $(set +o) == "$before" && $(umask) == "$old_umask" && -z $(trap -p) ]]'
source ops/protocol.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
count=0
pass() { count=$((count + 1)); }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
valid() { loom_protocol_validate "$1" "$2" "${3-}" || fail "valid $*"; pass; }
invalid() { if loom_protocol_validate "$1" "$2" "${3-}"; then fail "accepted invalid $*"; fi; pass; }
expect_exit() {
    local expected=$1 actual=0
    shift
    "$@" > "$work/output" 2> "$work/diagnostics" || actual=$?
    [[ $actual == "$expected" ]] || { cat "$work/output" >&2; fail "exit $actual expected $expected: $*"; }
    valid response "$work/output"
}
fixture() { jq -c --arg op "$1" --arg kind "${2-request}" '.[]|select(.op==$op and (.protocol=="execution" or .op!="hello"))|.[$kind]' tests/contract/fixtures/operations.json; }
printf 'contract: all operations, required fields, closed arguments/results\n'
while IFS= read -r row; do
    printf '%s\n' "$row" | jq -c .request > "$work/request"
    printf '%s\n' "$row" | jq -c .response > "$work/response"
    op=$(jq -r .op <<< "$row")
    valid request "$work/request"
    valid response "$work/response" "$work/request"
    # Delete every present core/args/result member. Optional args are checked
    # separately by the schema; these examples omit them intentionally.
    for kind in request response; do
        while IFS= read -r key; do
            jq --arg k "$key" 'del(.[$k])' "$work/$kind" > "$work/bad"
            invalid "$kind" "$work/bad"
        done < <(jq -r 'keys[]' "$work/$kind")
        node=args; [[ $kind != response ]] || node=result
        while IFS= read -r key; do
            jq --arg n "$node" --arg k "$key" 'del(.[$n][$k])' "$work/$kind" > "$work/bad"
            invalid "$kind" "$work/bad"
            jq --arg n "$node" --arg k "$key" '.[$n][$k]={unexpected:true}' "$work/$kind" > "$work/bad"
            invalid "$kind" "$work/bad"
        done < <(jq -r --arg n "$node" '.[$n]|keys[]' "$work/$kind")
        jq '.unexpected=true' "$work/$kind" > "$work/bad"; invalid "$kind" "$work/bad"
        jq --arg n "$node" '.[$n].unexpected=true' "$work/$kind" > "$work/bad"; invalid "$kind" "$work/bad"
    done
    # S1 serves no runtime operations, on either protocol.
    if [[ $op != hello ]]; then expect_exit 2 bash ops/protocol.sh < "$work/request"; fi
    printf '  %s\n' "$op"
done < <(jq -c '.[]' tests/contract/fixtures/operations.json)
printf 'contract: framing, lexical and bounds\n'
fixture execution.start > "$work/request"
for expr in '.version.major=2' '.version.minor=1' '.timeout_ms=0' '.timeout_ms=300001' '.timeout_ms="1"' '.actor.epoch=9007199254740992' '.actor.epoch=-1' '.actor.epoch=1.5' '.actor.epoch=9007199254740990.5' '.args.argv=[]' '.args.argv[0]=""' '.args.argv[0]=1' '.args.argv[0]="\u0000"' '.args.profile_digest="sha1:wrong"' '.args.prompt_ref="../escape"' '.extensions={plain:true}' '.target.attempt_id=null' '.idempotency_key=null' '.expected_revision=1' '.request_id=("x"*129)' '.request_id=("é"*65)' '.args.argv[0]=("x"*65537)' '.args.limits.allow_kill=true'; do
    jq "$expr" "$work/request" > "$work/bad"; invalid request "$work/bad"
done
for input in '{"a":1,"a":2}' '{"a":1,"\u0061":2}' '{"x":{"a":1,"a":2}}' '{"😀":1,"\ud83d\ude00":2}' '{"a":1}{}' 'progress {"a":1}' '{"a":NaN}' '{"a":Infinity}' '{"a":01}' '{"a":1e999}' '{"a":"\ud800"}' '{"a":"\udc00"}' '{"a":"\u0000"}' '{"a":true,}' '{"a":[1,]}' '{"a":"unterminated}' '[]'; do
    printf '%s\n' "$input" > "$work/bad"
    invalid request "$work/bad"
    expect_exit 2 bash ops/protocol.sh < "$work/bad"
done
# Duplicate names inside an otherwise valid envelope must fail before jq can
# erase them. These would pass structural validation with last-key-wins parsing.
for expr in 's/"protocol":/"protocol":"loom.execution","protocol":/' 's/"id":"Agni"/"id":"Agni","\\u0069d":"Agni"/' 's/"extensions":{}/"extensions":{"example.dup":{"😀":1,"\\ud83d\\ude00":2}}/'; do
    sed "$expr" "$work/request" > "$work/bad"; invalid request "$work/bad"
done
jq '.extensions["example.numeric"]=1e999' "$work/request" > "$work/bad"; invalid request "$work/bad"
# UTF-8 framing and a missing terminating newline are independently invalid.
printf '{"a":"\377"}\n' > "$work/bad"; invalid request "$work/bad"
printf '{"a":"\000"}\n' > "$work/bad"; invalid request "$work/bad"
tr -d '\n' < "$work/request" > "$work/bad"; invalid request "$work/bad"
jq '.extensions["example.deep"]=reduce range(0;65) as $n ({};{a:.})' "$work/request" > "$work/bad"; invalid request "$work/bad"
jq '.extensions["example.large"]=("x"*1048576)' "$work/request" > "$work/bad"
expect_exit 2 bash ops/protocol.sh < "$work/bad"
fixture hello > "$work/hello"
expect_exit 0 bash ops/protocol.sh < "$work/hello"
for expr in '.args.versions=[{major:2,minor:0}]' '.args.required_capabilities=["missing.capability.v1"]' '.args.required_capabilities=["execution.stop.group.v1"]'; do
    jq "$expr" "$work/hello" > "$work/bad"; expect_exit 2 bash ops/protocol.sh < "$work/bad"
done
jq '.extensions["example.large"]=("x"*65536)' "$work/hello" > "$work/bad"; invalid request "$work/bad"
jq '.args.required_capabilities=["bad"]' "$work/hello" > "$work/bad"; invalid request "$work/bad"
fixture mail.send > "$work/mail"
jq '.args.body=("x"*65536)' "$work/mail" > "$work/good"; valid request "$work/good"
jq '.args.body=("é"*32769)' "$work/mail" > "$work/bad"; invalid request "$work/bad"
# Unknown protocol operation is distinct from an invalid known operation.
jq '.op="execution.future"' "$work/request" > "$work/bad"
expect_exit 2 bash ops/protocol.sh < "$work/bad"
jq -e '.error.code=="unsupported_operation" and .effects==[]' "$work/output" >/dev/null || fail unknown-operation
printf 'contract: command adapter boundary\n'
exe=$(realpath tests/contract/fixtures/adapter.sh)
exe_digest=$(loom_protocol_digest "$exe")
jq -n --arg exe "$exe" --arg digest "$exe_digest" --arg marker "$work/invocations" --slurpfile schema schemas/execution-v1/contract.json '
 {schema:1,executable:$exe,executable_digest:$digest,argv:["ok",$marker],
 capabilities:[$schema[0]."$defs".capability.properties.name.enum[]|{name:.,state:"supported",evidence:[],limits:{max_bytes:null,max_items:null}}],
 limits:{request_bytes:1048576,response_bytes:1048576,metadata_bytes:65536,message_bytes:65536,read_bytes:65536,list_rows:100,diagnostic_bytes:1048576}}' > "$work/base-config"
configure() { jq --arg mode "$1" '.argv[0]=$mode' "$work/base-config" > "$work/config"; : > "$work/invocations"; }
invoke() { expect_exit "$1" bash ops/protocol.sh invoke "$work/config" "$(loom_protocol_digest "$work/config")" < "${2-$work/request}"; }
configure ok
valid adapter_config "$work/config"
invoke 0
[[ $(cat "$work/invocations") == $'hello\nexecution.start' ]] || fail negotiation-order
jq -e '.extensions["loom.transport"]|.exit_code==0 and .adapter_exit==0 and .adapter_group.pid==.adapter_group.pgid and (.config_digest|startswith("git-blob-sha1-v1:"))' "$work/output" >/dev/null || fail transport-evidence
# Nonzero transport is different from an adapter-authored valid failure.
for mode in mixed duplicate nonzero exit_mismatch wrong_id wrong_attempt wrong_nested overflow_out overflow_err; do
    configure "$mode"; invoke 1
    jq -e '.status=="unknown" and .error.retry=="after_reconcile" and .effects[0].disposition=="unknown"' "$work/output" >/dev/null || fail "$mode uncertainty"
done
for mode in failure refusal; do
    configure "$mode"
    expected=1; [[ $mode != refusal ]] || expected=2
    invoke "$expected"
    jq -e '.extensions["loom.transport"].reason=="ok" and .status!="unknown"' "$work/output" >/dev/null || fail "$mode transport"
done
for mode in unknown_cap bad_cap bad_version; do
    configure "$mode"; invoke 2
    [[ $(cat "$work/invocations") == hello ]] || fail "$mode invoked effect"
done
# A separate sibling fixture must survive all adapter deadline signals.
sleep 30 & sibling=$!
sibling_ticks=$(sed 's/.*) //' "/proc/$sibling/stat" | awk '{print $20}')
for mode in timeout descendant ignore_term; do
    configure "$mode"
    jq '.timeout_ms=700' "$work/request" > "$work/timed"
    invoke 1 "$work/timed"
    jq -e '.status=="unknown" and .extensions["loom.transport"].reason=="timeout"' "$work/output" >/dev/null || fail "$mode timeout"
    kill -0 "$sibling" || fail unrelated-process-killed
    [[ $(sed 's/.*) //' "/proc/$sibling/stat" | awk '{print $20}') == "$sibling_ticks" ]] || fail sibling-identity
    pgid=$(jq -r '.extensions["loom.transport"].adapter_group.pgid' "$work/output")
    # Zombies have exited. No active member of the captured adapter group remains.
    if ps -eo pgid=,stat= | awk -v pgid="$pgid" '$1==pgid && $2!~/^Z/ {found=1} END {exit !found}'; then fail adapter-group-alive; fi
done
kill "$sibling"; wait "$sibling" 2>/dev/null || true
# Literal data cannot execute a command or inherit secret/model configuration.
configure ok
literal=$'spaces "quotes" `touch sentinel` $(touch sentinel)\n-leading-dash'
jq --arg literal "$literal" '.argv+=[$literal,"", "--leading"]' "$work/config" > "$work/new"; mv "$work/new" "$work/config"
export LOOM_CONTRACT_SECRET=fixture-secret-value
invoke 0
jq -e --arg literal "$literal" '.extensions["fixture.literal"]|.argv==[$literal,"","--leading"] and .leaked==false and .agent=="Agni"' "$work/output" >/dev/null || fail literal-argv
[[ ! -e sentinel ]] || fail shell-evaluation
jq --arg literal "$literal" '.args.argv=["Agni",$literal,"--leading",""]' "$work/request" > "$work/literal-request"
invoke 0 "$work/literal-request"
jq -e --arg literal "$literal" '.extensions["fixture.literal"].request_argv==["Agni",$literal,"--leading",""]' "$work/output" >/dev/null || fail literal-request-argv
jq --arg literal "$literal" '.args.body=$literal' "$work/mail" > "$work/literal-mail"
configure ok; invoke 2 "$work/literal-mail"; [[ ! -s $work/invocations && ! -e sentinel ]] || fail literal-mail
configure secret_stderr; invoke 0
! rg -q fixture-secret-value "$work/output" "$work/diagnostics" || fail secret-leaked
unset LOOM_CONTRACT_SECRET
# Refuse malformed/pin-mismatched config before even hello.
for expr in '.executable="relative"' '.executable="/does/not/exist"' '.argv="command string"' '.argv=["\u0000"]' '.schema=2' '.capabilities[0].name="unknown.v1"' '.capabilities+=[.capabilities[0]]' '.executable_digest="git-blob-sha1-v1:0000000000000000000000000000000000000000"' '.limits.response_bytes=1048577'; do
    configure ok; jq "$expr" "$work/config" > "$work/new"; mv "$work/new" "$work/config"
    invoke 2; [[ ! -s $work/invocations ]] || fail config-invoked
 done
configure ok
expect_exit 2 bash ops/protocol.sh invoke "$work/config" 'git-blob-sha1-v1:0000000000000000000000000000000000000000' < "$work/request"
[[ ! -s $work/invocations ]] || fail wrong-config-digest
configure ok; jq '.capabilities=[]' "$work/config" > "$work/new"; mv "$work/new" "$work/config"
invoke 2; [[ ! -s $work/invocations ]] || fail missing-capability-invoked
configure ok; invoke 2 "$work/mail"; [[ ! -s $work/invocations ]] || fail coordination-delegated
configure nonzero
fixture execution.inspect > "$work/read-request"
invoke 1 "$work/read-request"
jq -e '.status=="failed" and .extensions["loom.transport"].exit_code==7' "$work/output" >/dev/null || fail read-failure
# Refusal, failure, malformed and unsupported calls all produce one response.
# shellcheck source=tests/contract/regressions.sh
source tests/contract/regressions.sh
printf 'contract: PASS (%s assertions)\n' "$count"
