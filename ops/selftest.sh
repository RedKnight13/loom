#!/usr/bin/env bash
set -euo pipefail
ops=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
scratch="$ops/.selftest-$$-$RANDOM"
worker=
cleanup() {
    if [[ -n $worker ]]; then
        kill -KILL "$worker" 2>/dev/null || :
        wait "$worker" 2>/dev/null || :
    fi
    rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/bin" "$scratch/repo"
export LOOM_STATE="$scratch/state" LOOM_REPO="$scratch/repo"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME='Loom Test' GIT_AUTHOR_EMAIL='test@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git -C "$LOOM_REPO" init -q -b main
git -C "$LOOM_REPO" -c commit.gpgsign=false commit -q --allow-empty -m fixture
base=$(git -C "$LOOM_REPO" rev-parse HEAD)
git -C "$LOOM_REPO" checkout -q -b unrelated
git -C "$LOOM_REPO" -c commit.gpgsign=false commit -q --allow-empty -m unrelated
cat > "$scratch/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -eu
case "$1 $2" in
    'issue view')
        [[ $* == 'issue view 7 --repo example/fixture --json number,title,body' ]] || exit 98
        jq -n '{number: 7, title: "Fixture ticket", body: "## Mandate\n\n**Ticket short name:** fixture-task\n**Scope:** fixture\n**Out of scope:** everything else\n**Laws:** fixture\n**Done means:** selftest\n**Stop by impact:** ready\n**Report:** structured"}' ;;
    'repo view')
        [[ $* == 'repo view example/fixture --json defaultBranchRef --jq .defaultBranchRef.name' ]] || exit 98
        printf 'main\n' ;;
    *) exit 99 ;;
esac
EOF
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH"
cat > "$scratch/consumer.toml" <<EOF
repo = "example/fixture" # test comments
checks = "true"
worktrees = "$scratch/worktrees with spaces"
laws = [
  "Workers never push.",
  "Keep # inside strings.",
]
EOF
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[[ -f $ops/dispatch.sh ]] || fail 'dispatch.sh is missing'
result=$(bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7)
worktree=${result%$'\n'*}
assignment=${result##*$'\n'}
record="$LOOM_STATE/$assignment.json"
[[ -f $worktree/WORK.md ]] || fail 'no mandate'
[[ $(git -C "$worktree" branch --show-current) == fixture-task ]] || fail 'wrong branch'
[[ $(git -C "$worktree" rev-parse HEAD) == "$base" ]] || fail 'worktree not based on default branch'
[[ $(< "$worktree/WORK.md") == *'Keep # inside strings.'* ]] || fail 'laws missing'
jq -e '.ticket == 7 and .repo == "example/fixture" and .short_name == "fixture-task" and .worker_pid == null and .reports == []' "$record" >/dev/null
if bash "$ops/dispatch.sh" "$scratch/consumer.toml" 7 >/dev/null 2>&1; then fail 'duplicate dispatch accepted'; fi
[[ -z $(bash "$ops/status.sh") ]] || fail 'unreported assignment needs no person'
if bash "$ops/report.sh" "$assignment" unknown bad 2>/dev/null; then fail 'invalid state accepted'; fi
if bash "$ops/report.sh" ../escape ready bad 2>/dev/null; then fail 'unsafe id accepted'; fi
if bash "$ops/report.sh" missing ready bad 2>/dev/null; then fail 'missing assignment accepted'; fi
jq -e '.reports == []' "$record" >/dev/null
bash "$ops/report.sh" "$assignment" blocked 'Which branch?'
[[ $(bash "$ops/status.sh") == *'blocked'*'Which branch?'* ]] || fail 'blocked not visible'
bash "$ops/report.sh" "$assignment" ready $'review\nthis'
status=$(bash "$ops/status.sh")
[[ $status == *'ready'* && $status != *$'\n'* ]] || fail 'status must be one line'
bash "$ops/report.sh" "$assignment" waiting 'continuing'
jq -e '[.reports[].state] == ["blocked", "ready", "waiting"] and .reports[0].fact == "Which branch?"' "$record" >/dev/null
[[ -z $(bash "$ops/status.sh") ]] || fail 'waiting should be silent'
# A disposable Bash child stands in for a worker; no real worker is signalled.
bash -c 'while :; do :; done' &
worker=$!
jq --argjson pid "$worker" '.worker_pid = $pid' "$record" > "$record.tmp"
mv "$record.tmp" "$record"
# An old start must not override a recent report.
jq '.started_at = "2000-01-01T00:00:00Z"' "$record" > "$record.tmp"
mv "$record.tmp" "$record"
[[ -z $(bash "$ops/watchdog.sh") ]] || fail 'fresh reports must not trigger watchdog'
kill -0 "$worker"
jq '.started_at = "2000-01-01T00:00:00Z" | .reports |= map(.at = "2000-01-01T00:00:00Z")' "$record" > "$record.tmp"
mv "$record.tmp" "$record"
action=$(bash "$ops/watchdog.sh" --limit-min 1)
[[ $action == *"$assignment"*watchdog_kill* ]] || fail 'watchdog action missing'
wait "$worker" 2>/dev/null || :
worker=
jq -e '.worker_pid == null and (.reports | length) == 4 and .reports[-1].state == "failed" and .reports[-1].fact == "watchdog_kill"' "$record" >/dev/null
[[ -d $worktree ]] || fail 'watchdog removed worktree'
[[ $(bash "$ops/status.sh") == *failed*watchdog_kill* ]] || fail 'failure not visible'
[[ -z $(bash "$ops/watchdog.sh" --limit-min 1) ]] || fail 'watchdog repeated action'
if bash "$ops/watchdog.sh" --limit-min nope 2>/dev/null; then fail 'invalid limit accepted'; fi
# A worker that never reports is timed from started_at.
bash -c 'while :; do :; done' &
worker=$!
jq --argjson pid "$worker" '.worker_pid = $pid | .reports = []' "$record" > "$LOOM_STATE/never-reported.json"
[[ $(bash "$ops/watchdog.sh" --limit-min 1) == 'never-reported failed watchdog_kill' ]] || fail 'missing first-report deadline'
wait "$worker" 2>/dev/null || :
worker=
jq -e '.reports[0].fact == "watchdog_kill"' "$LOOM_STATE/never-reported.json" >/dev/null
# The global lock must reject a competing writer without changing history.
mkdir "$LOOM_STATE/.lock"
if bash "$ops/report.sh" "$assignment" ready 'lost update' 2>/dev/null; then fail 'lock ignored'; fi
rmdir "$LOOM_STATE/.lock"
jq -e '(.reports | length) == 4' "$record" >/dev/null
# Malformed records must not be treated as healthy.
printf '{' > "$LOOM_STATE/broken.json"
if bash "$ops/status.sh" >/dev/null 2>&1; then fail 'corrupt state ignored'; fi
rm "$LOOM_STATE/broken.json"
printf 'PASS: dispatch → report → watchdog → status\n'
