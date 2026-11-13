#!/usr/bin/env bash
# jira.sh — QA-only Jira helper. Jira is the source of truth.
# Reads are free. Writes (comment, create-bug, create-access, attach, transition, link) print a preview
# and stop unless --yes is passed. QA-only: no story/task/epic creation, no grooming, no sprint edits.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"

API2="$JIRA_BASE_URL/rest/api/2"
API3="$JIRA_BASE_URL/rest/api/3"
FIELDS="summary,status,issuetype,priority,assignee,reporter,labels,fixVersions,versions,components,updated,created,issuelinks,attachment,description${JIRA_AC_FIELD:+,$JIRA_AC_FIELD}"

usage() { cat <<'EOF'
jira.sh myself
jira.sh get KEY                         raw JSON (QA fields)
jira.sh view KEY                        readable ticket: status, AC, links, attachments, last comments
jira.sh updated KEY                     updated timestamp + status (drift check)
jira.sh search "JQL" [max]              table of matches
jira.sh dupes "words" [project]         open bugs matching text (dupe check before filing)
jira.sh comment KEY FILE.md [--yes]
jira.sh create-bug FILE.json [--yes]    issuetype Bug only
jira.sh create-access FILE.json [--yes] access request only (JIRA_ACCESS_ISSUETYPE)
jira.sh attach KEY FILE... [--yes]
jira.sh transitions KEY
jira.sh transition KEY "Name" [--yes]
jira.sh link FROM TO "Relates" [--yes]
EOF
}

