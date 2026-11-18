#!/usr/bin/env bash
# qa.sh — QA-only front door for scripts. The agent runs these; the person answers questions.
# Writes are previewed and need --yes (added only after the person says yes in chat).
set -euo pipefail
. "$(dirname "$0")/_lib.sh"
J="$SCRIPTS_DIR/jira.sh"; Z="$SCRIPTS_DIR/zephyr.sh"; C="python3 $SCRIPTS_DIR/cases.py"
mkdir -p "$QA_DIR/runs" "$QA_DIR/cases" "$QA_DIR/reports" "$QA_DIR/exports"

usage() { cat <<'EOF'
Setup        preflight                         tokens, connectivity, anchor, version source
Pin          anchor KEY | anchor               pin the ticket for this chat (one ticket, one scenario)
             anchor --sheet CASES.json         pin an imported Excel/CSV sheet instead (no Jira needed)
             drift [KEY]                       exit 3 = different key (re-anchor), 4 = ticket changed in Jira
Manual run   laneguard [URL]                   confirm QA lane: anchored, no drift, non-prod host, version
             run start [CASEKEY]               open a hand-run (records app version)
             steprun N "action" "expected" "actual" pass|fail|blocked [evidence] [data]
             snap FILE [label]                 move a screenshot into this run's evidence
             handresult pass|fail|blocked      compile result.md (local, no write to Jira/Zephyr)
             walkthrough [OUT.json]            turn the recorded run into a draft test case
Submit       submit [--case CASEKEY --cycle CYCLEKEY] [--yes]   Jira comment + evidence + Zephyr result
Cases        cases lint FILE | cases export FILE [--xlsx|--csv] [OUT] | cases push FILE [--yes]
             cases import SHEET.xlsx|.csv [--sheet NAME] [OUT.json]   read the tester's own sheet
             cases list FILE | cases show FILE CASEID | cases results FILE [OUT.xlsx]
Reports      coverage KEY | ready KEY | readiness VERSION | signoff VERSION [CYCLEKEY] | standup [Nd]
Bugs         retest | dupes "words" | autoclose-candidates | cnr-draft KEY ATTEMPTS
Automation   flaky N -- <test command...>
Misc         appversion
EOF
}

cur_run() { [ -f "$QA_DIR/runs/current" ] && cat "$QA_DIR/runs/current" || die "no open run — qa.sh run start [CASEKEY]"; }
require_anchor() { local k; k="$(anchor_key || true)"; [ -n "$k" ] || die "no ticket pinned — qa.sh anchor KEY (or anchor --sheet CASES.json)"; echo "$k"; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }
is_sheet() { case "$1" in SHEET-*) return 0;; esac; return 1; }

drift() { # [KEY] -> 0 ok, 3 key mismatch, 4 changed
  local k want line upd st
  k="$(require_anchor)"; want="${1:-$k}"
  if [ "$want" != "$k" ]; then echo "DRIFT: chat is pinned to $k but you asked about $want. Re-anchor: qa.sh anchor $want"; return 3; fi
  if is_sheet "$k"; then # sheet pin: drift = the tester's Excel file changed after import
    local cj src; cj="$(cut -d'|' -f4 "$(anchor_file)")"; src="$(jq -r '.source.file' "$cj" 2>/dev/null)"
    [ -f "$src" ] || { echo "DRIFT CHECK FAILED: source sheet $src not found."; return 5; }
    if [ "$(mtime "$src")" != "$(cut -d'|' -f2 "$(anchor_file)")" ]; then
      echo "DRIFT: $(basename "$src") changed since it was imported. Re-import: qa.sh cases import \"$src\" then qa.sh anchor --sheet $cj"; return 4
    fi
    echo "No drift: $k (sheet $(basename "$src"), no Jira)"; return 0
  fi
  line="$("$J" updated "$k")" || { echo "DRIFT CHECK FAILED: cannot read $k from Jira. Do not write until this works."; return 5; }
  upd="$(echo "$line" | cut -d'|' -f2)"; st="$(echo "$line" | cut -d'|' -f3)"
  if [ "$upd" != "$(cut -d'|' -f2 "$(anchor_file)")" ]; then
    echo "DRIFT: $k changed in Jira since it was pinned (was $(cut -d'|' -f3 "$(anchor_file)"), now $st, updated $upd)."
    echo "Re-read it (jira.sh view $k) and re-anchor before writing."; return 4
  fi
  echo "No drift: $k ($st)"
}

