#!/usr/bin/env bash
# Finite approved-script process fixtures only; no network, models or authority.
# shellcheck disable=SC2016
set -euo pipefail
root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
# shellcheck source=ops/policy.sh
source "$root/ops/policy.sh"
umask 077
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
run_case() {
    local name=$1 script=$2 timeout=$3 expected=$4 rc=0
    dir=$scratch/$name
    mkdir -p "$dir/workspace" "$dir/result"
    printf '%s\n' "$script" > "$dir/script"
    jq -cn --arg dir "$dir" --arg sd "$(loom_policy_digest "$dir/script")" --arg bd "$(loom_policy_digest /usr/bin/bash)" --argjson timeout "$timeout" '{workspace:($dir+"/workspace"),script:($dir+"/script"),result_dir:($dir+"/result"),script_digest:$sd,interpreter_digest:$bd,timeout_ms:$timeout,output_bytes:8192}' > "$dir/plan"
    setsid --wait bash "$root/ops/workflow.sh" --check-keeper "$dir/plan" > "$dir/keeper.log" 2>&1 || rc=$?
    [[ $rc == "$expected" ]] || { cat "$dir/keeper.log" >&2; printf 'FAIL %s exit %s wanted %s\n' "$name" "$rc" "$expected" >&2; exit 1; }
}
run_case descendants '(sleep 0.25; printf child > completed) & exit 0' 3000 0
[[ $(cat "$dir/workspace/completed") == child ]]
jq -e '.captured and .exit_code==0 and .group_empty and .output_eof' "$dir/result/check-terminal" >/dev/null
printf 'ok check completion waits for descendant and drained output\n'
run_case nonzero 'exit 7' 3000 0
jq -e '.captured and .exit_code==7 and .group_empty' "$dir/result/check-terminal" >/dev/null
printf 'ok captured nonzero check exit is retained\n'
run_case quota 'head -c 65536 /dev/zero; printf "\377\000tail"; exit 0' 10000 0
jq -e '.exit_code==0 and .output_eof and .lost_prefix_bytes>0 and .total_output_bytes==65542' "$dir/result/check-terminal" >/dev/null
retained=$(find "$dir/result/output" -name '*.chunk' -printf '%s\n' | awk '{n+=$1}END{print n}')
(( retained<=8192 ))
printf 'ok binary output quota drains without failing check or changing captured exit\n'
sleep 3 & unrelated=$!
run_case timeout 'trap "" TERM; while :; do sleep 0.1; done' 300 137
[[ -f $dir/result/check-timeout && ! -f $dir/result/check-terminal ]]
kill -0 "$unrelated"
wait "$unrelated"
printf 'ok check timeout remains unknown, unrelated process retained\n'
printf 'PASS bounded check keeper, captured exits, descendants and binary draining\n'
