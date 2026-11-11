#!/usr/bin/env bash
# Shared helpers for the loom ops scripts. Sourced, never run.
#
# State model: one JSON record per assignment in $LOOM_STATE (conductor-only;
# workers never write it). Workers speak only through REPORT.md in their own
# workdir; harvest folds the newest state line into the record.

loom_error() { printf 'loom: %s\n' "$*" >&2; exit 1; }

# Loom's own state is private (umask 077), but children loom runs (workers,
# checks) get the caller's umask: a tightened umask changes file modes and
# breaks consumers' tests (found by the D1 baseline, gap #19).
LOOM_CALLER_UMASK=${LOOM_CALLER_UMASK:-$(umask)}
export LOOM_CALLER_UMASK

loom_init() {
    umask 077
    LOOM_STATE=${LOOM_STATE:-$HOME/.loom}
    mkdir -p "$LOOM_STATE"
}

# Each acquisition publishes a uniquely named owner file. Only the contender
# that successfully removes that exact file may remove the empty lock directory.
# A delayed reaper/unlocker therefore cannot unlink a replacement owner's file.
loom_lock() {
    local tries=0 max owner pid start now claim
    max=$(( ${LOOM_LOCK_WAIT:-10} * 5 ))
    # Unlike $$, this is the current shell even inside a Bash 3.2 subshell.
    pid=$(exec bash -c 'printf "%s" "$PPID"')
    # Restricted offline drills may omit ps; a PID-only claim is conservative.
    start=$(LC_ALL=C loom_pstart "$pid") || start=
    claim=$(mktemp "$LOOM_STATE/.lock-owner.$pid.XXXXXXXX") || loom_error 'cannot create lock claim'
    printf '%s\n%s\n' "$pid" "$start" > "$claim"
    until mkdir "$LOOM_STATE/.lock" 2>/dev/null; do
        for owner in "$LOOM_STATE/.lock"/owner.* "$LOOM_STATE/.lock/owner"; do
            [[ -f $owner && ! -L $owner ]] || continue
            { IFS= read -r pid; IFS= read -r start || :; } < "$owner" || continue
            [[ $pid =~ ^[1-9][0-9]*$ ]] || continue
            now=$(LC_ALL=C loom_pstart "$pid") || now=
            # A failed observation alone is not death; kill -0 is a second
            # conservative check. Old PID-only owners remain supported.
            if { [[ -n $start && -n $now && $start != "$now" ]]; } ||
               { [[ -z $now ]] && ! kill -0 "$pid" 2>/dev/null; }; then
                if rm -- "$owner" 2>/dev/null; then
                    rmdir "$LOOM_STATE/.lock" 2>/dev/null || :
                fi
            fi
        done
        if (( tries++ >= max )); then
            rm -f "$claim"
            loom_error 'state is locked; retry after the active operation finishes'
        fi
        sleep 0.2
    done
    LOOM_LOCK_OWNER="$LOOM_STATE/.lock/owner.${claim##*/}"
    mv "$claim" "$LOOM_LOCK_OWNER"
    trap loom_unlock EXIT
}

loom_unlock() {
    if [[ -n ${LOOM_LOCK_OWNER:-} ]] && rm -- "$LOOM_LOCK_OWNER" 2>/dev/null; then
        rm -f "$LOOM_STATE/.pending"
        rmdir "$LOOM_STATE/.lock" 2>/dev/null || :
    fi
    LOOM_LOCK_OWNER=
    trap - EXIT
}

loom_id() {
    [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && $1 != *..* ]] || loom_error 'invalid assignment id'
}

loom_record() {
    local file="$LOOM_STATE/$1.json"
    [[ -f $file && ! -L $file ]] || loom_error 'assignment not found or is a symlink'
    loom_validate "$file"
    printf '%s' "$file"
}

