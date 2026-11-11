#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031 # isolated fault injection in subshells
# Offline regression entrypoint for legacy ownership, collection and dispatch.
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/loom-review-legacy.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
export LOOM_STATE="$scratch/state" LOOM_LOCK_WAIT=0
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$LOOM_STATE" "$scratch/bin"
fail() { printf 'FAIL review-legacy: %s\n' "$*" >&2; exit 1; }
# shellcheck source=ops/lib.sh
source "$root/ops/lib.sh"

# A paused stale reaper loses to another reaper, then encounters a new owner.
# Inject exactly at unlink, after reading the old owner identity.
(
    mkdir "$LOOM_STATE/.lock"
    printf '99999999\nold\n' > "$LOOM_STATE/.lock/owner.stale"
    rm() {
        if [[ $* == *'/owner.stale' ]]; then
            command rm "$LOOM_STATE/.lock/owner.stale"
            command rmdir "$LOOM_STATE/.lock"
            command mkdir "$LOOM_STATE/.lock"
            printf '%s\n' "$$" > "$LOOM_STATE/.lock/owner.replacement"
        fi
        command rm "$@"
    }
    if (loom_lock) > "$scratch/reaper.log" 2>&1; then fail 'stale reaper acquired replacement lock'; fi
    [[ -f $LOOM_STATE/.lock/owner.replacement ]] || fail 'stale reaper removed replacement owner'
)
# Delayed unlock must leave both the replacement lock and its pending write.
printf 'replacement write\n' > "$LOOM_STATE/.pending"
(
    LOOM_LOCK_OWNER="$LOOM_STATE/.lock/owner.stale"
    loom_unlock
)
[[ -f $LOOM_STATE/.lock/owner.replacement && -f $LOOM_STATE/.pending ]] || fail 'stale unlock damaged replacement owner'
rm "$LOOM_STATE/.lock/owner.replacement" "$LOOM_STATE/.pending"
rmdir "$LOOM_STATE/.lock"
# The winning reaper may remove the old directory while a new acquisition is
# between mkdir and owner publication. A losing reaper must not remove it.
(
    mkdir "$LOOM_STATE/.lock"
    printf '99999999\nold\n' > "$LOOM_STATE/.lock/owner.stale"
    rm() {
        if [[ $* == *'/owner.stale' ]]; then
            command rm "$LOOM_STATE/.lock/owner.stale"
            command rmdir "$LOOM_STATE/.lock"
            command mkdir "$LOOM_STATE/.lock"
        fi
        command rm "$@"
    }
    if (loom_lock) >/dev/null 2>&1; then fail 'losing reaper acquired unpublished replacement'; fi
    [[ -d $LOOM_STATE/.lock ]] || fail 'losing reaper removed unpublished replacement'
)
rmdir "$LOOM_STATE/.lock"
# Legacy PID-only records are recoverable; a live owner still fences entry.
mkdir "$LOOM_STATE/.lock"
printf '%s\n' "$$" > "$LOOM_STATE/.lock/owner"
if (loom_lock) >/dev/null 2>&1; then fail 'live lock bypassed'; fi
printf '99999999\n' > "$LOOM_STATE/.lock/owner"
(LOOM_LOCK_WAIT=1; loom_lock; loom_unlock)
[[ ! -d $LOOM_STATE/.lock ]] || fail 'legacy dead lock not reclaimed'
# PID reuse: stale start time must not keep the lock forever.
mkdir "$LOOM_STATE/.lock"
printf '%s\nobsolete start\n' "$$" > "$LOOM_STATE/.lock/owner.reused"
(LOOM_LOCK_WAIT=1; loom_lock; loom_unlock)
# Competing real shells must serialize the whole critical section.
lock_pids=()
for _ in 1 2 3 4; do
    (
        for _ in 1 2 3; do
            LOOM_LOCK_WAIT=10; loom_lock
            mkdir "$scratch/critical" || fail 'overlapping lock owners'
            sleep .01
            rmdir "$scratch/critical"
            loom_unlock
        done
    ) & lock_pids+=("$!")
done
for lock_pid in "${lock_pids[@]}"; do wait "$lock_pid"; done
printf 'PASS review-legacy ownership-safe stale reclaim, unlock and contention\n'

