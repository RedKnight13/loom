#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted $names here are jq variables
# orca.sh — the Orca executor (gaps #25, #26). Owner, 2026-11-07: workers
# "only start or stop through orcacli".
#
#   orca.sh detect                  is the Orca CLI/runtime ready? (exit 0 = yes)
#   orca.sh start <id> [--agent A]  orchestration worker-start; adopt its worktree
#   orca.sh harvest <id>            after Orca reports the worker done: fold
#                                   REPORT.md, commit, settle
#   orca.sh stop <id>               orchestration worker-stop; settle only on a
#                                   stop Orca confirmed
#
# Orca creates the worker's workspace (a new top-level worktree of the
# consumer checkout, which must be registered in Orca once) and supervises
# it. Loom never signals an Orca worker; a stale one is surfaced by status.sh
# for the owner. Orca wakes the conductor when a worker finishes: do not poll.
# Raw receipts are kept as $LOOM_STATE/<id>.orca-*.receipt (never *.json: that
# suffix is reserved for assignment records).
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
usage='usage: orca.sh detect | start <id> [--agent A] | harvest <id> | stop <id> | release <id>'
[[ $# -ge 1 ]] || loom_error "$usage"
cmd=$1
shift

# First string value, anywhere in a JSON document, of the first listed key that
# appears (receipt shapes are Orca's, not loom's; search rather than assume).
receipt_get() {  # receipt_get <file> <key>...
    local key val
    for key in "${@:2}"; do
        val=$(jq -r --arg k "$key" '[.. | objects | .[$k]? | select(type == "string" and length > 0)] | first // empty' "$1")
        [[ -z $val ]] || { printf '%s' "$val"; return 0; }
    done
    return 1
}

case $cmd in
detect)
    [[ $# == 0 ]] || loom_error "$usage"
    if runtime=$(loom_orca_ready); then
        printf 'orca ready: runtime %s\n' "$runtime"
    else
        printf 'orca not ready: CLI missing or runtime unreachable (orca status)\n'
        exit 1
    fi
    ;;

start)
    [[ $# == 1 || ( $# == 3 && $2 == --agent ) ]] || loom_error "$usage"
    id=$1
    agent=${3:-codex}
    loom_id "$id"
    [[ $agent =~ ^[a-z0-9-]+$ ]] || loom_error 'invalid agent id'
    loom_init
    runtime=$(loom_orca_ready) || loom_error 'the Orca CLI/runtime is not ready (orca status); nothing started'
    loom_lock
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca ]] || loom_error "$id is not an Orca assignment"
    [[ $(jq -r '.executor.state' "$file") == pending ]] || loom_error "$id is not pending (state: $(jq -r '.executor.state' "$file"))"
    loom_write "$file" '.executor.state = "starting"'
    loom_unlock
    checkout=$(jq -r '.checkout' "$file")
    base=$(jq -r '.base_sha' "$file")
    spec="$LOOM_STATE/$id.spec.md"
    {
        printf 'You are a loom worker for assignment %s. Orca created this workspace for you; work only inside it.\n' "$id"
        printf 'The mandate below is complete. End your turn by appending one state line to REPORT.md at the root of this workspace, exactly as described. Never run git add, git commit or git push: loom commits your work when you report.\n\n'
        cat "$LOOM_STATE/$id.WORK.md"
    } > "$spec"
    receipt="$LOOM_STATE/$id.orca-start.receipt"
    rc=0
    loom_orca orchestration worker-start --spec-file "$spec" --worktree new-top-level \
        --repo "path:$checkout" --name "$id" --base-branch "$base" --setup skip \
        --agent "$agent" --task-title "loom $id" --json > "$receipt" 2>&1 || rc=$?
    dispatch=$(receipt_get "$receipt" dispatchId dispatch_id) || dispatch=''
    # Gap #29: a real receipt has result.workspace = "<repo-id>::<path>", not worktree.path.
    # Split on the last "::". A value with no separator is not a path.
    workspace=$(receipt_get "$receipt" workspace) || workspace=''
    workdir=''
    if [[ $workspace == *::* ]]; then workdir=${workspace##*::}; fi
    if [[ -z $workdir || ! -d $workdir ]]; then
        workdir=$(receipt_get "$receipt" worktreePath worktree_path) ||
            workdir=$(jq -r '[.. | objects | .worktree? | objects | .path? | strings] | first // empty' "$receipt" 2>/dev/null) || workdir=''
    fi
    if [[ -z $workdir || ! -d $workdir ]]; then
        workdir=$(loom_orca worktree show --worktree "name:$id" --json 2>/dev/null | jq -r '[.. | objects | .path? | select(type == "string")] | first // empty') || workdir=''
    fi
    loom_lock
    file=$(loom_record "$id")
    if [[ $rc != 0 || -z $dispatch || -z $workdir || ! -d $workdir ]]; then
        # Orca: if worker-start fails, do not rerun it. Loom records and stops.
        loom_write "$file" '.executor.state = "failed_start" | .executor.receipt = $r' --arg r "${receipt##*/}"
        loom_append "$file" failed "orca worker-start did not yield a worker (exit $rc, dispatch '${dispatch:-none}', workspace '${workdir:-none}'): see ${receipt##*/}"
        loom_unlock
        printf '%s failed_start (exit %s): see %s\n' "$id" "$rc" "$receipt" >&2
        exit 1
    fi
    # Keep loom's files out of the consumer's commits (worktrees share info/exclude).
    common=$(git -C "$workdir" rev-parse --git-common-dir)
    [[ $common == /* ]] || common="$workdir/$common"
    for f in WORK.md REPORT.md .loom/; do
        grep -qxF "$f" "$common/info/exclude" 2>/dev/null || printf '%s\n' "$f" >> "$common/info/exclude"
    done
    cp "$LOOM_STATE/$id.WORK.md" "$workdir/WORK.md"
    branch=$(git -C "$workdir" branch --show-current)
    head=$(git -C "$workdir" rev-parse HEAD)
    kept=false
    jq -e '[.. | objects | .keptOpen? | booleans] | any' "$receipt" >/dev/null && kept=true
    loom_write "$file" '
      .workdir = $w | .branch = $b | .launched_at = (now | todateiso8601) | .report_offset = 0 |
      .executor += {state: "running", dispatch: $d, runtime: $rt, agent: $a, receipt: $r,
                    task: $t, run: $run, kept_open: $kept}' \
        --arg w "$workdir" --arg b "$branch" --arg d "$dispatch" --arg rt "$runtime" --arg a "$agent" \
        --arg r "${receipt##*/}" --arg t "$(receipt_get "$receipt" taskId task_id || :)" \
        --arg run "$(receipt_get "$receipt" runId run_id || :)" --argjson kept "$kept"
    loom_unlock
    printf '%s started via orca: dispatch %s, agent %s, workspace %s (branch %s)\n' "$id" "$dispatch" "$agent" "$workdir" "$branch"
    [[ $head == "$base" ]] || printf 'loom: warning: workspace HEAD %s is not the recorded base %s\n' "${head:0:7}" "${base:0:7}" >&2
    ;;

harvest)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    loom_lock
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca && $(jq -r '.executor.state' "$file") == running ]] || loom_error "$id has no running Orca worker to harvest"
    state=$(loom_harvest "$file" 'worker_done_without_report (orca)')
    loom_write "$file" '.executor.state = "settled"'
    loom_unlock
    printf '%s %s (harvested from orca dispatch %s)\n' "$id" "$state" "$(jq -r '.executor.dispatch' "$file")"
    ;;

stop)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca && $(jq -r '.executor.state' "$file") == running ]] || loom_error "$id has no running Orca worker to stop"
    dispatch=$(jq -r '.executor.dispatch' "$file")
    receipt="$LOOM_STATE/$id.orca-stop.receipt"
    rc=0
    loom_orca orchestration worker-stop --dispatch "$dispatch" --json > "$receipt" 2>&1 || rc=$?
    # Claim a stop only when Orca confirmed one (Orca: stop_unknown proves nothing).
    if [[ $rc != 0 ]] || grep -q 'stop_unknown' "$receipt"; then
        printf '%s: orca could not confirm the stop (exit %s); nothing recorded. See %s, then orca orchestration worker-show --dispatch %s\n' "$id" "$rc" "$receipt" "$dispatch" >&2
        exit 1
    fi
    loom_lock
    file=$(loom_record "$id")
    loom_harvest "$file" 'stopped via orca by the conductor' >/dev/null
    if [[ $(jq -r '.reports[-1].fact' "$file") != 'stopped via orca by the conductor' ]]; then
        loom_append "$file" failed 'stopped via orca by the conductor'
    fi
    loom_write "$file" '.executor.state = "settled"'
    loom_unlock
    printf '%s stopped via orca (dispatch %s)\n' "$id" "$dispatch"
    ;;