loom_validate() {
    jq -e '
      def iso: type == "string" and (fromdateiso8601 | type == "number");
      type == "object" and (.ticket | type == "number") and
      (.repo | type == "string") and (.short_name | type == "string") and
      (.workdir | type == "string") and (.checkout | type == "string") and
      (.base_sha | type == "string") and (.attempt | type == "number") and
      (.worker_pid == null or (.worker_pid | type == "number" and . > 1 and . == floor)) and
      (.worker_pid == null or (.worker_start | type == "string" and length > 0)) and
      (.legacy_guard == null or (.legacy_guard | type == "object" and
          (.identity | type == "string" and test("^([a-f0-9-]+:[0-9]+|ps:[A-Za-z0-9_:]+)$")) and
          (.stop_requested == null or (.stop_requested | type == "boolean")) and
          (.pgid | type == "number" and . > 1 and . == floor) and
          (.directory | type == "string" and test("^[a-zA-Z0-9._-]+$") and (contains("..") | not)))) and
      (.started_at | iso) and
      ((has("launched_at") | not) or (.launched_at | iso)) and
      ((has("executor") | not) or (.executor | type == "object" and
          (.kind == "local" or .kind == "orca") and
          (.kind == "local" or (.state | IN("pending", "starting", "running", "settled", "failed_start", "abandoned"))))) and
      ((has("branch") | not) or .branch == null or (.branch | type == "string")) and
      ((has("compute") | not) or .compute == null or (.compute | type == "array" and all(.[]; type == "string"))) and
      ((has("compute_setup") | not) or .compute_setup == null or (.compute_setup | type == "string")) and
      ((has("compute_selector") | not) or .compute_selector == null or (.compute_selector | type == "string")) and
      ((has("model") | not) or .model == null or (.model | type == "string")) and
      ((has("effort") | not) or .effort == null or (.effort | type == "string")) and
      ((has("start_timeout_ms") | not) or .start_timeout_ms == null or (.start_timeout_ms | type == "number" and . > 0)) and
      ((has("workers") | not) or .workers == null or (.workers | type == "number" and . > 0)) and
      ((has("agent") | not) or .agent == null or (.agent | type == "string" and test("^[a-z0-9-]+$"))) and
      ((has("config_commit") | not) or .config_commit == null or (.config_commit | type == "string" and test("^[0-9a-f]{40}$"))) and
      ((has("checks") | not) or .checks == null or (.checks | type == "string")) and
      ((has("checks_runs") | not) or (.checks_runs | type == "array" and
          all(.[]; (.kind == "baseline" or .kind == "branch") and (.sha | type == "string") and
              (.exit | type == "number") and (.at | iso)))) and
      ((has("limit_min") | not) or .limit_min == null or (.limit_min | type == "number" and . > 0)) and
      ((has("report_offset") | not) or (.report_offset | type == "number" and . >= 0)) and
      ((has("harvest_report_lines") | not) or (.harvest_report_lines | type == "number" and . >= 0 and . == floor)) and
      (.executor.continuation_pending == null or (.executor.continuation_pending | type == "boolean")) and
      (.executor.send_boundary == null or (.executor.send_boundary | type == "number" and . >= 0 and . == floor)) and
      ((has("collected_sha") | not) or (.collected_sha | type == "string" and test("^[0-9a-f]{40}$"))) and
      ((has("previous_collected_sha") | not) or .previous_collected_sha == null or (.previous_collected_sha | type == "string" and test("^[0-9a-f]{40}$"))) and
      ((has("acked") | not) or (.acked | type == "object" and (.at | iso) and (.fact | type == "string" and length > 0))) and
      (.reports | type == "array") and
      all(.reports[]; (.at | iso) and
          (.state == "ready" or .state == "blocked" or .state == "failed" or .state == "waiting") and
          (.fact | type == "string"))
    ' "$1" >/dev/null || loom_error "invalid assignment record: ${1##*/}"
}

loom_write() {  # loom_write <file> <jq filter> [jq args...]; caller holds the lock
    local file=$1 filter=$2
    shift 2
    jq "$@" "$filter" "$file" > "$LOOM_STATE/.pending"
    mv "$LOOM_STATE/.pending" "$file"
}

loom_append() {  # loom_append <file> <state> <fact> [clear_pid]
    # shellcheck disable=SC2016  # $state/$fact/$clear are jq variables
    loom_write "$1" '
      .reports += [{at: (now | todateiso8601), state: $state, fact: $fact}] |
      if $clear then .worker_pid = null | .worker_start = null else . end
    ' --arg state "$2" --arg fact "$3" --argjson clear "${4:-false}"
}

# Process identity is PID plus start time, so a recycled PID is never mistaken
# for our worker (and never signalled).
loom_pstart() {
    local s
    s=$(ps -o lstart= -p "$1" 2>/dev/null) || return 1
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    [[ -n $s ]] || return 1
    printf '%s' "$s"
}

