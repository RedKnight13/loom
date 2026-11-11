#!/usr/bin/env bash
# The baseline regression suite additionally covers legacy local/Orca fixtures.
set -euo pipefail
root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export LOOM_STATE=$scratch/state
bash "$root/ops/loom" status | jq -S '.v="VERSION"' > "$scratch/result"
jq -S . "$root/tests/conformance/legacy-golden.json" > "$scratch/golden"
cmp "$scratch/result" "$scratch/golden"
# Reading v2 configuration is opt-in; it never changes legacy TOML semantics.
bash -c 'source "$1/ops/lib.sh"; loom_config "$1/consumers/example.toml"' _ "$root" > "$scratch/config"
jq -e '.repo and .worktrees and .laws' "$scratch/config" >/dev/null
printf 'PASS legacy empty status golden and TOML reader\n'
