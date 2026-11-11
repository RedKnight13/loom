#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2030,SC2031,SC2154 # actual fixture libraries provide shared state
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
source "$root/ops/output.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkfifo "$scratch/pipe"
loom_output_drain "$scratch/spool" 8192 test < "$scratch/pipe" &
drain=$!
exec 9> "$scratch/pipe"
printf 'working\n' >&9
visible=false
for _ in {1..30}; do
    if [[ -f $scratch/spool/index ]] && loom_output_read "$scratch/spool" '' 64 > "$scratch/read"; then
        if jq -e '.data=="d29ya2luZwo=" and .eof==false' "$scratch/read" >/dev/null; then visible=true; break; fi
    fi
    sleep 0.05
done
exec 9>&-
wait "$drain"
[[ $visible == true ]] || { printf 'FAIL: sparse output withheld until EOF\n' >&2; exit 1; }
loom_output_read "$scratch/spool" 'test:8' 64 > "$scratch/read"
jq -e '.data=="" and .eof==true' "$scratch/read" >/dev/null
printf 'PASS sparse output before EOF and empty terminal read\n'
