#!/usr/bin/env bash
# status.sh — prints ONLY what waits for a person: the latest report of each
# assignment when it is ready, blocked or failed. Silent when healthy.
# A live worker is healthy; a waiting one is healthy.
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
[[ $# == 0 ]] || loom_error 'usage: status.sh'
LOOM_STATE=${LOOM_STATE:-$HOME/.loom}
shopt -s nullglob
for file in "$LOOM_STATE"/*.json; do
    loom_validate "$file"
    id=${file##*/}
    jq -r --arg id "${id%.json}" '
      select(.worker_pid == null) | .reports[-1] // empty |
      select(.state == "blocked" or .state == "ready" or .state == "failed") |
      [$id, .state, (.fact | gsub("[\\t\\r\\n]+"; " "))] | @tsv
    ' "$file"
done