# Linux keeps boot ID/start-tick identity; Darwin retains the existing ps start
# time precision. Never downgrade Linux when /proc is inaccessible. The Darwin
# guard pins its process group through completion, but ps is not an atomic or
# high-resolution identity primitive (see tests/legacy/README.md).
_loom_legacy_platform=
loom_legacy_platform() {
    # Merely sourcing lib.sh must work in the calibration drill's restricted
    # tool environment, which does not perform process supervision.
    [[ -n $_loom_legacy_platform ]] || _loom_legacy_platform=$(uname -s)
}

loom_legacy_ps() {  # complete snapshot: failure/malformed output is unknown
    local rows pid pgid state extra
    rows=$(LC_ALL=C ps -axo pid=,pgid=,stat= 2>/dev/null) || return 2
    [[ -n $rows ]] || return 2
    while read -r pid pgid state extra; do
        # Darwin ps can report an indeterminate Mach state as '?'. Preserve
        # that row as live rather than rejecting the entire process snapshot.
        [[ $pid =~ ^[0-9]+$ && $pgid =~ ^[0-9]+$ && $state =~ ^[A-Za-z?] && -z $extra ]] || return 2
    done <<< "$rows"
    printf '%s\n' "$rows"
}

loom_legacy_proc() {  # sets _loom_proc: state, ppid, pgrp, ... start ticks
    local stat rows pid pgid state
    loom_legacy_platform || return 2
    [[ $1 =~ ^[0-9]+$ ]] || return 2
    case $_loom_legacy_platform in
        Darwin)
            rows=$(loom_legacy_ps) || return 2
            while read -r pid pgid state; do
                if [[ $pid == "$1" ]]; then
                    _loom_proc=("${state:0:1}" 0 "$pgid")
                    return 0
                fi
            done <<< "$rows"
            return 1 ;;
        Linux) ;;
        *) return 2 ;;
    esac
    if ! IFS= read -r stat 2>/dev/null < "/proc/$1/stat"; then
        [[ ! -d /proc/$1 ]] && return 1
        return 2
    fi
    [[ $stat == *') '* ]] || return 2
    read -r -a _loom_proc <<< "${stat##*) }"
    [[ ${#_loom_proc[@]} -ge 20 && ${_loom_proc[2]} =~ ^[0-9]+$ && ${_loom_proc[19]} =~ ^[0-9]+$ ]] || return 2
}

loom_legacy_identity() {
    local boot start
    loom_legacy_platform || return 1
    case $_loom_legacy_platform in
        Darwin)
            start=$(LC_ALL=C loom_pstart "$1") || return 1
            printf 'ps:%s' "${start// /_}"
            return ;;
        Linux) ;;
        *) return 1 ;;
    esac
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    loom_legacy_proc "$1" || return 1
    printf '%s:%s' "$boot" "${_loom_proc[19]}"
}

loom_legacy_group() {  # <pgid> [exclude-pid]: 0 live, 1 empty, 2 unknown
    local pgid=$1 except=${2:-0} path pid found=1 rows group state
    loom_legacy_platform || return 2
    case $_loom_legacy_platform in
        Darwin)
            rows=$(loom_legacy_ps) || return 2
            while read -r pid group state; do
                if [[ $pid != "$except" && $group == "$pgid" && $state != Z* && $state != X* ]]; then
                    found=0
                fi
            done <<< "$rows"
            return "$found" ;;
        Linux) ;;
        *) return 2 ;;
    esac
    [[ -r /proc/self/stat ]] || return 2
    for path in /proc/[0-9]*/stat; do
        pid=${path#/proc/}; pid=${pid%/stat}
        [[ $pid != "$except" ]] || continue
        if ! loom_legacy_proc "$pid"; then
            # A process may disappear during enumeration; unreadable survivors
            # are uncertainty, not evidence of an empty group.
            [[ ! -d /proc/$pid ]] && continue
            return 2
        fi
        if [[ ${_loom_proc[2]} == "$pgid" && ${_loom_proc[0]} != Z && ${_loom_proc[0]} != X ]]; then
            found=0
        fi
    done
    return "$found"
}

