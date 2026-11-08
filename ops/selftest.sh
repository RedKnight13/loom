#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031,SC2016 # subshell env; literal sed        #
# Offline self-test: a throwaway consumer repo, a stubbed gh, disposable
# fake workers. No network, no pushes, no real worker is signalled.
set -euo pipefail
ops=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/loom-selftest.XXXXXX")
scratch=$(cd "$scratch" && pwd -P)
pids=()
cleanup() {
    local p
    for p in ${pids[@]+"${pids[@]}"}; do kill -KILL "$p" 2>/dev/null || :; done
    # Stub workers started by the Orca stub are not all in pids; their command
    # lines carry the scratch path. Kill them so the suite leaves no orphans.
    pkill -f "$scratch" 2>/dev/null || :
    rm -rf "$scratch"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok  %s\n' "$*"; }

mkdir -p "$scratch/bin" "$scratch/repo"
export LOOM_STATE="$scratch/state" LOOM_REPO="$scratch/repo" LOOM_LOCK_WAIT=2
export GH_STATE="$scratch/gh"
# Every test below runs without Orca unless it says otherwise (the real CLI may
# be installed on the conductor's machine).
export LOOM_ORCA="$scratch/no-orca-cli"
mkdir -p "$GH_STATE"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
repo=$LOOM_REPO
git -C "$repo" init -q -b main
git -C "$repo" remote add origin https://github.com/example/fixture
git -C "$repo" config user.name 'Loom Fixture'
git -C "$repo" config user.email 'fixture@example.invalid'
git -C "$repo" config commit.gpgsign false
git -C "$repo" commit -q --allow-empty -m fixture
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q -b unrelated
git -C "$repo" commit -q --allow-empty -m unrelated

cat > "$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -eu
case "$1 $2" in
    'issue view')
        if [[ $* == 'issue view 9 --repo example/fixture --json number,title,body' ]]; then
            jq -n --rawfile b "$GH_STATE/issue9.body" '{number: 9, title: "Rendered", body: $b}'
            exit 0
        fi
        [[ $* == 'issue view '[78]' --repo example/fixture --json number,title,body' ]] || exit 98
        jq -n --argjson n "$3" '{number: $n, title: "Fixture ticket", body: "## Mandate\n\n**Ticket short name:** fixture-task\n**Scope:** fixture\n**Out of scope:** everything else\n**Laws:** fixture\n**Done means:** selftest\n**Stop by impact:** ready\n**Report:** structured"}' ;;
    'issue create')
        shift 2
        repo='' title='' body='' labels=''
        while [[ $# -gt 0 ]]; do
            case $1 in
                --repo) repo=$2; shift 2 ;;
                --title) title=$2; shift 2 ;;
                --body) body=$2; shift 2 ;;
                --label) labels="$labels$2"$'\n'; shift 2 ;;
                *) exit 97 ;;
            esac
        done
        [[ $repo == example/fixture ]] || exit 97
        printf '%s' "$body" > "$GH_STATE/issue9.body"
        printf '%s' "$labels" > "$GH_STATE/issue9.labels"
        printf 'https://github.com/example/fixture/issues/9\n' ;;
    'label list')
        [[ $* == *'--repo example/fixture'* ]] || exit 98
        printf 'bug\nloom-ready\n' ;;
    'repo view')
        [[ $* == 'repo view example/fixture --json defaultBranchRef --jq .defaultBranchRef.name' ]] || exit 98
        printf 'main\n' ;;
    *) exit 99 ;;
esac
EOF
cat > "$scratch/bin/w-ready" <<'EOF'
printf 'built\n' > out.txt
git add out.txt
git commit -q -m 'build out.txt'
printf 'state: ready — built out.txt\n' >> REPORT.md
EOF
cat > "$scratch/bin/w-blocked" <<'EOF'
printf 'state: blocked — Which license should the new file carry?\n' >> REPORT.md
EOF
printf 'exit 3\n' > "$scratch/bin/w-silent"
cat > "$scratch/bin/w-files" <<'EOF'
printf 'notes\n' > notes.txt
printf 'state: ready — wrote notes.txt\n' >> REPORT.md
EOF
cat > "$scratch/bin/w-hang" <<'EOF'
sleep 1000 &
printf '%s\n' "$!" > "$GRANDCHILD"
wait
EOF
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"
cat > "$scratch/consumer.toml" <<EOF
repo = "example/fixture" # test comments
checks = "true"
worktrees = "$scratch/work dirs"
laws = [
  "Workers never push.",
  "Keep # inside strings.",
]
EOF

dispatch() { bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7; }
dispatch_n() { bash "$ops/dispatch.sh" "$scratch/consumer.toml" "$1"; }
within() {  # within <secs> <cmd...>: fail instead of hanging
    local secs=$1 p
    shift
    "$@" & p=$!
    for _ in $(seq 1 $((secs * 10))); do
        kill -0 "$p" 2>/dev/null || { wait "$p"; return $?; }
        sleep 0.1
    done
    kill -KILL "$p" 2>/dev/null || :
    fail "timed out after ${secs}s: $*"
}
rec() { printf '%s/%s.json' "$LOOM_STATE" "$1"; }
age() {  # make an assignment look silent since 2000
    jq '.started_at = "2000-01-01T00:00:00Z" | if has("launched_at") then .launched_at = "2000-01-01T00:00:00Z" else . end | .reports |= map(.at = "2000-01-01T00:00:00Z")' "$(rec "$1")" > "$scratch/aged"
    mv "$scratch/aged" "$(rec "$1")"
}
await_pid() {
    local _
    for _ in $(seq 1 50); do
        [[ $(jq -r '.worker_pid // empty' "$(rec "$1")") ]] && return 0
        sleep 0.1
    done
    fail "worker pid never recorded for $1"
}

