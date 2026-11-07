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
      ((has("config_commit") | not) or .config_commit == null or (.config_commit | type == "string" and test("^[0-9a-f]{40}$"))) and
      ((has("checks") | not) or .checks == null or (.checks | type == "string")) and
      ((has("checks_runs") | not) or (.checks_runs | type == "array" and
          all(.[]; (.kind == "baseline" or .kind == "branch") and (.sha | type == "string") and
              (.exit | type == "number") and (.at | iso)))) and
      ((has("limit_min") | not) or .limit_min == null or (.limit_min | type == "number" and . > 0)) and
      ((has("report_offset") | not) or (.report_offset | type == "number" and . >= 0)) and
      ((has("collected_sha") | not) or (.collected_sha | type == "string" and test("^[0-9a-f]{40}$"))) and
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

loom_alive() {  # loom_alive <file>: the recorded worker is live (local process or Orca worker)
    local pid start now
    if jq -e '.executor.kind == "orca"' "$1" >/dev/null; then
        loom_orca_running "$1"
        return
    fi
    pid=$(jq -r '.worker_pid // empty' "$1")
    [[ -n $pid ]] || return 1
    start=$(jq -r '.worker_start // empty' "$1")
    now=$(loom_pstart "$pid") || return 1
    [[ $now == "$start" ]]
}

# Keep loom's own files out of the consumer commit. .loom/ is the worker's
# evidence directory (gap #33): copied into state, never committed.
loom_exclude() {  # loom_exclude <workdir>
    local workdir=$1 common f
    [[ -d $workdir ]] || return 0
    common=$(git -C "$workdir" rev-parse --git-common-dir 2>/dev/null) || return 0
    [[ $common == /* ]] || common="$workdir/$common"
    mkdir -p "$common/info"
    for f in WORK.md REPORT.md .loom/; do
        grep -qxF "$f" "$common/info/exclude" 2>/dev/null || printf '%s\n' "$f" >> "$common/info/exclude"
    done
}

# Copy .loom/ to $LOOM_STATE/<id>.evidence before the commit. A symlink is
# refused: evidence must not walk out of the workdir.
loom_take_evidence() {  # loom_take_evidence <workdir> <id>
    local src="$1/.loom" dest="$LOOM_STATE/$2.evidence"
    [[ -e $src || -L $src ]] || return 0
    [[ -d $src && ! -L $src ]] || loom_error "evidence path is not a directory: $src"
    rm -rf "$dest"
    cp -R "$src" "$dest"
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
    loom_exclude "$workdir"
    loom_take_evidence "$workdir" "$id"
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
     ((has("executor") | not) or (.executor | IN("auto", "local", "orca"))) and
     ((has("compute") | not) or (.compute | (type == "string" and length > 0) or (type == "array" and length > 0 and all(.[]; type == "string" and length > 0)))) and
     ((has("compute_setup") | not) or (.compute_setup | type == "string")) and
     ((has("compute_selector") | not) or (.compute_selector | type == "string" and startswith("--") and (test("\n") | not))) and
     ((has("model") | not) or (.model | type == "string" and (test("[\\s]") | not))) and
     ((has("effort") | not) or (.effort | type == "string" and (test("[\\s]") | not))) and
     ((has("start_timeout_ms") | not) or (.start_timeout_ms | type == "number" and . > 0 and . == floor)) and
     ((keys - ["repo", "checks", "worktrees", "laws", "limit_min", "executor", "compute", "compute_setup", "compute_selector", "model", "effort", "start_timeout_ms"]) | length == 0)
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
    jq -e '.executor.kind == "orca" and (.executor.state == "running" or .executor.state == "starting")' "$1" >/dev/null
}

# --- compute hosts (gap #36) --------------------------------------------------
# Owner, 2026-11-07: "why are you doing it here instead of build1 ??". Checks
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
