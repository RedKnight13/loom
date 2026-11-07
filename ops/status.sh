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
    # An Orca worker is never stopped by loom; past its limit it is surfaced
    # here for the owner's decision instead (Orca: a timeout alone never
    # authorizes a stop).
    jq -r --arg id "${id%.json}" '
      select(.executor.kind == "orca" and .executor.state == "running") |
      (.limit_min // 30) as $limit |
      ([.launched_at, .started_at] + [.reports[].at] | map(select(. != null) | fromdateiso8601) | max) as $last |
      select($last <= (now - $limit * 60)) |
      [$id, "stale", "no report for \(((now - $last) / 60) | floor) min (Orca dispatch \(.executor.dispatch)); owner decides: ops/orca.sh stop \($id)"] | @tsv
    ' "$file"
    jq -r --arg id "${id%.json}" '
      select(.worker_pid == null and ((.executor.state // "") | IN("running", "starting") | not)) | .reports[-1] // empty |
      select(.state == "blocked" or .state == "ready" or .state == "failed") |
      [$id, .state, (.fact | gsub("[\\t\\r\\n]+"; " "))] | @tsv
    ' "$file"
done
