#!/usr/bin/env bash
# Synthetic storage-only workloads. No real agents, SSH, GitHub or service calls.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
umask 077
export LOOM_STATE="$TMP/store"
STATE="$ROOT/ops/state.sh"
EVENTS="$ROOT/ops/events.sh"
passed=0
ok() { passed=$((passed+1)); printf 'ok %s - %s\n' "$passed" "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; cat "$TMP/err" >&2 2>/dev/null || :; exit 1; }
expect() {
    local wanted=$1 actual=0; shift
    "$@" > "$TMP/out" 2> "$TMP/err" || actual=$?
    [[ $actual == "$wanted" ]] || fail "exit $actual, expected $wanted: $*"
}
assert_json() { jq -e "$1" "$TMP/out" >/dev/null || fail "$1"; }
new_store() { rm -rf -- "$LOOM_STATE"; expect 0 bash "$STATE" init store-example; }
request() {
    local op=${1:-op-1} revision=${2:-null} value=${3:-1}
    jq -cnS --arg op "$op" --argjson revision "$revision" --argjson value "$value" '
      {schema:2,store_id:"store-example",operation_id:$op,idempotency_key:$op,op:"config.put",
       actor:{id:"actor-example",run_id:null,epoch:0},target:{},checks:[],
       changes:[{kind:"config",id:"capacity",expected_revision:$revision,run_id:null,epoch:0,data:{value:$value}}],
       events:[{type:"config.put",entity_ids:["capacity"],payload:{value:$value},observed_at:null}],result:{value:$value}}' > "$TMP/request.json"
}
edit_request() { jq -cS "$1" "$TMP/request.json" > "$TMP/edit.json"; mv "$TMP/edit.json" "$TMP/request.json"; }
commit() { expect 0 bash "$STATE" transact "$TMP/request.json"; }
lock_fixture() {
    local pid=$1 ticks=$2 host boot ns
    host="git-blob-sha1-v1:$(git hash-object --stdin < /etc/machine-id)"
    boot=$(cat /proc/sys/kernel/random/boot_id)
    ns=$(readlink /proc/self/ns/pid)
    jq -cnS --arg host "$host" --arg boot "$boot" --arg ns "$ns" --argjson pid "$pid" --arg ticks "$ticks" '
      {schema:2,host_id:$host,boot_id:$boot,pid_namespace:$ns,pid:$pid,start_ticks:$ticks,nonce:"00000000-0000-0000-0000-000000000001"}' > "$LOOM_STATE/v2/lock.json"
}

# Schema artifacts have resolvable local references and closed envelope fields.
jq -e '
  . as $root | .["$schema"]=="https://json-schema.org/draft/2020-12/schema" and
  all(..|objects|select(has("$ref")); .["$ref"] as $ref | ($ref|startswith("#/$defs/")) and ($root["$defs"]|has($ref|split("/")[-1]))) and
  all(..|objects|select(.additionalProperties?==false and has("required")); (.required|sort)==(.properties|keys))
' "$ROOT/schemas/state-v2/contract.json" >/dev/null
ok 'published schema references and closed envelopes are structurally sound'

# Source has no effects, including in strict callers with custom traps/options.
# shellcheck disable=SC2016 # Run assertions in the isolated child shell.
expect 0 bash -c '
  set -eu; before=$(set +o); mask=$(umask); cwd=$PWD
  trap ": source-safe" EXIT; traps=$(trap -p)
  source "$1"; source "$2"
  [[ $(set +o) == "$before" && $(umask) == "$mask" && $PWD == "$cwd" && $(trap -p) == "$traps" ]]
  [[ ! -e $LOOM_STATE ]]
' _ "$STATE" "$EVENTS"
ok 'source leaves state, options, traps, cwd and umask untouched'
new_store
expect 0 bash "$STATE" init store-example
expect 2 bash "$STATE" init other-store
ok 'installation identity is immutable'
request; commit
cp "$TMP/out" "$TMP/receipt.json"
assert_json '.durable and .sequence==1 and .revisions[0].revision==1'
expect 0 bash "$STATE" get config capacity
assert_json '.revision==1 and .data.value==1'
commit
cmp -s "$TMP/out" "$TMP/receipt.json" || fail 'dedupe receipt changed'
expect 0 bash "$STATE" operation actor-example config.put op-1
assert_json '.outcome.sequence==1'
ok 'commit, read and exact retry preserve immutable operation outcome'
edit_request '.result.value=2'
expect 2 bash "$STATE" transact "$TMP/request.json"
[[ $(cat "$TMP/err") == *idempotency_conflict* ]] || fail 'missing dedupe conflict'
request op-2 0 2
expect 2 bash "$STATE" transact "$TMP/request.json"
[[ $(cat "$TMP/err") == *revision_conflict* ]] || fail 'missing revision conflict'
request op-2 1 2; commit
request op-1 null 1; commit
assert_json '.sequence==1'
ok 'changed payload conflicts; stale CAS refuses; old retry survives newer revision'
request op-3 2 3
edit_request '.changes += [{kind:"config",id:"second",expected_revision:7,run_id:null,epoch:0,data:{}}]'
expect 2 bash "$STATE" transact "$TMP/request.json"
expect 0 bash "$STATE" get config capacity
assert_json '.revision==2 and .data.value==2'
ok 'multi-record CAS is all-or-nothing'
request op-3 2 3
edit_request '.checks=[{kind:"config",id:"capacity",revision:1}]'
expect 2 bash "$STATE" transact "$TMP/request.json"
edit_request '.checks[0].revision=2 | .changes[0].id="literal/../entity" | .changes[0].expected_revision=null'
commit
expect 0 bash "$STATE" get config literal/../entity
assert_json '.id=="literal/../entity"'
[[ ! -e $LOOM_STATE/entity ]] || fail 'ID interpreted as path'
expect 0 bash "$STATE" list config '' 1
assert_json '(.items|length)==1 and .next_cursor=="capacity"'
expect 0 bash "$STATE" list config capacity 1
assert_json '.items[0].id=="literal/../entity"'
expect 2 bash "$STATE" list config '' 101
expect 0 bash "$EVENTS" 0 1
assert_json '.next_sequence==1 and (.events|length)==1'
expect 0 bash "$EVENTS" 1 100
assert_json '.next_sequence==3 and (.events|length)==2'
expect 2 bash "$EVENTS" 99 1
ok 'read checks, opaque IDs and bounded event/entity cursors'
cp -R "$LOOM_STATE" "$TMP/base"

# Snapshot is never trusted, even after missing/corrupt/lagged projection.
printf 'broken snapshot\n' > "$LOOM_STATE/v2/snapshot.json"
expect 0 bash "$STATE" replay
assert_json '.sequence==3'
jq -e '.entities.config.capacity.revision==2' "$LOOM_STATE/v2/snapshot.json" >/dev/null
rm "$LOOM_STATE/v2/snapshot.json"
expect 0 bash "$STATE" get config capacity
assert_json '.revision==2'
ok 'missing/corrupt snapshots rebuild from authoritative journal'
for corruption in gap tail malformed digest outcome duplicate filename unknown_field; do
    rm -rf "$LOOM_STATE"; cp -R "$TMP/base" "$LOOM_STATE"
    file="$LOOM_STATE/v2/journal/0000000000000002.json"
    case $corruption in
        gap) rm "$file" ;;
        tail) rm "$LOOM_STATE/v2/journal/0000000000000003.json" ;;
        malformed) printf '{\n' > "$file" ;;
        digest) jq -cS '.previous_digest="git-blob-sha1-v1:0000000000000000000000000000000000000000"' "$file" > "$TMP/edit.json"; cp "$TMP/edit.json" "$file" ;;
        outcome) jq -cS '.outcome.result.value=999' "$file" > "$TMP/edit.json"; cp "$TMP/edit.json" "$file" ;;
        duplicate) cp "$LOOM_STATE/v2/journal/0000000000000001.json" "$file" ;;
        filename) mv "$file" "$LOOM_STATE/v2/journal/unexpected.json" ;;
        unknown_field) jq -cS '.extra=true' "$file" > "$TMP/edit.json"; cp "$TMP/edit.json" "$file" ;;
    esac
    expect 2 bash "$STATE" replay
    ok "refuse $corruption journal"
