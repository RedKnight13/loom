#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031  # subshell-scoped env/pids are intentional
# Offline self-test: a throwaway consumer repo, a stubbed gh, disposable
# fake workers. No network, no pushes, no real worker is signalled.
set -euo pipefail
ops=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/loom-selftest.XXXXXX")
pids=()
cleanup() {
    local p
    for p in ${pids[@]+"${pids[@]}"}; do kill -KILL "$p" 2>/dev/null || :; done
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
                jq -n --arg d "$4" --arg s "$st" '{ok: true, result: {dispatchId: $d, status: $s}}' ;;
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
            send|ask|reply)
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

    [[ $(bash "$ops/orca.sh" show "$idp") == *settled* ]] || fail 'worker-show verdict'
    bash "$ops/orca.sh" read "$idp" >/dev/null || fail 'worker-read'
    [[ -s $LOOM_STATE/$idp.evidence/orca-transcript.txt ]] || fail 'transcript not saved as evidence'
    bash "$ops/orca.sh" keep-open "$idp" >/dev/null || fail 'keep-open'
    jq -e '.executor.kept_open == true' "$(rec "$idp")" >/dev/null || fail 'keep-open not recorded'
    bash "$ops/orca.sh" list | grep -q 'disp-' || fail 'worker-list empty'
    bash "$ops/orca.sh" peek | jq -e '.ok == true' >/dev/null || fail 'peek'
    bash "$ops/orca.sh" send "$idp" --subject hi --body there | jq -e '.ok == true' >/dev/null || fail 'send'
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
)
pass 'orca map: placement refused when unconnected, show/read/keep-open/list/peek/send/gate/run, abandon is fencing'

# --- checks run on the compute host, never silently here (gap #36) ---
(
    cat > "$scratch/bin/ssh" <<'EOF'
#!/usr/bin/env bash
# ssh stub: fake-agni* hosts get their own HOME (with a marker the conductor's
# HOME lacks); anything else fails like an unreachable host.
while [[ $1 == -o ]]; do shift 2; done
host=$1; shift
[[ $host == fake-agni* ]] || exit 255
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
    mk fallback 'compute = ["dead-agni", "fake-agni"]'
    out=$(bash "$ops/dispatch.sh" "$scratch/fallback.toml" 7); idc=${out##*$'\n'}
    jq -e '.compute == ["dead-agni", "fake-agni"]' "$(rec "$idc")" >/dev/null || fail 'compute not recorded as a list'
    obj=$(bash "$ops/loom" compute --consumer "$scratch/fallback.toml")
    jq -e '.ok == true and .fact == "compute host: fake-agni"' <<< "$obj" >/dev/null || fail "loom compute: $obj"
    out=$(bash "$ops/verify.sh" "$idc" --baseline) || fail "remote baseline failed: $out $(cat "$LOOM_STATE/$idc.checks-baseline.log")"
    [[ $out == *' on fake-agni' ]] || fail "verify must name the compute host: $out"
    jq -e '.checks_runs[-1] | .host == "fake-agni" and .exit == 0' "$(rec "$idc")" >/dev/null || fail 'run not recorded with its host'
    grep -q '^== on compute host fake-agni$' "$LOOM_STATE/$idc.checks-baseline.log" || fail 'log does not say where it ran'
    [[ -z $(ls -A "$GH_STATE/remote-home-fake-agni/.loom-remote") ]] || fail 'remote workspace not cleaned up'

    mk dead 'compute = "dead-agni"'
    out=$(bash "$ops/dispatch.sh" "$scratch/dead.toml" 7); idd=${out##*$'\n'}
    err=$(bash "$ops/verify.sh" "$idd" --baseline 2>&1) && fail 'verify ran with no reachable compute host'
    [[ $err == *"refusing to run checks on the conductor's machine"* ]] || fail "wrong refusal: $err"
    jq -e '(.checks_runs // []) == []' "$(rec "$idd")" >/dev/null || fail 'a refused verify recorded a run'

    # --on: a record without compute (dispatched before the consumer declared one)
    out=$(bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7); idn=${out##*$'\n'}
    out=$(bash "$ops/verify.sh" "$idn" --baseline --on fake-agni-2) || fail "--on run failed: $out"
    jq -e '.compute == null and .checks_runs[-1].host == "fake-agni-2"' "$(rec "$idn")" >/dev/null || fail '--on host not recorded'
    bash "$ops/verify.sh" "$idn" --baseline --on dead-agni >/dev/null 2>&1 && fail '--on an unreachable host ran'
    bash "$ops/verify.sh" "$idn" --on 'bad;host' >/dev/null 2>&1 && fail 'unsafe --on host accepted'
    obj=$(bash "$ops/loom" verify "$idn" --baseline --on fake-agni-3) || fail "loom verify --on failed: $obj"
    jq -e '.ok == true' <<< "$obj" >/dev/null || fail "loom verify --on not ok: $obj"
    jq -e '.checks_runs[-1].host == "fake-agni-3"' "$(rec "$idn")" >/dev/null || fail 'loom verify --on did not reach the host'

    mk badsetup 'compute = "fake-agni"' 'false'
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