export LOOM_REPO="$scratch/repo" LOOM_ALLOW_ANY_CHECKOUT=1
export LOOM_ORCA="$scratch/bin/orca" FIXTURE_ROOT="$scratch"
export PATH="$scratch/bin:$PATH"
git init -q -b main "$LOOM_REPO"
git -C "$LOOM_REPO" config user.name Fixture
git -C "$LOOM_REPO" config user.email fixture@example.invalid
git -C "$LOOM_REPO" -c commit.gpgsign=false commit -q --allow-empty -m base
base=$(git -C "$LOOM_REPO" rev-parse HEAD)
cat > "$scratch/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    'repo view') printf 'main\n' ;;
    'issue view') jq -n --argjson n "$3" '{number:$n,title:"Fixture",body:"## Mandate\n**Ticket short name:** ticket\n**Scope:** fixture"}' ;;
    *) exit 98 ;;
esac
STUB
cat > "$LOOM_ORCA" <<'STUB'
#!/usr/bin/env bash
set -eu
case "$1 ${2:-}" in
    'status ') printf 'runtimeReachable: true\nruntimeState: ready\nruntimeId: fixture\n' ;;
    'orchestration ask') printf '%s\n' "$*" > "$FIXTURE_ROOT/ask.args" ;;
    'orchestration worker-show') cat "$FIXTURE_ROOT/view-$4" ;;
    'orchestration worker-start') touch "$FIXTURE_ROOT/started"; exit 99 ;;
    *) exit 98 ;;