loom_legacy_run() {  # <private launch dir> <workdir> <command...>
    local dir=$1 workdir=$2 guard identity child rc=0 group parent=$$ parent_identity observer
    shift 2
    trap - EXIT
    set +m
    loom_legacy_platform || return 125
    parent_identity=$(loom_legacy_identity "$parent") || return 125
    # Parent records the stable group identity before any worker code runs.
    while [[ ! -f $dir/start ]]; do
        [[ $(loom_legacy_identity "$parent") == "$parent_identity" ]] || return 125
        sleep .05
    done
    # The parent supplies $! atomically; BASHPID is unavailable in Bash 3.2.
    read -r guard identity < "$dir/start" || return 125
    [[ $(loom_legacy_identity "$guard") == "$identity" ]] || return 125
    (cd "$workdir" && umask "$LOOM_CALLER_UMASK" && exec "$@") &
    child=$!
    wait "$child" || rc=$?
    while :; do
        group=0
        if [[ $_loom_legacy_platform == Darwin ]]; then
            # ps observes itself and its shell wrappers. Give the observer a
            # separate group so it cannot keep the worker group alive forever.
            set -m
            (loom_legacy_group "$guard" "$guard") &
            observer=$!
            set +m
            wait "$observer" 2>/dev/null || group=$?
        else
            loom_legacy_group "$guard" "$guard" || group=$?
        fi
        case $group in
            0) sleep .1 ;;
            1) break ;;
            *) return 125 ;;
        esac
    done
    # The guard pins the PGID until every other non-zombie member is gone.
    # Publish only after that proof, and bind the receipt to this exact guard.
    printf '%s %s %s\n' "$guard" "$identity" "$rc" > "$dir/settled.tmp"
    mv "$dir/settled.tmp" "$dir/settled"
    return "$rc"
}

loom_legacy_status() {  # running | settled | unknown; never infers completion
    local file=$1 pid identity now dir receipt_pid receipt_identity rc extra group=0 observed=0
    pid=$(jq -r '.worker_pid // empty' "$file")
    identity=$(jq -r '.legacy_guard.identity // empty' "$file")
    dir=$(jq -r '.legacy_guard.directory // empty' "$file")
    if [[ -z $pid || -z $identity || ! $dir =~ ^[a-zA-Z0-9._-]+$ || $dir == *..* ]] ||
        [[ $(jq -r '.legacy_guard.pgid // empty' "$file") != "$pid" ]]; then
        printf 'unknown'; return
    fi
    loom_legacy_proc "$pid" || observed=$?
    [[ $observed != 2 ]] || { printf 'unknown'; return; }
    if [[ $observed == 0 ]]; then
        now=$(loom_legacy_identity "$pid") || { printf 'unknown'; return; }
        [[ $now == "$identity" ]] || { printf 'unknown'; return; }
        loom_legacy_proc "$pid" || { printf 'unknown'; return; }
        [[ ${_loom_proc[2]} == "$pid" ]] || { printf 'unknown'; return; }
        if [[ ${_loom_proc[0]} != Z && ${_loom_proc[0]} != X ]]; then
            printf 'running'; return
        fi
    fi
    # A watchdog stop is bound to this guard while it is still verified live.
    # Signal delivery alone is never settlement: retain ownership until a fresh
    # scan proves every non-zombie group member gone, including the guard.
    if jq -e '.legacy_guard.stop_requested == true' "$file" >/dev/null; then
        loom_legacy_group "$pid" || group=$?
        if [[ $group == 1 ]]; then printf 'settled'; else printf 'unknown'; fi
        return
    fi
    # Even after loss of the launcher, a completed guard can prove settlement.
    # Loss of the guard itself, or a stale/reused identity, cannot do so.
    dir="$LOOM_STATE/$dir"
    if [[ -L $dir || ! -f $dir/settled || -L $dir/settled ]] ||
        ! read -r receipt_pid receipt_identity rc extra < "$dir/settled" ||
        [[ $receipt_pid != "$pid" || $receipt_identity != "$identity" || ! $rc =~ ^(0|[1-9][0-9]{0,2})$ || -n $extra || $rc -gt 255 ]]; then
        printf 'unknown'; return
    fi
    loom_legacy_group "$pid" || group=$?
    if [[ $group == 1 ]]; then printf 'settled'; else printf 'unknown'; fi
}

