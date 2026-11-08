#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2154,SC2088
# Subshell isolation and caller-owned envelope variables are intentional.
# Sourced by loom: its emit function owns the sole public JSON envelope.
# Digests detect accidental drift; they are not signatures or authenticity proof.

# GIT_DIR disables repository discovery; explicit environment/config isolation
# keeps hashes SHA-1 even inside SHA-256 repositories or with Git overrides.
cal_hash() (
    unset GIT_CONFIG_PARAMETERS GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    export GIT_DIR=/dev/null GIT_DEFAULT_HASH=sha1 GIT_CONFIG_COUNT=0
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    git hash-object --stdin
)
cal_file_hash() { cal_hash < "$1"; }
cal_json_hash() { jq -Sc . | cal_hash; }
cal_finish() {
    local readiness=$1 fact=$2 state=${3:-blocked} ok=false
    [[ $readiness != ready ]] || { state=ready; ok=true; }
    items=$(jq -nc --arg mode "$mode" --arg readiness "$readiness" \
        --argjson fingerprint "$fingerprint" --argjson stages "$stages" --argjson drift "$drift" \
        '[{schema:1,mode:$mode,readiness:$readiness,fingerprint:$fingerprint,
           stages:$stages,drift:$drift,acceptance:"not_run"}]')
    emit "$ok" "$state" "$fact" '' '' "$items" \
        '["Review the reported wiring or drift before explicitly recording calibration.","Project acceptance and real agent execution remain not run."]'
}
cal_stage() {
    local stage=$1
    case $stage in
        consumer|checkout) stage=configuration ;;
        bridge) stage=instructions ;;
        environment|evidence) stage=installation ;;
        executor) stage=connectivity ;;
    esac
    stages=$(jq -c --arg name "$stage" --arg status "$2" '.[$name]=$status' <<< "$stages")
}
cal_refuse() { cal_stage "$1" failed; cal_finish incomplete "$2" "${3:-blocked}"; }
cal_unwired() { cal_stage "$1" failed; cal_finish unwired "$2"; }
# Bound only the exact child launched here; the watchdog is always reaped.
cal_bounded() (
    local seconds=$1 child timer rc=0
    shift
    "$@" & child=$!
    (
        sleep "$seconds" & sleeper=$!
        trap 'kill "$sleeper" 2>/dev/null || :; wait "$sleeper" 2>/dev/null || :; exit' TERM
        wait "$sleeper"
        kill -KILL "$child" 2>/dev/null || :
    ) >/dev/null 2>&1 & timer=$!
    wait "$child" || rc=$?
    kill "$timer" 2>/dev/null || :
    wait "$timer" 2>/dev/null || :
    exit "$rc"
)
# Bash 3.2 unwinds function locals before EXIT traps; keep only owned cleanup
# paths in globals, and never resolve cleanup targets from consumer data.
cal_cleanup() {
    [[ -z ${cal_cleanup_dir:-} ]] || rm -rf -- "$cal_cleanup_dir"
    [[ -z ${cal_cleanup_temp:-} ]] || rm -f -- "$cal_cleanup_temp"
    [[ -z ${cal_cleanup_lock:-} ]] || rmdir -- "$cal_cleanup_lock" 2>/dev/null || :
}
cal_private() {
    local mode
    [[ -O $1 ]] || return 1
    mode=$(stat -f '%Lp' "$1" 2>/dev/null) || mode=$(stat -c '%a' "$1" 2>/dev/null) || return 1
    [[ $mode == "$2" ]]
}

