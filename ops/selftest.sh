#!/usr/bin/env bash
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
        [[ $3 == --repo && $4 == example/fixture && $5 == --title && $7 == --body ]] || exit 97
        printf '%s' "$8" > "$GH_STATE/issue9.body"
        printf 'https://github.com/example/fixture/issues/9\n' ;;
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

printf 'PASS: dispatch → launch → report/harvest → watchdog → status → collect\n'
