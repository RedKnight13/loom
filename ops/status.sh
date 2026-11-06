#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=ops/report.sh
source "${BASH_SOURCE[0]%/*}/report.sh"
[[ $# == 0 ]] || loom_error 'usage: status.sh'
LOOM_STATE=${LOOM_STATE:-$HOME/.loom}
shopt -s nullglob
for file in "$LOOM_STATE"/*.json; do
    loom_validate "$file"
    id=${file##*/}
    jq -r --arg id "${id%.json}" '
      .reports[-1] | select(.state == "blocked" or .state == "ready" or .state == "failed") |
      [$id, .state, .fact] | @tsv
    ' "$file"
done
