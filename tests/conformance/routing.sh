#!/usr/bin/env bash
# Authority opt-in applies before an assignment routing snapshot exists.
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
umask 077
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
# shellcheck source=ops/state.sh
source "$repo/ops/state.sh"
export LOOM_STATE=$scratch/state LOOM_ORCA=$scratch/orca
mkdir "$LOOM_STATE"
loom_state_init routing-fixture >/dev/null
printf '#!/usr/bin/env bash\nprintf called >> %q\nexit 89\n' "$scratch/called" > "$LOOM_ORCA"
chmod 700 "$LOOM_ORCA"
for cmd in run task gate status capacity hosts compute; do
    rc=0; bash "$repo/ops/loom" "$cmd" > "$scratch/result" || rc=$?
    [[ $rc == 2 && ! -e $scratch/called ]]
    jq -e '.ok==false and (.fact|contains("explicit --context"))' "$scratch/result" >/dev/null
done
[[ ! -d $LOOM_STATE/v2/workflows ]]
printf 'PASS authority-only v2 routing refuses implicit adapter discovery before dispatch\n'