done

# New run, fenced changes, explicit owner epoch change, and stale retry.
new_store
request run-create
edit_request '.actor.run_id="run-example" | .changes=[{kind:"run",id:"run-example",expected_revision:null,run_id:"run-example",epoch:0,data:{owner_id:"actor-example",objective:"synthetic"}}]'
commit
cp "$TMP/request.json" "$TMP/run-create.json"
request run-change
edit_request '.actor.run_id="run-example" | .changes=[{kind:"run",id:"run-example",expected_revision:1,run_id:"run-example",epoch:0,data:{owner_id:"next-owner"}}]'
expect 2 bash "$STATE" transact "$TMP/request.json"
edit_request '.changes[0].epoch=1'
commit
request stale
edit_request '.actor.run_id="run-example" | .changes=[{kind:"task",id:"task-example",expected_revision:null,run_id:"run-example",epoch:0,data:{}}]'
expect 2 bash "$STATE" transact "$TMP/request.json"
[[ $(cat "$TMP/err") == *owner_fenced* ]] || fail 'missing fencing error'
edit_request '.actor.epoch=1 | .changes[0].epoch=1'
commit
edit_request '.operation_id="cross-run" | .idempotency_key="cross-run" | .changes[0].run_id="other"'
expect 2 bash "$STATE" transact "$TMP/request.json"
expect 0 bash "$STATE" transact "$TMP/run-create.json"
assert_json '.sequence==1'
ok 'run epochs fence stale/cross-run mutations and preserve exact retries'