release)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca ]] || loom_error "$id is not an Orca assignment"
    [[ $(jq -r '.executor.state' "$file") == settled ]] || loom_error "$id is not settled; release after harvest or a confirmed stop"
    [[ $(jq -r '.collected_sha // empty' "$file") =~ ^[0-9a-f]{40}$ ]] || loom_error "$id branch is not collected; release after collect"
    [[ $(jq -r '.executor.released // false' "$file") == false ]] || loom_error "$id already released"
    dispatch=$(jq -r '.executor.dispatch // empty' "$file")
    [[ -n $dispatch ]] || loom_error "$id has no Orca dispatch to release"
    receipt="$LOOM_STATE/$id.orca-release.receipt"
    rc=0
    loom_orca orchestration worker-release --dispatch "$dispatch" --json > "$receipt" 2>&1 || rc=$?
    if [[ $rc != 0 ]] || ! jq -e '.ok == true' "$receipt" >/dev/null 2>&1; then
        printf '%s: orca did not confirm the release (exit %s); nothing recorded. See %s\n' "$id" "$rc" "$receipt" >&2
        exit 1
    fi
    loom_lock
    file=$(loom_record "$id")
    # shellcheck disable=SC2016
    loom_write "$file" '.executor.released = true | .executor.release_receipt = $r' --arg r "${receipt##*/}"
    loom_unlock
    printf '%s released via orca (dispatch %s)\n' "$id" "$dispatch"
    ;;

*) loom_error "$usage" ;;
esac