host_of() { echo "$1" | sed -E 's#^[a-z]+://##; s#[/:].*$##'; }

cmd="${1:-help}"; shift || true
case "$cmd" in
  preflight)
    echo "QA preflight"; ok=1
    for v in JIRA_BASE_URL JIRA_EMAIL JIRA_API_TOKEN JIRA_PROJECT ZEPHYR_TOKEN ZEPHYR_PROJECT_KEY; do
      if [ -n "${!v:-}" ]; then echo "  [x] $v set"; else echo "  [ ] $v missing"; ok=0; fi; done
    if "$J" myself >/dev/null 2>&1; then echo "  [x] Jira reachable as $("$J" myself | jq -r .displayName)"; else echo "  [ ] Jira not reachable"; ok=0; fi
    if "$Z" ping >/dev/null 2>&1; then echo "  [x] $("$Z" ping)"; else echo "  [ ] Zephyr not reachable (Excel export still works)"; fi
    if v="$("$SCRIPTS_DIR/appversion.sh" 2>/dev/null)"; then echo "  [x] App version: $v"; else echo "  [ ] App version source not set (APP_VERSION_URL / APP_VERSION_CMD) — will ask tester"; fi
    echo "  [i] Test env: ${APP_URL:-not set}   Prod hosts blocked: ${PROD_HOSTS:-none listed}"
    k="$(anchor_key || true)"; echo "  [i] Pinned ticket: ${k:-none}"
    [ $ok = 1 ] && echo "Preflight OK" || { echo "Preflight incomplete — run the qa-config skill"; exit 1; } ;;

  anchor)
    if [ -z "${1:-}" ]; then [ -f "$(anchor_file)" ] && tr '|' '\n' < "$(anchor_file)" | paste -d' ' <(printf 'key\nupdated\nstatus\nsummary\npinned\n') - || echo "No ticket pinned"; exit 0; fi
    if [ "$1" = "--sheet" ]; then
      f="${2:-}"; [ -f "$f" ] || die "usage: qa.sh anchor --sheet CASES.json (from qa.sh cases import)"
      src="$(jq -r '.source.file // empty' "$f")"; [ -n "$src" ] || die "$f was not imported from a sheet — run qa.sh cases import first"
      k="SHEET-$(printf '%s' "$(jq -r '.source.sheet' "$f")" | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9' '_' | cut -c1-30)"
      fa="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
      echo "$k|$(mtime "$src")|sheet|$fa|$(now_iso)" > "$(anchor_file)"; rm -f "$QA_DIR/runs/current"
      echo "Pinned sheet $k: $(jq '.cases|length' "$f") case(s) from $(basename "$src"). Results go back to Excel; Jira is not touched."; exit 0
    fi
    valid_key "$1" || die "not a Jira key: $1 (type it; never read keys from a screenshot)"
    old="$(anchor_key || true)"
    line="$("$J" updated "$1")"; echo "$line|$(now_iso)" > "$(anchor_file)"
    rm -f "$QA_DIR/runs/current"
    [ -n "$old" ] && [ "$old" != "$1" ] && echo "Switched from $old. Start a fresh chat per ticket when you can."
    echo "Pinned $(echo "$line" | cut -d'|' -f1): $(echo "$line" | cut -d'|' -f4) [$(echo "$line" | cut -d'|' -f3)]" ;;

  drift) drift "${1:-}" ;;

  laneguard)
    k="$(require_anchor)"; drift >/dev/null || { drift || exit $?; }
    url="${1:-${APP_URL:-}}"; [ -n "$url" ] || die "no test URL — pass one or set APP_URL in .qa/platform.env"
    h="$(host_of "$url")"
    for p in $(echo "${PROD_HOSTS:-}" | tr ',' ' '); do [ "$h" = "$p" ] && die "LANE BLOCKED: $h is a production host. QA hand-runs go to test environments only."; done
    v="$("$SCRIPTS_DIR/appversion.sh" 2>/dev/null | cut -f1 || true)"
    echo "$url" > "$QA_DIR/lane_url"
    echo "LANE OK: QA | ticket $k | host $h | version ${v:-UNKNOWN (ask tester)}" ;;

  run)
    [ "${1:-}" = start ] || die "usage: qa.sh run start [CASEKEY]"
    k="$(require_anchor)"; id="$(date +%Y%m%d-%H%M%S)"; d="$QA_DIR/runs/$k/$id"; mkdir -p "$d/evidence"
    v="$("$SCRIPTS_DIR/appversion.sh" 2>/dev/null | cut -f1 || true)"
    printf 'KEY=%s\nCASE=%s\nVERSION=%s\nURL=%s\nSTARTED=%s\n' "$k" "${2:-}" "${v:-UNKNOWN}" "$(cat "$QA_DIR/lane_url" 2>/dev/null || echo "${APP_URL:-}")" "$(now_iso)" > "$d/meta.env"
    : > "$d/steps.jsonl"; echo "$d" > "$QA_DIR/runs/current"
    echo "Run open: $d (version ${v:-UNKNOWN — ask tester and set VERSION in meta.env})" ;;

  steprun)
    [ $# -ge 5 ] || die 'usage: qa.sh steprun N "action" "expected" "actual" pass|fail|blocked [evidence] [data]'
    d="$(cur_run)"; case "$5" in pass|fail|blocked|skip) ;; *) die "status must be pass|fail|blocked|skip";; esac
    jq -nc --arg n "$1" --arg a "$2" --arg e "$3" --arg x "$4" --arg s "$5" --arg ev "${6:-}" --arg dt "${7:-}" --arg t "$(now_iso)" \
      '{n:($n|tonumber),action:$a,expected:$e,actual:$x,status:$s,evidence:$ev,data:$dt,at:$t}' >> "$d/steps.jsonl"
    echo "Step $1: $5" ;;

  snap)
    [ -f "${1:-}" ] || die "usage: qa.sh snap FILE [label]  (file not found: ${1:-})"
    d="$(cur_run)"; n=$(( $(ls "$d/evidence" | wc -l) + 1 )); ext="${1##*.}"
    lab="$(printf '%s' "${2:-shot}" | tr -c 'A-Za-z0-9_-' '-' | cut -c1-40)"
    dest="$d/evidence/$(printf '%02d' $n)-$lab.$ext"; mv "$1" "$dest"; echo "$dest" ;;

  handresult)
    case "${1:-}" in pass|fail|blocked) ;; *) die "usage: qa.sh handresult pass|fail|blocked";; esac
    d="$(cur_run)"; . "$d/meta.env"
    nowv="$("$SCRIPTS_DIR/appversion.sh" 2>/dev/null | cut -f1 || true)"
    [ -n "$nowv" ] && [ "$VERSION" != "UNKNOWN" ] && [ "$nowv" != "$VERSION" ] && warn "app version changed during run: $VERSION -> $nowv. Re-run or note it."
    [ "$VERSION" = "UNKNOWN" ] && die "app version unknown. Ask the tester for it and set VERSION= in $d/meta.env (not from memory)."
    up="$(echo "$1" | tr a-z A-Z)"
    { echo "QA result: $up"
      echo "Ticket: $KEY${CASE:+   Case: $CASE}"
      echo "App version: $VERSION   Env: ${URL:-n/a}   Run: $(basename "$d")   Date: $(now_iso)"
      echo
      echo "|#|Action|Expected|Actual|Status|Evidence|"; echo "|-|-|-|-|-|-|"
      jq -r '"|\(.n)|\(.action)|\(.expected)|\(.actual)|\(.status)|\((.evidence // "") | if .=="" then "-" else split("/")|last end)|"' "$d/steps.jsonl"
      echo; echo "Evidence files:"; ls "$d/evidence" | sed 's/^/- /'
    } > "$d/result.md"
    echo "$1" > "$d/status"
    [ "$1" = pass ] && jq -e 'select(.status=="fail")' "$d/steps.jsonl" >/dev/null 2>&1 && warn "a step failed but overall is pass — confirm with the tester"
    [ -z "$(ls "$d/evidence")" ] && warn "no screenshots in evidence — result comments need screenshots"
    cat "$d/result.md" ;;

  walkthrough)
    d="$(cur_run)"; . "$d/meta.env"; out="${1:-$QA_DIR/cases/$KEY.walkthrough.json}"
    $C from-walkthrough "$d/steps.jsonl" "$KEY" "$out" ;;

  submit)
    d="$(cur_run)"; . "$d/meta.env"; [ -f "$d/result.md" ] || die "run qa.sh handresult first"
    is_sheet "$KEY" && die "Sheet-only run: write results back to Excel with qa.sh cases results <cases.json>. To also post to Jira, pin the story (qa.sh anchor KEY) and run the case again."
    st="$(cat "$d/status")"; case_key="$CASE"; cycle=""; yes=""
    while [ $# -gt 0 ]; do case "$1" in --case) case_key="$2"; shift;; --cycle) cycle="$2"; shift;; --yes) yes="--yes";; esac; shift; done
    drift "$KEY" >/dev/null || { drift "$KEY"; exit 4; }
    zst="$(echo "$st" | sed 's/pass/Pass/;s/fail/Fail/;s/blocked/Blocked/')"
    echo "SUBMIT PREVIEW for $KEY (status $zst, version $VERSION):"
    echo "  1) Jira comment on $KEY:"; sed 's/^/     /' "$d/result.md"
    echo "  2) Attach $(ls "$d/evidence" | wc -l | tr -d ' ') evidence file(s) to $KEY"
    if [ -n "$case_key" ]; then
      [ -n "$cycle" ] || die "--cycle CYCLEKEY needed to record the Zephyr result for $case_key"
      echo "  3) Zephyr: record $zst on $case_key in $cycle"; zephyr_nodelete_notice
    else echo "  3) Zephyr: skipped (no --case)"; fi
    gate "submit result for $KEY" $yes
    "$J" comment "$KEY" "$d/result.md" --yes
    ev="$(ls "$d"/evidence/* 2>/dev/null || true)"; [ -n "$ev" ] && "$J" attach "$KEY" $ev --yes
    [ -n "$case_key" ] && "$Z" execute "$case_key" "$zst" "$d/result.md" --cycle "$cycle" --yes
    echo "Submitted." ;;

  cases)
    sub="${1:-}"; f="${2:-}"; [ -f "$f" ] || die "usage: qa.sh cases lint|export|push|import|list|show|results FILE ..."
    case "$sub" in
      import) sheet=""; out=""; shift 2
              while [ $# -gt 0 ]; do case "$1" in --sheet) sheet="$2"; shift;; *) out="$1";; esac; shift; done
              clean() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_' | tr -s '_'; }
              base="$(clean "$(basename "${f%.*}")")"; [ -n "$sheet" ] && base="$base-$(clean "$sheet")"
              out="${out:-$QA_DIR/cases/$base.json}"
              $C import "$f" "$out" ${sheet:+--sheet "$sheet"} && { echo; $C list "$out"; echo; $C lint "$out" | tail -8 || true; } ;;
      list) $C list "$f" ;;
      show) [ -n "${3:-}" ] || die "usage: qa.sh cases show FILE CASEID"; $C show "$f" "$3" ;;
      results) out="${3:-$QA_DIR/exports/$(basename "${f%.*}")-results-$(date +%Y%m%d-%H%M).xlsx}"
               $C results "$f" "$QA_DIR/runs" "$out" ;;
      lint) $C lint "$f" ;;
      export) fmt="${3:---xlsx}"; story="$(jq -r .story "$f")"; ext="${fmt#--}"
              out="${4:-$QA_DIR/exports/$story-cases.$ext}"; $C export "$f" "$fmt" "$out" ;;
      push) $C lint "$f" || die "fix lint errors before pushing"
            story="$(jq -r .story "$f")"; drift "$story" >/dev/null || { drift "$story"; exit 4; }
            echo "Push $(jq '.cases|length' "$f") case(s) to Zephyr $ZEPHYR_PROJECT_KEY, linked to $story:"
            jq -r '.cases[]|"  - \(.name) (\(.steps|length) steps)"' "$f"; zephyr_nodelete_notice
            existing="$("$Z" cases-for "$story" 2>/dev/null | cut -f4 || true)"
            [ -n "$existing" ] && { echo "Already linked to $story:"; echo "$existing" | sed 's/^/  = /'; echo "(check for duplicates before saying yes)"; }
            gate "create $(jq '.cases|length' "$f") Zephyr case(s)" "$@"
            tmp="$(mktemp -d)"; for c in $($C split "$f" "$tmp"); do "$Z" create-case "$c" "$story" --yes; done ;;
      *) die "cases lint|export|push|import|list|show|results" ;;
    esac ;;

  coverage)
    valid_key "${1:-}" || die "usage: qa.sh coverage KEY"
    echo "Coverage for $1"; "$J" view "$1" | sed -n '1,3p'
    echo; echo "Zephyr cases (key, last result, date, name):"; out="$("$Z" cases-for "$1")"; echo "$out"
    n=$(echo "$out" | grep -c -- '-T' || true); nr=$(echo "$out" | grep -c 'never-run' || true); nf=$(echo "$out" | grep -ci 'fail' || true)
    echo; echo "Summary: $n linked, $nr never run, $nf last-failed."
    [ -f "$QA_DIR/cases/$1.json" ] && { echo "Local draft lint:"; $C lint "$QA_DIR/cases/$1.json" | tail -5 || true; }
    [ "$n" = 0 ] && echo "GAP: no test cases linked to $1." || true ;;

  ready)
    valid_key "${1:-}" || die "usage: qa.sh ready KEY"
    j="$("$J" get "$1")"
    chk() { if [ "$2" = 1 ]; then echo "  [x] $1"; else echo "  [ ] $1"; fi; }
    st="$(echo "$j" | jq -r .fields.status.name)"
    chk "Status is ready for QA ($st)" "$(echo "[$QA_READY_STATUSES]" | jq --arg s "$st" 'map(ascii_downcase)|index($s|ascii_downcase)|if .==null then 0 else 1 end')"
    chk "Acceptance criteria present" "$(echo "$j" | jq --arg ac "${JIRA_AC_FIELD:-}" '((if $ac!="" then .fields[$ac] else null end) // .fields.description // "" | tostring | test("acceptance|given .* when|\\bAC\\s*[0-9]";"i")) | if . then 1 else 0 end')"
    chk "Fix version set ($(echo "$j" | jq -r '[.fields.fixVersions[]?.name]|join(",")'))" "$(echo "$j" | jq '.fields.fixVersions|length>0|if . then 1 else 0 end')"
    chk "Linked work/PRs/bugs visible" "$(echo "$j" | jq '.fields.issuelinks|length>0|if . then 1 else 0 end')"
    tc="$("$Z" cases-for "$1" 2>/dev/null | grep -c -- '-T' || true)"; chk "Test cases linked in Zephyr ($tc)" "$([ "$tc" -gt 0 ] && echo 1 || echo 0)"
    v="$("$SCRIPTS_DIR/appversion.sh" 2>/dev/null | cut -f1 || true)"; chk "Test env answers with a version (${v:-unknown})" "$([ -n "$v" ] && echo 1 || echo 0)"
    echo "Report only. The tester decides whether to start." ;;

  readiness|signoff)
    [ -n "${1:-}" ] || die "usage: qa.sh $cmd VERSION [CYCLEKEY]"
    ver="$1"; cyc="${2:-}"; out="$QA_DIR/reports/$cmd-$(echo "$ver" | tr ' /' '__').md"
    { echo "# $( [ "$cmd" = signoff ] && echo 'QA sign-off summary' || echo 'Release readiness evidence' ): $ver"
      echo "Generated $(now_iso) from Jira${cyc:+ and Zephyr cycle $cyc}. App version on test env: $("$SCRIPTS_DIR/appversion.sh" 2>/dev/null | cut -f1 || echo unknown)"
      echo; echo "## Scope (fixVersion = $ver)"; echo '```'
      "$J" search "project = $JIRA_PROJECT AND fixVersion = \"$ver\" ORDER BY issuetype, status" 200 || echo "(query failed)"
      echo '```'; echo; echo "## Open bugs in $ver"; echo '```'
      "$J" search "project = $JIRA_PROJECT AND fixVersion = \"$ver\" AND issuetype = Bug AND statusCategory != Done ORDER BY priority DESC" 200 || echo "(query failed)"
      echo '```'
      if [ -n "$cyc" ]; then echo; echo "## Cycle $cyc results"; echo '```'
        "$Z" cycle "$cyc" | tail -n +2 | cut -f2 | sort | uniq -c | while read -r n sid; do echo "$n x $("$Z" statuses | awk -F'\t' -v s="$sid" '$1==s{print $2}')"; done
        echo '```'; fi
      echo; echo "## Not covered / unknown"; echo "- Stories without linked cases: run qa.sh coverage KEY per story listed above."
      echo; echo "---"; echo "This is evidence, not a verdict. The tester makes the release call."
    } > "$out"
    cat "$out"; echo; echo "Saved: $out" ;;

  standup)
    since="${1:-}"; [ -z "$since" ] && { [ "$(date +%u)" = 1 ] && since="-3d" || since="-1d"; }
    me="$("$J" myself | jq -r .accountId)"
    sec() { echo; echo "## $1"; "$J" search "$2" 50 || echo "(query failed — adjust in .qa/config.env)"; }
    echo "# QA standup ($since)"
    sec "Bugs I filed" "reporter = currentUser() AND issuetype = Bug AND created >= $since ORDER BY created DESC"
    sec "Bugs closed/verified by me" "issuetype = Bug AND status CHANGED BY currentUser() AFTER $since AND statusCategory = Done"
    sec "Bugs reopened" "issuetype = Bug AND status CHANGED TO \"${QA_REOPEN_STATUS:-Reopened}\" AFTER $since AND (reporter = currentUser() OR status CHANGED BY currentUser())"
    sec "Waiting for my retest" "issuetype = Bug AND status in ($QA_RETEST_STATUSES) AND (reporter = currentUser() OR assignee = currentUser())"
    sec "Blockers" "${QA_BLOCKER_JQL:-(Flagged = Impediment) AND (assignee = currentUser() OR reporter = currentUser()) AND statusCategory != Done}"
    echo; echo "## Zephyr results I recorded"
    n="$(echo "$since" | tr -cd '0-9')"; d="$(date -u -v-"${n}"d +%Y-%m-%d 2>/dev/null || date -u -d "$n days ago" +%Y-%m-%d)"
    "$Z" executions-since "$d" 2>/dev/null |
      awk -F'\t' -v me="$me" '$3==me{c[$2]++} END{for(s in c) print "  status " s ": " c[s]; if(length(c)==0) print "  none"}' || echo "  (Zephyr not reachable)" ;;

  retest) "$J" search "project = $JIRA_PROJECT AND issuetype = Bug AND status in ($QA_RETEST_STATUSES) AND (reporter = currentUser() OR assignee = currentUser()) ORDER BY priority DESC" 50 ;;
  dupes) "$J" dupes "$@" ;;
  autoclose-candidates) "$J" search "project = $JIRA_PROJECT AND issuetype = Bug AND labels in (${QA_AUTOMATION_LABELS:-automation,auto-failure}) AND statusCategory != Done ORDER BY updated ASC" 100 ;;

  cnr-draft)
    valid_key "${1:-}" && [ -n "${2:-}" ] || die "usage: qa.sh cnr-draft KEY ATTEMPTS"
    v="$("$SCRIPTS_DIR/appversion.sh" | cut -f1)" || die "need app version for a could-not-reproduce note"
    f="$QA_DIR/reports/$1-cnr.md"; d="$(cat "$QA_DIR/runs/current" 2>/dev/null || true)"
    { echo "Could not reproduce on app version $v (${APP_URL:-test env}) after $2 attempt(s) on $(date +%Y-%m-%d)."
      [ -n "$d" ] && [ -f "$d/result.md" ] && { echo; cat "$d/result.md"; }
      echo; echo "Reporter: please add anything missing from the steps (data, role, browser). QA leaves the status call to the team."; } > "$f"
    cat "$f"; echo; echo "Draft: $f  ->  jira.sh comment $1 $f   (preview, then yes)" ;;

  flaky)
    n="${1:-}"; [ "${2:-}" = "--" ] || die "usage: qa.sh flaky N -- <test command>"; shift 2
    log="$QA_DIR/reports/flaky-$(date +%H%M%S)"; mkdir -p "$log"; p=0; f=0
    for i in $(seq 1 "$n"); do if "$@" > "$log/run$i.log" 2>&1; then p=$((p+1)); echo "run $i: pass"; else f=$((f+1)); echo "run $i: FAIL"; fi; done
    echo "Result: $p/$n passed, $f failed. Logs: $log"
    [ "$f" -gt 0 ] && [ "$p" -gt 0 ] && echo "Verdict: FLAKY (mixed results)"; [ "$f" = 0 ] && echo "Verdict: stable pass"; [ "$p" = 0 ] && echo "Verdict: consistent failure"; true ;;

  appversion) "$SCRIPTS_DIR/appversion.sh" ;;
  help|*) usage ;;
esac