# Actual SIGKILL: no acknowledgement before commit, deterministic recovery.
for area in journal snapshot; do
    for boundary in before_write after_write after_file_flush after_rename after_directory_flush; do
        new_store; request
        actual=0
        env LOOM_STATE_TESTING=1 LOOM_STATE_TEST_CRASH="$area.$boundary" bash "$STATE" transact "$TMP/request.json" > "$TMP/out" 2> "$TMP/err" || actual=$?
        [[ $actual == 137 ]] || fail "crash $area.$boundary returned $actual"
        [[ ! -s $TMP/out ]] || fail 'crashed call acknowledged'
        expected=0
        if [[ $area == journal && $boundary != after_rename && $boundary != after_directory_flush ]]; then expected=2; fi
        expect "$expected" bash "$STATE" get config capacity
        commit
        assert_json '.sequence==1 and .durable'
        [[ $(find "$LOOM_STATE/v2/journal" -name '*.json' | wc -l) == 1 ]] || fail 'duplicate after crash'
        ok "SIGKILL at $area.$boundary recovers exactly one transaction"
    done
done
for area in lock metadata; do
    for boundary in before_write after_write after_file_flush after_rename after_directory_flush; do
        rm -rf "$LOOM_STATE"
        actual=0
        env LOOM_STATE_TESTING=1 LOOM_STATE_TEST_CRASH="$area.$boundary" bash "$STATE" init store-example > "$TMP/out" 2> "$TMP/err" || actual=$?
        [[ $actual == 137 && ! -s $TMP/out ]] || fail "crash $area.$boundary"
        expect 0 bash "$STATE" init store-example
        ok "SIGKILL at $area.$boundary permits safe reinitialization"
    done
done
new_store; request
expect 1 env LOOM_STATE_TESTING=1 LOOM_STATE_TEST_FAIL=journal.after_write bash "$STATE" transact "$TMP/request.json"
[[ ! -s $TMP/out ]] || fail 'failed write acknowledged'
expect 2 bash "$STATE" get config capacity
commit
ok 'write failure leaves no authoritative partial state'
new_store; request
expect 1 env LOOM_STATE_TESTING=1 LOOM_STATE_TEST_FAIL=journal.after_rename bash "$STATE" transact "$TMP/request.json"
[[ ! -s $TMP/out ]] || fail 'failed directory barrier acknowledged'
commit
assert_json '.sequence==1'
ok 'uncertain rename replays instead of duplicating operation'

# Actual failing sync executable exercises capability/file/directory barriers.
mkdir "$TMP/bin"
real_sync=$(command -v sync)
cat > "$TMP/bin/sync" <<'SH'
#!/usr/bin/env bash
if [[ ${SYNC_FAIL_MODE:-} == probe ]]; then exit 19; fi
if [[ ${SYNC_FAIL_MODE:-} == file && ${*: -1} == */journal/.tmp.* ]]; then exit 19; fi
if [[ ${SYNC_FAIL_MODE:-} == directory && ${*: -1} == */journal ]]; then
  if [[ -e $SYNC_COUNTER ]]; then exit 19; fi
  : > "$SYNC_COUNTER"
