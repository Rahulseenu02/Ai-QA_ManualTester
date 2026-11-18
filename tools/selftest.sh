#!/usr/bin/env bash
# selftest.sh — check the QA skill pack locally.
#   tools/selftest.sh          offline checks (no Jira/Zephyr needed, nothing written anywhere real)
#   tools/selftest.sh --live   also runs read-only preflight against your real .qa/config.env
#   tools/selftest.sh --mcp    also checks that the Playwright MCP server starts (downloads it via npx)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SK="$ROOT/.cursor/skills"; P="$SK/qa-qa-work/scripts"
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
expect_exit() { local name="$1" want="$2"; shift 2; "$@" >/dev/null 2>&1; local got=$?; [ "$got" = "$want" ] && ok "$name" || bad "$name (exit $got, want $want)"; }

echo "1. Tools"
for t in bash curl jq python3 npx; do check "$t installed" command -v "$t"; done

echo "2. Skills"
for s in qa-qa-guide qa-qa-work qa-qa-standup qa-config qa-platform; do
  f="$SK/$s/SKILL.md"
  check "$s has SKILL.md with name + description" bash -c "head -5 '$f' | grep -q '^name: $s\$' && grep -q '^description: ' '$f'"
done
check "qa-qa-guide is auto-discoverable" bash -c "! grep -q 'disable-model-invocation: true' '$SK/qa-qa-guide/SKILL.md'"
check "no Dev/PMO menus in skills" bash -c "! grep -rqiE 'choose your lane|pick up stor|sprint planning menu|grooming menu' '$SK'"
check "synced to .github/skills (VS Code)" diff -rq "$SK/qa-qa-guide" "$ROOT/.github/skills/qa-qa-guide"
check "synced to .claude/skills (Claude Code)" diff -rq "$SK/qa-qa-guide" "$ROOT/.claude/skills/qa-qa-guide"

echo "3. Config files"
check ".cursor/mcp.json is valid JSON with playwright" jq -e '.mcpServers.playwright' "$ROOT/.cursor/mcp.json"
check ".vscode/mcp.json is valid JSON with playwright" jq -e '.servers.playwright' "$ROOT/.vscode/mcp.json"
check ".qa/ is gitignored" grep -qx '.qa/' "$ROOT/.gitignore"
for f in "$P"/*.sh; do check "$(basename "$f") syntax" bash -n "$f"; done
check "cases.py compiles" python3 -c "import ast,sys; ast.parse(open('$P/cases.py').read())"

echo "4. Offline flows (in a temp sandbox)"
T="$(mktemp -d)"; cd "$T"; mkdir .qa
printf 'APP_VERSION_CMD="echo 9.9.9-selftest"\nAPP_URL=https://staging.example.com\n' > .qa/platform.env
echo 'DEMO-1|2026-01-01T00:00:00.000+0000|Ready for QA|Self-test story|2026-01-01T00:00:00Z' > .qa/anchor
cat > good.json <<'EOF'
{"story":"DEMO-1","story_ac":["AC1"],"cases":[{"id":"TC1","name":"Verify user can log in with valid credentials","precondition":"Test user exists","priority":"High","ac":["AC1"],
 "steps":[{"action":"Open login page","expected":"Login form with Email and Password fields is shown"},{"action":"Submit valid credentials","expected":"Dashboard heading 'Welcome' is visible"}]}]}
EOF
echo '{"story":"DEMO-1","cases":[{"name":"x","steps":[{"action":"a","expected":""}]}]}' > bad.json
check "lint passes a good case file" "$P/qa.sh" cases lint good.json
expect_exit "lint fails a bad case file" 1 "$P/qa.sh" cases lint bad.json
check "Excel export creates a valid .xlsx" bash -c "'$P/qa.sh' cases export good.json --xlsx && python3 -c \"import zipfile;assert zipfile.ZipFile('.qa/exports/DEMO-1-cases.xlsx').testzip() is None\""
check "CSV export" bash -c "'$P/qa.sh' cases export good.json --csv && grep -q 'Case ID' .qa/exports/DEMO-1-cases.csv"
check "appversion reads from the app source" bash -c "'$P/qa.sh' appversion | grep -q 9.9.9-selftest"
check "hand-run: run start" "$P/qa.sh" run start DEMO-T1
echo png > shot.png
check "hand-run: snap moves screenshot into evidence" bash -c "'$P/qa.sh' snap shot.png login | grep -q evidence/01-login.png"
check "hand-run: steprun logs a step" "$P/qa.sh" steprun 1 "Open login" "Form shown" "Form shown" pass
check "hand-run: handresult has version + evidence" bash -c "'$P/qa.sh' handresult pass | grep -q 'App version: 9.9.9-selftest' && grep -q 01-login.png .qa/runs/DEMO-1/*/result.md"
check "walkthrough becomes a draft case" bash -c "'$P/qa.sh' walkthrough && test -f .qa/cases/DEMO-1.walkthrough.json"
# Messy real-world header: typo, singular "Test Step " with trailing space, steps numbered inline on one line
printf ',,Project Name,Demo\n\nTest Case ID,Test Scenario,Test Case Discription,Test Step ,Expected Result,Priority\nTC_01,Verify login,Login with valid user,"1.Open login     2.Submit valid user","Dashboard visible",P1\n' > sheet.csv
check "Excel/CSV import reads the tester's sheet" bash -c "'$P/qa.sh' cases import sheet.csv | grep -q 'Imported 1 case(s), 2 step(s)'"
check "sheet pin works without Jira" bash -c "'$P/qa.sh' anchor --sheet .qa/cases/sheet.json && '$P/qa.sh' drift | grep -q 'no Jira'"
check "sheet run writes a new results workbook" bash -c "'$P/qa.sh' run start TC_01 && '$P/qa.sh' steprun 1 'Open login' 'Form shown' 'Form shown' pass && '$P/qa.sh' handresult pass && '$P/qa.sh' cases results .qa/cases/sheet.json res.xlsx | grep -q 'results for 1 of 1'"
expect_exit "sheet-only run cannot submit to Jira" 1 "$P/qa.sh" submit
sleep 1; touch sheet.csv
expect_exit "drift when the Excel file changes after import" 4 "$P/qa.sh" drift
echo 'DEMO-1|2026-01-01T00:00:00.000+0000|Ready for QA|Self-test story|2026-01-01T00:00:00Z' > .qa/anchor
check "flaky check reports a verdict" bash -c "'$P/qa.sh' flaky 2 -- true | grep -q 'stable pass'"

