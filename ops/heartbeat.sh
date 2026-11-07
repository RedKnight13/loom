#!/usr/bin/env bash
# heartbeat.sh --until <ID|all> [--every SEC] [--limit-min N]
#
# The conductor's clock. Every SEC seconds (default 60) runs the watchdog and
# prints only its actions, timestamped. Stops when the named assignment has
# been launched and has settled (no live worker), or with --until all when no
# assignment has a recorded worker. Then prints status.sh: what waits for a
# person. Waits up to 60s for a just-launched assignment to record its worker.
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
ops=${BASH_SOURCE[0]%/*}
usage='usage: heartbeat.sh --until <ID|all> [--every SEC] [--limit-min N]'
until_id='' every=60 wargs=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --until) [[ $# -ge 2 ]] || loom_error "$usage"; until_id=$2; shift 2 ;;
        --every) [[ $# -ge 2 && $2 =~ ^[1-9][0-9]{0,4}$ ]] || loom_error "$usage"; every=$2; shift 2 ;;
        --limit-min) [[ $# -ge 2 ]] || loom_error "$usage"; wargs=(--limit-min "$2"); shift 2 ;;
        *) loom_error "$usage" ;;
    esac
done
[[ -n $until_id ]] || loom_error "$usage"
[[ $until_id == all ]] || loom_id "$until_id"
loom_init

settled() {
    local f
    if [[ $until_id == all ]]; then
        shopt -s nullglob
        for f in "$LOOM_STATE"/*.json; do
            [[ -z $(jq -r '.worker_pid // empty' "$f") ]] || return 1
        done
        return 0
    fi
    f=$(loom_record "$until_id")
    [[ -n $(jq -r '.launched_at // empty' "$f") && -z $(jq -r '.worker_pid // empty' "$f") ]]
}

if [[ $until_id != all ]]; then
    for _ in $(seq 1 60); do
        [[ -z $(jq -r '.launched_at // empty' "$(loom_record "$until_id")") ]] || break
        sleep 1
    done
    [[ -n $(jq -r '.launched_at // empty' "$(loom_record "$until_id")") ]] || loom_error "$until_id was never launched"
fi
while :; do
    acted=$(bash "$ops/watchdog.sh" ${wargs[@]+"${wargs[@]}"})
    [[ -z $acted ]] || printf '%s %s\n' "$(date -u +%H:%M:%S)" "$acted"
    settled && break
    sleep "$every"
done
bash "$ops/status.sh"
