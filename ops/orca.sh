#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted $names here are jq variables
# orca.sh — the Orca executor and the Orca surface Loom needs (gaps #25, #26,
# #35, #36, #37). Owner, 2026-11-07: workers "only start or stop through
# orcacli", and all compute runs on Agni, never the laptop.
#
#   orca.sh detect                  is the Orca CLI/runtime ready? (exit 0 = yes)
#   orca.sh hosts                   name, connected, selector per Orca host
#   orca.sh start <id> [--agent A]  worker-start, on the consumer's compute host
#   orca.sh harvest <id>            after Orca reports the worker done: fold
#                                   REPORT.md, commit, settle
#   orca.sh stop <id>               worker-stop; settle only on a confirmed stop
#   orca.sh release <id>            worker-release after collect
#   orca.sh show <id>               worker-show: is the dispatch settled?
#   orca.sh read <id>               worker-read into the evidence directory
#   orca.sh abandon <id>            worker-abandon; fencing, not a stop
#   orca.sh keep-open <id>          worker-keep-open
#   orca.sh list                    worker-list (reconciliation)
#   orca.sh request <request-id>    request-show
#   orca.sh peek                    check --peek (never check without --peek)
#   orca.sh inbox                   inbox
#   orca.sh send <id> --subject S [--body B]
#   orca.sh ask <id> --question Q
#   orca.sh reply --id M --body B
#   orca.sh gate create|resolve|list ...
#   orca.sh task create|update ...
#   orca.sh run create|use|current|show|list ...
#   orca.sh reference add|find|list ...
#   orca.sh worktree rm|ps|list ...
#   orca.sh repo                    repo show
#   orca.sh base-ref <ref>          repo set-base-ref
#   orca.sh automation create|list|run|remove ...
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
usage='usage: orca.sh detect | hosts | start <id> [--agent A] | harvest <id> | stop <id> | release <id> | show <id> | read <id> | abandon <id> | keep-open <id> | list [--run R] | request <request-id> | peek | inbox | send <id> --subject S [--body B] | ask <id> --question Q | reply --id M --body B | gate create|resolve|list | task create|update | run create|use|current|show|list | reference add|find|list | worktree rm|ps|list | repo | base-ref <ref> | automation create|list|run|remove'
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

# Classify what worker-show says about one dispatch: active | settled | unknown.
dispatch_state() {  # dispatch_state <receipt>
    local words
    words=$(jq -r '[.. | objects | (.terminalState? // .state? // .status?) | select(type == "string")] | unique | join(",")' "$1" 2>/dev/null || :)
    case ",$words," in
        *',active,'*|*',running,'*|*',starting,'*|*',in_progress,'*|*',working,'*) printf 'active' ;;
        *',settled,'*|*',closed,'*|*',finished,'*|*',succeeded,'*|*',completed,'*|*',released,'*) printf 'settled' ;;
        *) printf 'unknown' ;;
    esac
}