# Reject symlinks in every existing component, including the state root.
cal_no_links() {
    local p=$1
    while [[ $p != / && $p != . && -n $p ]]; do
        [[ ! -L $p ]] || return 1
        [[ $p == "$1" || ! -e $p || -d $p ]] || return 1
        if [[ $p == */* ]]; then p=${p%/*}; else p=.; fi
    done
}

# A fixed offline fixture, isolated from consumer configuration and git hooks.
# No model invocation, remote access, consumer checks or setup commands.
cal_drill() (
    set -euo pipefail
    local d=$1 tool resolved
    mkdir -p "$d/bin"
    for tool in bash git jq awk mkdir rm cp mv cat grep sed tr head tail date wc dirname basename mktemp chmod rmdir; do
        resolved=$(command -v "$tool")
        ln -s "$resolved" "$d/bin/$tool"
    done
    export PATH="$d/bin" TMPDIR="$d"
    export HOME="$d/home" XDG_CONFIG_HOME="$d/home/config"
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=0 GIT_DEFAULT_HASH=sha1
    export GIT_CONFIG_SYSTEM=/dev/null GIT_TEMPLATE_DIR="$d/templates"
    mkdir "$d/templates"
    unset GIT_CONFIG_PARAMETERS
    unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
    export LOOM_STATE="$d/state" LOOM_ORCA="$d/no-orca" LOOM_REPO="$d/source"
    mkdir -p "$HOME" "$LOOM_STATE" "$d/source"
    git -C "$d/source" -c init.defaultObjectFormat=sha1 init -q
    git -C "$d/source" -c core.hooksPath=/dev/null -c user.name=Fixture \
        -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m fixture
    git -c core.hooksPath=/dev/null clone -q --no-hardlinks "$d/source" "$d/worker"
    git -C "$d/worker" checkout -q -b drill
    git -C "$d/worker" remote remove origin
    [[ -z $(git -C "$d/worker" remote) ]]
    local sha obj state expected
    sha=$(git -C "$d/source" rev-parse HEAD)
    jq -n --arg w "$d/worker" --arg c "$d/source" --arg sha "$sha" \
        '{ticket:1,repo:"fixture/offline",short_name:"drill",attempt:1,workdir:$w,
          checkout:$c,base_sha:$sha,worker_pid:null,worker_start:null,
          started_at:(now|todateiso8601),reports:[],checks:"true",report_offset:0}' > "$LOOM_STATE/drill.1.json"
    mkdir "$d/worker/.loom"
    printf 'offline evidence\n' > "$d/worker/.loom/drill.txt"
    printf 'state: ready — fixed offline drill\n' > "$d/worker/REPORT.md"
    loom_harvest "$LOOM_STATE/drill.1.json" 'missing fixture report' >/dev/null
    loom_validate "$LOOM_STATE/drill.1.json"
    jq -e '.reports[-1].state == "ready"' "$LOOM_STATE/drill.1.json" >/dev/null
    [[ -f $LOOM_STATE/drill.1.evidence/drill.txt ]]
    bash "$ops/verify.sh" drill.1 >/dev/null
    jq -e '.checks_runs[-1].exit == 0' "$LOOM_STATE/drill.1.json" >/dev/null
    obj=$(bash "$ops/loom" status)
    jq -e '.ok and .state == "ready"' <<< "$obj" >/dev/null
    for state in blocked missing; do
        if [[ $state == blocked ]]; then
            printf 'state: blocked — fixed blocker\n' >> "$d/worker/REPORT.md"
            expected=blocked
        else
            rm "$d/worker/REPORT.md"
            expected=failed
        fi
        loom_harvest "$LOOM_STATE/drill.1.json" 'missing fixture report' >/dev/null
        obj=$(bash "$ops/loom" status)
        jq -e --arg expected "$expected" '.state == $expected' <<< "$obj" >/dev/null
    done
)

cal_observe() {
    for name in "$root/VERSION" "$ops/loom" "$ops"/*.sh; do
        if ! cal_no_links "$name" || [[ ! -f $name || ! -r $name || $name == *[[:cntrl:]]* ]]; then
            cal_refuse environment 'Loom sources must be readable regular files without symlinks.' failed
        fi
    done
    command -v git >/dev/null 2>&1 || cal_unwired environment 'Install git before calibration.'
    [[ $consumer != *[[:cntrl:]]* ]] || cal_refuse consumer 'Consumer path contains control characters.' failed
    if ! cal_no_links "$consumer" || [[ ! -f $consumer || ! -r $consumer ]]; then
        cal_refuse consumer 'Consumer config must be a readable regular file without symlink ancestors.' failed
    fi
    # shellcheck disable=SC2317,SC2329  # loom_config invokes this subshell-only override
    config=$(loom_error() { exit 1; }; loom_config "$consumer" 2>/dev/null) || cal_refuse consumer 'Repair the consumer config before calibration.'
    jq -e '.checks | type == "string" and length > 0' <<< "$config" >/dev/null || cal_refuse consumer 'Consumer checks must be a nonempty string; calibration does not execute them.'
    cpath=$(cd "$(dirname "$consumer")" && printf '%s/%s' "$(pwd -P)" "$(basename "$consumer")")
    checkout=$(git -C "${LOOM_REPO:-.}" rev-parse --show-toplevel 2>/dev/null) || cal_refuse checkout 'Run in the consumer checkout or set LOOM_REPO.'
    checkout=$(cd "$checkout" && pwd -P)
    [[ $checkout != *[[:cntrl:]]* ]] || cal_refuse checkout 'Checkout path contains control characters.' failed
    common=$(git -C "$checkout" rev-parse --git-common-dir 2>/dev/null) || cal_refuse checkout 'Cannot resolve checkout Git metadata.'
    [[ $common == /* ]] || common=$checkout/$common
    common=$(cd "$common" && pwd -P)
    [[ $common != *[[:cntrl:]]* ]] || cal_refuse checkout 'Git metadata path contains control characters.' failed
    jq -e '(.compute // []) | if type == "string" then [.] else . end |
        all(.[]; test("\\A[A-Za-z0-9][A-Za-z0-9._-]*\\z"))' <<< "$config" >/dev/null ||
        cal_refuse consumer 'Consumer compute hosts must be safe SSH host names.'

    git -C "$checkout" rev-parse --verify 'HEAD^{commit}' >/dev/null 2>&1 || cal_refuse checkout 'The consumer checkout needs a commit.'
    origin=$(git -C "$checkout" remote get-url origin 2>/dev/null || :)
    repo=$(jq -r '.repo' <<< "$config")
    slug=$(printf '%s' "$origin" | sed -E 's#^(git@|ssh://git@|https?://|git://)##; s#^[^/:]+[:/]##; s#\.git$##; s#/$##' | tr '[:upper:]' '[:lower:]')
    want=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
    [[ ${LOOM_ALLOW_ANY_CHECKOUT:-0} == 1 || ( -n $origin && $slug == "$want" ) ]] || cal_refuse checkout 'Checkout origin does not match consumer repo; repair the wiring.'
    worktrees=$(jq -r '.worktrees' <<< "$config")
    [[ $worktrees == /* || $worktrees == '~/'* ]] || cal_refuse consumer 'Consumer worktrees must be absolute or start with ~/.'
    if git -C "$(dirname "$cpath")" ls-files --error-unmatch -- "$(basename "$cpath")" >/dev/null 2>&1; then
        [[ -z $(GIT_OPTIONAL_LOCKS=0 git -C "$(dirname "$cpath")" status --porcelain -- "$(basename "$cpath")") ]] || cal_refuse consumer 'Commit reviewed consumer changes before calibration.'
    fi
    cal_stage consumer passed
    cal_stage checkout passed
    bridge='[]'
    marker=false
    for name in AGENTS.md CLAUDE.md; do
        value=null
        if [[ -e $checkout/$name || -L $checkout/$name ]]; then
            [[ -f $checkout/$name && -r $checkout/$name && ! -L $checkout/$name ]] || cal_refuse bridge 'Instruction bridges must be readable regular files without symlinks.' failed
            value=$(cal_file_hash "$checkout/$name" | jq -R .)
            if grep -qF 'loom-calibration:v1' "$checkout/$name"; then marker=true; fi
        fi
        bridge=$(jq -c --arg name "$name" --argjson value "$value" '. + [[$name,$value]]' <<< "$bridge")
    done
    $marker || cal_refuse bridge 'Add the reviewed loom-calibration:v1 instruction bridge before calibration.'
    cal_stage bridge passed
    tools_json='{}'
    for tool in bash git jq gh; do
        resolved=$(command -v "$tool" 2>/dev/null || :)
        [[ -n $resolved ]] || cal_unwired environment 'A required tool is unavailable; install bash, git, jq and gh.'
        [[ -f $resolved && -x $resolved ]] || cal_refuse environment 'Required tool must resolve to an executable file.'
        digest=$(jq -nc --arg path "$resolved" --arg bytes "$(cal_file_hash "$resolved")" '[$path,$bytes]' | cal_json_hash)
        tools_json=$(jq -c --arg name "$tool" --arg digest "$digest" '. + {($name):$digest}' <<< "$tools_json")
    done
    resolved=$(command -v "${LOOM_ORCA:-orca}" 2>/dev/null || :)
    digest=absent
    if [[ -n $resolved && -f $resolved && -x $resolved ]]; then
        digest=$(jq -nc --arg path "$resolved" --arg bytes "$(cal_file_hash "$resolved")" '[$path,$bytes]' | cal_json_hash)
    fi
    tools_json=$(jq -c --arg digest "$digest" '. + {orca:$digest}' <<< "$tools_json")
    # Exercise safe local capabilities rather than equating PATH presence with proof.
    BASH_ENV=/dev/null bash -c '[[ ${BASH_VERSINFO[0]} -gt 3 || ( ${BASH_VERSINFO[0]} -eq 3 && ${BASH_VERSINFO[1]} -ge 2 ) ]]' || cal_refuse environment 'Bash 3.2 or newer is required.'
    jq -ne '([1]|any(. == 1)) and ("2020-01-01T00:00:00Z"|fromdateiso8601 > 0)' >/dev/null || cal_refuse environment 'A compatible jq is required.'
    policy=$(jq -r '.executor // "auto"' <<< "$config")
    availability=not_probed
    if [[ $policy != local ]]; then
        availability=unavailable
        if probe=$(cal_bounded 5 "${LOOM_ORCA:-orca}" status 2>/dev/null); then
            if grep -qx 'runtimeReachable: true' <<< "$probe" && grep -qx 'runtimeState: ready' <<< "$probe" &&
                grep -q '^runtimeId: .' <<< "$probe"; then
                availability=runtime_ready
            fi
        fi
    fi
    [[ $policy != orca || $availability == runtime_ready ]] || cal_unwired executor 'Required Orca runtime is unavailable; inspect orca status.'
    executor=local
    [[ $availability != runtime_ready ]] || executor=orca
    cal_stage environment passed
    cal_stage executor passed
    code='[]'
    for name in "$root/VERSION" "$ops/loom" "$ops"/*.sh; do
        if ! cal_no_links "$name" || [[ ! -f $name || ! -r $name || $name == *[[:cntrl:]]* ]]; then
            cal_refuse environment 'Loom sources must be readable regular files without symlinks.' failed
        fi
        digest=$(cal_file_hash "$name")
        code=$(jq -c --arg name "${name#"$root/"}" --arg digest "$digest" '. + [[$name,$digest]]' <<< "$code")
    done
    code=$(jq -c 'sort_by(.[0])' <<< "$code" | cal_json_hash)
    value=$(tr -d '[:space:]' < "$root/VERSION")
    [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || cal_refuse environment 'Loom version must be a release version.' failed
    fingerprint=$(jq -nc --arg loom_version "$value" --arg loom_code "$code" \
        --arg consumer "$(cal_file_hash "$cpath")" \
        --arg checkout "$(jq -nc --arg root "$checkout" --arg common "$common" --arg origin "$origin" --arg override "${LOOM_ALLOW_ANY_CHECKOUT:-0}" '[$root,$common,$origin,$override]' | cal_json_hash)" \
        --arg bridge "$(printf '%s\n' "$bridge" | cal_json_hash)" \
        --arg tools "$(jq -nc --argjson tools "$tools_json" --arg orca "${LOOM_ORCA:-orca}" --arg availability "$availability" '[$tools,$orca,$availability]' | cal_json_hash)" \
        --arg executor "$executor" \
        '{algorithm:"git-blob-sha1-v1",loom_version:$loom_version,loom_code:$loom_code,consumer:$consumer,
          checkout:$checkout,bridge:$bridge,tools:$tools,executor:$executor}')
    key=$(jq -nc --arg c "$cpath" --arg r "$checkout" '[$c,$r]' | cal_json_hash)
    [[ $key =~ ^[0-9a-f]{40}$ ]] || cal_refuse evidence 'Cannot derive a valid calibration record key.' failed
}

# Compare a second complete observation with the one used for this operation.
# The check is deliberately bounded to observable changes, not hostile races.
cal_reobserve() {
    local before=$fingerprint
    cal_observe
    drift=$(jq -nc --argjson old "$before" --argjson current "$fingerprint" \
        '[$current | keys[] as $k | select(.[$k] != $old[$k]) | $k]')
    [[ $drift == '[]' ]] || cal_finish drifted 'Calibration inputs changed during observation; review the named fields and retry.'
}

cal_valid_record() {
    jq -se 'length == 1 and (.[0] | type == "object" and
          (keys == ["acceptance","fingerprint","recorded_at","schema","stages"]) and .schema == 1 and .acceptance == "not_run" and
          (.recorded_at | type == "string" and (fromdateiso8601 | type == "number")) and
          (.fingerprint | type == "object" and (keys == ["algorithm","bridge","checkout","consumer","executor","loom_code","loom_version","tools"]) and .algorithm == "git-blob-sha1-v1" and
            (.loom_version | type == "string") and (.executor | IN("local","orca")) and
            ([.loom_code,.consumer,.checkout,.bridge,.tools] | all(.[]; type == "string" and test("^[0-9a-f]{40}$")))) and
          (.stages | type == "object" and
            keys == ["configuration","connectivity","drill","installation","instructions"] and
            all(.[]; . == "passed")))' >/dev/null 2>&1
}

loom_calibrate() {
    local consumer='' mode=record fingerprint=null stages='{"installation":"not_run","configuration":"not_run","connectivity":"not_run","instructions":"not_run","drill":"not_run"}'  drift='[]' items
    local config checkout cpath key state_dir proof origin repo want slug worktrees policy executor
    local code bridge tools_json tool resolved availability digest marker=false name value old
    local temp='' drill_dir='' recorded common probe
    export LC_ALL=C GIT_OPTIONAL_LOCKS=0
    trap 'cal_finish incomplete "Calibration observation failed; repair the local toolchain or storage and retry." failed' ERR
    while [[ $# -gt 0 ]]; do
        case $1 in
            --consumer)
                [[ $# -ge 2 && -n $2 && -z $consumer ]] || emit false failed "$usage" '' '' '[]' '[]' 2
                consumer=$2; shift 2 ;;
            --check)
                [[ $mode != check ]] || emit false failed "$usage" '' '' '[]' '[]' 2
                mode=check; shift ;;
            *) emit false failed "$usage" '' '' '[]' '[]' 2 ;;
        esac
    done
    [[ -n $consumer ]] || emit false failed "$usage" '' '' '[]' '[]' 2
    cal_observe
    state_dir=${LOOM_STATE:-$HOME/.loom}
    [[ $state_dir == /* ]] || state_dir=$(pwd -P)/$state_dir
    state_dir=${state_dir%/}/calibration
    [[ $state_dir != *'/../'* && $state_dir != *'/./'* && $state_dir != *[[:cntrl:]]* ]] || cal_refuse evidence 'Use a calibration state path without traversal or control characters.' failed
    proof=$state_dir/$key.json
    cal_no_links "$proof" || cal_refuse evidence 'Calibration state contains a symlink or nondirectory ancestor; choose private directory storage.' failed
    if [[ -e $state_dir ]]; then
        [[ -d $state_dir ]] || cal_refuse evidence 'Calibration storage must be a directory.' failed
        cal_private "$state_dir" 700 || cal_refuse evidence 'Calibration storage must be owned by the current user with mode 700.' failed
    fi
    if [[ -e ${state_dir%/*} ]]; then
        [[ -d ${state_dir%/*} ]] || cal_refuse evidence 'Loom state must be a directory.' failed
        cal_private "${state_dir%/*}" 700 || cal_refuse evidence 'Loom state must be owned by the current user with mode 700.' failed
    fi
    if [[ -e $proof ]]; then
        [[ -f $proof ]] || cal_refuse evidence 'Calibration proof must be a regular file.' failed
        cal_private "$proof" 600 || cal_refuse evidence 'Calibration proof must be a private regular file with mode 600.' failed
    fi
    if [[ $mode == check ]]; then
        [[ -f $proof ]] || cal_refuse evidence 'Calibration proof is missing; review wiring and run calibrate without --check.'
        recorded=$(head -c 65537 "$proof"; printf '.')
        recorded=${recorded%.}
        [[ $(printf '%s' "$recorded" | wc -c) -le 65536 ]] || cal_refuse evidence 'Calibration proof exceeds the schema size limit; review and recalibrate.' failed
        cal_valid_record <<< "$recorded" || cal_refuse evidence 'Calibration proof is corrupt or incompatible; review and explicitly recalibrate.' failed
        old=$(jq -c '.fingerprint' <<< "$recorded")
        drift=$(jq -nc --argjson old "$old" --argjson current "$fingerprint" \
            '[$current | keys[] as $k | select(.[$k] != $old[$k]) | $k]')
        [[ $drift == '[]' ]] || cal_finish drifted 'Calibration wiring changed; review the named fingerprint fields before recalibrating.'
        stages=$(jq -c '.stages' <<< "$recorded")
        cal_reobserve
        cal_finish ready 'Recorded offline drill and current wiring match; real agent execution and project acceptance are not run.'
    fi
    umask 077
    mkdir -p "$state_dir" || cal_refuse evidence 'Cannot create private calibration storage.'
    mkdir "$state_dir/.record-lock" 2>/dev/null || cal_refuse evidence 'Calibration recording is locked; wait for the active record or review a stale lock.'
    cal_cleanup_dir='' cal_cleanup_temp=''
    cal_cleanup_lock=$state_dir/.record-lock
    trap cal_cleanup EXIT
    drill_dir=$(mktemp -d "$state_dir/.drill.XXXXXX") || cal_refuse drill 'Cannot create isolated offline drill.'
    cal_cleanup_dir=$drill_dir
    export -f cal_drill
    # shellcheck disable=SC2016  # expands only in the isolated child
    if ! BASH_ENV=/dev/null ENV=/dev/null cal_bounded 15 bash -e -c 'ops=$1; source "$ops/lib.sh"; cal_drill "$2"' _ "$ops" "$drill_dir" >/dev/null 2>&1; then
        cal_refuse drill 'The fixed offline workflow drill failed; inspect Loom installation and rerun calibration.'
    fi
    cal_stage drill passed
    cal_stage evidence passed
    temp=$(mktemp "$state_dir/.pending.XXXXXX") || cal_refuse evidence 'Cannot prepare calibration evidence.'
    cal_cleanup_temp=$temp
    recorded=$(jq -nc --argjson fingerprint "$fingerprint" --argjson stages "$stages" \
        '{schema:1,fingerprint:$fingerprint,stages:$stages,acceptance:"not_run",recorded_at:(now|todateiso8601)}')
    cal_valid_record <<< "$recorded" || cal_refuse evidence 'Cannot validate calibration evidence.' failed
    printf '%s\n' "$recorded" > "$temp"
    cal_reobserve
    mv -f "$temp" "$proof" || cal_refuse evidence 'Cannot atomically save calibration evidence.'
    cal_finish ready 'Wiring and fixed offline drill passed; real agent execution and project acceptance are not run.'
}
# Missing jq cannot use the normal serializer. Emit a fixed, sanitized envelope.
if ! command -v jq >/dev/null 2>&1; then
    [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || v=unknown
    missing_mode=record
    for missing_arg in "$@"; do [[ $missing_arg != --check ]] || missing_mode=check; done
    printf '{"v":"%s","cmd":"calibrate","ok":false,"state":"blocked","fact":"Install a compatible jq before calibration.","id":null,"ticket":null,"items":[{"schema":1,"mode":"%s","readiness":"unwired","fingerprint":null,"stages":{"installation":"failed","configuration":"not_run","connectivity":"not_run","instructions":"not_run","drill":"not_run"},"drift":[],"acceptance":"not_run"}],"actions":[]}\n' "$v" "$missing_mode" >&3
    exit 1
fi
# Keep third-party diagnostics private; refusals use static facts only.
loom_calibrate "$@" 2>/dev/null
