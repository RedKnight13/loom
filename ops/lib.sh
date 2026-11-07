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

# A mkdir lock that records its owner. A lock whose owner is dead is broken;
# a live owner is waited on for LOOM_LOCK_WAIT seconds (default 10).
loom_lock() {
    local tries=0 max owner
    max=$(( ${LOOM_LOCK_WAIT:-10} * 5 ))
    until mkdir "$LOOM_STATE/.lock" 2>/dev/null; do
        owner=$(cat "$LOOM_STATE/.lock/owner" 2>/dev/null || :)
        if [[ -n $owner ]] && ! kill -0 "$owner" 2>/dev/null; then
            rm -f "$LOOM_STATE/.lock/owner"
            rmdir "$LOOM_STATE/.lock" 2>/dev/null || :
            continue
        fi
        (( tries++ < max )) || loom_error 'state is locked; retry after the active operation finishes'
        sleep 0.2
    done
    printf '%s\n' "$$" > "$LOOM_STATE/.lock/owner"
    trap loom_unlock EXIT
}

loom_unlock() {
    rm -f "$LOOM_STATE/.pending" "$LOOM_STATE/.lock/owner"
    rmdir "$LOOM_STATE/.lock" 2>/dev/null || :
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
      (.started_at | iso) and
      ((has("launched_at") | not) or (.launched_at | iso)) and
      ((has("config_commit") | not) or .config_commit == null or (.config_commit | type == "string" and test("^[0-9a-f]{40}$"))) and
      ((has("checks") | not) or .checks == null or (.checks | type == "string")) and
      ((has("checks_runs") | not) or (.checks_runs | type == "array" and
          all(.[]; (.kind == "baseline" or .kind == "branch") and (.sha | type == "string") and
              (.exit | type == "number") and (.at | iso)))) and
      ((has("limit_min") | not) or .limit_min == null or (.limit_min | type == "number" and . > 0)) and
      ((has("report_offset") | not) or (.report_offset | type == "number" and . >= 0)) and
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

loom_alive() {  # loom_alive <file>: the recorded worker is this exact live process
    local pid start now
    pid=$(jq -r '.worker_pid // empty' "$1")
    [[ -n $pid ]] || return 1
    start=$(jq -r '.worker_start // empty' "$1")
    now=$(loom_pstart "$pid") || return 1
    [[ $now == "$start" ]]
}

# Fold the newest state line written since launch into the record and clear the
# worker. Accepted line: "state: <ready|blocked|failed|waiting> — <fact>"
# (separator may be —, --, - or :).
loom_harvest() {  # loom_harvest <file> <why-if-silent>
    local file=$1 silent=$2 workdir offset line state fact
    local re='^state:[[:space:]]*(ready|blocked|failed|waiting)[[:space:]]*(—|--|-|:)?[[:space:]]*(.*)$'
    workdir=$(jq -r '.workdir' "$file")
    offset=$(jq -r '.report_offset // 0' "$file")
    line=
    if [[ -f $workdir/REPORT.md && ! -L $workdir/REPORT.md ]]; then
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
    # The consumer's commit hooks run (they are its quality gate). Auto-fixers
    # rewrite files and fail the first commit by design, so loom re-stages and
    # retries once, as a person would; a second failure is logged (gap #22).
    if [[ -n $(git -C "$workdir" status --porcelain 2>/dev/null) ]]; then
        local clog="$LOOM_STATE/$id.commit.log" try
        : > "$clog"
        for try in 1 2; do
            if { git -C "$workdir" add -A &&
                 git -C "$workdir" -c commit.gpgsign=false commit -q -m "loom($id): $state — $fact"; } >> "$clog" 2>&1; then
                break
            fi
            if [[ $try == 2 ]]; then
                fact="$fact [loom commit rejected by the consumer's hooks: ${clog##*/}]"
            fi
        done
    fi
    loom_append "$file" "$state" "$fact" true
    printf '%s\n' "$state"
}

# Parse a consumer registration; never execute it. Strings use JSON-compatible
# TOML escapes; comments are stripped only outside quoted strings. Prints JSON.
loom_config() {
    [[ -f $1 ]] || loom_error 'consumer config not found'
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
     ((keys - ["repo", "checks", "worktrees", "laws", "limit_min"]) | length == 0)
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
