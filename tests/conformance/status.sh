#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
scratch=$(mktemp -d)
trap 'chmod -R u+rwX "$scratch"; rm -rf -- "$scratch"' EXIT
export LOOM_STATE=$scratch/state
mkdir "$LOOM_STATE"
for kind in malformed invalid unreadable; do
    case $kind in
        malformed) printf '{' > "$LOOM_STATE/broken.json" ;;
        invalid) printf '{}\n' > "$LOOM_STATE/broken.json" ;;
        unreadable) chmod 000 "$LOOM_STATE/broken.json" ;;
    esac
    rc=0
    bash "$root/ops/loom" status > "$scratch/result" 2> "$scratch/error" || rc=$?
    [[ $rc != 0 && $(wc -l < "$scratch/result") == 1 ]]
    jq -e 'keys==["actions","cmd","fact","id","items","ok","state","ticket","v"] and .ok==false and .cmd=="status" and (.fact|length>0)' "$scratch/result" >/dev/null
    printf 'ok status %s is one error envelope (exit %s)\n' "$kind" "$rc"
done
chmod 600 "$LOOM_STATE/broken.json"
rm "$LOOM_STATE/broken.json"
bash "$root/ops/loom" status | jq -e '.ok and .state=="waiting" and .items==[]' >/dev/null
printf 'PASS corrupt status envelope and healthy empty compatibility\n'