loom_legacy_finish_stop() {  # caller holds the state lock; never harvest a kill
    local file=$1 _
    for _ in {1..20}; do
        if [[ $(loom_legacy_status "$file") == settled ]]; then
            loom_append "$file" failed watchdog_kill true
            printf 'failed watchdog_kill'
            return
        fi
        sleep .05
    done
    printf 'pending settlement_unproven'
}

loom_alive() {  # A local assignment owns its slot until positively settled.
    if jq -e '.executor.kind == "orca"' "$1" >/dev/null; then
        loom_orca_running "$1"
        return
    fi
    # A lost guard is pending, not permission to relaunch, collect, or verify.
    jq -e '.worker_pid != null' "$1" >/dev/null
}

# Workspace host (#47): an Orca worker placed with --on runs on that host, and
# so does its workspace. Empty = this machine.
loom_ws_host() { jq -r '.ws_host // empty' "$1"; }

# Run argv inside a workspace, here or on its host.
loom_ws() {  # loom_ws <host> <workdir> <argv...>
    local h=$1 w=$2
    shift 2
    if [[ -z $h ]]; then
        (cd "$w" && "$@")
    else
        loom_ssh "$h" "cd $(printf '%q' "$w") && $(printf '%q ' "$@")"
    fi
}

# git over loom's ssh (fetching a branch from a workspace on its host).
loom_git_ssh() { GIT_SSH_COMMAND="${LOOM_SSH:-ssh} -o BatchMode=yes -o ConnectTimeout=5" git "$@"; }

# Keep loom's own files out of the consumer commit. .loom/ is the worker's
# evidence directory (gap #33): copied into state, never committed.
loom_exclude() {  # loom_exclude <workdir> [host]
    local workdir=$1 host=${2:-}
    loom_ws "$host" "$workdir" true 2>/dev/null || return 0
    # shellcheck disable=SC2016  # expands in the workspace's shell
    loom_ws "$host" "$workdir" bash -c 'common=$(git rev-parse --git-common-dir 2>/dev/null) || exit 0
mkdir -p "$common/info"
for f in WORK.md REPORT.md .loom/; do
    grep -qxF "$f" "$common/info/exclude" 2>/dev/null || printf "%s\n" "$f" >> "$common/info/exclude"
done'
}

# Copy .loom/ to $LOOM_STATE/<id>.evidence before the commit. A symlink is
# refused: evidence must not walk out of the workdir.
loom_take_evidence() {  # loom_take_evidence <workdir> <id> [host]
    local src="$1/.loom" dest="$LOOM_STATE/$2.evidence" host=${3:-} kind
    if [[ -n $host ]]; then
        kind=$(loom_ws "$host" "$1" bash -c 'if [ -L .loom ]; then echo link; elif [ -d .loom ]; then echo dir; elif [ -e .loom ]; then echo other; fi') ||
            loom_error "cannot read the workspace on $host: $1"
        [[ -n $kind ]] || return 0
        [[ $kind == dir ]] || loom_error "evidence path is not a directory: $host:$src"
        rm -rf "$dest"
        mkdir -p "$dest"
        loom_ws "$host" "$1" tar -C .loom -cf - . | tar -C "$dest" -xf - || loom_error "could not copy evidence from $host"
        return 0
    fi
    [[ -e $src || -L $src ]] || return 0
    [[ -d $src && ! -L $src ]] || loom_error "evidence path is not a directory: $src"
    rm -rf "$dest"
    cp -R "$src" "$dest"
}

# Read a report without following a symlink; use the recorded workspace host.
loom_report_text() {
    local host workdir
    host=${2-$(loom_ws_host "$1")}
    workdir=$(jq -r '.workdir' "$1")
    loom_ws "$host" "$workdir" bash -c '
      if [ -L REPORT.md ]; then exit 1; fi
      if [ -f REPORT.md ]; then cat REPORT.md; fi'
}