fi
exec "$REAL_SYNC" "$@"
SH
chmod +x "$TMP/bin/sync"
new_store; request
expect 2 env PATH="$TMP/bin:$PATH" REAL_SYNC="$real_sync" SYNC_FAIL_MODE=probe bash "$STATE" transact "$TMP/request.json"
[[ $(cat "$TMP/err") == *unsupported_capability* ]] || fail 'missing unsupported capability'
for mode in file directory; do
    new_store; request; rm -f "$TMP/sync-count"
    expect 1 env PATH="$TMP/bin:$PATH" REAL_SYNC="$real_sync" SYNC_COUNTER="$TMP/sync-count" SYNC_FAIL_MODE="$mode" bash "$STATE" transact "$TMP/request.json"
    [[ ! -s $TMP/out ]] || fail 'sync failure acknowledged'
    commit; assert_json '.sequence==1'
    ok "real sync $mode failure refuses acknowledgement and recovers"
done

new_store; request; commit
request racer-a 1 2; cp "$TMP/request.json" "$TMP/a.json"
request racer-b 1 3; cp "$TMP/request.json" "$TMP/b.json"
(set +e; bash "$STATE" transact "$TMP/a.json" > "$TMP/a.out" 2> "$TMP/a.err"; echo $? > "$TMP/a.exit") & a=$!
(set +e; bash "$STATE" transact "$TMP/b.json" > "$TMP/b.out" 2> "$TMP/b.err"; echo $? > "$TMP/b.exit") & b=$!
wait "$a"
wait "$b"
[[ $(sort "$TMP/a.exit" "$TMP/b.exit" | tr '\n' ' ') == '0 2 ' ]] || fail 'concurrent CAS did not select one writer'
expect 0 bash "$STATE" get config capacity
assert_json '.revision==2'
ok 'concurrent capacity writers select exactly one expected revision'
new_store; request
pids=()
for i in 1 2 3 4; do
    (set +e; bash "$STATE" transact "$TMP/request.json" > "$TMP/dedupe-$i.out" 2> "$TMP/dedupe-$i.err"; echo $? > "$TMP/dedupe-$i.exit") & pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
for i in 1 2 3 4; do
    [[ $(cat "$TMP/dedupe-$i.exit") == 0 ]] || fail 'concurrent dedupe writer failed'
    cmp -s "$TMP/dedupe-1.out" "$TMP/dedupe-$i.out" || fail 'concurrent dedupe changed receipt'
done
ok 'concurrent identical operations return one durable outcome'

new_store
lock_fixture 2147483647 0
expect 0 bash "$STATE" replay
raw=$(cat "/proc/$$/stat"); raw=${raw##*) }; read -r -a proc_fields <<< "$raw"
lock_fixture "$$" 0
expect 0 bash "$STATE" replay
ok 'dead and reused PID locks reclaim with start-token evidence'
lock_fixture "$$" "${proc_fields[19]}"
expect 2 bash "$STATE" replay
[[ -e $LOOM_STATE/v2/lock.json ]] || fail 'live lock removed'
ok 'exact live owner cannot be reclaimed'
for field in host_id boot_id pid_namespace; do
    lock_fixture 2147483647 0
    jq -cS --arg field "$field" '.[$field]=(if $field=="host_id" then "git-blob-sha1-v1:0000000000000000000000000000000000000000" else "foreign" end)' "$LOOM_STATE/v2/lock.json" > "$TMP/edit.json"
    cp "$TMP/edit.json" "$LOOM_STATE/v2/lock.json"
    expect 2 bash "$STATE" replay
    [[ -e $LOOM_STATE/v2/lock.json ]] || fail 'foreign lock removed'
    ok "ambiguous $field blocks reclamation"
done
lock_fixture 2147483647 0
pids=()
for i in 1 2 3 4; do
    (set +e; bash "$STATE" replay > "$TMP/reclaim-$i.out" 2> "$TMP/reclaim-$i.err"; echo $? > "$TMP/reclaim-$i.exit") & pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
for i in 1 2 3 4; do [[ $(cat "$TMP/reclaim-$i.exit") == 0 ]] || fail 'reclaim race'; done
ok 'concurrent reclaim cannot remove a replacement owner'
(flock -x 9; : > "$TMP/held"; sleep 1) 9<> "$LOOM_STATE/v2/guard" & holder=$!
while [[ ! -e $TMP/held ]]; do sleep 0.01; done
expect 124 env LOOM_STATE_TIMEOUT_MS=30 bash "$STATE" replay
wait "$holder"
ok 'whole-call timeout bounds busy lock wait'

for unsafe in root ancestor v2 journal record snapshot lock guard nested hardlink mode unreadable fifo; do
    new_store; request; commit
    case $unsafe in
        root) mv "$LOOM_STATE" "$TMP/real-store"; ln -s "$TMP/real-store" "$LOOM_STATE" ;;
        ancestor) mkdir "$TMP/parent"; mv "$LOOM_STATE" "$TMP/parent/store"; ln -s "$TMP/parent" "$TMP/link-parent"; export LOOM_STATE="$TMP/link-parent/store" ;;
        v2) mv "$LOOM_STATE/v2" "$TMP/real-v2"; ln -s "$TMP/real-v2" "$LOOM_STATE/v2" ;;
        journal) mv "$LOOM_STATE/v2/journal" "$TMP/real-journal"; ln -s "$TMP/real-journal" "$LOOM_STATE/v2/journal" ;;
        record) rm "$LOOM_STATE/v2/journal/0000000000000001.json"; ln -s "$TMP/request.json" "$LOOM_STATE/v2/journal/0000000000000001.json" ;;
        snapshot) rm "$LOOM_STATE/v2/snapshot.json"; ln -s "$TMP/request.json" "$LOOM_STATE/v2/snapshot.json" ;;
        lock) ln -s "$TMP/request.json" "$LOOM_STATE/v2/lock.json" ;;
        guard) rm "$LOOM_STATE/v2/guard"; ln -s "$TMP/request.json" "$LOOM_STATE/v2/guard" ;;
        nested) mkdir "$LOOM_STATE/v2/nested"; ln -s "$TMP/request.json" "$LOOM_STATE/v2/nested/link" ;;
        hardlink) ln "$LOOM_STATE/v2/snapshot.json" "$TMP/hardlink" ;;
        mode) chmod 755 "$LOOM_STATE/v2" ;;
        unreadable) chmod 000 "$LOOM_STATE/v2/journal/0000000000000001.json"; rm "$LOOM_STATE/v2/snapshot.json" ;;
        fifo) mkfifo "$LOOM_STATE/v2/fifo" ;;
    esac
    expect 2 bash "$STATE" replay
    ok "refuse unsafe $unsafe"
    if [[ $unsafe == ancestor ]]; then export LOOM_STATE="$TMP/store"; fi
    if [[ -L $LOOM_STATE ]]; then rm "$LOOM_STATE"; fi
