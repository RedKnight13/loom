#!/usr/bin/env bash
# Agni fixture only: no model, external adapter or real worker invocation.
set -euo pipefail
fixture_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$fixture_root/ops/protocol.sh"
mode=$1
marker=$2
shift 2
request=$(cat)
op=$(jq -r .op <<< "$request")
printf '%s\n' "$request" > "$TMPDIR/fixture-request"
printf '%s\n' "$op" >> "$marker"
if [[ $op == hello ]]; then
    jq -cn --argjson q "$request" --slurpfile fixture "$fixture_root/tests/contract/fixtures/operations.json" \
        --slurpfile schema "$fixture_root/schemas/execution-v1/contract.json" --arg mode "$mode" '
      ($fixture[0][]|select(.protocol=="execution" and .op=="hello")|.response) as $r |
      $r + ($q|{protocol,version,request_id,operation_id,op,target}) |
      .result.limits={request_bytes:1048576,response_bytes:1048576,metadata_bytes:65536,message_bytes:65536,read_bytes:65536,list_rows:100,diagnostic_bytes:1048576} |
      .result.capabilities=[$schema[0]."$defs".capability.properties.name.enum[]|{name:.,state:(if $mode=="unknown_cap" then "unknown" else "supported" end),evidence:[],limits:{max_bytes:null,max_items:null}}] |
      if $mode=="bad_cap" then .result.capabilities[0].name="imaginary.v1" else . end |
      if $mode=="bad_version" then .result.selected_version.minor=1 else . end |
      if $mode=="effectful_hello" then .effects=[{kind:"launch",resource:"example",disposition:"created"}] else . end |
      if $mode=="low_read" then .result.limits.read_bytes=1 else . end |
      if $mode=="low_list" then .result.limits.list_rows=1 else . end |
      if $mode=="low_metadata" then .result.limits.metadata_bytes=1 else . end |
      if $mode=="low_cap" then .result.capabilities |= map(.limits.max_bytes=1) else . end |
      if $mode=="deep_hello" then .extensions["example.deep"]=reduce range(0;59) as $n ({};{a:.}) else . end'
    exit 0
fi
case $mode in
    timeout) sleep 30 ;;
    descendant) sleep 30 & exit 0 ;;
    ignore_term) trap "" TERM; sleep 30 ;;
    overflow_out) head -c 1100000 /dev/zero; exit 0 ;;
    overflow_err) head -c 1100000 /dev/zero >&2 ;;
    mixed) printf 'progress\n' ;;
    duplicate) printf '{"ok":true,"ok":false}\n'; exit 0 ;;
    nonzero) exit 7 ;;
    failure) loom_protocol_receipt "$TMPDIR/fixture-request" failed resource_busy 'Fixture refused resource'; exit 1 ;;
    refusal) loom_protocol_receipt "$TMPDIR/fixture-request" refused policy_denied 'Fixture policy refusal'; exit 2 ;;
    secret_stderr) printf 'fixture-secret-value\n' >&2 ;;
esac
leaked=false
[[ ! -v LOOM_CONTRACT_SECRET ]] || leaked=true
jq -cn --argjson q "$request" --slurpfile fixture "$fixture_root/tests/contract/fixtures/operations.json" \
    --arg mode "$mode" --argjson leaked "$leaked" --args -- '
    ($fixture[0][]|select(.protocol=="execution" and .op==$q.op)|.response) +
    ($q|{protocol,version,request_id,operation_id,op,target}) |
    if .result|has("binding") then .result.binding=$q.target else . end |
    if $mode=="wrong_id" then .operation_id="wrong" else . end |
    if $mode=="wrong_attempt" then .target.attempt_id="wrong" else . end |
    if $mode=="wrong_nested" then .result.binding.attempt_id="wrong" else . end |
    if $mode=="extensions_full" then .extensions=reduce range(0;31) as $i ({};.["example.k\($i)"]=true) else . end |
    if $mode=="padded" then .extensions["example.padding"]=("x"*1047700) else . end |
    .extensions["fixture.literal"]={argv:$ARGS.positional,request_argv:($q.args.argv//null),leaked:$leaked,agent:"Agni"}
    ' "$@"
if [[ $mode == exit_mismatch ]]; then exit 7; fi
