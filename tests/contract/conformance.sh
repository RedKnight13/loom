#!/usr/bin/env bash
# Reusable invocation assertions. CONFIG pins the adapter executable, argv
# (including any fixture transport selector) and capability fixture. Run real
# providers only under separate explicit authorization; run.sh uses fakes only.
set -euo pipefail
contract_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
source "$contract_root/ops/protocol.sh"
[[ $# == 3 ]] || { printf 'usage: conformance.sh CONFIG CONFIG_DIGEST CASES_JSON\n' >&2; exit 2; }
config=$1
digest=$2
cases=$3
loom_protocol_validate adapter_config "$config"
jq -e 'type=="array" and length>0 and all(.[];
  type=="object" and (keys|sort)==(["request","exit","status","error_code"]|sort) and
  (.request|type)=="object" and (.exit==0 or .exit==1 or .exit==2) and
  (.status|type)=="string" and (.error_code==null or (.error_code|type)=="string"))' "$cases" >/dev/null
private=$(mktemp -d)
trap 'rm -rf -- "$private"' EXIT
index=0
while IFS= read -r spec; do
    index=$((index + 1))
    printf '%s\n' "$spec" | jq -c .request > "$private/request"
    actual_exit=0
    loom_protocol_invoke "$config" "$digest" < "$private/request" > "$private/response" 2> "$private/diagnostics" || actual_exit=$?
    loom_protocol_validate response "$private/response"
    jq -e --argjson spec "$spec" --argjson actual_exit "$actual_exit" '
        $spec.exit==$actual_exit and .status==$spec.status and .error.code==$spec.error_code
    ' "$private/response" >/dev/null || { printf 'conformance: case %s failed\n' "$index" >&2; exit 1; }
done < <(jq -c '.[]' "$cases")
printf 'conformance: PASS (%s cases)\n' "$index"
