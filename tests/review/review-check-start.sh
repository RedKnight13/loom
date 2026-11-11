#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2031,SC2154 # copied fixture modules and observation hook
set -euo pipefail
umask 077
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
[[ $(uname -s) == Linux ]] || { printf "SKIP check startup: Linux required\n"; exit 0; }
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cp -R "$root/ops" "$root/schemas" "$root/VERSION" "$scratch/"
mkdir "$scratch/work" "$scratch/result"
printf 'touch completed\nexit 0\n' > "$scratch/check"
source "$scratch/ops/policy.sh"
jq -cn --arg root "$scratch" --arg digest "$(loom_policy_digest "$scratch/check")" --arg interpreter "$(loom_policy_digest /usr/bin/bash)" '{workspace:($root+"/work"),script:($root+"/check"),result_dir:($root+"/result"),script_digest:$digest,interpreter_digest:$interpreter,timeout_ms:2000,output_bytes:4096}' > "$scratch/plan"
rc=0
timeout --kill-after=1 5 setsid --wait bash "$scratch/ops/workflow.sh" --check-keeper "$scratch/plan" > "$scratch/control-log" 2>&1 || rc=$?
printf 'control exit=%s terminal=%s\n' "$rc" "$(test -f "$scratch/result/check-terminal" && echo present || echo absent)"
[[ $rc == 0 && -f $scratch/result/check-terminal ]] || { cat "$scratch/control-log"; exit 2; }
rm -rf "$scratch/result"; mkdir "$scratch/result"
rm "$scratch/work/completed"
cat >> "$scratch/ops/native.sh" <<'HOOK'
# Review-only scheduling delay before the first observation of the check child.
eval "$(declare -f _loom_native_proc | sed '1s/_loom_native_proc/review_real_proc/')"
_loom_native_proc() {
    if [[ ${child:-} == "$1" && ! -f $dir/review-delayed ]]; then
        touch "$dir/review-delayed"
        sleep 0.2
    fi
    review_real_proc "$@"
}
HOOK
rc=0
timeout --kill-after=1 5 setsid --wait bash "$scratch/ops/workflow.sh" --check-keeper "$scratch/plan" > "$scratch/delayed-log" 2>&1 || rc=$?
printf 'delayed exit=%s check_completed=%s terminal=%s\n' "$rc" "$(test -f "$scratch/work/completed" && echo yes || echo no)" "$(test -f "$scratch/result/check-terminal" && echo present || echo absent)"
cat "$scratch/delayed-log"
[[ $rc == 0 && -f $scratch/result/check-terminal ]]

printf "PASS fast check preserves terminal evidence across delayed identity capture\n"
