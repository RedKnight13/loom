#!/usr/bin/env bash
# Conductor-side report: append a structured state to an assignment record.
# Workers do not call this; they write REPORT.md in their workdir (see lib.sh).
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
[[ $# == 3 ]] || loom_error 'usage: report.sh <assignment-id> <ready|blocked|failed|waiting> "<fact>"'
loom_id "$1"
case $2 in ready|blocked|failed|waiting) ;; *) loom_error 'invalid report state' ;; esac
[[ -n $3 ]] || loom_error 'fact must not be empty'
loom_init
loom_lock
file=$(loom_record "$1")
loom_append "$file" "$2" "$3"
