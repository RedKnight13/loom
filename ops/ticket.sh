#!/usr/bin/env bash
# ticket.sh <consumer.toml> --short NAME --title TITLE --scope TEXT --out TEXT --done TEXT
#           [--label NAME]... [--no-default-label] [--dry-run]
#
# Renders a Ticket whose Mandate is exactly the template (templates/MANDATE.md),
# proves dispatch will accept it by parsing it with dispatch's own parser, and
# opens it as an issue in the consumer repo (prints the URL). --dry-run prints
# the body instead. Hand-typed tickets drift; rendered ones cannot.
#
# Labels (#38): --label is repeatable. When the consumer repo has a `loom-ready`
# label, it is added by default unless --no-default-label is given.
set -euo pipefail
# shellcheck source=ops/lib.sh
source "${BASH_SOURCE[0]%/*}/lib.sh"
usage='usage: ticket.sh <consumer.toml> --short NAME --title TITLE --scope TEXT --out TEXT --done TEXT [--label NAME]... [--no-default-label] [--dry-run]'
[[ $# -ge 1 ]] || loom_error "$usage"
config=$(loom_config "$1")
shift
short='' title='' scope='' out='' done_means='' dry=false
labels=()
default_label=true
while [[ $# -gt 0 ]]; do
    case $1 in
        --short|--title|--scope|--out|--done|--label)
            [[ $# -ge 2 && -n $2 ]] || loom_error "$1 needs a non-empty value"
            case $1 in
                --short) short=$2 ;; --title) title=$2 ;; --scope) scope=$2 ;;
                --out) out=$2 ;; --done) done_means=$2 ;;
                --label)
                    [[ $2 =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]*$ ]] || loom_error "invalid label: $2"
                    labels+=("$2")
                    ;;
            esac
            shift 2 ;;
        --no-default-label) default_label=false; shift ;;
        --dry-run) dry=true; shift ;;
        *) loom_error "$usage" ;;
    esac
done
[[ -n $short && -n $title && -n $scope && -n $out && -n $done_means ]] || loom_error "$usage"
for field in "$title" "$scope" "$out" "$done_means"; do
    [[ $field != *$'\n'* ]] || loom_error 'fields are single lines (a Mandate line ends at the newline)'
    [[ $field != *'## '* ]] || loom_error 'fields may not contain a markdown heading'
done
body=$(cat <<EOF
## Mandate

**Ticket short name:** $short
**Scope:** $scope
**Out of scope:** $out
**Laws:** see the consumer laws in WORK.md
**Done means:** $done_means
**Stop by impact:** a reviewable result ends the turn \`ready\`; a design decision ends it \`blocked\` with one concrete question. Effort is not a stopping reason.
**Report:** end the turn with one state line in REPORT.md as WORK.md describes.
EOF
)
# Self-check with dispatch's own parser: the short name must survive the trip.
mandate=$(printf '%s\n' "$body" | loom_mandate)
[[ $(loom_short "$mandate") == "$short" ]] || loom_error "short name '$short' does not survive dispatch's parser (lowercase words joined by '-')"
if $dry; then
    printf '%s\n' "$body"
    exit 0
fi
repo=$(jq -r '.repo' <<< "$config")
# Default label: only when the repo actually has it (#38). A repo without the
# label is not an error; a failed label listing only skips the default.
if $default_label; then
    have=''
    have=$(gh label list --repo "$repo" --limit 200 --json name --jq '.[].name' 2>/dev/null || true)
    if grep -qxF 'loom-ready' <<< "$have"; then
        labels+=('loom-ready')
    fi
fi
args=(--repo "$repo" --title "Ticket: $short — $title" --body "$body")
# Collapse duplicates while keeping order.
seen=' '
for label in ${labels[@]+"${labels[@]}"}; do
    if [[ $seen == *" $label "* ]]; then continue; fi
    seen="$seen$label "
    args+=(--label "$label")
done
gh issue create "${args[@]}"