echo "5. Safety gates (nothing is sent)"
echo '{"summary":"test DEMO-99","priority":"High"}' > b1.json
echo '{"summary":"Login: error shown for valid password"}' > b2.json
echo '{"summary":"Login: error shown for valid password","priority":"High","description":"x"}' > b3.json
expect_exit "refuses 'test KEY' tickets" 1 env JIRA_PROJECT=DEMO "$P/jira.sh" create-bug b1.json
expect_exit "refuses a bug with no priority" 1 env JIRA_PROJECT=DEMO "$P/jira.sh" create-bug b2.json
expect_exit "bug create without --yes = preview only (exit 2)" 2 env JIRA_PROJECT=DEMO "$P/jira.sh" create-bug b3.json
echo note > c.md
expect_exit "Zephyr result without --yes = preview only (exit 2)" 2 env ZEPHYR_TOKEN=x ZEPHYR_PROJECT_KEY=DEMO "$P/zephyr.sh" execute DEMO-T1 Pass c.md --cycle DEMO-R1
check "Zephyr preview warns it cannot delete" bash -c "ZEPHYR_TOKEN=x ZEPHYR_PROJECT_KEY=DEMO '$P/zephyr.sh' execute DEMO-T1 Pass c.md --cycle DEMO-R1 | grep -q 'cannot delete'"
cd "$ROOT"; rm -rf "$T"

for a in "$@"; do
  if [ "$a" = "--live" ]; then
    echo "6. Live read-only preflight (uses $ROOT/.qa/config.env)"
    (cd "$ROOT" && "$P/qa.sh" preflight) && ok "preflight" || bad "preflight (run the qa-config skill: say 'set up QA')"
  fi
  if [ "$a" = "--mcp" ]; then
    echo "7. Playwright MCP"
    check "@playwright/mcp starts (--help)" bash -c "npx -y @playwright/mcp@latest --help"
  fi
done

echo; echo "Result: $pass passed, $fail failed"
[ "$fail" = 0 ]
