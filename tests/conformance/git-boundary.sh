#!/usr/bin/env bash
# Git config/attributes are input, never implicit approval to run helper commands.
# shellcheck disable=SC1091,SC2016
set -euo pipefail
project_root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
source "$project_root/ops/remote-helper.sh"
source "$project_root/ops/workflow.sh"
umask 077
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
_rw_workspace=$scratch/repo
mkdir "$_rw_workspace"
git init -q "$_rw_workspace"
git -C "$_rw_workspace" config user.name Fixture
git -C "$_rw_workspace" config user.email fixture@example.invalid
printf base > "$_rw_workspace/data"
printf 'data text eol=lf\n' > "$_rw_workspace/.gitattributes"
GIT_INDEX_FILE=$scratch/index _loom_rw_git_index read-tree --empty
printf 'data\0.gitattributes\0' | GIT_INDEX_FILE=$scratch/index _loom_rw_git_index update-index --add -z --stdin
tree=$(GIT_INDEX_FILE=$scratch/index _loom_rw_git_index write-tree)
sha=$(printf fixture | _loom_remote_git -C "$_rw_workspace" commit-tree "$tree")
_loom_remote_git -C "$_rw_workspace" update-ref HEAD "$sha"
_loom_remote_git -C "$_rw_workspace" read-tree "$sha"
[[ $(_loom_remote_git -C "$_rw_workspace" rev-parse HEAD) == "$sha" ]]
_loom_remote_git -C "$_rw_workspace" status --porcelain >/dev/null
printf 'ok ordinary config, text attributes, exact objects and isolated index\n'
printf '#!/bin/sh\nprintf invoked >> %s\ncat\n' "$scratch/marker" > "$scratch/command"
chmod 700 "$scratch/command"
reject() { local rc=0; "$@" > "$scratch/out" 2> "$scratch/error" || rc=$?; [[ $rc == 2 && ! -e $scratch/marker ]]; }
git -C "$_rw_workspace" config filter.review.clean "$scratch/command"
printf 'data filter=review\n' > "$_rw_workspace/.gitattributes"
GIT_INDEX_FILE=$scratch/index reject _loom_rw_git_index read-tree HEAD
printf 'data\0' | GIT_INDEX_FILE=$scratch/index reject _loom_rw_git_index update-index --add -z --stdin
reject _loom_remote_git -C "$_rw_workspace" status --porcelain
git -C "$_rw_workspace" config --remove-section filter.review
# A filter attribute is unsupported even without a configured executable.
reject _loom_remote_git -C "$_rw_workspace" rev-parse HEAD
printf 'data text eol=lf\n' > "$_rw_workspace/.gitattributes"
git -C "$_rw_workspace" config core.fsmonitor "$scratch/command"
reject _loom_remote_git -C "$_rw_workspace" status --porcelain
git -C "$_rw_workspace" config --unset core.fsmonitor
printf '[core]\nfsmonitor = %s\n' "$scratch/command" > "$scratch/included"
git -C "$_rw_workspace" config include.path "$scratch/included"
reject _loom_remote_git -C "$_rw_workspace" rev-parse HEAD
git -C "$_rw_workspace" config --unset include.path
# Clone sources cannot import command-bearing repository metadata.
git -C "$_rw_workspace" config uploadpack.packObjectsHook "$scratch/command"
reject _loom_remote_git clone --no-checkout "$_rw_workspace" "$scratch/check"
git -C "$_rw_workspace" config --remove-section uploadpack
_loom_remote_git clone --no-hardlinks --no-checkout "$_rw_workspace" "$scratch/check" >/dev/null 2>&1
_loom_remote_git -C "$scratch/check" checkout --detach "$sha" >/dev/null 2>&1
[[ $(cat "$scratch/check/data") == base && ! -e $scratch/marker ]]
printf 'PASS clean-filter/fsmonitor/include/clone hook denied without execution; legitimate Git objects preserved\n'

# Exact target-tree bypass: source has objects but an empty index/worktree.
for attribute in working-tree-encoding=UTF-16LE filter=review eol=crlf; do
    mkdir "$scratch/target-source"
    git init -q "$scratch/target-source"
    blob=$(printf 'abc\n' | git -C "$scratch/target-source" hash-object -w --stdin)
    attrs=$(printf 'data %s\n' "$attribute" | git -C "$scratch/target-source" hash-object -w --stdin)
    tree=$(printf '100644 blob %s\t.gitattributes\n100644 blob %s\tdata\n' "$attrs" "$blob" | git -C "$scratch/target-source" mktree)
    sha=$(GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid git -C "$scratch/target-source" commit-tree "$tree" -m fixture)
    git -C "$scratch/target-source" update-ref HEAD "$sha"
    _loom_remote_git clone --no-hardlinks --no-checkout "$scratch/target-source" "$scratch/target-check" > "$scratch/clone-log" 2>&1
    reject _loom_remote_git -C "$scratch/target-check" checkout --detach "$sha"
    reject _loom_remote_git -C "$scratch/target-check" read-tree --reset -u "$sha"
    reject _loom_remote_git -C "$scratch/target-check" reset --hard "$sha"
    [[ ! -e $scratch/target-check/data && ! -e $scratch/target-check/.gitattributes ]]
    rm -rf -- "$scratch/target-source" "$scratch/target-check"
done
printf 'PASS target-tree encoding/filter/CRLF rejected before checkout/read-tree/reset materialization\n'