no_test_tickets() { # QA never creates "test BWS-nnnn" style tickets
  if echo "$1" | grep -Eiq '^[[:space:]]*(\[?test\]?[[:space:]:-]|test[[:space:]]+[A-Z]+-[0-9]+|dummy|sample ticket)'; then
    die "Refused: summary looks like a test ticket ('$1'). QA files real defects and access requests only."
  fi
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  myself) jira_http GET "$API3/myself" | jq '{accountId,displayName,emailAddress}' ;;

  get) valid_key "${1:-}" || die "usage: jira.sh get KEY"
       jira_http GET "$API2/issue/$1?fields=$FIELDS" ;;

  updated) valid_key "${1:-}" || die "usage: jira.sh updated KEY"
       jira_http GET "$API2/issue/$1?fields=updated,status,summary" | jq -r '[.key,.fields.updated,.fields.status.name,.fields.summary]|join("|")' ;;

  view) valid_key "${1:-}" || die "usage: jira.sh view KEY"
       j="$(jira_http GET "$API2/issue/$1?fields=$FIELDS,comment")"
       echo "$j" | jq -r --arg ac "${JIRA_AC_FIELD:-}" '
         .fields as $f |
         "\(.key)  [\($f.issuetype.name)]  \($f.status.name)  prio:\($f.priority.name // "-")",
         "Summary:    \($f.summary)",
         "Assignee:   \($f.assignee.displayName // "-")   Reporter: \($f.reporter.displayName // "-")",
         "Fix ver:    \([$f.fixVersions[]?.name]|join(", "))   Affects: \([$f.versions[]?.name]|join(", "))",
         "Labels:     \($f.labels|join(", "))   Components: \([$f.components[]?.name]|join(", "))",
         "Updated:    \($f.updated)",
         "",
         "--- Description ---", ($f.description // "(empty)"),
         (if $ac != "" then "", "--- Acceptance criteria (\($ac)) ---", ($f[$ac] // "(empty)" | tostring) else empty end),
         "", "--- Links ---",
         ($f.issuelinks[]? | "  \(.type.name): \((.outwardIssue // .inwardIssue).key) \((.outwardIssue // .inwardIssue).fields.status.name) — \((.outwardIssue // .inwardIssue).fields.summary)"),
         "", "--- Attachments ---", ($f.attachment[]? | "  \(.filename) (\(.size) bytes)"),
         "", "--- Last 5 comments ---",
         ($f.comment.comments[-5:][]? | "  [\(.created[0:16])] \(.author.displayName): \(.body|gsub("\n";" ")|.[0:300])")' ;;

  search) [ -n "${1:-}" ] || die "usage: jira.sh search \"JQL\" [max]"
       jira_http GET "$API3/search/jql?jql=$(urlenc "$1")&maxResults=${2:-50}&fields=summary,status,priority,assignee,updated,issuetype" |
         jq -r '.issues[]? | [.key, .fields.issuetype.name, .fields.status.name, (.fields.priority.name//"-"), (.fields.assignee.displayName//"-"), .fields.updated[0:10], .fields.summary] | @tsv' ;;

  dupes) [ -n "${1:-}" ] || die "usage: jira.sh dupes \"words\" [project]"
       proj="${2:-$JIRA_PROJECT}"; [ -n "$proj" ] || die "set JIRA_PROJECT"
       words="$(echo "$1" | sed 's/"//g')"
       "$0" search "project = $proj AND issuetype = Bug AND text ~ \"$words\" ORDER BY statusCategory ASC, updated DESC" 15 ;;

  comment) valid_key "${1:-}" && [ -f "${2:-}" ] || die "usage: jira.sh comment KEY FILE.md [--yes]"
       echo "Comment on $1:"; echo "-----"; cat "$2"; echo "-----"
       gate "add comment to $1" "$@"
       jira_http POST "$API2/issue/$1/comment" "$(jq -n --rawfile b "$2" '{body:$b}')" | jq -r '"Comment added: \(.id)"' ;;

  create-bug|create-access) [ -f "${1:-}" ] || die "usage: jira.sh $cmd FILE.json [--yes]"
       f="$1"; proj="$(jq -r '.project // empty' "$f")"; proj="${proj:-$JIRA_PROJECT}"
       [ -n "$proj" ] || die "no project (set JIRA_PROJECT or .project)"
       summary="$(jq -r '.summary // empty' "$f")"; [ -n "$summary" ] || die ".summary required"
       no_test_tickets "$summary"
       if [ "$cmd" = create-bug ]; then itype="Bug"; prio="$(jq -r '.priority // empty' "$f")"
         [ -n "$prio" ] || die ".priority required — ask the person for priority before creating a bug"
       else itype="${JIRA_ACCESS_ISSUETYPE:-Task}"; prio="$(jq -r '.priority // empty' "$f")"; fi
       body="$(jq --arg p "$proj" --arg t "$itype" '{fields:({
           project:{key:$p}, issuetype:{name:$t}, summary:.summary, description:(.description//""),
           labels:(.labels//[])}
           + (if .priority then {priority:{name:.priority}} else {} end)
           + (if .components then {components:[.components[]|{name:.}]} else {} end)
           + (if .affects then {versions:[.affects[]|{name:.}]} else {} end))}' "$f")"
       echo "Create $itype in $proj:"; echo "$body" | jq -r '.fields | "Summary:  \(.summary)\nPriority: \(.priority.name//"-")\nLabels:   \(.labels|join(", "))\n\n\(.description)"'
       link="$(jq -r '.linkTo // empty' "$f")"; [ -n "$link" ] && echo "Will link to: $link (Relates)"
       gate "create $itype '$summary'" "$@"
       key="$(jira_http POST "$API2/issue" "$body" | jq -r .key)"; echo "Created: $key  $JIRA_BASE_URL/browse/$key"
       [ -n "$link" ] && "$0" link "$key" "$link" "Relates" --yes >/dev/null && echo "Linked $key -> $link"
       echo "Next: attach evidence with  jira.sh attach $key <files> (preview first)" ;;

  attach) valid_key "${1:-}" || die "usage: jira.sh attach KEY FILE... [--yes]"
       key="$1"; shift; files="$(strip_yes "$@")"; [ -n "$files" ] || die "no files"
       echo "Attach to $key:"; echo "$files" | while read -r x; do [ -f "$x" ] || die "missing $x"; echo "  $x"; done
       gate "attach files to $key" "$@"; need_jira
       echo "$files" | while read -r x; do
         curl -sS -f -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -H 'X-Atlassian-Token: no-check' -F "file=@$x" "$API3/issue/$key/attachments" | jq -r '.[]|"Attached: \(.filename)"'
       done ;;

  transitions) valid_key "${1:-}" || die "usage: jira.sh transitions KEY"
       jira_http GET "$API2/issue/$1/transitions" | jq -r '.transitions[]|"\(.id)\t\(.name) -> \(.to.name)"' ;;

  transition) valid_key "${1:-}" && [ -n "${2:-}" ] || die "usage: jira.sh transition KEY \"Name\" [--yes]"
       id="$(jira_http GET "$API2/issue/$1/transitions" | jq -r --arg n "$2" '.transitions[]|select((.name|ascii_downcase)==($n|ascii_downcase) or (.to.name|ascii_downcase)==($n|ascii_downcase))|.id' | head -1)"
       [ -n "$id" ] || die "no transition '$2' available on $1 (see: jira.sh transitions $1)"
       echo "Transition $1 via '$2' (id $id)"
       gate "move $1 via '$2'" "$@"
       jira_http POST "$API2/issue/$1/transitions" "{\"transition\":{\"id\":\"$id\"}}" >/dev/null; echo "Moved $1" ;;

  link) valid_key "${1:-}" && valid_key "${2:-}" || die "usage: jira.sh link FROM TO \"Type\" [--yes]"
       t="${3:-Relates}"; echo "Link $1 --$t--> $2"; gate "link $1 to $2" "$@"
       jira_http POST "$API2/issueLink" "$(jq -n --arg a "$1" --arg b "$2" --arg t "$t" '{type:{name:$t},inwardIssue:{key:$a},outwardIssue:{key:$b}}')" >/dev/null; echo "Linked" ;;

  help|*) usage ;;
esac