orca_call() {  # orca_call <receipt> <args...>: run Orca, save its output
    local receipt=$1
    shift
    loom_orca "$@" > "$receipt" 2>&1
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

hosts)
    [[ $# == 0 ]] || loom_error "$usage"
    loom_orca host list --json | jq -r '.result.hosts[] | [.name, (.kind == "local" or .connected == true), (.selector // "--host \(.id)")] | @tsv'
    ;;

start)
    [[ $# == 1 || ( $# == 3 && $2 == --agent ) ]] || loom_error "$usage"
    id=$1
    agent=${3:-codex}
    loom_id "$id"
    [[ $agent =~ ^[a-z0-9-]+$ ]] || loom_error 'invalid agent id'
    loom_init
    runtime=$(loom_orca_ready) || loom_error 'the Orca CLI/runtime is not ready (orca status); nothing started'
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca ]] || loom_error "$id is not an Orca assignment"
    # Placement (#37): a declared compute host must exist in Orca and be
    # connected. Loom never falls back to the conductor's machine.
    hosts=$(jq -c '.compute // []' "$file")
    placement_args=()
    placement_host=''
    placement_selector=''
    if [[ $hosts != '[]' && $hosts != 'null' ]]; then
        placement_host=$(jq -r '.compute[0]' "$file")
        rc=0
        loom_orca_host "$placement_host" >/dev/null || rc=$?
        if [[ $rc == 1 ]]; then
            loom_error "compute host '$placement_host' is not a known Orca host; connect it in Orca first"
        elif [[ $rc == 2 ]]; then
            loom_error "compute host '$placement_host' is known to Orca but not connected; connect it in Orca first"
        fi
        placement_selector=$(jq -r '.compute_selector // empty' "$file" 2>/dev/null || :)
        if [[ -n $placement_selector ]]; then
            read -r -a placement_args <<< "$placement_selector"
        else
            placement_args=(--on "$placement_host")
        fi
    fi
    loom_lock
    file=$(loom_record "$id")
    [[ $(jq -r '.executor.state' "$file") == pending ]] || loom_error "$id is not pending (state: $(jq -r '.executor.state' "$file"))"
    loom_write "$file" '.executor.state = "starting"'
    loom_unlock
    checkout=$(jq -r '.checkout' "$file")
    base=$(jq -r '.base_sha' "$file")
    ticket=$(jq -r '.ticket' "$file")
    repo=$(jq -r '.repo' "$file")
    spec="$LOOM_STATE/$id.spec.md"
    {
        printf 'You are a loom worker for assignment %s. Orca created this workspace for you; work only inside it.\n' "$id"
        printf 'The mandate below is complete. End your turn by appending one state line to REPORT.md at the root of this workspace, exactly as described. Never run git add, git commit or git push: loom commits your work when you report.\n\n'
        cat "$LOOM_STATE/$id.WORK.md"
    } > "$spec"
    receipt="$LOOM_STATE/$id.orca-start.receipt"
    extra=()
    model=$(jq -r '.model // empty' "$file")
    effort=$(jq -r '.effort // empty' "$file")
    timeout=$(jq -r '.start_timeout_ms // empty' "$file")
    [[ -z $model ]] || extra+=(--model "$model")
    [[ -z $effort ]] || extra+=(--effort "$effort")
    [[ -z $timeout ]] || extra+=(--timeout-ms "$timeout")
    rc=0
    loom_orca orchestration worker-start --spec-file "$spec" --worktree new-top-level \
        --repo "path:$checkout" --name "$id" --base-branch "$base" --setup skip \
        --agent "$agent" --task-title "loom $id" --display-name "loom $id" \
        --comment "$repo#$ticket" ${placement_args[@]+"${placement_args[@]}"} ${extra[@]+"${extra[@]}"} \
        --json > "$receipt" 2>&1 || rc=$?
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
                    task: $t, run: $run, kept_open: $kept,
                    placement: (if $ph == "" then null else {host: $ph, selector: $sel} end)}' \
        --arg w "$workdir" --arg b "$branch" --arg d "$dispatch" --arg rt "$runtime" --arg a "$agent" \
        --arg r "${receipt##*/}" --arg t "$(receipt_get "$receipt" taskId task_id || :)" \
        --arg run "$(receipt_get "$receipt" runId run_id || :)" --argjson kept "$kept" \
        --arg ph "$placement_host" --arg sel "$placement_selector"
    loom_unlock
    # Attach the ticket to the workspace. Not fatal: the worker is already up.
    loom_orca reference add --worktree "path:$workdir" \
        --url "https://github.com/$repo/issues/$ticket" --json >/dev/null 2>&1 ||
        printf 'loom: warning: could not attach the ticket reference to %s\n' "$workdir" >&2
    printf '%s started via orca: dispatch %s, agent %s, workspace %s (branch %s)%s\n' \
        "$id" "$dispatch" "$agent" "$workdir" "$branch" "${placement_host:+ on $placement_host}"
    [[ $head == "$base" ]] || printf 'loom: warning: workspace HEAD %s is not the recorded base %s\n' "${head:0:7}" "${base:0:7}" >&2
    ;;

harvest)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca && $(jq -r '.executor.state' "$file") == running ]] || loom_error "$id has no running Orca worker to harvest"
    dispatch=$(jq -r '.executor.dispatch' "$file")
    # Ask Orca before claiming the dispatch settled (#35). Unknown shapes do
    # not block a conductor's explicit harvest; a clearly active one does.
    show="$LOOM_STATE/$id.orca-show.receipt"
    if loom_orca orchestration worker-show --dispatch "$dispatch" --json > "$show" 2>&1; then
        case $(dispatch_state "$show") in
            active) loom_error "dispatch $dispatch is still active; wait for it to settle before harvest" ;;
            settled) : ;;
            *) printf 'loom: warning: worker-show gave no settled verdict; harvesting anyway: see %s\n' "${show##*/}" >&2 ;;
        esac
    else
        printf 'loom: warning: worker-show failed; harvesting anyway: see %s\n' "${show##*/}" >&2
    fi
    loom_lock
    file=$(loom_record "$id")
    state=$(loom_harvest "$file" 'worker_done_without_report (orca)')
    loom_write "$file" '.executor.state = "settled" | .executor.settled_at = (now | todateiso8601)'
    loom_unlock
    printf '%s %s (harvested from orca dispatch %s)\n' "$id" "$state" "$dispatch"
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

