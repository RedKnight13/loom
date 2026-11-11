def keysare($k): type == "object" and (keys == ($k|sort));
def uint: type == "number" and . >= 0 and . <= 9007199254740991 and . == floor;
def id: type == "string" and utf8bytelength > 0 and utf8bytelength <= 128 and (contains("\u0000")|not);
def kind: IN("run","task","assignment","attempt","message","delivery","gate","operation","config","host","profile");
def stamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") and (. as $date | try ((fromdateiso8601 | strftime("%Y-%m-%dT%H:%M:%SZ"))==$date) catch false);
def digest: type == "string" and test("^git-blob-sha1-v1:[0-9a-f]{40}$");
def jsonsafe: all(..; if type=="object" then all(keys[]; (contains("\u0000")|not)) elif type=="string" then (contains("\u0000")|not) elif type=="number" then isfinite and (if .==floor then (fabs <= 9007199254740991) else true end) else true end);
def actor: keysare(["id","run_id","epoch"]) and (.id|id) and (.run_id == null or (.run_id|id)) and (.epoch|uint);
def check: keysare(["kind","id","revision"]) and (.kind|kind) and (.id|id) and (.revision|uint);
def change:
  keysare(["kind","id","expected_revision","run_id","epoch","data"]) and
  (.kind|kind) and (.id|id) and (.expected_revision == null or (.expected_revision|uint)) and
  (.run_id == null or (.run_id|id)) and (.epoch|uint) and (.data|type=="object") and
  (if .kind=="run" then .run_id==.id and (.data.owner_id|id) else true end);
def event:
  keysare(["type","entity_ids","payload","observed_at"]) and (.type|id) and
  (.entity_ids|type=="array" and length<=100 and all(.[];id) and length==(unique|length)) and
  (.payload|type=="object") and (.observed_at==null or (.observed_at|stamp));
def request:
  keysare(["schema","store_id","operation_id","idempotency_key","op","actor","target","checks","changes","events","result"]) and
  .schema==2 and (.store_id|id) and (.operation_id|id) and (.idempotency_key|id) and (.op|id) and
  (.actor|actor) and (.target|type=="object") and
  (.checks|type=="array" and length<=100 and all(.[];check) and length==([.[]|[.kind,.id]]|unique|length)) and
  (.changes|type=="array" and length<=100 and all(.[];change) and length==([.[]|[.kind,.id]]|unique|length)) and
  (.events|type=="array" and length>=1 and length<=100 and all(.[];event)) and
  (.result|type=="object") and jsonsafe;
def metadata: keysare(["schema","store_id","created_at"]) and .schema==2 and (.store_id|id) and (.created_at|stamp);
def lock:
  keysare(["schema","host_id","boot_id","pid_namespace","pid","start_ticks","nonce"]) and .schema==2 and
  (.host_id|digest) and (.boot_id|id) and (.pid_namespace|id) and
  (.pid|uint and .>1) and (.start_ticks|type=="string" and test("^[0-9]+$")) and
  (.nonce|type=="string" and test("^[a-f0-9-]{36}$"));
def transaction:
  keysare(["schema","store_id","sequence","transaction_id","previous_digest","recorded_at","request","request_digest","events","outcome"]) and
  .schema==2 and (.store_id|id) and (.sequence|uint and .>0) and (.transaction_id|id) and
  (.previous_digest==null or (.previous_digest|digest)) and (.recorded_at|stamp) and
  (.request|request) and (.request_digest|digest) and (.events|type=="array") and (.outcome|type=="object") and jsonsafe;
if $kind=="request" then request
elif $kind=="metadata" then metadata
elif $kind=="lock" then lock
elif $kind=="transaction" then transaction
else false end
