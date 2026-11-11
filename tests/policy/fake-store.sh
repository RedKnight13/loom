#!/usr/bin/env bash
# Synthetic CAS only: no durability, epoch or journal claims. Real S2 is tested
# separately by passing its state.sh path to run.sh.
loom_state_init() { mkdir -p "$LOOM_STATE"; printf '{"store_id":"%s"}\n' "$1"; }
loom_state_get() { [[ $1 == config && $2 == loom.policy.capacity ]] && jq -ce .ledger "$LOOM_STATE/fake.json"; }
loom_state_transact() (
    flock -x 9 || return 2
    local request=$1 previous='{"ledger":null,"receipts":{}}' next hash
    [[ ! -f $LOOM_STATE/fake.json ]] || previous=$(cat "$LOOM_STATE/fake.json")
    hash=$(git hash-object -- "$request") || return 2
    next=$(jq -cen --argjson s "$previous" --slurpfile r "$request" --arg hash "$hash" '
      $r[0] as $r | ($r.actor.id + ":" + $r.op + ":" + $r.idempotency_key) as $key |
      $s.receipts[$key] as $prior |
      if $prior != null then
        if $prior.hash == $hash then {store:$s,result:$prior.result} else error("idempotency_conflict") end
      elif $s.ledger.revision != $r.changes[0].expected_revision then error("revision_conflict")
      else ($r.changes[0]) as $c | (($s.ledger.revision // 0)+1) as $rev |
        {schema:2,operation_id:$r.operation_id,durable:false,result:$r.result} as $result |
        {store:($s | .ledger={schema:2,kind:$c.kind,id:$c.id,revision:$rev,run_id:null,epoch:0,data:$c.data}
          | .receipts[$key]={hash:$hash,result:$result}),result:$result} end') || return 2
    jq -c .store <<< "$next" > "$LOOM_STATE/fake.json"
    jq -c .result <<< "$next"
) 9> "$LOOM_STATE/fake.lock"
