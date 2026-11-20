#!/usr/bin/env bash
# Reserve private instance storage. The consumer config is supplied by setup.
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
[[ $# == 0 ]] || loom_error 'usage: setup-worktree.sh (run in the consumer or set LOOM_REPO)'
checkout=$(git -C "${LOOM_REPO:-.}" rev-parse --show-toplevel) || loom_error 'select a consumer Git worktree'
loom_check_instance "$checkout"
ignore=$checkout/.gitignore
[[ ! -L $ignore && ( ! -e $ignore || -f $ignore ) ]] || loom_error 'expected a regular root .gitignore'
if [[ ! -f $ignore ]] || ! grep -qxF '/.loom-instance/' "$ignore"; then
    printf '\n/.loom-instance/\n' >> "$ignore"
fi
git -C "$checkout" check-ignore -q -- .loom-instance/ || loom_error 'review rules overriding /.loom-instance/ in .gitignore'
(umask 077 && mkdir -p "$checkout/.loom-instance/state")
printf '%s\n' "$checkout/.loom-instance"