abandon)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca ]] || loom_error "$id is not an Orca assignment"
    [[ $(jq -r '.executor.state' "$file") == running ]] || loom_error "$id has no running Orca worker to abandon"
    dispatch=$(jq -r '.executor.dispatch' "$file")
    receipt="$LOOM_STATE/$id.orca-abandon.receipt"
    rc=0
    loom_orca orchestration worker-abandon --dispatch "$dispatch" --json > "$receipt" 2>&1 || rc=$?
    [[ $rc == 0 ]] || { printf '%s: orca refused the abandon (exit %s): see %s\n' "$id" "$rc" "$receipt" >&2; exit 1; }
    loom_lock
    file=$(loom_record "$id")
    # Fencing, not a stop: never record a stopped state from an abandon.
    loom_append "$file" failed 'owner_fenced (abandoned; Orca did not claim the process stopped)'
    loom_write "$file" '.executor.state = "abandoned"'
    loom_unlock
    printf '%s abandoned via orca (dispatch %s); no stop claimed\n' "$id" "$dispatch"
    ;;

keep-open)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    file=$(loom_record "$id")
    [[ $(loom_executor "$file") == orca ]] || loom_error "$id is not an Orca assignment"
    dispatch=$(jq -r '.executor.dispatch // empty' "$file")
    [[ -n $dispatch ]] || loom_error "$id has no Orca dispatch"
    receipt="$LOOM_STATE/$id.orca-keep-open.receipt"
    rc=0
    loom_orca orchestration worker-keep-open --dispatch "$dispatch" --json > "$receipt" 2>&1 || rc=$?
    [[ $rc == 0 ]] || { printf '%s: orca refused keep-open (exit %s): see %s\n' "$id" "$rc" "$receipt" >&2; exit 1; }
    loom_lock
    file=$(loom_record "$id")
    loom_write "$file" '.executor.kept_open = true'
    loom_unlock
    printf '%s kept open via orca (dispatch %s)\n' "$id" "$dispatch"
    ;;

show)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    file=$(loom_record "$id")
    dispatch=$(jq -r '.executor.dispatch // empty' "$file")
    [[ -n $dispatch ]] || loom_error "$id has no Orca dispatch"
    receipt="$LOOM_STATE/$id.orca-show.receipt"
    orca_call "$receipt" orchestration worker-show --dispatch "$dispatch" --json ||
        { printf '%s: worker-show failed: see %s\n' "$id" "${receipt##*/}" >&2; exit 1; }
    state=$(dispatch_state "$receipt")
    printf '%s show: %s (dispatch %s)\n' "$id" "$state" "$dispatch"
    ;;