# Before a send, count existing lines. For settled legacy records, recover the
# consumed boundary only from one exact match to the previously folded report.
loom_report_boundary() {
    local file=$1 report offset matches reports
    report=$(loom_report_text "$file") || loom_error 'cannot read report boundary'
    if [[ $(jq -r '.executor.state' "$file") != settled ]]; then
        if [[ -z $report ]]; then printf 0; else printf '%s\n' "$report" | awk 'END {print NR}'; fi
        return
    fi
    offset=$(jq -r '.harvest_report_lines // empty' "$file")
    if [[ -n $offset ]]; then printf '%s' "$offset"; return; fi
    reports=$(jq -c '.reports | reverse' "$file")
    matches=$(jq -Rn --argjson reports "$reports" '
      [inputs] | to_entries | map({line: (.key + 1), report: (.value |
        try capture("^state:[ \t]*(?<state>ready|blocked|failed|waiting)[ \t]*(?:—|--|-|:)?[ \t]*(?<fact>.*)$") catch null)}) as $lines |
      [$reports[] as $r | [$lines[] | select(.report.state == $r.state and .report.fact == $r.fact) | .line] |
       select(length > 0)] | first // []
    ' <<< "$report")
    [[ $(jq length <<< "$matches") == 1 ]] || loom_error 'legacy report boundary is ambiguous; cannot reconcile safely'
    jq -r '.[0]' <<< "$matches"
}

# Fold the newest state line written since launch into the record and clear the
# worker. Accepted line: "state: <ready|blocked|failed|waiting> — <fact>"
# (separator may be —, --, - or :).
loom_harvest() {  # loom_harvest <file> <why-if-silent>
    local file=$1 silent=$2 workdir offset line state fact host
    if [[ $(loom_executor "$file") == local && $(jq -r '.worker_pid // empty' "$file") ]]; then
        jq -e '.legacy_guard.stop_requested != true' "$file" >/dev/null ||
            loom_error 'watchdog stop must settle as failure; nothing harvested'
        [[ $(loom_legacy_status "$file") == settled ]] ||
            loom_error 'legacy worker settlement is unproven; nothing harvested'
    fi
    local re='^state:[[:space:]]*(ready|blocked|failed|waiting)[[:space:]]*(—|--|-|:)?[[:space:]]*(.*)$'
    workdir=$(jq -r '.workdir' "$file")
    offset=$(jq -r '.report_offset // 0' "$file")
    host=$(loom_ws_host "$file")
    line=
    if [[ -n $host ]]; then
        # shellcheck disable=SC2016  # expands in the workspace's shell
        line=$(loom_ws "$host" "$workdir" bash -c '[ -f REPORT.md ] && [ ! -L REPORT.md ] && tail -n +"$1" REPORT.md' _ "$((offset + 1))" 2>/dev/null | grep -E '^state:' | tail -n 1 || :)
    elif [[ -f $workdir/REPORT.md && ! -L $workdir/REPORT.md ]]; then
        line=$(tail -n +"$((offset + 1))" "$workdir/REPORT.md" | grep -E '^state:' | tail -n 1 || :)
    fi
    if [[ -n $line && $line =~ $re ]]; then
        state=${BASH_REMATCH[1]}
        fact=${BASH_REMATCH[3]:-no fact given}
    else
        state=failed
        fact=$silent
    fi
    # Workers never touch git (executor sandboxes may forbid it): loom seals
    # whatever the worker left in its workdir as one commit on the ticket
    # branch. WORK.md and REPORT.md are excluded at dispatch.
    local id=${file##*/}
    id=${id%.json}
    loom_exclude "$workdir" "$host"
    loom_take_evidence "$workdir" "$id" "$host"
    # The consumer's commit hooks run (they are its quality gate). Auto-fixers
    # rewrite files and fail the first commit by design, so loom re-stages and
    # retries once, as a person would; a second failure is logged (gap #22).
    if [[ -n $(loom_ws "$host" "$workdir" git status --porcelain 2>/dev/null) ]]; then
        local clog="$LOOM_STATE/$id.commit.log" try
        : > "$clog"
        for try in 1 2; do
            if { loom_ws "$host" "$workdir" git add -A &&
                 loom_ws "$host" "$workdir" git -c commit.gpgsign=false commit -q -m "loom($id): $state — $fact"; } >> "$clog" 2>&1; then
                loom_write "$file" 'del(.seal_failed)'
                break
            fi
            if [[ $try == 2 ]]; then
                state=failed
                loom_write "$file" ' .seal_failed = true '
                fact="$fact [loom commit rejected by the consumer's hooks: ${clog##*/}]"
            fi
        done
    fi
    # Persist the consumed boundary for the next authorized continuation.
    local report_lines
    report_lines=$(loom_report_text "$file" "$host" | awk 'END {print NR+0}') || loom_error 'cannot record consumed report boundary'
    # shellcheck disable=SC2016
    loom_write "$file" '.report_offset = $n | .harvest_report_lines = $n' --argjson n "$report_lines"
    loom_append "$file" "$state" "$fact" true
    printf '%s\n' "$state"
}

# Parse a consumer registration; never execute it. Strings use JSON-compatible
# TOML escapes; comments are stripped only outside quoted strings. Prints JSON.
loom_config() {
    [[ -f $1 ]] || loom_error 'consumer config not found'
    if [[ $(LC_ALL=C sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/\(.\).*/\1/;p;q;}' "$1") == '{' ]]; then
        # Schema 2 is JSON; never reinterpret it as legacy TOML or auto placement.
        # shellcheck source=ops/policy.sh
        source "${BASH_SOURCE[0]%/*}/policy.sh"
        loom_policy_validate config "$(realpath -e "$1")" || loom_error 'invalid schema-2 config'
        cat "$1"
        return
    fi
    jq -Rse '
  def fields:
    if test("^\\s*$") then {}
    else capture("^\\s*(?<key>[a-z_]+)\\s*=\\s*(?<value>\"(?:[^\"\\\\]|\\\\.)*\"|\\[(?:[^]\\\"\\\\]|\"(?:[^\"\\\\]|\\\\.)*\")*\\]|[0-9]+)(?<rest>[\\s\\S]*)$") as $m |
      ($m.rest | fields) as $rest |
      if $rest | has($m.key) then error("duplicate config key")
      else $rest + {($m.key): ($m.value | sub(",\\s*]$"; "]") | fromjson)} end
    end;
  [scan("\"(?:[^\"\\\\]|\\\\.)*\"|#[^\n]*|[^\"#]+") |
    select(startswith("#") | not)] | join("") | fields |
  if (.repo | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
     (.worktrees | type == "string" and length > 0) and
     (.laws | type == "array" and all(.[]; type == "string")) and
     ((has("limit_min") | not) or (.limit_min | type == "number" and . > 0 and . == floor)) and
     ((has("executor") | not) or (.executor | IN("auto", "local", "orca"))) and
     ((has("compute") | not) or (.compute | (type == "string" and length > 0) or (type == "array" and length > 0 and all(.[]; type == "string" and length > 0)))) and
     ((has("compute_setup") | not) or (.compute_setup | type == "string")) and
     ((has("compute_selector") | not) or (.compute_selector | type == "string" and startswith("--") and (test("\n") | not))) and
     ((has("model") | not) or (.model | type == "string" and (test("[\\s]") | not))) and
     ((has("effort") | not) or (.effort | type == "string" and (test("[\\s]") | not))) and
     ((has("start_timeout_ms") | not) or (.start_timeout_ms | type == "number" and . > 0 and . == floor)) and
     ((has("workers") | not) or (.workers | type == "number" and . > 0 and . == floor)) and
     ((has("agent") | not) or (.agent | type == "string" and test("^[a-z0-9-]+$"))) and
     ((keys - ["repo", "checks", "worktrees", "laws", "limit_min", "executor", "compute", "compute_setup", "compute_selector", "model", "effort", "start_timeout_ms", "workers", "agent"]) | length == 0)
  then . else error("invalid consumer config") end
' "$1" || loom_error 'unsupported or invalid consumer TOML; see ops/README.md'
}

# The Mandate block of an issue body (stdin -> stdout). One parser for dispatch
# and ticket.sh, so a rendered ticket is exactly what dispatch accepts.
loom_mandate() {
    jq -Rser 'capture("(?ms)^## Mandate[ \\t]*\\r?\\n(?<text>.*?)(?=^## |\\z)") | "## Mandate\n" + .text' || loom_error 'issue has no Mandate block'
}

loom_short() {  # loom_short <mandate>
    jq -ner --arg mandate "$1" '$mandate | capture("(?m)^\\*\\*Ticket short name:\\*\\*[ \\t]*(?<name>[a-z0-9]+(?:-[a-z0-9]+)*)[ \\t]*(?:<!--[^\\n]*-->)?\\r?$").name' || loom_error 'missing or invalid ticket short name'
}

# --- executors (gaps #25, #26) ------------------------------------------------
# Owner, 2026-11-07: workers "only start or stop through orcacli". Loom detects
# the Orca CLI rather than assuming it. LOOM_ORCA names the binary (tests stub it).
loom_orca() { "${LOOM_ORCA:-orca}" "$@"; }

# Ready = the CLI exists and its runtime is reachable and ready. Prints the
# runtime id on success.
loom_orca_ready() {
    local out
    command -v "${LOOM_ORCA:-orca}" >/dev/null 2>&1 || return 1
    out=$(loom_orca status 2>/dev/null) || return 1
    grep -q '^runtimeReachable: true$' <<< "$out" || return 1
    grep -q '^runtimeState: ready$' <<< "$out" || return 1
    sed -n 's/^runtimeId: //p' <<< "$out" | head -n 1
}

loom_executor() {  # loom_executor <record>: local | orca
    jq -r '.executor.kind // "local"' "$1"
}

# An Orca worker is live while loom has recorded it running; Orca, not loom,
# supervises the process.
loom_orca_running() {
    jq -e '.executor.kind == "orca" and (.executor.state == "running" or .executor.state == "starting" or .executor.continuation_pending == true)' "$1" >/dev/null
}

# --- compute hosts (gap #36) --------------------------------------------------
# Owner, 2026-11-07: "why are you doing it here instead of the build host ??". Checks
# run on the consumer's compute host, never silently on the conductor's
# machine. LOOM_SSH names the ssh binary (tests stub it).
loom_ssh() { "${LOOM_SSH:-ssh}" -o BatchMode=yes -o ConnectTimeout=5 "$@"; }

loom_compute_pick() {  # loom_compute_pick <host>...: first reachable host
    local h
    for h in "$@"; do
        if loom_ssh "$h" true >/dev/null 2>&1; then
            printf '%s' "$h"
            return 0
        fi
    done
    return 1
}

# An assignment still occupying a worker slot: live, or dispatched and not yet
# settled (an Orca pending record).
loom_open() {  # loom_open <file>
    if jq -e '.executor.kind == "orca"' "$1" >/dev/null; then
        jq -e '.executor.continuation_pending == true or (.executor.state | IN("pending", "starting", "running"))' "$1" >/dev/null
    else
        loom_alive "$1" || [[ $(jq -r '.reports | length' "$1") == 0 ]]
    fi
}

# Resolve a host name/id in Orca's host list. Prints "<name>\t<selector>" when
# the host exists and is connected; returns 1 when missing, 2 when disconnected.
loom_orca_host() {  # loom_orca_host <name-or-id>
    local want=$1 out
    out=$(loom_orca host list --json 2>/dev/null) || return 1
    jq -e --arg w "$want" '[.result.hosts[] | select(.id == $w or .name == $w)] | length > 0'         <<< "$out" >/dev/null 2>&1 || return 1
    jq -e --arg w "$want" '
      [.result.hosts[] | select(.id == $w or .name == $w) | select(.connected == true or .kind == "local")] | length > 0
    ' <<< "$out" >/dev/null 2>&1 || return 2
    # A name can appear twice (an ssh target and an environment); take the connected one.
    jq -r --arg w "$want" '
      [.result.hosts[] | select(.id == $w or .name == $w) | select(.connected == true or .kind == "local")][0] | [.name, (.selector // "--host \(.id)")] | @tsv
    ' <<< "$out"
}

# Older routing cannot ignore a v2 authority and allocate a second capacity pool.
# Existing legacy observations/stop/harvest remain available without migration.
loom_legacy_dispatch_fence() {
    [[ ! -d ${LOOM_STATE:-$HOME/.loom}/v2 ]] || loom_error 'v2 authority present; legacy dispatch/launch refused; use an explicit native context'
}

# Dispatch reserves pending tickets; launch/start recheck under the same lock
# so records created by older clients cannot produce simultaneous siblings.
loom_no_open_sibling() {  # <record>; caller holds the state lock
    local file=$1 sibling repo ticket
    repo=$(jq -r '.repo' "$file")
    ticket=$(jq -r '.ticket' "$file")
    for sibling in "$LOOM_STATE"/*.json; do
        [[ -f $sibling && $sibling != "$file" ]] || continue
        loom_validate "$sibling"
        if jq -e --arg repo "$repo" --argjson ticket "$ticket" '.repo == $repo and .ticket == $ticket' "$sibling" >/dev/null &&
            loom_open "$sibling"; then
            loom_error "ticket already has an open assignment: ${sibling##*/}"
        fi
    done
}
