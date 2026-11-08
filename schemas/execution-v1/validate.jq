# Deliberately limited interpreter for the keywords used by the checked-in
# 2020-12 schemas. Unknown assertion keywords are rejected by the suite audit.
def matches($s; $root):
  . as $v |
  if ($s|type)=="boolean" then $s
  elif $s|has("$ref") then
    ($s["$ref"]|ltrimstr("#/" )|split("/")) as $p |
    matches($root|getpath($p); $root)
  else
    (if $s|has("type") then
       if $s.type=="integer" then type=="number" and .==floor and (isinfinite|not) and (isnan|not)
       else type==$s.type end else true end) and
    (if $s|has("const") then .==$s.const else true end) and
    (if $s|has("enum") then . as $x | $s.enum|index($x)!=null else true end) and
    (if $s|has("not") then matches($s.not;$root)|not else true end) and
    (if $s|has("allOf") then all($s.allOf[]; . as $sub | $v|matches($sub;$root)) else true end) and
    (if $s|has("anyOf") then any($s.anyOf[]; . as $sub | $v|matches($sub;$root)) else true end) and
    (if $s|has("oneOf") then [$s.oneOf[]|. as $sub|$v|matches($sub;$root)|select(.)]|length==1 else true end) and
    (if $s|has("if") then
      if matches($s.if;$root) then matches($s.then//true;$root) else matches($s.else//true;$root) end
     else true end) and
    (if type=="number" then
      (if $s|has("minimum") then . >= $s.minimum else true end) and
      (if $s|has("maximum") then . <= $s.maximum else true end)
     elif type=="string" then
      (if $s|has("minLength") then length >= $s.minLength else true end) and
      (if $s|has("maxLength") then length <= $s.maxLength else true end) and
      (if $s|has("x-loom-maxUtf8Bytes") then utf8bytelength <= $s["x-loom-maxUtf8Bytes"] else true end) and
      (if $s|has("pattern") then test($s.pattern) else true end) and
      (if $s.format?=="date-time" then . as $date | try ((fromdateiso8601|strftime("%Y-%m-%dT%H:%M:%SZ"))==$date) catch false else true end)
     elif type=="array" then
      (if $s|has("minItems") then length >= $s.minItems else true end) and
      (if $s|has("maxItems") then length <= $s.maxItems else true end) and
      (if $s.uniqueItems//false then length==(unique|length) else true end) and
      all(range(0;length); . as $i | $v[$i] | matches(($s.prefixItems[$i]//$s.items//true);$root))
     elif type=="object" then
      (if $s|has("maxProperties") then length <= $s.maxProperties else true end) and
      all(($s.required//[])[]; . as $k | $v|has($k)) and
      all(keys[]; . as $k |
        ($k|matches($s.propertyNames//true;$root)) and
        ($v[$k]|matches(($s.properties[$k]//$s.additionalProperties//true);$root))) and
      (if $s.additionalProperties==false then (keys-($s.properties//{}|keys)|length)==0 else true end)
     else true end)
  end;
# Wire-level assertions apply even inside optional extension values.
def wire:
  all(..; if type=="string" then (contains("\u0000")|not)
         elif type=="number" then (isinfinite|not) and (isnan|not) else true end);
def unique_names:
  if type=="array" then length==([.[].name]|unique|length) else false end;
def observation_identity:
  .identity==null or (.identity.attempt_id==.binding.attempt_id and .identity.host_id==.binding.host_id);
def unique_field($key): length==([.[]|getpath($key)]|unique|length);
def semantics:
  (if .op?=="execution.reconcile" and .ok? then .result.observation|observation_identity
   elif .op?=="execution.list" and .ok? then all(.result.items[];observation_identity) and (.result.items|unique_field(["binding","attempt_id"]))
   elif .op?=="watch" and .ok? then all(.result.observations[];observation_identity) and (.result.observations|unique_field(["binding","attempt_id"]))
   else true end) and
  (if .op?=="mail.read" and .ok? then
      .result.delivery.message_id==.result.message.message_id and
      (.result.delivery.recipient as $recipient|.result.message.to|index($recipient)!=null)
   elif (.op?=="mail.send" or .op?=="mail.reply" or .op?=="mail.status") and .ok? then
      .result.message_id as $message | all(.result.deliveries[];.message_id==$message) and (.result.deliveries|unique_field(["delivery_id"]))
   else true end) and
  (if .args.deps? then [.args.deps[].task_id] as $ids | ($ids|length)==($ids|unique|length) else true end) and
  (if .result.capabilities? then .result.capabilities|unique_names else true end) and
  (if .capabilities? then .capabilities|unique_names else true end) and
  (if .op?=="execution.start" and .ok?==true then
      .result.binding==.target and
      (.result.identity==null or (.result.identity.attempt_id==.target.attempt_id and .result.identity.host_id==.target.host_id))
   elif (.op?=="execution.inspect" or .op?=="execution.stop" or .op?=="execution.release" or .op?=="execution.prompt" or .op?=="execution.fence") and .ok?==true then
      .result.binding==.target and
      (if .result.identity? then .result.identity.attempt_id==.target.attempt_id and .result.identity.host_id==.target.host_id else true end)
   elif .op?=="execution.reconcile" and .ok?==true then .result.observation.binding==.target
   else true end);
wire and matches($schema[0]["$defs"][$kind];$schema[0]) and semantics
