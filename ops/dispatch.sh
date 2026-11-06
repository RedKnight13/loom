#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=ops/report.sh
source "${BASH_SOURCE[0]%/*}/report.sh"
[[ $# == 2 ]] || loom_error 'usage: dispatch.sh <consumer.toml> <issue#>'
[[ $2 =~ ^[1-9][0-9]*$ ]] || loom_error 'issue must be a positive integer'
[[ -f $1 ]] || loom_error 'consumer config not found'

# Parse the registration format, never execute it. Strings use JSON-compatible
# TOML escapes; comments are stripped only outside quoted strings.
config=$(jq -Rse '
  def fields:
    if test("^\\s*$") then {}
    else capture("^\\s*(?<key>[a-z_]+)\\s*=\\s*(?<value>\"(?:[^\"\\\\]|\\\\.)*\"|\\[(?:[^]\\\"\\\\]|\"(?:[^\"\\\\]|\\\\.)*\")*\\])(?<rest>[\\s\\S]*)$") as $m |
      ($m.rest | fields) as $rest |
      if $rest | has($m.key) then error("duplicate config key")
      else $rest + {($m.key): ($m.value | sub(",\\s*]$"; "]") | fromjson)} end
    end;
  [scan("\"(?:[^\"\\\\]|\\\\.)*\"|#[^\n]*|[^\"#]+") |
    select(startswith("#") | not)] | join("") | fields |
  if (.repo | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
     (.worktrees | type == "string" and length > 0) and
     (.laws | type == "array" and all(.[]; type == "string")) and
     ((keys - ["repo", "checks", "worktrees", "laws"]) | length == 0)
  then . else error("invalid consumer config") end
' "$1") || loom_error 'unsupported or invalid consumer TOML; see ops/README.md'
repo=$(jq -r '.repo' <<< "$config")
worktrees=$(jq -r '.worktrees' <<< "$config")
case $worktrees in \~) worktrees=$HOME ;; \~/*) worktrees="$HOME/${worktrees:2}" ;; esac
[[ $worktrees == /* ]] || loom_error 'worktrees must be an absolute path (or ~/...)'
checkout=$(git -C "${LOOM_REPO:-.}" rev-parse --show-toplevel) || loom_error 'run in the consumer checkout or set LOOM_REPO'
issue=$(gh issue view "$2" --repo "$repo" --json number,title,body)
jq -e --argjson number "$2" '.number == $number and (.title | type == "string") and (.body | type == "string")' <<< "$issue" >/dev/null || loom_error 'invalid issue response'
mandate=$(jq -er '.body | capture("(?ms)^## Mandate[ \\t]*\\r?\\n(?<text>.*?)(?=^## |\\z)") | "## Mandate\n" + .text' <<< "$issue") || loom_error 'issue has no Mandate block'
short=$(jq -ner --arg mandate "$mandate" '$mandate | capture("(?m)^\\*\\*Ticket short name:\\*\\*[ \\t]*(?<name>[a-z0-9]+(?:-[a-z0-9]+)*)[ \\t]*(?:<!--[^\\n]*-->)?\\r?$").name') || loom_error 'missing or invalid ticket short name'
default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name')
git check-ref-format --branch "$default_branch" >/dev/null || loom_error 'invalid default branch'
if git -C "$checkout" show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
    base="refs/remotes/origin/$default_branch"
elif git -C "$checkout" show-ref --verify --quiet "refs/heads/$default_branch"; then
    base="refs/heads/$default_branch"
else
    loom_error 'default branch is not available locally; conductor must fetch it first'
fi
loom_init
loom_lock
shopt -s nullglob
for file in "$LOOM_STATE"/*.json; do
    loom_validate "$file"
    if jq -e --arg repo "$repo" --argjson ticket "$2" '.repo == $repo and .ticket == $ticket' "$file" >/dev/null; then
        pid=$(jq -r '.worker_pid // empty' "$file")
        [[ -z $pid ]] || ! kill -0 "$pid" 2>/dev/null || loom_error 'ticket already has a live assignment'
    fi
done
mkdir -p "$worktrees"
worktree="$worktrees/$short"
[[ ! -e $worktree && ! -L $worktree ]] || loom_error 'worktree path already exists; conductor must resolve it'
if git -C "$checkout" show-ref --verify --quiet "refs/heads/$short"; then
    loom_error 'ticket branch already exists; conductor must resolve it'
fi
id="$short-$(jq -nr 'now | floor')-$$-$RANDOM"
[[ ! -e $LOOM_STATE/$id.json ]] || loom_error 'assignment id collision'
git -C "$checkout" worktree add -b "$short" "$worktree" "$base" >&2
[[ ! -e $worktree/WORK.md && ! -L $worktree/WORK.md ]] || loom_error 'checkout already contains WORK.md; worktree retained for inspection'
{
    printf '# %s\n\n%s\n\n## Consumer laws\n\n' "$(jq -r '.title' <<< "$issue")" "$mandate"
    jq -r '.laws[]' <<< "$config"
} > "$worktree/WORK.md"
jq -n --argjson ticket "$2" --arg repo "$repo" --arg short "$short" --arg worktree "$worktree" '
  {ticket: $ticket, repo: $repo, short_name: $short, worktree: $worktree,
   worker_pid: null, started_at: (now | todateiso8601), reports: []}
' > "$LOOM_STATE/.pending"
mv "$LOOM_STATE/.pending" "$LOOM_STATE/$id.json"
printf '%s\n%s\n' "$worktree" "$id"
