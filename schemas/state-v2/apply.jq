# Replay and live commits use exactly the same CAS and fencing implementation.
def fail($c): error($c);
def entity($s;$k;$id): $s.entities[$k][$id] // null;
. as $s | $q[0] as $q |
if $q.store_id != $s.store_id then fail("identity_mismatch") else . end |
([$s.operations[] | select(.actor_id==$q.actor.id and .op==$q.op and .key==$q.idempotency_key)] | first) as $prior |
if $prior != null then
  if $prior.digest==$digest then {replay:$prior.outcome,state:$s}
  else fail("idempotency_conflict") end
elif any($s.operations[];.operation_id==$q.operation_id) then fail("idempotency_conflict")
else
  entity($s;"run";$q.actor.run_id // "") as $run |
  if $q.actor.run_id==null then
    if $q.actor.epoch!=0 or any($q.changes[];.run_id!=null or (.kind|IN("config","host","profile")|not)) then fail("owner_fenced") else . end
  elif $run==null then
    if $q.actor.epoch!=0 or ([ $q.changes[] | select(.kind=="run" and .id==$q.actor.run_id and .expected_revision==null and .epoch==0 and .data.owner_id==$q.actor.id)]|length)!=1
    then fail("owner_fenced") else . end
  elif $run.epoch!=$q.actor.epoch then fail("owner_fenced") else . end |
  if any($q.checks[]; . as $c | entity($s;$c.kind;$c.id) as $old |
       $old==null or $old.revision!=$c.revision) then fail("revision_conflict") else . end |
  if any($q.checks[]; . as $c | entity($s;$c.kind;$c.id).run_id != $q.actor.run_id) then fail("owner_fenced") else . end |
  reduce $q.changes[] as $c ($s;
    entity($s;$c.kind;$c.id) as $old |
    if ($old==null and $c.expected_revision!=null) or ($old!=null and ($c.expected_revision==null or $old.revision!=$c.expected_revision))
    then fail("revision_conflict") else . end |
    if $c.run_id!=$q.actor.run_id or ($old!=null and $old.run_id!=$c.run_id) then fail("owner_fenced") else . end |
    if $c.kind=="run" then
      if $c.epoch!=$q.actor.epoch and $c.epoch!=($q.actor.epoch+1) then fail("owner_fenced")
      elif $old!=null and $old.data.owner_id!=$c.data.owner_id and $c.epoch!=($old.epoch+1) then fail("owner_fenced")
      else . end
    elif $c.epoch!=$q.actor.epoch then fail("owner_fenced") else . end |
    (($old.revision // 0)+1) as $rev |
    if $rev>9007199254740991 or $c.epoch>9007199254740991 then fail("revision_conflict") else . end |
    .entities[$c.kind][$c.id]={schema:2,kind:$c.kind,id:$c.id,revision:$rev,run_id:$c.run_id,epoch:$c.epoch,data:$c.data}
  ) | {replay:null,state:.}
end
