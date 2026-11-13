#!/usr/bin/env bash
# zephyr.sh — Zephyr Scale Cloud (API v2) helper. Zephyr holds the test protocols.
# Reads are free. Writes print a preview and stop unless --yes. Nothing here deletes: the pack never
# deletes test cases, cycles or results, so tell the person before they confirm a create.
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
Z="$ZEPHYR_BASE_URL"

usage() { cat <<'EOF'
zephyr.sh ping
zephyr.sh statuses                         execution status names (Pass/Fail/Blocked/...)
zephyr.sh cases-for ISSUE                  test cases linked to a Jira issue (+ last result)
zephyr.sh case CASEKEY                     case + steps
zephyr.sh create-case CASE.json ISSUE [--yes]     one case object (see test-case-format.md)
zephyr.sh update-steps CASEKEY CASE.json [--yes]  overwrite steps of an existing case
zephyr.sh create-cycle NAME [VERSION] [--yes]
zephyr.sh cycle CYCLEKEY                   cycle + executions
zephyr.sh execute CASEKEY STATUS COMMENT_FILE [--cycle KEY] [--env NAME] [--yes]
zephyr.sh executions-since YYYY-MM-DD      executions ended since date (standup)
EOF
}

last_result() { # CASEKEY -> "status date"
  zephyr_http GET "$Z/testexecutions?projectKey=$ZEPHYR_PROJECT_KEY&testCase=$1&maxResults=50" 2>/dev/null |
    jq -r '[.values[]?] | sort_by(.actualEndDate // "") | last | if . == null then "never-run" else "\(.testExecutionStatus.id)@\(.actualEndDate // "-")" end' || echo "?"
}
status_name() { zephyr_http GET "$Z/statuses/$1" | jq -r .name; }

