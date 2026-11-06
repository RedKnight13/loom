#!/usr/bin/env bash
# Shared state helpers live here to keep the operational surface to four scripts.
set -euo pipefail

loom_error() { printf 'loom: %s\n' "$*" >&2; exit 1; }
loom_init() {
    umask 077
    LOOM_STATE=${LOOM_STATE:-$HOME/.loom}
    mkdir -p "$LOOM_STATE"
}
loom_lock() {
    mkdir "$LOOM_STATE/.lock" 2>/dev/null || loom_error 'state is locked; retry after the active operation finishes'
    trap 'rm -f "$LOOM_STATE/.pending"; rmdir "$LOOM_STATE/.lock"' EXIT
}
loom_id() {
    [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || loom_error 'invalid assignment id'
}
loom_validate() {
    jq -e '
      type == "object" and (.ticket | type == "number") and
      (.repo | type == "string") and (.short_name | type == "string") and
      (.worktree | type == "string") and
      (.worker_pid == null or (.worker_pid | type == "number" and . > 1 and . == floor)) and
      (.started_at | fromdateiso8601 | type == "number") and
      (.reports | type == "array") and
      all(.reports[]; (.at | fromdateiso8601 | type == "number") and
          (.state == "ready" or .state == "blocked" or .state == "failed" or .state == "waiting") and
          (.fact | type == "string"))
    ' "$1" >/dev/null || loom_error 'invalid assignment record'
}
loom_append() {
    local file=$1 state=$2 fact=$3 clear_pid=${4:-false}
    jq --arg state "$state" --arg fact "$fact" --argjson clear "$clear_pid" '
      .reports += [{at: (now | todateiso8601), state: $state, fact: $fact}] |
      if $clear then .worker_pid = null else . end
    ' "$file" > "$LOOM_STATE/.pending"
    mv "$LOOM_STATE/.pending" "$file"
}
loom_report() {
    [[ $# == 3 ]] || loom_error 'usage: report.sh <assignment-id> <ready|blocked|failed|waiting> "<fact>"'
    loom_id "$1"
    case $2 in ready|blocked|failed|waiting) ;; *) loom_error 'invalid report state' ;; esac
    [[ -n $3 ]] || loom_error 'fact must not be empty'
    loom_init
    loom_lock
    local file="$LOOM_STATE/$1.json"
    [[ -f $file && ! -L $file ]] || loom_error 'assignment not found or is a symlink'
    loom_validate "$file"
    loom_append "$file" "$2" "$3"
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    loom_report "$@"
fi