# --- calibration: proof is private, explicit, and never consumer execution ---
(
    export LOOM_STATE="$scratch/calibration-state"
    cp "$scratch/consumer.toml" "$scratch/calibration.toml"
    printf '\nexecutor = "local"\n' >> "$scratch/calibration.toml"
    # A declared check/setup is data, never an implicit calibration action.
    sed 's/checks = "true"/checks = "touch SHOULD_NOT_EXIST"/' "$scratch/calibration.toml" > "$scratch/calibration-next"
    mv "$scratch/calibration-next" "$scratch/calibration.toml"
    printf 'compute_setup = "touch SHOULD_NOT_EXIST"\n' >> "$scratch/calibration.toml"
    sed -n '/<!-- loom-session:start -->/,/<!-- loom-session:end -->/p' "$ops/../templates/LOOM_SESSION.md" > "$repo/AGENTS.md"
    [[ -s $repo/AGENTS.md ]] || fail 'bootstrap bridge template is missing'
    cp "$repo/AGENTS.md" "$scratch/bootstrap-bridge"
    rc=0; obj=$(bash "$ops/loom" calibrate --consumer "$scratch/not-a-config" --check) || rc=$?
    [[ $rc == 1 ]] || fail 'missing config calibration status'
    jq -se 'length == 1 and .[0].ok == false and .[0].items[0].readiness == "incomplete"' <<< "$obj" >/dev/null || fail 'missing config emitted multiple envelopes'
    printf 'private-invalid-value\n' > "$scratch/invalid-calibration.toml"
    rc=0; obj=$(bash "$ops/loom" calibrate --consumer "$scratch/invalid-calibration.toml" --check) || rc=$?
    [[ $rc == 1 && $obj != *private-invalid-value* ]] || fail 'invalid config was accepted or exposed'
    jq -se 'length == 1 and .[0].ok == false' <<< "$obj" >/dev/null || fail 'invalid config emitted multiple envelopes'
    calops=$ops
    cal() { bash "$calops/loom" calibrate --consumer "$scratch/calibration.toml" "$@"; }
    rc=0; obj=$(cal --check) || rc=$?
    [[ $rc == 1 ]] || fail 'calibration accepted missing proof'
    jq -e '.ok == false and .items[0].readiness == "incomplete"' <<< "$obj" >/dev/null || fail 'missing proof contract'
    [[ ! -e $LOOM_STATE ]] || fail 'check created state'
    obj=$(cal) || fail "calibration fixture failed: $obj"
    jq -e '.ok and .state == "ready" and .items[0].schema == 1 and .items[0].acceptance == "not_run"' <<< "$obj" >/dev/null || fail 'calibration readiness contract'
    proofs=("$LOOM_STATE"/calibration/*.json)
    [[ ${#proofs[@]} == 1 && -f ${proofs[0]} ]] || fail 'calibration proof missing'
    proof=${proofs[0]}
    cp "$proof" "$scratch/proof-good"
    obj=$(cal --check) || fail 'unchanged calibration rejected'
    cmp -s "$proof" "$scratch/proof-good" || fail 'check rewrote evidence'
    [[ $(printf '%s\n' "$obj" | wc -l | tr -d ' ') == 1 ]] || fail 'calibration emitted multiple objects'
    if grep -F -e "$scratch" -e 'example/fixture' -e 'SHOULD_NOT_EXIST' "$proof"; then fail 'calibration retained private input'; fi
    [[ ! -e SHOULD_NOT_EXIST && ! -e $repo/SHOULD_NOT_EXIST ]] || fail 'calibration executed consumer commands'
    # The format is SHA-1 regardless of caller repository/config/environment.
    expected=$(jq -nc --arg c "$scratch/calibration.toml" --arg r "$repo" '[$c,$r]' | git hash-object --stdin)
    [[ ${proof##*/} == "$expected.json" ]] || fail 'calibration key is not canonical JSON with a trailing newline'
    bridge_digest=$(git hash-object --no-filters "$repo/AGENTS.md")
    expected=$(printf '[["AGENTS.md","%s"],["CLAUDE.md",null]]\n' "$bridge_digest" | git hash-object --stdin)
    [[ $(jq -r '.fingerprint.bridge' "$proof") == "$expected" ]] || fail 'bridge serialization is not canonical'
    expected=$(
        for source in "$ops/../VERSION" "$ops/loom" "$ops"/*.sh; do
            case $source in */VERSION) relative=VERSION ;; *) relative=ops/${source##*/} ;; esac
            jq -nc --arg n "$relative" --arg d "$(git hash-object --no-filters "$source")" '[$n,$d]'
        done | jq -Scs 'sort_by(.[0])' | git hash-object --stdin
    )
    [[ $(jq -r '.fingerprint.loom_code' "$proof") == "$expected" ]] || fail 'source fingerprint omits VERSION or canonical source names'
    mkdir "$scratch/hash-caller"
    if git -C "$scratch/hash-caller" init -q --object-format=sha256 2>/dev/null; then
        (
            cd "$scratch/hash-caller"
            export GIT_DEFAULT_HASH=sha256
            obj=$(cal) || fail 'record from SHA-256 caller failed'
            jq -e '.items[0].fingerprint | [.loom_code,.consumer,.checkout,.bridge,.tools] | all(.[]; test("^[0-9a-f]{40}$"))' <<< "$obj" >/dev/null || fail 'SHA-256 caller changed digest format'
            cal --check >/dev/null || fail 'check from SHA-256 caller failed'
        )
        [[ $(jq -c '.fingerprint' "$proof") == "$(jq -c '.fingerprint' "$scratch/proof-good")" ]] || fail 'caller object format changed fingerprint'
        (
            export LOOM_REPO="$scratch/hash-caller" LOOM_STATE="$scratch/sha256-state"
            git -C "$LOOM_REPO" remote add origin https://github.com/example/fixture
            git -C "$LOOM_REPO" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m fixture
            cp "$repo/AGENTS.md" "$LOOM_REPO/AGENTS.md"
            cal >/dev/null || fail 'SHA-256 consumer checkout could not record'
            cal --check >/dev/null || fail 'SHA-256 consumer checkout could not check'
        )
    else
        pass 'SHA-256 caller fixture not run: Git lacks SHA-256 repository support'
    fi
    # Relative paths resolve against invocation cwd, including spaces, without
    # creating missing state during check or rewriting a successful baseline.
    (
        cd "$scratch"
        export LOOM_STATE='relative state'
        rc=0; cal --check >/dev/null || rc=$?
        [[ $rc == 1 && ! -e $LOOM_STATE ]] || fail 'relative missing-state check wrote state or succeeded'
        cal >/dev/null || fail 'relative state record failed'
        relative_proof=("$LOOM_STATE"/calibration/*.json)
        cp "${relative_proof[0]}" "$scratch/relative-proof"
        cal --check >/dev/null || fail 'relative state check failed'
        LOOM_STATE="$scratch/relative state" cal --check >/dev/null || fail 'absolute alias of relative state failed'
        cmp -s "${relative_proof[0]}" "$scratch/relative-proof" || fail 'relative state check rewrote proof'
    )
    # Reject nonregular/symlink inputs before parsing/hashing. The watchdog
    # makes a regression to a FIFO read fail promptly instead of hanging CI.
    refuse_input() {
        local got status=0 timed=$scratch/input-timed-out child timer
        rm -f "$timed"
        bash "$calops/loom" calibrate --consumer "$1" > "$scratch/input-result" 2> "$scratch/input-error" & child=$!
        (sleep 4; if kill -0 "$child" 2>/dev/null; then : > "$timed"; kill -KILL "$child" 2>/dev/null || :; fi) & timer=$!
        wait "$child" || status=$?
        kill "$timer" 2>/dev/null || :
        wait "$timer" 2>/dev/null || :
        [[ ! -e $timed && $status == 1 ]] || fail "unsafe input was accepted or blocked: $2"
        got=$(cat "$scratch/input-result")
        jq -se 'length == 1 and .[0].ok == false and .[0].state == "failed" and .[0].items[0].readiness == "incomplete"' <<< "$got" >/dev/null || fail "unsafe input envelope: $2"
        [[ ! -s $scratch/input-error && $got != *"$scratch"* ]] || fail 'unsafe input leaked diagnostics'
    }
    mkdir "$scratch/config-dir"
    cp "$scratch/calibration.toml" "$scratch/config-dir/consumer.toml"
    ln -s "$scratch/config-dir" "$scratch/config-link"
    refuse_input "$scratch/config-link/consumer.toml" 'config ancestor symlink'
    ln -s "$scratch/calibration.toml" "$scratch/config-symlink"
    refuse_input "$scratch/config-symlink" 'config symlink'
    mkfifo "$scratch/config-fifo"
    refuse_input "$scratch/config-fifo" 'config FIFO'
    refuse_input "$scratch/config-dir" 'config directory'
    cp "$scratch/calibration.toml" "$scratch/"$'control\tconfig'
    refuse_input "$scratch/"$'control\tconfig' 'config control character'
    mkdir "$scratch/safety-install"
    cp -R "$ops" "$scratch/safety-install/ops"
    cp "$ops/../VERSION" "$scratch/safety-install/VERSION"
    calops=$scratch/safety-install/ops
    for unsafe in symlink fifo directory; do
        case $unsafe in
            symlink) ln -s "$ops/lib.sh" "$calops/extra.sh" ;;
            fifo) mkfifo "$calops/extra.sh" ;;
            directory) mkdir "$calops/extra.sh" ;;
        esac
        refuse_input "$scratch/calibration.toml" "source $unsafe"
        if [[ $unsafe == directory ]]; then rmdir "$calops/extra.sh"; else rm "$calops/extra.sh"; fi
    done
    # VERSION and lib are consumed by the entry point before the module runs.
    for source in "$scratch/safety-install/VERSION" "$calops/lib.sh"; do
        mv "$source" "$source.safe"
        mkfifo "$source"
        refuse_input "$scratch/calibration.toml" 'early source FIFO'
        rm "$source"; mv "$source.safe" "$source"
    done
    calops=$ops
    (
        export LOOM_STATE="$scratch/state-file"
        : > "$LOOM_STATE"; chmod 600 "$LOOM_STATE"
        refuse_input "$scratch/calibration.toml" 'nondirectory state'
        rm "$LOOM_STATE"
        ln -s "$scratch/calibration-state" "$LOOM_STATE"
        refuse_input "$scratch/calibration.toml" 'symlink state'
    )
    # Deterministic races use fixture-installed tools, not timing assumptions.
    # The check changes a bridge only after the initial fingerprint comparison.
    real_jq=$(command -v jq)
    cat > "$scratch/bin/jq" <<EOF_JQ
#!/usr/bin/env bash
if [[ \${1:-} == -c && \${2:-} == .stages && -n \${CAL_RACE_TARGET:-} ]]; then
    printf '# concurrent check change\\n' >> "\$CAL_RACE_TARGET"
fi
exec "$real_jq" "\$@"
EOF_JQ
    chmod +x "$scratch/bin/jq"
    cal >/dev/null || fail 'race fixture baseline failed'
    cp "$proof" "$scratch/race-proof"
    cp "$repo/AGENTS.md" "$scratch/race-bridge"
    rc=0; obj=$(CAL_RACE_TARGET="$repo/AGENTS.md" cal --check) || rc=$?
    [[ $rc == 1 ]] || fail 'check accepted a concurrent fingerprint change'
    jq -e '.items[0].readiness == "drifted" and .items[0].drift == ["bridge"]' <<< "$obj" >/dev/null || fail 'check did not name concurrent bridge drift'
    cmp -s "$proof" "$scratch/race-proof" || fail 'concurrent check replaced evidence'
    cp "$scratch/race-bridge" "$repo/AGENTS.md"
    rm "$scratch/bin/jq"
    calops=$scratch/safety-install/ops
    sed '/^exit "\$rc"/i\
[[ -z ${CAL_RACE_TARGET:-} ]] || printf "# concurrent drill change\\n" >> "$CAL_RACE_TARGET"' "$ops/verify.sh" > "$calops/verify.sh"
    cal >/dev/null || fail 'record race fixture baseline failed'
    cp "$proof" "$scratch/race-proof"
    rc=0; obj=$(CAL_RACE_TARGET="$repo/AGENTS.md" cal) || rc=$?
    [[ $rc == 1 ]] || fail 'record published evidence after concurrent fingerprint change'
    jq -e '.items[0].readiness == "drifted" and .items[0].drift == ["bridge"]' <<< "$obj" >/dev/null || fail 'record did not name concurrent bridge drift'
    cmp -s "$proof" "$scratch/race-proof" || fail 'concurrent record replaced prior evidence'
    [[ ! -e $LOOM_STATE/calibration/.record-lock ]] || fail 'concurrent record leaked its lock'
    cp "$scratch/race-bridge" "$repo/AGENTS.md"
    # A late source mutation must also invalidate the record.
    rc=0; obj=$(CAL_RACE_TARGET="$calops/lib.sh" cal) || rc=$?
    [[ $rc == 1 ]] || fail 'record accepted a concurrent source change'
    jq -e '.items[0].drift == ["loom_code"]' <<< "$obj" >/dev/null || fail 'record did not name concurrent source drift'
    cmp -s "$proof" "$scratch/race-proof" || fail 'source race replaced prior evidence'
    calops=$ops
    cp "$scratch/proof-good" "$proof"
    # Each independently changed input must name its own drift field.
    expect_drift() {
        local got status=0
        got=$(cal --check) || status=$?
        [[ $status == 1 ]] || fail "calibration missed $1 drift"
        jq -e --arg field "$1" '.items[0].readiness == "drifted" and (.items[0].drift | index($field) != null)' <<< "$got" >/dev/null || fail "calibration omitted $1 drift"
    }
    printf '# bridge change\n' >> "$repo/AGENTS.md"
    expect_drift bridge
    cp "$scratch/bootstrap-bridge" "$repo/AGENTS.md"
    cp "$scratch/bin/gh" "$scratch/gh-original"
    printf '# tool change\n' >> "$scratch/bin/gh"
    expect_drift tools
    cp "$scratch/gh-original" "$scratch/bin/gh"
    git -C "$repo" remote set-url origin git@github.com:example/fixture.git
    expect_drift checkout
    git -C "$repo" remote set-url origin https://github.com/example/fixture
    # A separate installation lets the fixture change source bytes and version.
    mkdir "$scratch/install"
    cp -R "$ops" "$scratch/install/ops"
    cp "$ops/../VERSION" "$scratch/install/VERSION"
    calops=$scratch/install/ops
    printf '# dirty source\n' >> "$calops/lib.sh"
    expect_drift loom_code
    cp "$ops/lib.sh" "$calops/lib.sh"
    printf '0.0.0\n' > "$scratch/install/VERSION"
    expect_drift loom_version
    calops=$ops
    cal --check >/dev/null || fail 'restored inputs did not restore proof'
    # Failed recording cannot replace prior evidence, including a failed drill.
    cp "$repo/AGENTS.md" "$scratch/bridge-original"
    rm "$repo/AGENTS.md"
    cal >/dev/null && fail 'missing bridge passed'
    cmp -s "$proof" "$scratch/proof-good" || fail 'failed record replaced proof'
    ln -s "$scratch/bridge-original" "$repo/AGENTS.md"
    cal >/dev/null && fail 'symlink bridge passed'
    rm "$repo/AGENTS.md"; cp "$scratch/bridge-original" "$repo/AGENTS.md"
    calops=$scratch/install/ops
    # Valid Bash, but broken envelope semantics make the fixed drill fail.
    sed 's/state:$state/state:"ready"/' "$ops/loom" > "$calops/loom"
    rc=0; obj=$(cal) || rc=$?
    [[ $rc == 1 ]] || fail 'broken report envelope passed the offline drill'
    cmp -s "$proof" "$scratch/proof-good" || fail 'failed drill replaced proof'
    # A consumed report must be followed by a newly appended line; the drill
    # must distinguish blocked from failed, not merely refuse ready.
    sed 's/state:$state/state:(if $state == "blocked" then "failed" else $state end)/' "$ops/loom" > "$calops/loom"
    cal >/dev/null && fail 'drill accepted failed in place of blocked'
    cmp -s "$proof" "$scratch/proof-good" || fail 'misclassified blocked drill replaced proof'
    sed 's/state:$state/state:(if $state == "failed" then "blocked" else $state end)/' "$ops/loom" > "$calops/loom"
    cal >/dev/null && fail 'drill accepted blocked in place of failed'
    cmp -s "$proof" "$scratch/proof-good" || fail 'misclassified missing drill replaced proof'
    calops=$ops
    mkdir "$LOOM_STATE/calibration/.record-lock"
    cal >/dev/null && fail 'concurrent calibration ignored record lock'
    cal --check >/dev/null || fail 'readonly check took a record lock'
    rmdir "$LOOM_STATE/calibration/.record-lock"
    chmod 755 "$LOOM_STATE/calibration"
    cal --check >/dev/null && fail 'unsafe evidence directory permissions accepted'
    chmod 700 "$LOOM_STATE/calibration"
    printf '\n# reviewed later\n' >> "$scratch/calibration.toml"
    rc=0; obj=$(cal --check) || rc=$?
    [[ $rc == 1 ]] || fail 'calibration accepted consumer drift'
    jq -e '.items[0].readiness == "drifted"' <<< "$obj" >/dev/null || fail 'drift not identified'
    cmp -s "$proof" "$scratch/proof-good" || fail 'drift check refreshed proof'
    cal >/dev/null || fail 'explicit recalibration failed'
    printf '{' > "$proof"
    rc=0; obj=$(cal --check) || rc=$?
    [[ $rc == 1 ]] || fail 'calibration accepted corrupt proof'
    [[ $(cat "$proof") == '{' ]] || fail 'check repaired corrupt proof'
    cp "$scratch/proof-good" "$proof"
    jq 'del(.stages)' "$proof" > "$scratch/proof-incomplete"
    mv "$scratch/proof-incomplete" "$proof"
    chmod 600 "$proof"
    cal --check >/dev/null && fail 'calibration accepted incomplete proof'
    cp "$scratch/proof-good" "$proof"
    jq '.schema = 99' "$proof" > "$scratch/proof-version"
    cat "$scratch/proof-version" > "$proof"
    cal --check >/dev/null && fail 'unknown proof schema accepted'
    head -c 65537 /dev/zero > "$proof"
    cal --check >/dev/null && fail 'oversized proof accepted'
    rm "$proof"; ln -s "$scratch/proof-good" "$proof"
    cal >/dev/null && fail 'calibration followed evidence symlink'
    cmp -s "$scratch/proof-good" "$proof" || fail 'calibration changed symlink target'
    rm "$proof"
    cp "$scratch/proof-good" "$proof"
    cat "$scratch/proof-good" >> "$proof"
    cal --check >/dev/null && fail 'multiple proof objects accepted'
    cp "$scratch/calibration.toml" "$scratch/calibration-local"
    printf 'compute = "-oProxyCommand=forbidden"\n' >> "$scratch/calibration.toml"
    cal >/dev/null && fail 'option-shaped compute host accepted'
    cp "$scratch/calibration-local" "$scratch/calibration.toml"
    printf '%s\n' 'compute = "safe\nunsafe"' >> "$scratch/calibration.toml"
    cal >/dev/null && fail 'multiline compute host accepted';
    cp "$scratch/calibration-local" "$scratch/calibration.toml"
    sed 's/executor = "local"/executor = "orca"/' "$scratch/calibration-local" > "$scratch/calibration.toml"
    rc=0; obj=$(cal) || rc=$?
    [[ $rc == 1 ]] || fail 'missing required Orca passed'
    jq -e '.items[0].readiness == "unwired"' <<< "$obj" >/dev/null || fail 'missing Orca not unwired'
    export LOOM_ORCA="$scratch/bin/cal-orca"
    printf '#!/bin/sh\nexec /bin/sleep 30\n' > "$LOOM_ORCA"
    chmod +x "$LOOM_ORCA"
    started=$(date +%s)
    rc=0; obj=$(cal) || rc=$?
    [[ $rc == 1 && $(( $(date +%s) - started )) -lt 12 ]] || fail 'Orca status timeout was not bounded'
    jq -e '.items[0].readiness == "unwired"' <<< "$obj" >/dev/null || fail 'Orca timeout not unwired'
    printf '#!/bin/sh\nprintf "runtimeReachable: true\\nruntimeState: ready\\n"\n' > "$LOOM_ORCA"
    rc=0; obj=$(cal) || rc=$?
    [[ $rc == 1 ]] || fail 'Orca status without runtime identity passed'
    jq -e '.items[0].readiness == "unwired"' <<< "$obj" >/dev/null || fail 'incomplete Orca status not unwired'
    printf '#!/bin/sh\nprintf "runtimeReachable: true\\nruntimeState: ready\\nruntimeId: fixture-runtime\\n"\n' > "$LOOM_ORCA"
    sed 's/executor = "local"/executor = "auto"/' "$scratch/calibration-local" > "$scratch/calibration.toml"
    cal >/dev/null || fail 'available Orca structural calibration failed'
    printf '#!/bin/sh\nexit 1\n' > "$LOOM_ORCA"
    expect_drift executor
    cp "$scratch/calibration-local" "$scratch/calibration.toml"
    # Exercise system Bash as well (Bash 3.2 on supported macOS installations).
    if [[ -x /bin/bash ]]; then
        obj=$(/bin/bash "$calops/loom" calibrate --consumer "$scratch/calibration.toml") || fail 'system Bash calibration cleanup failed'
        jq -e '.ok and .state == "ready"' <<< "$obj" >/dev/null || fail 'system Bash calibration envelope'
    fi
    rc=0; obj=$(cal --unknown) || rc=$?
    [[ $rc == 2 ]] || fail 'calibration usage status'
)
pass 'calibration refuses absent/corrupt/drifted proof without implicit execution'
[[ ${LOOM_SELFTEST_CALIBRATION_ONLY:-0} != 1 ]] || exit 0

# --- dispatch: a private clone on the ticket branch, at the default branch ---
out=$(dispatch)
work1=${out%$'\n'*}; id1=${out##*$'\n'}
[[ $id1 == fixture-task.1 ]] || fail "unexpected id $id1"
[[ $(git -C "$work1" branch --show-current) == fixture-task ]] || fail 'wrong branch'
[[ $(git -C "$work1" rev-parse HEAD) == "$base" ]] || fail 'not based on default branch'
[[ -z $(git -C "$work1" remote) ]] || fail 'clone must have no remote'
[[ -f $work1/.git/HEAD ]] || fail 'workdir must own its .git (clone, not worktree)'
[[ $(< "$work1/WORK.md") == *'Keep # inside strings.'*'How to report'* ]] || fail 'mandate/laws/report contract missing'
[[ -z $(git -C "$work1" status --porcelain) ]] || fail 'WORK.md must be excluded from git'
jq -e '.attempt == 1 and .worker_pid == null and .reports == [] and .base_sha == "'"$base"'"' "$(rec "$id1")" >/dev/null || fail 'record shape'
pass 'dispatch makes a private, remote-less clone with mandate'

# --- dispatch refuses a checkout whose origin is not the consumer's repo (#54) ---
mkdir -p "$scratch/other"
git -C "$scratch/other" init -q -b main
git -C "$scratch/other" config user.name 'Other Fixture'
git -C "$scratch/other" config user.email 'other@example.invalid'
git -C "$scratch/other" config commit.gpgsign false
git -C "$scratch/other" remote add origin https://github.com/example/other
git -C "$scratch/other" commit -q --allow-empty -m other
err=$(LOOM_REPO="$scratch/other" bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7 2>&1) && fail 'a foreign checkout was accepted'
[[ $err == *'not example/fixture'* ]] || fail "wrong refusal: $err"
out=$(LOOM_ALLOW_ANY_CHECKOUT=1 LOOM_REPO="$scratch/other" bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7) || fail 'explicit override refused'
# Leave no record or workdir: later cases assert attempt numbering.
rm -rf "${out%$'\n'*}" "$LOOM_STATE/${out##*$'\n'}.json"
pass 'dispatch refuses a foreign checkout; the override is explicit (#54)'

# --- workers: a declared cap limits open assignments (bootstrap asks for it) ---
(
    export LOOM_STATE="$scratch/limit-state"
    sed -e 's/^checks = "true"$/checks = "true"\nexecutor = "local"\nworkers = 1/' \
        -e "s|^worktrees = .*|worktrees = \"$scratch/limit-dirs\"|" "$scratch/consumer.toml" > "$scratch/limit1.toml"
    out=$(bash "$ops/dispatch.sh" "$scratch/limit1.toml" 7) || fail 'first dispatch under workers=1 refused'
    id1=${out##*$'\n'}
    jq -e '.workers == 1' "$LOOM_STATE/$id1.json" >/dev/null || fail 'workers not recorded'
    err=$(bash "$ops/dispatch.sh" "$scratch/limit1.toml" 8 2>&1) && fail 'workers=1 allowed a second open assignment'
    [[ $err == *'worker limit reached (workers=1)'* ]] || fail "wrong worker-limit error: $err"
    sed 's/^workers = 1$/workers = 2/' "$scratch/limit1.toml" > "$scratch/limit2.toml"
    bash "$ops/dispatch.sh" "$scratch/limit2.toml" 8 >/dev/null || fail 'workers=2 refused a second assignment'
    rm -rf "$scratch/limit-state" "$scratch/limit-dirs"
)
pass 'workers cap: open assignments stop at the declared number (#64)'

# --- conductor report validation ---
if bash "$ops/report.sh" "$id1" unknown bad 2>/dev/null; then fail 'invalid state accepted'; fi
if bash "$ops/report.sh" ../escape ready bad 2>/dev/null; then fail 'unsafe id accepted'; fi
if bash "$ops/report.sh" missing ready bad 2>/dev/null; then fail 'missing assignment accepted'; fi
[[ -z $(bash "$ops/status.sh") ]] || fail 'fresh assignment needs no person'
pass 'report validation; fresh assignment is silent'

# --- D1 shape: worker commits and reports ready; conductor collects ---
out=$(bash "$ops/launch.sh" "$id1" -- bash "$scratch/bin/w-ready")
[[ $out == *'ready (worker exit 0)'* ]] || fail "launch outcome: $out"
jq -e '.worker_pid == null and .reports[-1].state == "ready" and .reports[-1].fact == "built out.txt" and has("launched_at")' "$(rec "$id1")" >/dev/null || fail 'ready not harvested'
[[ $(bash "$ops/status.sh") == "$id1"$'\t'ready$'\t''built out.txt' ]] || fail 'status must show exactly the ready line'
out=$(bash "$ops/collect.sh" "$id1")
[[ $out == *'1 commit(s) over base'* ]] || fail "collect: $out"
[[ $(git -C "$repo" log -1 --format=%s fixture-task) == 'build out.txt' ]] || fail 'branch not in checkout'
[[ $(git -C "$repo" log -1 --format=%an fixture-task) == 'Loom Fixture' ]] || fail 'consumer identity not carried into clone'
pass 'launch harvests ready; collect brings the branch home'

# --- D2/D4: hung worker refused a twin, killed with its children, re-dispatchable ---
out=$(dispatch)
id2=${out##*$'\n'}
[[ $id2 == fixture-task.2 ]] || fail 'ended assignment must allow attempt 2'
export GRANDCHILD="$scratch/grandchild"
bash "$ops/launch.sh" "$id2" -- bash "$scratch/bin/w-hang" > "$scratch/launch2.out" 2>&1 &
launcher=$!; pids+=("$launcher")
await_pid "$id2"
worker=$(jq -r '.worker_pid' "$(rec "$id2")"); pids+=("$worker")
for _ in $(seq 1 30); do [[ -s $GRANDCHILD ]] && break; sleep 0.1; done
grandchild=$(< "$GRANDCHILD"); pids+=("$grandchild")
if dispatch >/dev/null 2>&1; then fail 'second live assignment accepted (D4)'; fi
[[ -z $(bash "$ops/watchdog.sh") ]] || fail 'fresh worker must not trip the watchdog'
kill -0 "$worker" || fail 'watchdog killed a fresh worker'
age "$id2"
[[ -z $(bash "$ops/watchdog.sh" --limit-min 1 --id "$id1") ]] || fail 'scoped watchdog touched another assignment'
kill -0 "$worker" || fail 'scoped watchdog killed an out-of-scope worker'
[[ $(bash "$ops/watchdog.sh" --limit-min 1 --id "$id2") == "$id2 failed watchdog_kill" ]] || fail 'watchdog action missing'
for _ in $(seq 1 300); do kill -0 "$launcher" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$launcher" 2>/dev/null; then
    kill -KILL "$launcher" 2>/dev/null || :
    fail 'launcher did not return after the watchdog kill'
fi
wait "$launcher" 2>/dev/null || :
sleep 0.3
! kill -0 "$worker" 2>/dev/null || fail 'worker survived'
! kill -0 "$grandchild" 2>/dev/null || fail "worker's child survived (process group not killed)"
[[ $(< "$scratch/launch2.out") == *'already settled by watchdog'* ]] || fail 'launcher double-reported'
jq -e '[.reports[].state] == ["failed"] and .reports[0].fact == "watchdog_kill" and .worker_pid == null' "$(rec "$id2")" >/dev/null || fail 'watchdog record'
[[ -d $(jq -r '.workdir' "$(rec "$id2")") ]] || fail 'watchdog must keep the workdir'
[[ -z $(bash "$ops/watchdog.sh" --limit-min 1) ]] || fail 'watchdog repeated an action'
if bash "$ops/watchdog.sh" --limit-min nope 2>/dev/null; then fail 'invalid limit accepted'; fi
if bash "$ops/watchdog.sh" --id ../x 2>/dev/null; then fail 'unsafe watchdog id accepted'; fi
pass 'hung worker: twin refused, group killed, recorded once, workdir kept'

# --- silent exit, then a blocked turn, then report_offset ignores old lines ---
out=$(dispatch); id3=${out##*$'\n'}
[[ $id3 == fixture-task.3 ]] || fail 're-dispatch after watchdog must yield exactly attempt 3'
records=("$LOOM_STATE"/*.json)
[[ ${#records[@]} == 3 ]] || fail 'expected exactly three records'
bash "$ops/launch.sh" "$id3" -- bash "$scratch/bin/w-silent" >/dev/null
jq -e '.reports[-1].state == "failed" and .reports[-1].fact == "worker_exit_no_report (exit 3)"' "$(rec "$id3")" >/dev/null || fail 'silent exit not failed'
bash "$ops/launch.sh" "$id3" -- bash "$scratch/bin/w-blocked" >/dev/null
st=$(bash "$ops/status.sh" | grep "^$id3")
[[ $st == "$id3"$'\t'blocked$'\t''Which license should the new file carry?' ]] || fail "blocked line: $st"
bash "$ops/launch.sh" "$id3" -- bash "$scratch/bin/w-silent" >/dev/null
jq -e '[.reports[].state] == ["failed","blocked","failed"]' "$(rec "$id3")" >/dev/null || fail 'old REPORT.md line was re-harvested'
pass 'silent exit fails; blocked shows its one question; old lines never re-read'

# --- launcher lost: harvest the report; a recycled PID is never signalled ---
out=$(dispatch); work4=${out%$'\n'*}; id4=${out##*$'\n'}
printf 'state: ready — finished before its launcher died\n' >> "$work4/REPORT.md"
sleep 1000 & stranger=$!; pids+=("$stranger")
jq --argjson pid "$stranger" '.worker_pid = $pid | .worker_start = "Thu Jan  1 00:00:00 2001" | .launched_at = "2000-01-01T00:00:00Z" | .report_offset = 0' "$(rec "$id4")" > "$scratch/lost"
mv "$scratch/lost" "$(rec "$id4")"
[[ $(bash "$ops/watchdog.sh" --limit-min 1) == "$id4 ready worker_gone" ]] || fail 'lost worker not harvested'
kill -0 "$stranger" || fail 'watchdog signalled a recycled PID'
jq -e '.worker_pid == null and .reports[-1].fact == "finished before its launcher died"' "$(rec "$id4")" >/dev/null || fail 'lost harvest record'
pass 'lost launcher harvested; recycled PID left alone'

# --- per-consumer watchdog limit (gap #7) and exact process start (gap #10) ---
sed 's/^checks = "true"$/checks = "true"\nlimit_min = 60/' "$scratch/consumer.toml" > "$scratch/slow.toml"
grep -q '^limit_min = 60$' "$scratch/slow.toml" || fail 'fixture: slow consumer not written'
sed 's/^limit_min = 60$/limit_min = "60"/' "$scratch/slow.toml" > "$scratch/bad.toml"
if bash "$ops/dispatch.sh" "$scratch/bad.toml" 7 >/dev/null 2>&1; then fail 'non-integer limit_min accepted'; fi
out=$(bash "$ops/dispatch.sh" "$scratch/slow.toml" 7); id5=${out##*$'\n'}
jq -e '.limit_min == 60' "$(rec "$id5")" >/dev/null || fail 'limit_min not copied into the record'
jq -e '.limit_min == null' "$(rec "$id4")" >/dev/null || fail 'default consumer must record no limit'
bash "$ops/launch.sh" "$id5" -- bash "$scratch/bin/w-hang" > /dev/null 2>&1 &
pids+=("$!"); slow_launcher=$!
await_pid "$id5"
slow=$(jq -r '.worker_pid' "$(rec "$id5")"); pids+=("$slow")
[[ $(jq -r '.worker_start' "$(rec "$id5")") == "$(ps -o lstart= -p "$slow" | sed 's/^ *//; s/ *$//')" ]] || fail 'worker_start must be trimmed both ends'
jq '.started_at = ((now - 2400) | todateiso8601) | .launched_at = .started_at' "$(rec "$id5")" > "$scratch/t"; mv "$scratch/t" "$(rec "$id5")"
[[ -z $(bash "$ops/watchdog.sh") ]] || fail '40 min silent under a 60-min consumer limit must survive the default run'
kill -0 "$slow" || fail 'consumer limit ignored: worker killed at the default 30'
jq '.limit_min = 1' "$(rec "$id5")" > "$scratch/t"; mv "$scratch/t" "$(rec "$id5")"
[[ $(bash "$ops/watchdog.sh") == "$id5 failed watchdog_kill" ]] || fail 'record limit below default not honoured'
wait "$slow_launcher" 2>/dev/null || :
pass 'consumer limit_min is parsed, recorded, and honoured; start time trimmed'

# --- workers never touch git; loom seals their work (gap #11) ---
out=$(dispatch); work6=${out%$'\n'*}; id6=${out##*$'\n'}
[[ $(< "$work6/WORK.md") == *'Do not run git add or git commit'* ]] || fail 'WORK.md must tell workers not to commit'
bash "$ops/launch.sh" "$id6" -- bash "$scratch/bin/w-files" >/dev/null
[[ $(git -C "$work6" log -1 --format=%s) == "loom($id6): ready — wrote notes.txt" ]] || fail 'loom did not commit the worker files'
[[ -z $(git -C "$work6" status --porcelain) ]] || fail 'workdir left dirty after harvest'
! git -C "$work6" ls-files | grep -qE '^(WORK|REPORT)\.md$' || fail 'WORK.md/REPORT.md must never be committed'
[[ $(git -C "$work6" log -1 --format=%an) == 'Loom Fixture' ]] || fail 'loom commit must use the consumer identity'
[[ $(bash "$ops/collect.sh" "$id6") == *'1 commit(s) over base'* ]] || fail 'sealed commit not collectable'
pass 'git-free worker: loom commits its files under the consumer identity'

# --- a corrected ticket may reuse a short name (gap #14) ---
out=$(bash "$ops/dispatch.sh" "$scratch/consumer.toml" 8) || fail 'new ticket reusing a short name refused'
id7=${out##*$'\n'}
[[ $id7 == fixture-task.7 ]] || fail "short-name attempts must continue across tickets, got $id7"
jq -e '.ticket == 8 and .attempt == 7' "$(rec "$id7")" >/dev/null || fail 'reused-name record'
pass 'a corrected ticket reuses its short name with the next attempt'

# --- the conductor's re-check (gaps #9, #12, #13) ---
sed 's/^checks = "true"$/checks = "test -f out.txt"/' "$scratch/consumer.toml" > "$scratch/checked.toml"
out=$(bash "$ops/dispatch.sh" "$scratch/checked.toml" 8); work8=${out%$'\n'*}; id8=${out##*$'\n'}
[[ $(< "$work8/WORK.md") == *'Checks the conductor will run'*'test -f out.txt'* ]] || fail 'WORK.md must show the checks'
rc=0; bash "$ops/verify.sh" "$id8" --baseline >/dev/null 2>&1 || rc=$?
[[ $rc == 1 ]] || fail "baseline must fail before the work exists (got $rc)"
jq -e '.checks_runs[-1].kind == "baseline" and .checks_runs[-1].exit == 1 and (.reports | length) == 0' "$(rec "$id8")" >/dev/null || fail 'baseline must be recorded, not reported'
bash "$ops/launch.sh" "$id8" -- bash "$scratch/bin/w-ready" >/dev/null
out=$(bash "$ops/verify.sh" "$id8") || fail "verify of a good branch failed: $out"
jq -e '.reports[-1].state == "ready" and (.reports[-1].fact | startswith("conductor verified: checks exit 0")) and (.reports[-1].fact | endswith("(baseline: 1)"))' "$(rec "$id8")" >/dev/null || fail 'verified report'
# The worker's uncommitted leftovers must not influence verification.
sed 's/^checks = "true"$/checks = "test -f leftover.txt"/' "$scratch/consumer.toml" > "$scratch/left.toml"
out=$(bash "$ops/dispatch.sh" "$scratch/left.toml" 8); work9=${out%$'\n'*}; id9=${out##*$'\n'}
bash "$ops/launch.sh" "$id9" -- bash "$scratch/bin/w-ready" >/dev/null
printf 'x\n' > "$work9/leftover.txt"
if bash "$ops/verify.sh" "$id9" >/dev/null 2>&1; then fail 'verify read the worker clone instead of a fresh clone'; fi
jq -e '.reports[-1].state == "failed" and (.reports[-1].fact | startswith("conductor check: checks exit 1"))' "$(rec "$id9")" >/dev/null || fail 'failed check report'
# A check that cannot start is not a test failure.
sed 's/^checks = "true"$/checks = "no-such-loom-check-cmd"/' "$scratch/consumer.toml" > "$scratch/norun.toml"
out=$(bash "$ops/dispatch.sh" "$scratch/norun.toml" 8); id10=${out##*$'\n'}
rc=0; bash "$ops/verify.sh" "$id10" --baseline >/dev/null 2>&1 || rc=$?
[[ $rc == 127 ]] || fail "unrunnable check must exit 127 (got $rc)"
bash "$ops/launch.sh" "$id10" -- bash "$scratch/bin/w-files" >/dev/null
bash "$ops/verify.sh" "$id10" >/dev/null 2>&1 || :
jq -e '.reports[-1].fact | startswith("conductor check: checks could not run (exit 127)")' "$(rec "$id10")" >/dev/null || fail 'could-not-run not distinguished'
pass 'verify: fresh clone, baseline recorded, could-not-run distinguished'

# --- collected branches can be rebased by the conductor (gap #74) ---
(
    bash "$ops/collect.sh" "$id8" >/dev/null
    old_tip=$(git -C "$work8" rev-parse HEAD)
    new_base=$(git -C "$repo" commit-tree "$base^{tree}" -p "$base" -m 'new base for verification')
    git -C "$repo" rebase --onto "$new_base" "$base" fixture-task >/dev/null 2>&1
    tip=$(git -C "$repo" rev-parse HEAD)
    git -C "$repo" checkout -q unrelated
    [[ $tip != "$old_tip" ]] || fail 'fixture: rebase did not change the branch tip'
    [[ $(git -C "$work8" rev-parse HEAD) == "$old_tip" ]] || fail 'fixture: worker tip moved'
    # Prove the checks themselves run at the new tip, not just the report.
    checks="test -f out.txt && test \"\$(git rev-parse HEAD)\" = $tip"
    jq --arg checks "$checks" '.checks = $checks' "$(rec "$id8")" > "$scratch/rebased"
    mv "$scratch/rebased" "$(rec "$id8")"
    obj=$(bash "$ops/loom" verify "$id8") || fail "verify after rebase failed: $obj"
    jq -e --arg tip "$tip" '.ok == true and (.fact | endswith(" at " + $tip))' <<< "$obj" >/dev/null || fail 'verify did not report the rebased tip'
    jq -e --arg tip "$tip" --arg old "$old_tip" '.collected_sha == $old and .checks_runs[-1].sha == $tip and .checks_runs[-1].exit == 0 and .reports[-1].state == "ready" and (.reports[-1].fact | contains($tip))' "$(rec "$id8")" >/dev/null || fail 'rebased check record or report names the wrong SHA'

    # A missing collected branch must never fall back to the old worker tip.
    runs=$(jq '.checks_runs | length' "$(rec "$id8")")
    git -C "$repo" update-ref -d refs/heads/fixture-task "$tip"
    rc=0; err=$(bash "$ops/verify.sh" "$id8" 2>&1) || rc=$?
    [[ $rc == 1 && $err == *'consumer checkout has no branch fixture-task'*"$old_tip"* ]] || fail "missing collected branch not refused: $err"
    [[ $(jq '.checks_runs | length' "$(rec "$id8")") == "$runs" ]] || fail 'missing branch recorded a check run'
    git -C "$repo" update-ref refs/heads/fixture-task "$tip"

    # Deterministically move the consumer branch while its checks are running.
    printf -v checks 'git -C %q update-ref refs/heads/fixture-task %q %q' "$repo" "$old_tip" "$tip"
    jq --arg checks "$checks" '.checks = $checks' "$(rec "$id8")" > "$scratch/moved"
    mv "$scratch/moved" "$(rec "$id8")"
    rc=0; obj=$(bash "$ops/loom" verify "$id8") || rc=$?
    [[ $rc == 1 ]] || fail 'verify passed after the branch moved during checks'
    jq -e --arg tip "$tip" --arg old "$old_tip" '.ok == false and (.fact | contains("checked " + $tip)) and (.fact | contains("current " + $old))' <<< "$obj" >/dev/null || fail 'moved branch refusal must name both SHAs'
    jq -e --arg tip "$tip" '.checks_runs[-1].sha == $tip and .checks_runs[-1].exit == 0 and .reports[-1].state == "failed"' "$(rec "$id8")" >/dev/null || fail 'moved branch must preserve the actual check result without certifying it'
)
pass 'verify: collected rebased tip checked and reported; missing or moving branch refused (#74)'

# --- rendered tickets cannot drift (gap #8) ---
if bash "$ops/ticket.sh" "$scratch/consumer.toml" --short Bad_Name --title t --scope s --out o --done d --dry-run >/dev/null 2>&1; then fail 'unparseable short name rendered'; fi
if bash "$ops/ticket.sh" "$scratch/consumer.toml" --short ok-name --title t --scope $'two\nlines' --out o --done d --dry-run >/dev/null 2>&1; then fail 'multi-line field accepted'; fi
body=$(bash "$ops/ticket.sh" "$scratch/consumer.toml" --short rendered-task --title 'Render me' --scope 'write `x`; and $(not this)' --out 'everything else' --done 'checks exit 0' --dry-run)
# shellcheck disable=SC2016  # the literal text is the point
[[ $body == *'**Scope:** write `x`; and $(not this)'* ]] || fail 'ticket text must be literal, never evaluated'
url=$(bash "$ops/ticket.sh" "$scratch/consumer.toml" --short rendered-task --title 'Render me' --scope s --out o --done d)
[[ $url == */issues/9 ]] || fail "ticket.sh did not open the issue: $url"
out=$(dispatch_n 9) || fail 'dispatch refused a rendered ticket'
[[ ${out##*$'\n'} == rendered-task.1 ]] || fail 'rendered ticket dispatched under the wrong name'
pass 'ticket.sh renders the template; dispatch accepts it; text stays literal'

# --- the heartbeat (gap #6) ---
out=$(dispatch); idh=${out##*$'\n'}
bash "$ops/launch.sh" "$idh" -- bash -c 'sleep 2; printf "state: ready — slow but fine\n" >> REPORT.md' >/dev/null &
pids+=("$!")
within 30 bash "$ops/heartbeat.sh" --until "$idh" --every 1 > "$scratch/hb1" || fail 'heartbeat failed'
grep -q "^$idh"$'\t'"ready"$'\t'"slow but fine$" "$scratch/hb1" || fail 'heartbeat must end with status'
out=$(dispatch); idk=${out##*$'\n'}
bash "$ops/launch.sh" "$idk" -- bash "$scratch/bin/w-hang" >/dev/null 2>&1 &
pids+=("$!")
within 30 bash "$ops/heartbeat.sh" --until "$idk" --every 1 --limit-min 0 > "$scratch/hb2" || fail 'heartbeat failed'
grep -q "$idk failed watchdog_kill" "$scratch/hb2" || fail 'heartbeat must surface the watchdog action'
if bash "$ops/heartbeat.sh" --until nobody.1 --every 1 >/dev/null 2>&1; then fail 'heartbeat on a missing assignment'; fi
pass 'heartbeat ends on settle, surfaces kills, ends with status'

# --- children get the caller's umask, not loom's private 077 (gap #19) ---
(
    umask 022
    # shellcheck disable=SC2016  # $(umask) must reach the checks unexpanded
    sed 's/^checks = "true"$/checks = "test $(umask) = 0022"/' "$scratch/consumer.toml" > "$scratch/umask.toml"
    out=$(bash "$ops/dispatch.sh" "$scratch/umask.toml" 7); idu=${out##*$'\n'}
    bash "$ops/launch.sh" "$idu" -- bash -c 'printf "state: ready — umask %s\n" "$(umask)" >> REPORT.md' >/dev/null
    jq -e '.reports[-1].fact == "umask 0022"' "$(rec "$idu")" >/dev/null || fail "worker ran under loom's umask: $(jq -r '.reports[-1].fact' "$(rec "$idu")")"
    bash "$ops/verify.sh" "$idu" --baseline >/dev/null 2>&1 || fail "checks ran under loom's umask"
)
pass "workers and checks run under the caller's umask"

# --- a versioned consumer config must be committed (gap #20) ---
mkdir -p "$scratch/cfg"
git -C "$scratch/cfg" init -q
cp "$scratch/consumer.toml" "$scratch/cfg/consumer.toml"
git -C "$scratch/cfg" add consumer.toml
git -C "$scratch/cfg" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m cfg
cfgsha=$(git -C "$scratch/cfg" rev-parse HEAD)
out=$(bash "$ops/dispatch.sh" "$scratch/cfg/consumer.toml" 7) || fail 'committed config refused'
jq -e --arg c "$cfgsha" '.config_commit == $c' "$(rec "${out##*$'\n'}")" >/dev/null || fail 'config commit not pinned in the record'
printf '# drift\n' >> "$scratch/cfg/consumer.toml"
if bash "$ops/dispatch.sh" "$scratch/cfg/consumer.toml" 7 >/dev/null 2>&1; then fail 'uncommitted config accepted'; fi
jq -e '.config_commit == null' "$(rec "$id1")" >/dev/null || fail 'unversioned config must record null'
pass 'versioned config: committed is pinned, uncommitted is refused'

# --- consumer commit hooks: fixers get a retry, rejections get a log (gap #22) ---
(
    mkdir -p "$scratch/hooks"
    cat > "$scratch/hooks/pre-commit" <<'EOF'
#!/bin/sh
# A fixer: rewrites TODO to DONE in staged files and fails, like ruff-format.
# A gate: rejects any staged file containing REJECT.
for f in $(git diff --cached --name-only); do
    grep -q REJECT "$f" && { echo "hook: rejected $f"; exit 1; }
    if grep -q TODO "$f"; then sed -i.bak 's/TODO/DONE/' "$f"; rm -f "$f.bak"; echo "hook: fixed $f"; exit 1; fi
done
exit 0
EOF
    chmod +x "$scratch/hooks/pre-commit"
    printf '[core]\n\thooksPath = %s\n' "$scratch/hooks" > "$scratch/hooks.gitconfig"
    export GIT_CONFIG_GLOBAL="$scratch/hooks.gitconfig"
    out=$(dispatch); workf=${out%$'\n'*}; idf=${out##*$'\n'}
    bash "$ops/launch.sh" "$idf" -- bash -c 'printf "TODO\n" > fixme.txt; printf "state: ready — wrote fixme\n" >> REPORT.md' >/dev/null
    [[ $(git -C "$workf" show HEAD:fixme.txt) == DONE ]] || fail 'fixer hook output not sealed after retry'
    [[ -z $(git -C "$workf" status --porcelain) ]] || fail 'workdir dirty after a fixer hook'
    jq -e '.reports[-1].fact == "wrote fixme"' "$(rec "$idf")" >/dev/null || fail "fixer retry must be clean: $(jq -r '.reports[-1].fact' "$(rec "$idf")")"
    out=$(dispatch); idr=${out##*$'\n'}
    bash "$ops/launch.sh" "$idr" -- bash -c 'printf "REJECT\n" > bad.txt; printf "state: ready — wrote bad\n" >> REPORT.md' >/dev/null
    jq -e '.reports[-1].fact | endswith("[loom commit rejected by the consumer'"'"'s hooks: '"$idr"'.commit.log]")' "$(rec "$idr")" >/dev/null || fail 'rejection not named'
    grep -q "hook: rejected bad.txt" "$LOOM_STATE/$idr.commit.log" || fail 'hook output not logged'
)
pass "consumer commit hooks: fixers retried, rejections logged"

# --- the Orca executor: detect, start, harvest, stop, stale (gaps #25, #26) ---
(
    cat > "$scratch/bin/orca" <<'EOF'
#!/usr/bin/env bash
# Stub of the Orca CLI: real git worktrees, a background "agent", guarded stops.
set -eu
case "$1" in
    status)
        if [[ ${ORCA_STUB_MODE:-ready} == ready ]]; then
            printf 'appRunning: true\nruntimeState: ready\nruntimeReachable: true\nruntimeId: stub-runtime-1\n'
        else
            printf 'appRunning: false\nruntimeState: stopped\nruntimeReachable: false\n'
        fi ;;
    orchestration)
        case "$2" in
            worker-start)
                [[ ${ORCA_STUB_FAIL:-0} != unknown ]] || { echo '{"ok":false,"result":{"dispatchId":"disp-unknown","state":"failed","failedStage":"agent_readiness"}}'; exit 1; }
                [[ ${ORCA_STUB_FAIL:-0} == 0 ]] || { echo '{"ok":false,"failedStage":"spawn"}'; exit 1; }
                allargs="$*"
                shift 2; name='' repo='' base='' spec=''
                while [[ $# -gt 0 ]]; do
                    case $1 in
                        --name) name=$2; shift 2 ;; --repo) repo=${2#path:}; shift 2 ;;
                        --base-branch) base=$2; shift 2 ;; --spec-file) spec=$2; shift 2 ;; *) shift ;;
                    esac
                done
                ws="$GH_STATE/orca-ws/$name"
                mkdir -p "$GH_STATE/orca-ws"
                git -C "$repo" worktree add -q -b "orca/$name" "$ws" "$base" >/dev/null 2>&1
                cp "$spec" "$GH_STATE/spec-$name.md"
                ( cd "$ws" && exec bash "$ORCA_STUB_WORKER" ) </dev/null >/dev/null 2>&1 &
                printf '%s\n' "$!" > "$GH_STATE/disp-$name.pid"
                printf '%s\n' "$allargs" > "$GH_STATE/start-$name.args"
                # Real receipt shape (gap #29): workspace is "<repo-id>::<path>", no worktree.path.
                jq -n --arg d "disp-$name" --arg w "$ws" '{ok: true, result: {dispatchId: $d, taskId: "task-1", runId: "run-1", workspace: ("repo-stub::" + $w), terminal: {id: "term-1"}, keptOpen: true}}' ;;
            worker-stop)
                if [[ ${ORCA_STUB_STOP:-ok} == unknown ]]; then echo '{"ok":false,"error":{"code":"stop_unknown"}}'; exit 1; fi
                kill -KILL "$(cat "$GH_STATE/$4.pid")" 2>/dev/null || :
                echo '{"ok":true,"result":{"status":"stopped"}}' ;;
            worker-release)
                if [[ ${ORCA_STUB_RELEASE:-ok} == fail ]]; then echo '{"ok":false}'; exit 1; fi
                echo '{"ok":true,"result":{"released":true}}' ;;
            worker-show)
                st='settled'
                [[ -f $GH_STATE/show-$4 ]] && st=$(cat "$GH_STATE/show-$4")
                [[ $st != notfound ]] || { echo '{"ok":false,"error":{"code":"dispatch_not_found"}}'; exit 1; }
                if [[ -f $GH_STATE/view-$4 ]]; then cat "$GH_STATE/view-$4"; exit "${ORCA_SHOW_EXIT:-0}"; fi
                state=completed; live=idle
                if [[ $st == active ]]; then state=dispatched; live=live; fi
                jq -n --arg d "$4" --arg s "$state" --arg l "$live" --arg w "repo-stub::$GH_STATE/orca-ws/${4#disp-}" \
                    '{ok: true, result: {dispatch: {id: $d, taskId: "task-1", runId: "run-1", status: $s}, worker: {state: "ready"}, projection: {workspace: {id: $w}, liveness: {verdict: $l}, resource: {terminalState: "retained"}}}}' ;;
            worker-read)
                echo '{"ok":true,"result":{"source":"transcript","text":"worker transcript"}}' ;;
            worker-abandon)
                echo '{"ok":true,"result":{"status":"abandoned","stopped":false}}' ;;
            worker-keep-open)
                echo '{"ok":true,"result":{"keptOpen":true}}' ;;
            worker-list)
                echo '{"ok":true,"result":{"workers":[{"dispatchId":"disp-listed","terminalState":"settled","agent":"codex","name":"listed"}]}}' ;;
            request-show)
                echo '{"ok":true,"result":{"request":"applied"}}' ;;
            check)
                [[ $* == *--peek* ]] || exit 97
                echo '{"ok":true,"result":{"messages":[]}}' ;;
            inbox)
                echo '{"ok":true,"result":{"messages":[]}}' ;;
            send)
                printf '%s\n' "$*" > "$GH_STATE/send.args"
                if [[ -n ${ORCA_SEND_RECEIPT:-} ]]; then cat "$ORCA_SEND_RECEIPT"; exit "${ORCA_SEND_EXIT:-0}"; fi
                jq -n --arg d "${4#dispatch:}" '{ok:true,result:{messageId:"message-stub",dispatchId:$d,queuedFor:"worker"}}' ;;
            ask|reply)
                shift 2
                echo "{\"ok\":true,\"result\":{\"args\":\"$*\"}}" ;;
            gate-create|gate-resolve|gate-list)
                echo '{"ok":true,"result":{"gate":"g1"}}' ;;
            task-create|task-update)
                echo '{"ok":true,"result":{"task":"t1"}}' ;;
            run-create|run-use|run-current|run-show|run-list)
                echo '{"ok":true,"result":{"run":"r1"}}' ;;
            *) exit 98 ;;
        esac ;;
    host)
        [[ $2 == list ]] || exit 98
        echo '{"ok":true,"result":{"hosts":[{"kind":"ssh","name":"orca-host","id":"ssh-on","connected":true,"selector":"--host ssh:ssh-on"},{"kind":"ssh","name":"orca-off","id":"ssh-off","connected":false,"selector":"--host ssh:ssh-off"},{"kind":"environment","name":"orca-dup","id":"env-dup","connected":null,"selector":"--environment orca-dup"},{"kind":"ssh","name":"orca-dup","id":"ssh-dup","connected":true,"selector":"--host ssh:ssh-dup"},{"kind":"ssh","name":"orca-bare","id":"ssh-bare","connected":true,"selector":"--host ssh:ssh-bare"}]}}' ;;
    project)
        [[ $2 == setups ]] || exit 98
        envname=''; [[ ${3:-} == --environment ]] && envname=$4
        case $envname in
            orca-host|orca-dup)
                jq -n --arg p "${ORCA_STUB_REMOTE_REPO:-/nonexistent}" '{ok: true, result: {setups: [{projectId: "github:example/fixture", hostId: "local", path: $p, setupState: "ready"}, {projectId: "github:example/fixture", hostId: "ssh-x", path: "/wrong", setupState: "ready"}]}}' ;;
            *) echo '{"ok":true,"result":{"setups":[]}}' ;;
        esac ;;
    reference|worktree|repo|automations)
        echo '{"ok":true,"result":{"stub":"ok"}}' ;;
    *) exit 99 ;;