cmd="${1:-help}"; shift || true
case "$cmd" in
  ping) zephyr_http GET "$Z/projects?maxResults=50" | jq -r --arg p "$ZEPHYR_PROJECT_KEY" '"Zephyr OK. Project \($p) " + (if ([.values[]?.key]|index($p)) then "found" else "NOT FOUND" end)' ;;

  statuses) zephyr_http GET "$Z/statuses?projectKey=$ZEPHYR_PROJECT_KEY&statusType=TEST_EXECUTION&maxResults=50" | jq -r '.values[]|"\(.id)\t\(.name)"' ;;

  cases-for) valid_key "${1:-}" || die "usage: zephyr.sh cases-for ISSUE"
     keys="$(zephyr_http GET "$Z/issuelinks/$1/testcases" | jq -r '.[]?.key')"
     [ -n "$keys" ] || { echo "No Zephyr test cases linked to $1"; exit 0; }
     for k in $keys; do
       name="$(zephyr_http GET "$Z/testcases/$k" | jq -r .name)"
       lr="$(last_result "$k")"; sid="${lr%@*}"; when="${lr#*@}"
       if [ "$sid" != "never-run" ] && [ "$sid" != "?" ]; then sid="$(status_name "$sid")"; fi
       printf '%s\t%s\t%s\t%s\n' "$k" "$sid" "${when:0:10}" "$name"
     done ;;

  case) [ -n "${1:-}" ] || die "usage: zephyr.sh case CASEKEY"
     zephyr_http GET "$Z/testcases/$1" | jq -r '"\(.key)  \(.name)\nObjective: \(.objective//"-")\nPrecondition: \(.precondition//"-")"'
     zephyr_http GET "$Z/testcases/$1/teststeps?maxResults=100" | jq -r '.values | to_entries[] | "\(.key+1). \(.value.inline.description//"")\n   data: \(.value.inline.testData//"-")\n   expect: \(.value.inline.expectedResult//"")"' ;;

  create-case) [ -f "${1:-}" ] && valid_key "${2:-}" || die "usage: zephyr.sh create-case CASE.json ISSUE [--yes]"
     f="$1"; issue="$2"
     jq -e '.name and (.steps|length>0)' "$f" >/dev/null || die "case needs .name and .steps"
     echo "Create Zephyr test case in $ZEPHYR_PROJECT_KEY, linked to $issue:"
     jq -r '"  \(.name)  (prio \(.priority//"Normal"), \(.steps|length) steps)"' "$f"
     zephyr_nodelete_notice
     gate "create Zephyr case '$(jq -r .name "$f")'" "$@"
     body="$(jq --arg p "$ZEPHYR_PROJECT_KEY" '{projectKey:$p,name,objective:(.objective//null),precondition:(.precondition//null),labels:(.labels//[])} + (if .priority then {priorityName:.priority} else {} end)' "$f")"
     key="$(zephyr_http POST "$Z/testcases" "$body" | jq -r .key)"
     zephyr_http POST "$Z/testcases/$key/teststeps" "$(jq '{mode:"OVERWRITE",items:[.steps[]|{inline:{description:.action,testData:(.data//""),expectedResult:.expected}}]}' "$f")" >/dev/null
     iid="$("$(dirname "$0")/jira.sh" get "$issue" | jq -r .id)"
     zephyr_http POST "$Z/testcases/$key/links/issues" "{\"issueId\":$iid}" >/dev/null
     echo "Created $key and linked to $issue" ;;

  update-steps) [ -n "${1:-}" ] && [ -f "${2:-}" ] || die "usage: zephyr.sh update-steps CASEKEY CASE.json [--yes]"
     echo "Overwrite steps of $1 with $(jq '.steps|length' "$2") steps from $2"; zephyr_nodelete_notice
     gate "overwrite steps on $1" "$@"
     zephyr_http POST "$Z/testcases/$1/teststeps" "$(jq '{mode:"OVERWRITE",items:[.steps[]|{inline:{description:.action,testData:(.data//""),expectedResult:.expected}}]}' "$2")" >/dev/null
     echo "Steps updated on $1" ;;

  create-cycle) [ -n "${1:-}" ] || die "usage: zephyr.sh create-cycle NAME [VERSION] [--yes]"
     name="$1"; ver=""; [ -n "${2:-}" ] && [ "$2" != "--yes" ] && ver="$2"
     echo "Create test cycle '$name' in $ZEPHYR_PROJECT_KEY${ver:+ (version $ver)}"; zephyr_nodelete_notice
     gate "create cycle '$name'" "$@"
     zephyr_http POST "$Z/testcycles" "$(jq -n --arg p "$ZEPHYR_PROJECT_KEY" --arg n "$name" --arg v "$ver" '{projectKey:$p,name:$n,description:(if $v=="" then null else "Release \($v)" end)}')" | jq -r '"Created cycle \(.key)"' ;;

  cycle) [ -n "${1:-}" ] || die "usage: zephyr.sh cycle CYCLEKEY"
     zephyr_http GET "$Z/testcycles/$1" | jq -r '"\(.key)  \(.name)"'
     zephyr_http GET "$Z/testexecutions?projectKey=$ZEPHYR_PROJECT_KEY&testCycle=$1&maxResults=500" |
       jq -r '.values[]? | "\(.testCase.self|split("/")|.[-3] // "?")\t\(.testExecutionStatus.id)\t\(.actualEndDate//"-")"' ;;

  execute) [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -f "${3:-}" ] || die "usage: zephyr.sh execute CASEKEY STATUS COMMENT_FILE [--cycle KEY] [--env NAME] [--yes]"
     case_key="$1"; st="$2"; cf="$3"; shift 3; cycle=""; env=""; yes=""
     while [ $# -gt 0 ]; do case "$1" in --cycle) cycle="$2"; shift;; --env) env="$2"; shift;; --yes) yes="--yes";; esac; shift; done
     [ -n "$cycle" ] || die "--cycle required (Zephyr records executions inside a cycle)"
     echo "Record $st on $case_key in cycle $cycle${env:+ env $env}:"; echo "-----"; cat "$cf"; echo "-----"
     zephyr_nodelete_notice
     gate "record $st on $case_key" $yes
     zephyr_http POST "$Z/testexecutions" "$(jq -n --arg p "$ZEPHYR_PROJECT_KEY" --arg c "$case_key" --arg cy "$cycle" --arg s "$st" --arg e "$env" --arg d "$(now_iso)" --rawfile m "$cf" \
        '{projectKey:$p,testCaseKey:$c,testCycleKey:$cy,statusName:$s,comment:($m|gsub("\n";"<br>")),actualEndDate:$d} + (if $e=="" then {} else {environmentName:$e} end)')" >/dev/null
     echo "Recorded $st on $case_key ($cycle)" ;;

  executions-since) d="${1:-$(yesterday)}"
     zephyr_http GET "$Z/testexecutions?projectKey=$ZEPHYR_PROJECT_KEY&actualEndDateAfter=${d}T00:00:00Z&maxResults=500" |
       jq -r '.values[]? | [(.testCase.self|split("/")|.[-3]//"?"), .testExecutionStatus.id, (.executedById//"-"), (.actualEndDate//"-")] | @tsv' ;;

  help|*) usage ;;
esac