done
new_store
request
for invalid in duplicate pretty unknown float nul nul_key timestamp multiple schema; do
    request
    case $invalid in
        duplicate) sed 's/"schema":2/"schema":2,"schema":2/' "$TMP/request.json" > "$TMP/edit.json"; mv "$TMP/edit.json" "$TMP/request.json" ;;
        pretty) jq . "$TMP/request.json" > "$TMP/edit.json"; mv "$TMP/edit.json" "$TMP/request.json" ;;
        unknown) edit_request '.unexpected=true' ;;
        float) edit_request '.actor.epoch=0.5' ;;
        nul_key) edit_request '.result["\u0000"]=true' ;;
        timestamp) edit_request '.events[0].observed_at="2026-02-30T00:00:00Z"' ;;
        nul) edit_request '.result.bad="\u0000"' ;;
        multiple) cat "$TMP/request.json" > "$TMP/edit.json"; cat "$TMP/edit.json" >> "$TMP/request.json" ;;
        schema) edit_request '.schema=3' ;;
    esac
    expect 2 bash "$STATE" transact "$TMP/request.json"
    ok "refuse invalid $invalid request"
done

rm -rf "$LOOM_STATE"; mkdir "$LOOM_STATE"
jq -cn '{ticket:1,repo:"example/fixture",short_name:"fixture",workdir:"/workspace/fixture",checkout:"/workspace/consumer",base_sha:"0000000000000000000000000000000000000000",attempt:1,started_at:"2026-11-08T00:00:00Z",reports:[],executor:{kind:"orca",state:"running"},worker_pid:null}' > "$LOOM_STATE/legacy.json"
before=$(git hash-object "$LOOM_STATE/legacy.json")
expect 0 bash "$STATE" legacy-get legacy
assert_json '.schema==1 and .read_only and .identity=="unknown" and .origin_provider=="orca"'
[[ ! -e $LOOM_STATE/v2 ]] || fail 'legacy read initialized v2'
expect 0 bash "$STATE" init store-example
request; commit
[[ $(git hash-object "$LOOM_STATE/legacy.json") == "$before" ]] || fail 'legacy rewritten'
[[ $(find "$LOOM_STATE" -maxdepth 1 -name '*.json' | wc -l) == 1 ]] || fail 'v2 leaked into legacy glob'
expect 2 bash "$STATE" legacy-get ../escape
expect 2 bash "$STATE" get config legacy
ok 'legacy read-only route and v2 schema/path isolation'