read)
    [[ $# == 1 ]] || loom_error "$usage"
    id=$1
    loom_id "$id"
    loom_init
    file=$(loom_record "$id")
    dispatch=$(jq -r '.executor.dispatch // empty' "$file")
    [[ -n $dispatch ]] || loom_error "$id has no Orca dispatch"
    mkdir -p "$LOOM_STATE/$id.evidence"
    out="$LOOM_STATE/$id.evidence/orca-transcript.txt"
    if loom_orca orchestration worker-read --dispatch "$dispatch" --source auto --json > "$out" 2>/dev/null; then
        printf '%s read: %s\n' "$id" "${out##*/}"
    else
        printf '%s: worker-read failed: see %s\n' "$id" "${out##*/}" >&2
        exit 1
    fi
    ;;

list)
    run=''
    if [[ $# == 2 && $1 == --run ]]; then run=$2; elif [[ $# != 0 ]]; then loom_error "$usage"; fi
    args=(--json)
    [[ -z $run ]] || args=(--run "$run" --json)
    loom_orca orchestration worker-list "${args[@]}" | jq -r '
      [.. | objects | select(has("dispatchId")) |
       [.dispatchId, (.terminalState // .state // .status // "unknown"), (.agent // ""), (.name // "")] | @tsv] | .[]' 2>/dev/null || :
    ;;

request)
    if [[ $# == 2 && $1 == --request ]]; then set -- "$2"; fi
    [[ $# == 1 ]] || loom_error "$usage"
    loom_orca orchestration request-show --request "$1" --json
    ;;

peek)
    [[ $# == 0 ]] || loom_error "$usage"
    loom_orca orchestration check --peek --json
    ;;

inbox)
    [[ $# == 0 ]] || loom_error "$usage"
    loom_orca orchestration inbox --json
    ;;

send)
    [[ $# -ge 3 && $2 == --subject ]] || loom_error "$usage"
    id=$1; subject=$3; shift 3
    body=''
    if [[ $# == 2 && $1 == --body ]]; then body=$2; elif [[ $# != 0 ]]; then loom_error "$usage"; fi
    loom_orca orchestration send --to "dispatch:$id" --subject "$subject" --body "$body" --json
    ;;

ask)
    [[ $# == 3 && $2 == --question ]] || loom_error "$usage"
    loom_orca orchestration ask --to "dispatch:$1" --question "$3" --json
    ;;

reply)
    [[ $# == 4 && $1 == --id && $3 == --body ]] || loom_error "$usage"
    loom_orca orchestration reply --id "$2" --body "$4" --json
    ;;

gate)
    [[ $# -ge 1 ]] || loom_error "$usage"
    sub=$1; shift
    case $sub in
        create) [[ $# -ge 4 && $1 == --task && $3 == --question ]] || loom_error "$usage"
                loom_orca orchestration gate-create --task "$2" --question "$4" --json ;;
        resolve) [[ $# == 4 && $1 == --id && $3 == --resolution ]] || loom_error "$usage"
                 loom_orca orchestration gate-resolve --id "$2" --resolution "$4" --json ;;
        list) loom_orca orchestration gate-list --json ;;
        *) loom_error "$usage" ;;
    esac
    ;;

task)
    [[ $# -ge 1 ]] || loom_error "$usage"
    sub=$1; shift
    case $sub in
        create) [[ $# -ge 2 && $1 == --spec ]] || loom_error "$usage"
                spec=$2
                loom_orca orchestration task-create --spec "$spec" --json ;;
        update) [[ $# -ge 4 && $1 == --id && $3 == --status ]] || loom_error "$usage"
                loom_orca orchestration task-update --id "$2" --status "$4" --json ;;
        *) loom_error "$usage" ;;
    esac
    ;;

run)
    [[ $# -ge 1 ]] || loom_error "$usage"
    sub=$1; shift
    case $sub in
        create) [[ $# == 2 && $1 == --objective ]] || loom_error "$usage"
                loom_orca orchestration run-create --objective "$2" --json ;;
        use) [[ $# == 2 && $1 == --id ]] || loom_error "$usage"
             loom_orca orchestration run-use --id "$2" --json ;;
        current) loom_orca orchestration run-current --json ;;
        show) [[ $# == 2 && $1 == --id ]] || loom_error "$usage"
              loom_orca orchestration run-show --id "$2" --json ;;
        list) loom_orca orchestration run-list --json ;;
        *) loom_error "$usage" ;;
    esac
    ;;

reference)
    [[ $# -ge 1 ]] || loom_error "$usage"
    sub=$1; shift
    case $sub in
        add) [[ $# == 4 && $1 == --worktree && $3 == --url ]] || loom_error "$usage"
             loom_orca reference add --worktree "$2" --url "$4" --json ;;
        find) [[ $# == 2 && $1 == --url ]] || loom_error "$usage"
              loom_orca reference find --url "$2" --json ;;
        list) [[ $# == 2 && $1 == --worktree ]] || loom_error "$usage"
              loom_orca reference list --worktree "$2" --json ;;
        *) loom_error "$usage" ;;
    esac
    ;;

worktree)
    [[ $# -ge 1 ]] || loom_error "$usage"
    sub=$1; shift
    case $sub in
        rm) [[ $# -ge 2 && $1 == --worktree ]] || loom_error "$usage"
            sel=$2; shift 2
            extra=()
            [[ $# == 0 || ( $# == 1 && $1 == --delete-branch ) ]] || loom_error "$usage"
            [[ $# == 0 ]] || extra=(--delete-branch)
            loom_orca worktree rm --worktree "$sel" ${extra[@]+"${extra[@]}"} --json ;;
        ps) loom_orca worktree ps --json ;;
        list) loom_orca worktree list --json ;;
        *) loom_error "$usage" ;;
    esac
    ;;

repo)
    [[ $# == 2 && $1 == --path ]] || loom_error "$usage"
    loom_orca repo show --repo "path:$2" --json
    ;;

base-ref)
    [[ $# == 1 ]] || loom_error "$usage"
    checkout=${LOOM_REPO:-.}
    loom_orca repo set-base-ref --repo "path:$checkout" --ref "$1" --json
    ;;

automation)
    [[ $# -ge 1 ]] || loom_error "$usage"
    sub=$1; shift
    case $sub in
        create) loom_orca automations create "$@" --json ;;
        list) loom_orca automations list --json ;;
        run) [[ $# == 1 ]] || loom_error "$usage"; loom_orca automations run "$1" --json ;;
        remove) [[ $# == 1 ]] || loom_error "$usage"; loom_orca automations remove "$1" --json ;;
        *) loom_error "$usage" ;;
    esac
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