esac
EOF
    chmod +x "$scratch/bin/orca"
    export LOOM_ORCA="$scratch/bin/orca"
    cat > "$scratch/bin/w-slow" <<'EOF'
sleep 1
mkdir -p .loom
printf 'log\n' > .loom/discovery.log
printf 'notes\n' > notes.txt
printf 'state: ready — wrote notes.txt\n' >> REPORT.md
EOF

    # detection
    ORCA_STUB_MODE=down bash "$ops/orca.sh" detect >/dev/null && fail 'detect: down runtime reported ready'
    [[ $(bash "$ops/orca.sh" detect) == 'orca ready: runtime stub-runtime-1' ]] || fail 'detect: ready runtime not reported'
    obj=$(bash "$ops/loom" capacity)
    jq -e '.ok == true and (.fact | test("suggested workers: [1-9]"))' <<< "$obj" >/dev/null || fail "capacity: $obj"
    sed 's/^checks = "true"$/checks = "true"\nexecutor = "orca"/' "$scratch/consumer.toml" > "$scratch/orca.toml"
    ORCA_STUB_MODE=down bash "$ops/dispatch.sh" "$scratch/orca.toml" 7 >/dev/null 2>&1 && fail 'required orca not ready: dispatch accepted'
    bash "$ops/dispatch.sh" "$scratch/orca.toml" 7 --executor local >/dev/null 2>&1 && fail 'consumer requires orca: --executor local accepted'

    # auto picks Orca when it is ready; no clone, WORK.md kept in state
    out=$(dispatch); ido=${out##*$'\n'}
    [[ $out == orca:* ]] || fail "auto with Orca ready must use the orca executor: $out"
    jq -e '.executor == {kind: "orca", state: "pending", runtime: "stub-runtime-1"} and .workdir == ""' "$(rec "$ido")" >/dev/null || fail 'orca record shape'
    [[ -f $LOOM_STATE/$ido.WORK.md ]] || fail 'orca WORK.md not kept in state'

    # nothing starts outside Orca
    bash "$ops/launch.sh" "$ido" -- bash "$scratch/bin/w-files" >/dev/null 2>&1 && fail 'launch.sh started an Orca assignment'
    out=$(bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7 --executor local); idl=${out##*$'\n'}
    bash "$ops/launch.sh" "$idl" -- bash "$scratch/bin/w-files" >/dev/null 2>&1 && fail 'launch.sh started a local worker while Orca is available'
    LOOM_ALLOW_LOCAL=1 bash "$ops/launch.sh" "$idl" -- bash "$scratch/bin/w-files" >/dev/null || fail 'explicit LOOM_ALLOW_LOCAL override refused'

    # start: refused when Orca is down; otherwise Orca's worktree is adopted
    ORCA_STUB_MODE=down bash "$ops/orca.sh" start "$ido" >/dev/null 2>&1 && fail 'start with Orca down'
    jq -e '.executor.state == "pending"' "$(rec "$ido")" >/dev/null || fail 'a refused start changed state'
    export ORCA_STUB_WORKER="$scratch/bin/w-slow"
    bash "$ops/orca.sh" start "$ido" >/dev/null || fail 'orca start failed'
    bash "$ops/verify.sh" "$ido" --baseline >/dev/null || fail 'baseline refused while the worker runs (gap #32)'
    bash "$ops/verify.sh" "$ido" >/dev/null 2>&1 && fail 'branch verify allowed while the worker runs'
    ws="$GH_STATE/orca-ws/$ido"
    jq -e --arg w "$ws" --arg b "orca/$ido" '.workdir == $w and .branch == $b and .executor.state == "running" and .executor.dispatch == "disp-'"$ido"'" and .worker_pid == null' "$(rec "$ido")" >/dev/null || fail "orca start record: $(jq -c . "$(rec "$ido")")"
    grep -q "loom worker for assignment $ido" "$GH_STATE/spec-$ido.md" || fail 'spec not handed to Orca'
    bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7 >/dev/null 2>&1 && fail 'twin dispatch while an Orca worker runs'
    ! bash "$ops/status.sh" | grep -q "^$ido" || fail 'a running Orca worker must be silent'
    bash "$ops/orca.sh" start "$ido" >/dev/null 2>&1 && fail 'double start accepted'
    pid=$(cat "$GH_STATE/disp-$ido.pid"); for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    # Start already excluded .loom/. Strip it so harvest's own exclude is what is under test.
    sed -i.orig '/^\.loom\/$/d' "$(git -C "$ws" rev-parse --git-common-dir)/info/exclude"
    [[ $(bash "$ops/orca.sh" harvest "$ido") == "$ido ready (harvested from orca dispatch disp-$ido)" ]] || fail 'harvest outcome'
    [[ $(git -C "$ws" log -1 --format=%s) == "loom($ido): ready — wrote notes.txt" ]] || fail 'orca worker files not committed'
    ! git -C "$ws" ls-files | grep -qE '^(WORK|REPORT)\.md$' || fail 'loom files committed from an Orca worktree'
    [[ -f $LOOM_STATE/$ido.evidence/discovery.log ]] || fail 'evidence not copied out of the workspace'
    ! git -C "$ws" ls-files | grep -q '^\.loom/' || fail '.loom evidence was committed'
    bash "$ops/orca.sh" release "$ido" >/dev/null 2>&1 && fail 'release before collect'
    jq -e '.executor.released != true and .collected_sha == null' "$(rec "$ido")" >/dev/null || fail 'a refused release changed the record'
    [[ $(bash "$ops/collect.sh" "$ido") == *'1 commit(s) over base'* ]] || fail 'collect of an Orca branch'
    jq -e '.collected_sha | test("^[0-9a-f]{40}$")' "$(rec "$ido")" >/dev/null || fail 'collect did not record the sha'
    grep -q "^$ido"$'\t'"release"$'\t' <<< "$(bash "$ops/status.sh")" || fail 'kept-open workspace not surfaced'
    bash "$ops/verify.sh" "$ido" >/dev/null || fail 'verify of an Orca branch'
    bash "$ops/orca.sh" release "$ido" >/dev/null || fail 'release after collect failed'
    jq -e '.executor.released == true' "$(rec "$ido")" >/dev/null || fail 'release not recorded'
    ! grep -q "^$ido"$'\t'"release"$'\t' <<< "$(bash "$ops/status.sh")" || fail 'released workspace still in status'
    bash "$ops/orca.sh" release "$ido" >/dev/null 2>&1 && fail 'double release accepted'

    # Follow-up lifecycle: already settled/released assignment, new dispatch.
    # Fixtures use full worker-show envelopes with deliberately distracting metadata.
    fixture_view() {
        jq -n --arg d "$1" --arg p "$2" --arg s "$3" --arg l "$4" --arg w "repo-stub::$ws" '
          {ok:true,result:{dispatch:{id:$d,taskId:("task-"+$d),runId:"run-1",followUpOf:$p,status:$s},
           worker:{state:"ready"},projection:{workspace:{id:$w},liveness:{verdict:$l},resource:{terminalState:"retained"}},
           unrelated:{status:"completed",dispatchId:$d}}}'
    }
    fixture_view follow-one "disp-$ido" dispatched live > "$GH_STATE/view-follow-one"
    jq -n --arg p "disp-$ido" '{ok:true,result:{delivery:"resumed",followUpOf:$p,dispatchId:"follow-one",state:"ready"}}' > "$scratch/send.receipt"
    # Legacy raw dispatch selectors must resolve to exactly one assignment.
    rm -f "$GH_STATE/send.args"
    bash "$ops/loom" send unknown-dispatch --subject continue >/dev/null 2>&1 && fail 'unknown raw dispatch sent'
    [[ ! -f $GH_STATE/send.args ]] || fail 'unknown dispatch had a delivery side effect'
    cp "$(rec "$ido")" "$LOOM_STATE/duplicate-dispatch.json"
    bash "$ops/loom" send "disp-$ido" --subject continue >/dev/null 2>&1 && fail 'ambiguous raw dispatch sent'
    [[ ! -f $GH_STATE/send.args ]] || fail 'ambiguous dispatch had a delivery side effect'
    rm "$LOOM_STATE/duplicate-dispatch.json"
    cp "$(rec "$ido")" "$scratch/before-placement"
    jq '.compute = ["declared-remote"]' "$(rec "$ido")" > "$scratch/wrong-placement"
    mv "$scratch/wrong-placement" "$(rec "$ido")"
    bash "$ops/loom" send "$ido" --subject continue >/dev/null 2>&1 && fail 'continuation fell back to a local worker'
    cp "$scratch/before-placement" "$(rec "$ido")"
    ORCA_SEND_RECEIPT="$scratch/send.receipt" bash "$ops/loom" send "disp-$ido" --subject continue --body review > "$scratch/send.out" || fail 'follow-up send failed'
    grep -q -- "--to dispatch:disp-$ido" "$GH_STATE/send.args" || fail 'send used assignment id as dispatch'
    jq -e '.executor.dispatch == "follow-one" and .executor.task == "task-follow-one" and .executor.state == "running" and
        .report_offset == 1 and .collected_sha == null and .executor.released == null and (.reports | length) == 2' "$(rec "$ido")" >/dev/null || fail "follow-up not tracked or old completion reused: $(jq -c . "$(rec "$ido")")"
    archive=$(jq -r '.executor.history[-1].archive' "$(rec "$ido")")
    [[ -s $LOOM_STATE/$archive/$ido.evidence/discovery.log ]] || fail 'old evidence lost on continuation'
    cp "$(rec "$ido")" "$scratch/before-denial"
    oldhead=$(git -C "$ws" rev-parse HEAD)
    printf 'follow-up change\n' >> "$ws/notes.txt"
    printf 'state: ready — follow-up finished\n' >> "$ws/REPORT.md"
    # Every refused read must leave assignment, report offset, index and HEAD alone.
    for mode in live unknown failed worker-failed nested wrong malformed false transport retained compact-live compact-unknown; do
        fixture_view follow-one "disp-$ido" completed idle > "$scratch/good-view"
        case $mode in
            live) jq '.result.projection.liveness.verdict = "live"' "$scratch/good-view" ;;
            unknown) jq '.result.projection.liveness.verdict = "unverifiable"' "$scratch/good-view" ;;
            failed) jq '.result.dispatch.status = "failed"' "$scratch/good-view" ;;
            worker-failed) jq '.result.worker.state = "failed"' "$scratch/good-view" ;;
            compact-live) printf '%s\n' '{"ok":true,"result":{"dispatchId":"follow-one","state":"ready","liveness":"live","terminalState":"retained","metadata":{"status":"completed"}}}' ;;
            compact-unknown) printf '%s\n' '{"ok":true,"result":{"dispatchId":"follow-one","terminalState":"retained","metadata":{"status":"completed"}}}' ;;
            nested) jq '.result.dispatch.status = "dispatched" | .result.worker.metadata = {state:"completed"}' "$scratch/good-view" ;;
            wrong) jq '.result.dispatch.id = "another-dispatch"' "$scratch/good-view" ;;
            malformed) printf 'not json\n' ;;
            false) jq '.ok = false' "$scratch/good-view" ;;
            transport) cat "$scratch/good-view" ;;
            retained) jq '.result.dispatch |= del(.status)' "$scratch/good-view" ;;
        esac > "$GH_STATE/view-follow-one"
        rc=0
        if [[ $mode == transport ]]; then
            ORCA_SHOW_EXIT=1 bash "$ops/loom" harvest "$ido" > "$scratch/denied" || rc=$?
        else
            bash "$ops/loom" harvest "$ido" > "$scratch/denied" || rc=$?
        fi
        [[ $rc != 0 ]] || fail "unsafe harvest accepted: $mode"
        jq -e '.ok == false' "$scratch/denied" >/dev/null || fail 'harvest refusal lost JSON envelope'
        cmp -s "$(rec "$ido")" "$scratch/before-denial" || fail "refused harvest changed state: $mode"
        [[ $(git -C "$ws" rev-parse HEAD) == "$oldhead" && -z $(git -C "$ws" diff --cached --name-only) ]] || fail "refused harvest touched git: $mode"
    done
    cp "$scratch/good-view" "$GH_STATE/view-follow-one"
    bash "$ops/loom" harvest "$ido" >/dev/null || fail 'completed follow-up harvest failed'
    jq -e '.executor.state == "settled" and .reports[-1].fact == "follow-up finished" and (.reports | length) == 3 and .report_offset == 2' "$(rec "$ido")" >/dev/null || fail 'second harvest reused initial report'
    bash "$ops/loom" harvest "$ido" >/dev/null 2>&1 && fail 'duplicate follow-up harvest accepted'
    [[ $(git -C "$ws" rev-list --count "$oldhead..HEAD") == 1 ]] || fail 'second harvest did not commit continuation exactly once'
    # Recovery for old Loom records after an external coordinator send: infer
    # the boundary from the unique prior report, never from the new last line.
    jq 'del(.harvest_report_lines) | .report_offset = 0' "$(rec "$ido")" > "$scratch/legacy"
    mv "$scratch/legacy" "$(rec "$ido")"
    printf 'recovered change\n' >> "$ws/notes.txt"
    printf 'state: ready — recovered review\n' >> "$ws/REPORT.md"
    fixture_view follow-two follow-one completed idle > "$GH_STATE/view-follow-two"
    cp "$(rec "$ido")" "$scratch/before-reconcile"
    for mode in parent workspace run task; do
        case $mode in
            parent) jq '.result.dispatch.followUpOf = "unrelated"' "$GH_STATE/view-follow-two" ;;
            workspace) jq '.result.projection.workspace.id = "other::/elsewhere"' "$GH_STATE/view-follow-two" ;;
            run) jq '.result.dispatch.runId = "another-run"' "$GH_STATE/view-follow-two" ;;
            task) jq '.result.dispatch.taskId = "task-follow-one"' "$GH_STATE/view-follow-two" ;;
        esac > "$GH_STATE/view-bad-followup"
        jq '.result.dispatch.id = "bad-followup"' "$GH_STATE/view-bad-followup" > "$scratch/bad"
        mv "$scratch/bad" "$GH_STATE/view-bad-followup"
        bash "$ops/loom" reconcile "$ido" --dispatch bad-followup >/dev/null 2>&1 && fail "reconcile accepted wrong $mode"
        cmp -s "$(rec "$ido")" "$scratch/before-reconcile" || fail 'rejected reconcile changed record'
    done
    cp "$ws/REPORT.md" "$scratch/report-before-ambiguous"
    printf 'state: ready — follow-up finished\n' >> "$ws/REPORT.md"
    bash "$ops/loom" reconcile "$ido" --dispatch follow-two >/dev/null 2>&1 && fail 'ambiguous legacy report boundary accepted'
    cmp -s "$(rec "$ido")" "$scratch/before-reconcile" || fail 'ambiguous boundary changed assignment'
    cp "$scratch/report-before-ambiguous" "$ws/REPORT.md"
    bash "$ops/loom" reconcile "$ido" --dispatch follow-two >/dev/null || fail 'legacy completed follow-up recovery failed'
    jq -e '.executor.dispatch == "follow-two" and .report_offset == 2' "$(rec "$ido")" >/dev/null || fail 'legacy recovery lost report boundary'
    bash "$ops/loom" harvest "$ido" >/dev/null || fail 'recovered review harvest failed'
    jq -e '.reports[-1].fact == "recovered review" and (.reports | length) == 4' "$(rec "$ido")" >/dev/null || fail 'recovered review not folded'
    # Same-dispatch reconcile is idempotent; it never authorizes another harvest.
    bash "$ops/loom" reconcile "$ido" --dispatch follow-two >/dev/null || fail 'idempotent reconcile failed'
    bash "$ops/loom" harvest "$ido" >/dev/null 2>&1 && fail 'same-dispatch recovery reopened settled work'
    fixture_view follow-three follow-two completed idle > "$GH_STATE/view-follow-three"
    bash "$ops/loom" reconcile "$ido" --dispatch follow-three >/dev/null || fail 'silent continuation reconcile failed'
    bash "$ops/loom" harvest "$ido" >/dev/null || fail 'silent completed continuation harvest failed'
    jq -e '.reports[-1].state == "failed" and .reports[-1].fact == "worker_done_without_report (orca)"' "$(rec "$ido")" >/dev/null || fail 'continuation without new report reused old ready'
    # Failed sends remain fenced, including the old completed dispatch.
    ORCA_SEND_RECEIPT="$scratch/send.receipt" ORCA_SEND_EXIT=1 bash "$ops/loom" send "$ido" --subject uncertain >/dev/null 2>&1 && fail 'failed send accepted'
    bash "$ops/loom" reconcile "$ido" --dispatch follow-three >/dev/null 2>&1 && fail 'old completion cleared uncertain send'
    bash "$ops/loom" collect "$ido" >/dev/null 2>&1 && fail 'uncertain continuation collected'
    bash "$ops/loom" release "$ido" >/dev/null 2>&1 && fail 'uncertain continuation released'
    # A verified child resolves the uncertain send, with no duplicate delivery.
    fixture_view follow-four follow-three completed idle > "$GH_STATE/view-follow-four"
    bash "$ops/loom" reconcile "$ido" --dispatch follow-four >/dev/null || fail 'uncertain send recovery failed'
    bash "$ops/loom" harvest "$ido" >/dev/null || fail 'uncertain send recovered harvest failed'
    # Remote queue acknowledgement on a settled assignment cannot establish
    # whether a follow-up will be created asynchronously. Keep it fenced.
    bash "$ops/loom" collect "$ido" >/dev/null || fail 'collect before queued continuation failed'
    printf '%s\n' '{"ok":true,"result":{"messageId":"queued-message","dispatchId":"follow-four","queuedFor":"worker"}}' > "$scratch/queued.receipt"
    ORCA_SEND_RECEIPT="$scratch/queued.receipt" bash "$ops/loom" send "$ido" --subject continue >/dev/null 2>&1 && fail 'settled queue-only receipt accepted as resolved'
    jq -e '.executor.continuation_pending == true and .executor.state == "settled" and .executor.dispatch == "follow-four"' "$(rec "$ido")" >/dev/null || fail 'settled queue-only receipt dropped continuation fence'
    bash "$ops/loom" collect "$ido" >/dev/null 2>&1 && fail 'queued settled continuation collected stale work'
    bash "$ops/loom" release "$ido" >/dev/null 2>&1 && fail 'queued settled continuation released stale work'
    bash "$ops/loom" reconcile "$ido" --dispatch follow-four >/dev/null 2>&1 && fail 'old dispatch resolved queued continuation'
    fixture_view follow-five follow-four completed idle > "$GH_STATE/view-follow-five"
    bash "$ops/loom" reconcile "$ido" --dispatch follow-five >/dev/null || fail 'queued continuation child reconcile failed'
    bash "$ops/loom" harvest "$ido" >/dev/null || fail 'queued continuation child harvest failed'
    # Real worker-show schema after completion telemetry expires: retained
    # resources and stale_status cannot erase durable exact-dispatch success.
    fixture_view follow-durable follow-five completed unverifiable | jq '
      .result.dispatch.completedAt = "2026-01-01T00:00:00Z" |
      .result.worker = {dispatchId:"follow-durable",state:"succeeded"} |
      .result.projection.outcome = "succeeded" |
      .result.projection.evidence = {durable:true,liveStatus:"stale"} |
      .result.projection.liveness.reason = "stale_status"
    ' > "$scratch/durable-view"
    cp "$scratch/durable-view" "$GH_STATE/view-follow-durable"
    bash "$ops/loom" reconcile "$ido" --dispatch follow-durable >/dev/null || fail 'durable completed review reconcile failed'
    printf 'durable review change\n' >> "$ws/notes.txt"
    printf 'state: ready — durable review finished\n' >> "$ws/REPORT.md"
    cp "$(rec "$ido")" "$scratch/before-durable-denial"
    oldhead=$(git -C "$ws" rev-parse HEAD)
    for mode in timestamp durable live-status reason outcome worker-id projection-id worker-state live failed; do
        case $mode in
            timestamp) jq 'del(.result.dispatch.completedAt)' "$scratch/durable-view" ;;
            durable) jq '.result.projection.evidence.durable = false' "$scratch/durable-view" ;;
            live-status) jq '.result.projection.evidence.liveStatus = "unknown"' "$scratch/durable-view" ;;
            reason) jq '.result.projection.liveness.reason = "no_observation"' "$scratch/durable-view" ;;
            outcome) jq '.result.projection.outcome = "failed"' "$scratch/durable-view" ;;
            worker-id) jq '.result.worker.dispatchId = "unrelated"' "$scratch/durable-view" ;;
            projection-id) jq '.result.projection.dispatchId = "unrelated"' "$scratch/durable-view" ;;
            worker-state) jq '.result.worker.state = "failed"' "$scratch/durable-view" ;;
            live) jq '.result.projection.liveness.verdict = "live"' "$scratch/durable-view" ;;
            failed) jq '.result.dispatch.status = "failed"' "$scratch/durable-view" ;;
        esac > "$GH_STATE/view-follow-durable"
        bash "$ops/loom" harvest "$ido" >/dev/null 2>&1 && fail "unsafe durable completion accepted: $mode"
        cmp -s "$(rec "$ido")" "$scratch/before-durable-denial" || fail 'rejected durable completion changed assignment'
        [[ $(git -C "$ws" rev-parse HEAD) == "$oldhead" && -z $(git -C "$ws" diff --cached --name-only) ]] || fail 'rejected durable completion touched git'
    done
    cp "$scratch/durable-view" "$GH_STATE/view-follow-durable"
    bash "$ops/loom" harvest "$ido" >/dev/null || fail 'durable exact-dispatch success rejected for stale telemetry'
    jq -e '.executor.state == "settled" and .reports[-1].fact == "durable review finished"' "$(rec "$ido")" >/dev/null || fail 'durable completed review not harvested'
    pass 'durable completed success survives stale telemetry; all incomplete or contradictory proofs fail closed'
    pass 'follow-up tracking, fail-closed harvest, identity-bound recovery and evidence preservation'

    # Unversioned configs inside a repo must produce usable records (gap #68).
    mkdir -p "$scratch/cfg/local"
    printf 'ignored.toml\n' > "$scratch/cfg/local/.gitignore"
    for config_name in ignored.toml untracked.toml; do
        cp "$scratch/consumer.toml" "$scratch/cfg/local/$config_name"
        out=$(bash "$ops/dispatch.sh" "$scratch/cfg/local/$config_name" 7) || fail "$config_name config refused"
        idc=${out##*$'\n'}
        jq -e 'has("config_commit") and .config_commit == null' "$(rec "$idc")" >/dev/null || fail "$config_name config must record null"
        ORCA_STUB_WORKER="$scratch/bin/w-files" bash "$ops/loom" start "$idc" >/dev/null || fail "start rejected $config_name config record"
        obj=$(bash "$ops/loom" show "$idc") || fail "show rejected $config_name config record"
        jq -e '.ok == true' <<< "$obj" >/dev/null || fail "show failed for $config_name config record"
        pid=$(cat "$GH_STATE/disp-$idc.pid"); for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
        bash "$ops/orca.sh" harvest "$idc" >/dev/null || fail "harvest failed for $config_name config record"
    done
    pass 'ignored and untracked configs inside a repo record null and start/show accept them'

    # stop: only on a stop Orca confirmed; stale is surfaced, never acted on
    out=$(dispatch); ids=${out##*$'\n'}
    export ORCA_STUB_WORKER="$scratch/bin/w-hang" GRANDCHILD="$scratch/orca-grandchild"
    bash "$ops/orca.sh" start "$ids" >/dev/null || fail 'orca start (hang) failed'
    spid=$(cat "$GH_STATE/disp-$ids.pid"); pids+=("$spid")
    ORCA_STUB_STOP=unknown bash "$ops/orca.sh" stop "$ids" >/dev/null 2>&1 && fail 'stop_unknown claimed as a stop'
    jq -e '.executor.state == "running" and .reports == []' "$(rec "$ids")" >/dev/null || fail 'an unconfirmed stop changed the record'
    jq '.launched_at = "2000-01-01T00:00:00Z" | .started_at = .launched_at' "$(rec "$ids")" > "$scratch/t"; mv "$scratch/t" "$(rec "$ids")"
    st=$(bash "$ops/status.sh" 2>&1) || fail "status failed: $st"
    grep -q "^$ids"$'\t'"stale"$'\t'".*ops/orca.sh stop $ids" <<< "$st" || fail "stale Orca worker not surfaced: $st"
    [[ -z $(bash "$ops/watchdog.sh" --limit-min 0) ]] || fail 'watchdog acted on an Orca worker'
    kill -0 "$spid" || fail 'loom signalled an Orca worker'
    bash "$ops/orca.sh" stop "$ids" >/dev/null || fail 'confirmed stop failed'
    jq -e '.executor.state == "settled" and .reports[-1].state == "failed" and .reports[-1].fact == "stopped via orca by the conductor"' "$(rec "$ids")" >/dev/null || fail 'stop record'
    grep -q "^$ids"$'\t'"failed"$'\t' <<< "$(bash "$ops/status.sh")" || fail 'handled failure missing from status before ack'
    bash "$ops/ack.sh" "$ids" 'owner retired this drill' >/dev/null || fail 'ack failed'
    ! grep -q "^$ids"$'\t'"failed"$'\t' <<< "$(bash "$ops/status.sh")" || fail 'acked failure still in status'
    bash "$ops/ack.sh" "$ids" 'again' >/dev/null 2>&1 && fail 'second ack accepted'

    # a failed start is recorded, never retried
    out=$(dispatch); idf=${out##*$'\n'}
    ORCA_STUB_FAIL=1 bash "$ops/orca.sh" start "$idf" >/dev/null 2>&1 && fail 'failed worker-start reported success'
    jq -e '.executor.state == "failed_start" and (.reports[-1].fact | contains("orca-start.receipt"))' "$(rec "$idf")" >/dev/null || fail 'failed start record'
    bash "$ops/orca.sh" abandon "$idf" >/dev/null 2>&1 && fail 'abandon accepted a failed start with no dispatch'
    # gap #50: a failed start that Orca gave a dispatch can be abandoned through loom
    ORCA_STUB_FAIL=unknown bash "$ops/orca.sh" start "$idf" >/dev/null 2>&1 && fail 'restart of a failed start accepted'
    out=$(dispatch) || fail "dispatch for #50 failed: $out"; idu=${out##*$'\n'}
    ORCA_STUB_FAIL=unknown bash "$ops/orca.sh" start "$idu" >/dev/null 2>&1 && fail 'failed worker-start reported success'
    jq -e '.executor.state == "failed_start" and .executor.dispatch == "disp-unknown"' "$(rec "$idu")" >/dev/null || fail 'failed start lost its dispatch (#50)'
    bash "$ops/orca.sh" abandon "$idu" >/dev/null || fail 'failed start with a dispatch not abandonable (#50)'
    jq -e '.executor.state == "abandoned" and (.reports[-1].fact | startswith("owner_fenced"))' "$(rec "$idu")" >/dev/null || fail 'failed-start abandon record (#50)'
    out=$(dispatch) || fail "dispatch for #50 failed: $out"; idn=${out##*$'\n'}
    ORCA_STUB_FAIL=unknown bash "$ops/orca.sh" start "$idn" >/dev/null 2>&1 && fail 'failed worker-start reported success'
    echo notfound > "$GH_STATE/show-disp-unknown"
    bash "$ops/orca.sh" abandon "$idn" >/dev/null || fail 'abandon of a dispatch Orca forgot failed (#50)'
    jq -e '.executor.state == "abandoned" and (.reports[-1].fact | contains("no longer knows"))' "$(rec "$idn")" >/dev/null || fail 'forgotten dispatch not recorded (#50)'
    rm -f "$GH_STATE/show-disp-unknown"
)
pass 'orca executor: detect, route, start, harvest, stop only on confirmation, stale surfaced'

# --- ticket labels (#38) ---
bash "$ops/ticket.sh" "$scratch/consumer.toml" --short labeled-task --title t --scope s --out o --done d >/dev/null
grep -qx 'loom-ready' "$GH_STATE/issue9.labels" || fail 'default loom-ready label not added'
bash "$ops/ticket.sh" "$scratch/consumer.toml" --short labeled-task --title t --scope s --out o --done d --label custom --label custom >/dev/null
[[ $(grep -c '^custom$' "$GH_STATE/issue9.labels") == 1 ]] || fail 'duplicate label not collapsed'
grep -qx 'loom-ready' "$GH_STATE/issue9.labels" || fail 'explicit labels dropped the default'
bash "$ops/ticket.sh" "$scratch/consumer.toml" --short labeled-task --title t --scope s --out o --done d --no-default-label >/dev/null
! grep -qx 'loom-ready' "$GH_STATE/issue9.labels" || fail '--no-default-label ignored'
pass 'ticket labels: repeatable, default loom-ready, no-default'

# --- loom accept forwards repeatable labels (gap #67) ---
out=$(bash "$ops/loom" accept --consumer "$scratch/consumer.toml" --short accepted-task --title t --scope s --out o --done d) || fail 'loom accept without labels failed'
jq -e '.ok == true and .state == "accepted" and .ticket == 9' <<< "$out" >/dev/null || fail 'loom accept did not return the created ticket'
grep -qx 'loom-ready' "$GH_STATE/issue9.labels" || fail 'loom accept without labels lost the default'
out=$(bash "$ops/loom" accept --consumer "$scratch/consumer.toml" --label custom --short accepted-task --title t --scope s --out o --done d --label 'needs review') || fail 'loom accept rejected repeatable labels'
jq -e '.ok == true and .state == "accepted" and .ticket == 9' <<< "$out" >/dev/null || fail 'labeled loom accept did not return the created ticket'
grep -qx 'custom' "$GH_STATE/issue9.labels" || fail 'loom accept dropped the first label (#67)'
grep -qx 'needs review' "$GH_STATE/issue9.labels" || fail 'loom accept dropped the second label or split its value (#67)'
grep -qx 'loom-ready' "$GH_STATE/issue9.labels" || fail 'loom accept labels dropped the default'
rc=0
out=$(bash "$ops/loom" accept --consumer "$scratch/consumer.toml" --short accepted-task --title t --scope s --out o --done d --label) || rc=$?
[[ $rc == 2 ]] || fail "loom accept --label without a value must exit 2 (got $rc)"
jq -e '.ok == false and (.fact | contains("[--label L]"))' <<< "$out" >/dev/null || fail 'loom accept missing label value did not return usage'
pass 'loom accept: zero or repeatable labels reach issue creation; missing value rejected'

# --- Orca placement and the map (#37, #35) ---
(
    export LOOM_ORCA="$scratch/bin/orca"
    # #47: the worker server has its own clone; loom must name that one.
    export ORCA_STUB_REMOTE_REPO="$scratch/remote-fixture"
    git clone -q "$LOOM_REPO" "$ORCA_STUB_REMOTE_REPO"
    git -C "$ORCA_STUB_REMOTE_REPO" config user.name 'Loom Fixture'
    git -C "$ORCA_STUB_REMOTE_REPO" config user.email "$(git -C "$LOOM_REPO" config user.email)"
    mkdir -p "$scratch/wsbin"
    cat > "$scratch/wsbin/ssh" <<'EOF'
#!/usr/bin/env bash
# ssh stub for workspace hosts: logs the host, runs the command here.
while [[ $1 == -o ]]; do shift 2; done
host=$1; shift
case $host in orca-host|orca-dup|orca-bare) ;; *) exit 255 ;; esac
printf '%s\n' "$host" >> "$GH_STATE/ssh-ws.log"
exec bash -c "$*"
EOF
    chmod +x "$scratch/wsbin/ssh"
    export LOOM_SSH="$scratch/wsbin/ssh"
    sed 's/^checks = "true"$/checks = "true"\nexecutor = "orca"\ncompute = "orca-host"/' "$scratch/consumer.toml" > "$scratch/placement.toml"
    out=$(bash "$ops/dispatch.sh" "$scratch/placement.toml" 7); idp=${out##*$'\n'}
    export ORCA_STUB_WORKER="$scratch/bin/w-slow"
    bash "$ops/orca.sh" start "$idp" >/dev/null || fail 'start on a connected compute host'
    grep -q -- '--on orca-host' "$GH_STATE/start-$idp.args" || fail 'worker not placed on the compute host'
    grep -q -- "--repo path:$ORCA_STUB_REMOTE_REPO " "$GH_STATE/start-$idp.args" || fail 'remote worker given the conductor checkout, not the host clone (#47)'
    jq -e '.ws_host == "orca-host"' "$(rec "$idp")" >/dev/null || fail 'workspace host not recorded (#47)'
    grep -qx orca-host "$GH_STATE/ssh-ws.log" || fail 'remote workspace not reached over ssh (#47)'
    jq -e '.executor.placement.host == "orca-host"' "$(rec "$idp")" >/dev/null || fail 'placement not recorded'
    pid=$(cat "$GH_STATE/disp-$idp.pid"); for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    sed 's/^compute = "orca-host"$/compute = "orca-off"/' "$scratch/placement.toml" > "$scratch/unplaced.toml"
    out=$(bash "$ops/dispatch.sh" "$scratch/unplaced.toml" 8); idb=${out##*$'\n'}
    bash "$ops/orca.sh" start "$idb" >/dev/null 2>&1 && fail 'start on an unconnected host accepted'
    jq -e '.executor.state == "pending"' "$(rec "$idb")" >/dev/null || fail 'a refused placement changed state'
    # #47: a connected host without the project is refused before worker-start.
    sed 's/^compute = "orca-host"$/compute = "orca-bare"/' "$scratch/placement.toml" > "$scratch/bare.toml"
    out=$(bash "$ops/dispatch.sh" "$scratch/bare.toml" 8); idn=${out##*$'\n'}
    err=$(bash "$ops/orca.sh" start "$idn" 2>&1) && fail 'start accepted on a host without the project'
    [[ $err == *'no ready Orca project on orca-bare'* ]] || fail "wrong refusal: $err"
    [[ ! -f $GH_STATE/start-$idn.args ]] || fail 'worker-start called for a host without the project'
    jq -e '.executor.state == "pending"' "$(rec "$idn")" >/dev/null || fail 'a host without the project changed state'
    # #48: a failed start is still one JSON object from the loom call.
    out=$(bash "$ops/dispatch.sh" "$scratch/placement.toml" 8); idz=${out##*$'\n'}
    obj=$(ORCA_STUB_FAIL=1 bash "$ops/loom" start "$idz") && fail 'failed start reported ok'
    jq -e '.ok == false and .cmd == "start" and (.fact | length > 0)' <<< "$obj" >/dev/null || fail "failed start printed no JSON object (#48): [$obj]"
    # #45: the first connected host wins, not compute[0].
    sed 's/^compute = "orca-host"$/compute = ["orca-off", "orca-dup", "orca-host"]/' "$scratch/placement.toml" > "$scratch/fallback.toml"
    out=$(bash "$ops/dispatch.sh" "$scratch/fallback.toml" 9); idf=${out##*$'\n'}
    bash "$ops/orca.sh" start "$idf" >/dev/null || fail 'start refused though a later compute host is connected'
    jq -e '.executor.placement.host == "orca-dup"' "$(rec "$idf")" >/dev/null || fail 'not placed on the first connected host'
    grep -q -- '--on orca-dup' "$GH_STATE/start-$idf.args" || fail 'worker not started on the first connected host'
    pid=$(cat "$GH_STATE/disp-$idf.pid"); for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    bash "$ops/orca.sh" harvest "$idf" >/dev/null || fail 'harvest the #45 worker'

    [[ $(bash "$ops/orca.sh" show "$idp") == *settled* ]] || fail 'worker-show verdict'
    bash "$ops/orca.sh" read "$idp" >/dev/null || fail 'worker-read'
    [[ -s $LOOM_STATE/$idp.evidence/orca-transcript.txt ]] || fail 'transcript not saved as evidence'
    bash "$ops/orca.sh" keep-open "$idp" >/dev/null || fail 'keep-open'
    jq -e '.executor.kept_open == true' "$(rec "$idp")" >/dev/null || fail 'keep-open not recorded'
    bash "$ops/orca.sh" list | grep -q 'disp-' || fail 'worker-list empty'
    bash "$ops/orca.sh" peek | jq -e '.ok == true' >/dev/null || fail 'peek'
    bash "$ops/orca.sh" send "$idp" --subject hi --body there | jq -e '.ok == true' >/dev/null || fail 'send'
    jq -e '.executor.state == "running" and .executor.continuation_pending == null' "$(rec "$idp")" >/dev/null || fail 'active queue-only delivery remained fenced'
    bash "$ops/orca.sh" ask "$idp" --question 'why?' | jq -e '.ok == true' >/dev/null || fail 'ask'
    bash "$ops/orca.sh" reply --id m1 --body 'because' | jq -e '.ok == true' >/dev/null || fail 'reply'
    bash "$ops/orca.sh" gate list | jq -e '.ok == true' >/dev/null || fail 'gate list'
    bash "$ops/orca.sh" run create --objective x | jq -e '.ok == true' >/dev/null || fail 'run create'
    # Every mapped row answers. Existence and shape, not yet behaviour.
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        # shellcheck disable=SC2086  # the line is a verb plus its args
        bash "$ops/orca.sh" $line | jq -e '.ok == true' >/dev/null || fail "verb failed: $line"
    done <<'VERBS'
inbox
request --request r1
task update --id t1 --status done
run use --id r1
run current
run show --id r1
run list
reference find --url https://github.com/example/fixture/issues/7
reference list --worktree path:/tmp
worktree rm --worktree name:gone
worktree ps
worktree list
repo --path /tmp
base-ref main
automation list
automation run a1
automation remove a1
VERBS
    # #47: harvest and collect reach the workspace through its host.
    : > "$GH_STATE/ssh-ws.log"
    [[ $(bash "$ops/orca.sh" harvest "$idp") == "$idp ready"* ]] || fail 'harvest after the read checks (remote)'
    grep -qx orca-host "$GH_STATE/ssh-ws.log" || fail 'remote harvest did not go through ssh'
    wsp=$(jq -r '.workdir' "$(rec "$idp")")
    [[ $(git -C "$wsp" log -1 --format=%s) == "loom($idp): ready — wrote notes.txt" ]] || fail 'remote worker files not committed'
    [[ -f $LOOM_STATE/$idp.evidence/discovery.log ]] || fail 'evidence not copied from the remote workspace'
    bash "$ops/collect.sh" "$idp" >/dev/null || fail 'remote collect failed'
    git -C "$LOOM_REPO" show-ref --verify --quiet "refs/heads/orca/$idp" || fail 'remote branch not fetched home'

    export ORCA_STUB_WORKER="$scratch/bin/w-hang" GRANDCHILD="$scratch/orca-grandchild"
    out=$(bash "$ops/dispatch.sh" "$scratch/placement.toml" 7); ida=${out##*$'\n'}
    bash "$ops/orca.sh" start "$ida" >/dev/null || fail 'start for the active-harvest case'
    pids+=("$(cat "$GH_STATE/disp-$ida.pid")")
    printf 'active\n' > "$GH_STATE/show-disp-$ida"
    bash "$ops/orca.sh" harvest "$ida" >/dev/null 2>&1 && fail 'harvest while the dispatch is active'
    jq -e '.executor.state == "running"' "$(rec "$ida")" >/dev/null || fail 'refused harvest changed the record'
    bash "$ops/orca.sh" abandon "$ida" >/dev/null || fail 'abandon'
    jq -e '.executor.state == "abandoned" and (.reports[-1].fact | startswith("owner_fenced"))' "$(rec "$ida")" >/dev/null || fail 'abandon recorded as a stop'

    # #56: watch must not end while an Orca dispatch is running.
    out=$(bash "$ops/dispatch.sh" "$scratch/placement.toml" 7); idw=${out##*$'\n'}
    bash "$ops/orca.sh" start "$idw" >/dev/null || fail 'start for the watch case'
    pids+=("$(cat "$GH_STATE/disp-$idw.pid")")
    started=$(date +%s)
    ( sleep 3; bash "$ops/orca.sh" abandon "$idw" >/dev/null ) &
    pids+=("$!")
    within 25 bash "$ops/heartbeat.sh" --until "$idw" --every 1 > "$scratch/hb-orca-id" || fail 'watch failed for an Orca worker'
    [[ $(( $(date +%s) - started )) -ge 2 ]] || fail 'watch ended while the Orca worker was running (#56)'
    grep -q "^$idw"$'\t' <<< "$(cat "$scratch/hb-orca-id")" || fail 'watch did not end with status for the Orca worker'

    out=$(bash "$ops/dispatch.sh" "$scratch/placement.toml" 7); idall=${out##*$'\n'}
    bash "$ops/orca.sh" start "$idall" >/dev/null || fail 'start for the --until all case'
    pids+=("$(cat "$GH_STATE/disp-$idall.pid")")
    started=$(date +%s)
    ( sleep 3; bash "$ops/orca.sh" abandon "$idall" >/dev/null ) &
    pids+=("$!")
    within 25 bash "$ops/heartbeat.sh" --until all --every 1 > "$scratch/hb-orca-all" || fail 'watch --until all failed'
    [[ $(( $(date +%s) - started )) -ge 2 ]] || fail 'watch --until all ended while an Orca worker was running (#56)'
    pass 'watch waits for running Orca workers, for one id and for all (#56)'
)
pass 'orca map: placement refused when unconnected, show/read/keep-open/list/peek/send/gate/run, abandon is fencing'

# --- checks run on the compute host, never silently here (gap #36) ---
(
    cat > "$scratch/bin/ssh" <<'EOF'
#!/usr/bin/env bash
# ssh stub: fake-build* hosts get their own HOME (with a marker the conductor's
# HOME lacks); anything else fails like an unreachable host.
while [[ $1 == -o ]]; do shift 2; done
host=$1; shift
[[ $host == fake-build* ]] || exit 255
export HOME="$GH_STATE/remote-home-$host"
mkdir -p "$HOME"; : > "$HOME/.remote-marker"
cd "$HOME"
exec bash -c "$*"
EOF
    chmod +x "$scratch/bin/ssh"
    export LOOM_SSH="$scratch/bin/ssh"
    # shellcheck disable=SC2016  # $HOME / $LOOM_SETUP_OK expand on the compute host
    mk() {  # mk <name> <compute line> [setup line]: a consumer whose check passes only remotely
        sed "s|^checks = \"true\"$|checks = \"test -f \$HOME/.remote-marker \&\& test \$LOOM_SETUP_OK = 1\"\n$2\ncompute_setup = \"${3:-export LOOM_SETUP_OK=1}\"|" "$scratch/consumer.toml" > "$scratch/$1.toml"
    }
    mk fallback 'compute = ["dead-build", "fake-build"]'
    out=$(bash "$ops/dispatch.sh" "$scratch/fallback.toml" 7); idc=${out##*$'\n'}
    jq -e '.compute == ["dead-build", "fake-build"]' "$(rec "$idc")" >/dev/null || fail 'compute not recorded as a list'
    obj=$(bash "$ops/loom" compute --consumer "$scratch/fallback.toml")
    jq -e '.ok == true and .fact == "compute host: fake-build"' <<< "$obj" >/dev/null || fail "loom compute: $obj"
    out=$(bash "$ops/verify.sh" "$idc" --baseline) || fail "remote baseline failed: $out $(cat "$LOOM_STATE/$idc.checks-baseline.log")"
    [[ $out == *' on fake-build' ]] || fail "verify must name the compute host: $out"
    jq -e '.checks_runs[-1] | .host == "fake-build" and .exit == 0' "$(rec "$idc")" >/dev/null || fail 'run not recorded with its host'
    grep -q '^== on compute host fake-build$' "$LOOM_STATE/$idc.checks-baseline.log" || fail 'log does not say where it ran'
    [[ -z $(ls -A "$GH_STATE/remote-home-fake-build/.loom-remote") ]] || fail 'remote workspace not cleaned up'

    mk dead 'compute = "dead-build"'
    out=$(bash "$ops/dispatch.sh" "$scratch/dead.toml" 7); idd=${out##*$'\n'}
    err=$(bash "$ops/verify.sh" "$idd" --baseline 2>&1) && fail 'verify ran with no reachable compute host'
    [[ $err == *"refusing to run checks on the conductor's machine"* ]] || fail "wrong refusal: $err"
    jq -e '(.checks_runs // []) == []' "$(rec "$idd")" >/dev/null || fail 'a refused verify recorded a run'

    # --on: a record without compute (dispatched before the consumer declared one)
    out=$(bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7); idn=${out##*$'\n'}
    out=$(bash "$ops/verify.sh" "$idn" --baseline --on fake-build-2) || fail "--on run failed: $out"
    jq -e '.compute == null and .checks_runs[-1].host == "fake-build-2"' "$(rec "$idn")" >/dev/null || fail '--on host not recorded'
    bash "$ops/verify.sh" "$idn" --baseline --on dead-build >/dev/null 2>&1 && fail '--on an unreachable host ran'
    bash "$ops/verify.sh" "$idn" --on 'bad;host' >/dev/null 2>&1 && fail 'unsafe --on host accepted'
    obj=$(bash "$ops/loom" verify "$idn" --baseline --on fake-build-3) || fail "loom verify --on failed: $obj"
    jq -e '.ok == true' <<< "$obj" >/dev/null || fail "loom verify --on not ok: $obj"
    jq -e '.checks_runs[-1].host == "fake-build-3"' "$(rec "$idn")" >/dev/null || fail 'loom verify --on did not reach the host'

    mk badsetup 'compute = "fake-build"' 'false'
    out=$(bash "$ops/dispatch.sh" "$scratch/badsetup.toml" 7); idb=${out##*$'\n'}
    rc=0; bash "$ops/verify.sh" "$idb" --baseline >/dev/null 2>&1 || rc=$?
    [[ $rc == 126 ]] || fail "failed compute_setup must be could-not-run (126), got $rc"
)
pass 'compute host: remote run with fallback, refusal when unreachable, setup failure is could-not-run'

# --- process start time is trimmed on every platform (gap #10) ---
# macOS pads ps's lstart; Linux does not. A stub ps pads both ends so the trim
# is tested everywhere, not only where the platform happens to pad.
(
    mkdir -p "$scratch/psbin"
    printf '#!/bin/sh\nprintf "  Sat Nov  7 05:26:31 2026    \\n"\n' > "$scratch/psbin/ps"
    chmod +x "$scratch/psbin/ps"
    got=$(PATH="$scratch/psbin:$PATH" bash -c 'source "$1"; loom_pstart 12345' _ "$ops/lib.sh")
    [[ $got == 'Sat Nov  7 05:26:31 2026' ]] || fail "loom_pstart must trim both ends: [$got]"
)
pass 'process start time trimmed (stub ps pads both ends)'

# --- the lock: a live holder blocks, a dead holder is broken ---
n=$(jq '.reports | length' "$(rec "$id1")")
mkdir "$LOOM_STATE/.lock"; printf '%s\n' "$$" > "$LOOM_STATE/.lock/owner"
if LOOM_LOCK_WAIT=0 bash "$ops/report.sh" "$id1" ready 'lost update' 2>/dev/null; then fail 'live lock ignored'; fi
bash -c 'exit 0' & dead=$!; wait "$dead"
printf '%s\n' "$dead" > "$LOOM_STATE/.lock/owner"
bash "$ops/report.sh" "$id1" waiting 'after stale lock' || fail 'stale lock not broken'
[[ $(jq '.reports | length' "$(rec "$id1")") == $((n + 1)) ]] || fail 'lock history'
[[ ! -d $LOOM_STATE/.lock ]] || fail 'lock not released'
pass 'live lock holds, dead lock breaks'

# --- corrupt state is never treated as healthy ---
printf '{' > "$LOOM_STATE/broken.json"
if bash "$ops/status.sh" >/dev/null 2>&1; then fail 'corrupt state ignored'; fi
rm "$LOOM_STATE/broken.json"
pass 'corrupt record refused'

# --- the call: one JSON object, same for every harness (0.5.0) ---
ver=$(tr -d '[:space:]' < "$ops/../VERSION")
obj=$(bash "$ops/loom" version)
[[ $(jq -r '.v' <<< "$obj") == "$ver" && $(jq -r '.ok' <<< "$obj") == true ]] || fail "version object: $obj"
[[ $(printf '%s\n' "$obj" | wc -l | tr -d ' ') == 1 ]] || fail 'version must be one line'
rc=0; bad=$(bash "$ops/loom" 2>/dev/null) || rc=$?
[[ $rc == 2 && $(jq -r '.ok' <<< "$bad") == false ]] || fail "usage must exit 2 with ok false (rc=$rc): $bad"
obj=$(bash "$ops/loom" ignore --consumer "$scratch/consumer.toml" --short not-this --reason 'out of scope')
[[ $(jq -r '.state' <<< "$obj") == ignored && $(jq -r '.ok' <<< "$obj") == true ]] || fail "ignore: $obj"
[[ $(jq -r '.decision' "$LOOM_STATE/decisions.jsonl") == ignore ]] || fail 'ignore not recorded'
if bash "$ops/loom" ignore --consumer "$scratch/consumer.toml" --short 'Bad Name' --reason 'no' >/dev/null 2>&1; then fail 'bad short name ignored'; fi
obj=$(bash "$ops/loom" status)
[[ $(jq -r '.cmd' <<< "$obj") == status && $(jq -r '.items | type' <<< "$obj") == array ]] || fail "status object: $obj"
pass 'loom call: version, usage, ignore, status'

printf 'PASS: dispatch → launch → report/harvest → watchdog → status → collect\n'