# Exercise exported functions directly and validate operation/entity lifecycles.
# shellcheck disable=SC2016 # Resolve positional arguments inside child.
expect 0 bash -c 'source "$1"; loom_state_get config capacity' _ "$STATE"
assert_json '.revision==1'
# shellcheck disable=SC2016 # Resolve positional arguments inside child.
expect 0 bash -c 'source "$1"; loom_events_read 0 100' _ "$EVENTS"
assert_json '.next_sequence==1'
ok 'sourceable functions execute the same bounded store path'
cp "$LOOM_STATE/v2/snapshot.json" "$TMP/lagged.json"
request next 1 2; commit
cp "$TMP/lagged.json" "$LOOM_STATE/v2/snapshot.json"
expect 0 bash "$STATE" replay
assert_json '.sequence==2'
jq -e '.entities.config.capacity.revision==2' "$LOOM_STATE/v2/snapshot.json" >/dev/null
ok 'valid lagged snapshot replays the missing committed suffix'
request reused-id 2 3
edit_request '.operation_id="op-1"'
expect 2 bash "$STATE" transact "$TMP/request.json"
[[ $(cat "$TMP/err") == *idempotency_conflict* ]] || fail 'reused operation ID was not rejected'
request distinct-actor null 7
edit_request '.actor.id="other-actor" | .idempotency_key="op-1" | .changes[0].id="another"'
commit
ok 'dedupe scope distinguishes actors and refuses reused operation IDs'
request batch 2 3
edit_request '.changes += [{kind:"host",id:"host-example",expected_revision:null,run_id:null,epoch:0,data:{slots:2}}] | .events += [{type:"host.created",entity_ids:["host-example"],payload:{},observed_at:null}]'
commit
assert_json '(.revisions|length)==2 and .revisions[0].revision==3 and .revisions[1].revision==1'
expect 0 bash "$EVENTS" 3 100
assert_json '(.events|length)==2 and .events[0].sequence==4 and .events[1].sequence==5 and .events[0].transaction_id==.events[1].transaction_id'
ok 'atomic multi-record success and multi-event sequence allocation'
request wrong-store 3 4
edit_request '.store_id="another-store"'
expect 2 bash "$STATE" transact "$TMP/request.json"
[[ $(cat "$TMP/err") == *identity_mismatch* ]] || fail 'store mismatch not diagnosed'
request duplicate-change 3 4
edit_request '.changes += .changes'
expect 2 bash "$STATE" transact "$TMP/request.json"
request large-revision 3 4
edit_request '.changes[0].expected_revision=9007199254740992'
expect 2 bash "$STATE" transact "$TMP/request.json"
ok 'store binding, duplicate changes and unsafe integers fail closed'
request symlink-input 3 4
ln -s "$TMP/request.json" "$TMP/request-link.json"
expect 2 bash "$STATE" transact "$TMP/request-link.json"
ok 'request-file symlink is refused'
# Retrying an intent and later reconciliation keeps both transaction history and
# the same lifecycle operation entity, with CAS at each stage.
new_store
request create-run
edit_request '.actor.run_id="run-example" | .changes=[{kind:"run",id:"run-example",expected_revision:null,run_id:"run-example",epoch:0,data:{owner_id:"actor-example"}}]'
commit
request intent
edit_request '.actor.run_id="run-example" | .changes=[{kind:"operation",id:"launch-example",expected_revision:null,run_id:"run-example",epoch:0,data:{stage:"intent",receipts:[],effects:[]}}]'
commit
cp "$TMP/request.json" "$TMP/intent.json"
request reconcile
edit_request '.actor.run_id="run-example" | .checks=[{kind:"run",id:"run-example",revision:1}] | .changes=[{kind:"operation",id:"launch-example",expected_revision:1,run_id:"run-example",epoch:0,data:{stage:"accepted",receipts:[{synthetic:true}],effects:[]}}]'
commit
expect 0 bash "$STATE" transact "$TMP/intent.json"
assert_json '.sequence==2'
expect 0 bash "$STATE" get operation launch-example
assert_json '.revision==2 and .data.stage=="accepted"'
ok 'intent and reconciliation retain history without reopening an old effect'
printf 'PASS: %s storage assertions\n' "$passed"
