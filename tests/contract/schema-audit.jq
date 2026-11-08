# Fail when a schema begins using an assertion the restricted interpreter does
# not implement. Property names and annotation payloads are not schema keywords.
def audit:
  if type=="boolean" then true else
    ([keys[]]-["$schema","$id","$ref","$defs","title","description","examples",
      "type","const","enum","not","allOf","anyOf","oneOf","if","then","else",
      "minimum","maximum","minLength","maxLength","pattern","format",
      "minItems","maxItems","uniqueItems","items","prefixItems",
      "properties","required","additionalProperties","maxProperties","propertyNames",
      "x-loom-maxUtf8Bytes","x-loom-operations","x-loom-maxEnvelopeBytes",
      "x-loom-maxHelloBytes","x-loom-maxDepth"]|length)==0 and
    all((.properties//{}|.[]),(."$defs"//{}|.[]),(.prefixItems//[]|.[]),(.allOf//[]|.[]),
        (.anyOf//[]|.[]),(.oneOf//[]|.[]),(.items//true),(.additionalProperties//true),
        (.propertyNames//true),(.not//true),(.if//true),(.then//true),(.else//true); audit)
  end;
audit