esac
STUB
chmod +x "$scratch/bin/gh" "$LOOM_ORCA"
printf 'repo = "fixture/offline"\nworktrees = "%s/work"\nlaws = []\nexecutor = "local"\n' "$scratch" > "$scratch/consumer.toml"
out=$(bash "$root/ops/dispatch.sh" "$scratch/consumer.toml" 1); id=${out##*$'\n'}
file="$LOOM_STATE/$id.json"
if bash "$root/ops/dispatch.sh" "$scratch/consumer.toml" 1 > "$scratch/duplicate.log" 2>&1; then fail 'duplicate pending local ticket accepted'; fi
cp "$file" "$LOOM_STATE/sibling.json"
if bash "$root/ops/launch.sh" "$id" -- touch "$scratch/started" >/dev/null 2>&1; then fail 'local launch ignored pending sibling'; fi
[[ ! -e $scratch/started ]] || fail 'duplicate local worker started'
rm "$LOOM_STATE/sibling.json"
jq '.executor = {kind:"orca",state:"pending"}' "$file" > "$scratch/edit"; mv "$scratch/edit" "$file"
if bash "$root/ops/dispatch.sh" "$scratch/consumer.toml" 1 >/dev/null 2>&1; then fail 'duplicate pending Orca ticket accepted'; fi
cp "$file" "$LOOM_STATE/sibling.json"
cp "$(jq -r .workdir "$file")/WORK.md" "$LOOM_STATE/$id.WORK.md"
if bash "$root/ops/orca.sh" start "$id" >/dev/null 2>&1; then fail 'Orca start ignored pending sibling'; fi
[[ ! -e $scratch/started ]] || fail 'duplicate Orca worker-start reached executor'
rm "$LOOM_STATE/sibling.json"
printf 'PASS review-legacy pending reservation and locked sibling checks\n'

# Collection refuses a linked consumer checkout, while a shared Orca branch
# is already home and must be observed without fetching or moving its ref.
work=$(jq -r '.workdir' "$file")
jq '.executor = {kind:"local"} | .reports = [{at:(now|todateiso8601),state:"ready",fact:"fixture"}]' "$file" > "$scratch/edit"; mv "$scratch/edit" "$file"
git -C "$LOOM_REPO" branch ticket "$base"
git -C "$LOOM_REPO" worktree add -q "$scratch/linked consumer" ticket
jq --arg s "$base" '.collected_sha = $s' "$file" > "$scratch/edit"; mv "$scratch/edit" "$file"
git -C "$work" -c commit.gpgsign=false commit -q --allow-empty -m incoming
incoming=$(git -C "$work" rev-parse HEAD)
if bash "$root/ops/collect.sh" "$id" > "$scratch/collect-refusal.log" 2>&1; then fail 'collection moved linked checkout'; fi
[[ $(git -C "$LOOM_REPO" rev-parse ticket) == "$base" ]] || fail 'linked checkout ref changed'
# Once detached, the prior collected SHA authorizes the exact replacement.
git -C "$scratch/linked consumer" checkout -q --detach
bash "$root/ops/collect.sh" "$id" >/dev/null
[[ $(git -C "$LOOM_REPO" rev-parse ticket) == "$incoming" ]] || fail 'guarded recollection failed'
[[ -z $(git -C "$LOOM_REPO" for-each-ref refs/loom/collect/) ]] || fail 'collection scratch ref leaked'
git -C "$LOOM_REPO" worktree add -q -b shared "$scratch/shared" "$base"
jq --arg w "$scratch/shared" '.workdir=$w | .branch="shared" | .executor={kind:"orca",state:"settled"}' "$file" > "$scratch/edit"; mv "$scratch/edit" "$file"
bash "$root/ops/collect.sh" "$id" >/dev/null
[[ $(git -C "$LOOM_REPO" rev-parse shared) == "$base" ]] || fail 'shared collection moved branch'
printf 'PASS review-legacy all linked checkout guards and shared no-move collection\n'

# A continuation invalidates current collection but retains its old SHA as the
# compare-and-swap baseline; it must not bless edits by the conductor.
jq --arg w "$work" --arg s "$incoming" '.workdir=$w | .branch="ticket" | .collected_sha=$s |
    .harvest_report_lines=0 | .executor={kind:"orca",state:"settled",dispatch:"parent",task:"task-parent",run:"run"}' "$file" > "$scratch/edit"; mv "$scratch/edit" "$file"
for dispatch in parent child; do
    jq -n --arg d "$dispatch" --arg w "repo::$work" '{ok:true,result:{dispatchId:$d,taskId:("task-"+$d),runId:"run",workspace:$w,state:"running",followUpOf:(if $d=="child" then "parent" else null end)}}' > "$scratch/view-$dispatch"
done
bash "$root/ops/orca.sh" ask "$id" --question fixture
[[ $(cat "$scratch/ask.args") == *'--to dispatch:parent --question fixture'* ]] || fail 'ask did not resolve assignment dispatch'
bash "$root/ops/orca.sh" reconcile "$id" --dispatch child >/dev/null
jq -e --arg s "$incoming" '.collected_sha==null and .previous_collected_sha==$s and .executor.dispatch=="child"' "$file" >/dev/null || fail 'followup lost guarded collection baseline'
git -C "$work" -c commit.gpgsign=false commit -q --allow-empty -m followup
followup=$(git -C "$work" rev-parse HEAD)
jq '.executor.state="settled"' "$file" > "$scratch/edit"; mv "$scratch/edit" "$file"
git -C "$LOOM_REPO" update-ref refs/heads/ticket "$base" "$incoming"
if bash "$root/ops/collect.sh" "$id" >/dev/null 2>&1; then fail 'followup overwrote conductor edit'; fi
git -C "$LOOM_REPO" update-ref refs/heads/ticket "$incoming" "$base"
bash "$root/ops/collect.sh" "$id" >/dev/null
[[ $(git -C "$LOOM_REPO" rev-parse ticket) == "$followup" ]] || fail 'followup recollection failed'
jq -e --arg s "$followup" '.collected_sha==$s and .previous_collected_sha==null' "$file" >/dev/null || fail 'followup collection state incorrect'
printf 'PASS review-legacy dispatch mailbox and guarded followup recollection\n'

# Exercise remote transport with an offline SSH boundary and real git fetch.
cat > "$scratch/bin/ssh" <<'STUB'
#!/usr/bin/env bash
while [[ $1 == -o ]]; do shift 2; done
shift
exec bash -c "$*"
STUB
chmod +x "$scratch/bin/ssh"
export LOOM_SSH="$scratch/bin/ssh"
jq '.ws_host="fixture-host"' "$file" > "$scratch/edit"; mv "$scratch/edit" "$file"
git -C "$work" -c commit.gpgsign=false commit -q --allow-empty -m remote
remote=$(git -C "$work" rev-parse HEAD)
bash "$root/ops/collect.sh" "$id" >/dev/null
[[ $(git -C "$LOOM_REPO" rev-parse ticket) == "$remote" ]] || fail 'remote collection skipped fetch'
printf 'PASS review-legacy remote fetch uses the guarded collection path\n'
