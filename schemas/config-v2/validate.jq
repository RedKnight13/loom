# Closed runtime schemas. All numeric fields are bounded integer tokens.
def closed($fields): type == "object" and (keys == ($fields | sort));
def text: type == "string" and utf8bytelength <= 65536 and (contains("\u0000") | not);
def name: text and length > 0 and utf8bytelength <= 128;
def path: text and startswith("/") and (test("[\u0000-\u001f\u007f]") | not)
  and (split("/")[1:] | all(. != "" and . != "." and . != ".."));
def digest: type == "string" and test("^git-blob-sha1-v1:[0-9a-f]{40}$");
def argv: type == "array" and length <= 256 and all(.[]; text);
def names: type == "array" and length > 0 and length <= 256
  and all(.[]; name) and (unique | length) == length;
def integer($max): type == "number" and . >= 1 and . <= $max and floor == .;
def mapping: . == null or (closed(["argv","values"]) and (.argv | argv and length > 0)
  and (.values | names));
def config: closed(["schema","repo","execution","limits","ticket_provider"])
  and .schema == 2 and (.repo | name) and .ticket_provider == "github"
  and (.execution | closed(["provider","transport","placement","agent_profile","model","effort"])
    and (.provider | name) and (.transport == "ssh" or .transport == "process")
    and (.agent_profile | name) and (.model == null or (.model | name))
    and (.effort == null or (.effort | name))
    and (.placement | closed(["allowed_hosts","selection","selected_host","allow_local","fallback"])
      and (.allowed_hosts | names) and .selection == "explicit"
      and (.selected_host | name) and (.allow_local | type == "boolean") and .fallback == "deny"
      and (.selected_host as $h | .allowed_hosts | index($h) != null)))
  and (.limits | closed(["workers","operation_timeout_ms"])
    and (.workers | integer(10000)) and (.operation_timeout_ms | integer(300000)));
def host: closed(["id","transport","destination","workspace_root","identity","helper"])
  and (.id | name) and (.transport == "ssh" or .transport == "process")
  and (if .transport == "ssh" then (.destination | type == "string" and
    test("^[A-Za-z0-9][A-Za-z0-9_.@:-]{0,254}$")) else .destination == null end)
  and (.workspace_root | path) and (.identity | name)
  and (.helper | closed(["version","digest"]) and (.version | name) and (.digest | digest));
def agent: closed(["id","executable","argv","prompt_ingress","model","effort"])
  and (.id | name) and (.executable | path) and (.argv | argv and length <= 253)
  and (.prompt_ingress == "stdin" or .prompt_ingress == "file")
  and (.model | mapping) and (.effort | mapping);
def adapter: closed(["id","executable","argv"])
  and (.id | name and . != "native") and (.executable | path) and (.argv | argv);
def unique_ids: (map(.id) | unique | length) == length;
def hosts: closed(["schema","hosts"]) and .schema == 2 and
  (.hosts | type == "array" and length > 0 and length <= 256 and all(.[]; host) and unique_ids);
def profiles: closed(["schema","agents","adapters"]) and .schema == 2 and
  (.agents | type == "array" and length > 0 and length <= 256 and all(.[]; agent) and unique_ids)
  and (.adapters | type == "array" and length <= 256 and all(.[]; adapter) and unique_ids);
def context: closed(["schema","store_id","actor_id","operation_id","idempotency_key","run_id","attempt_id"])
  and .schema == 2 and all(.store_id,.actor_id,.operation_id,.idempotency_key,.run_id,.attempt_id; name);
def slot: closed(["attempt_id","run_id","scope_digest","state"])
  and (.attempt_id | name) and (.run_id | name) and (.scope_digest | digest)
  and (.state | IN("reserved","running","unknown","settled"));
def ledger: closed(["schema","kind","id","revision","run_id","epoch","data"])
  and .schema == 2 and .kind == "config" and .id == "loom.policy.capacity"
  and (.revision | integer(9007199254740991)) and .run_id == null and .epoch == 0
  and (.data | closed(["schema","slots"]) and .schema == 2
    and (.slots | type == "array" and all(.[]; slot)
      and (map(.attempt_id) | unique | length) == length));
def observation: closed(["schema","scope_digest","state","evidence_ref","confirmed_stopped"])
  and .schema == 2 and (.scope_digest | digest)
  and (.state | IN("running","unknown","settled"))
  and (.evidence_ref | name)
  and (.confirmed_stopped | type == "boolean")
  and (if .state == "settled" then .confirmed_stopped else (.confirmed_stopped | not) end);
def stamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
  and (try (fromdateiso8601 | type == "number") catch false);
def artifact: type == "string" and length <= 256 and test("^[A-Za-z0-9][A-Za-z0-9_-]*(/[A-Za-z0-9][A-Za-z0-9_-]*)*$");
def discovery_observation:
  closed(["dimension","value","source","observed_at","evidence_ref","attempt_id"])
  and (.dimension | IN("installed","reachable","launch_verified"))
  and (.value == null or (.value | type == "boolean")) and (.observed_at | stamp)
  and (.evidence_ref == null or (.evidence_ref | artifact))
  and (.attempt_id == null or (.attempt_id | name))
  and (if .value == null then .source == "unavailable"
    elif .dimension == "installed" then .attempt_id == null and .evidence_ref != null and
      (if .value then .source == "bounded_version_probe" else .source == "missing_executable" end)
    elif .dimension == "reachable" then .source == "transport_probe" and .attempt_id == null and .evidence_ref != null
    else .source == "authorized_attempt" and .attempt_id != null and .evidence_ref != null end);
def discovery_evidence: closed(["schema","scope_digest","observations"]) and .schema == 2
  and (.scope_digest | digest) and (.observations | type == "array" and length <= 3
    and all(.[]; discovery_observation) and (map(.dimension) | unique | length) == length);
if $kind == "config" then config elif $kind == "hosts" then hosts
elif $kind == "profiles" then profiles elif $kind == "context" then context
elif $kind == "ledger" then ledger elif $kind == "observation" then observation
elif $kind == "discovery-evidence" then discovery_evidence else false end
