# QA skill pack: tester cheat sheet

**Start here:** type *"guide me"* (or just say what you want, like *"test BWS-123"*). The agent runs every command. You answer numbered questions.

## Say this → get this
| You say | What happens |
|---|---|
| "guide me" / "QA guide" | short guide + 18-item QA menu |
| "test BWS-123" / "review this ticket and test it" | pin the ticket → review the AC and gaps → ready check → coverage → hand-run in the browser (Playwright MCP) → result |
| "explore jira ticket BWS-123" | risk map, test ideas, questions, optional exploratory session |
| "ready to test BWS-123?" | checklist: status, AC, fix version, links, cases, version |
| "write test cases for BWS-123" | cases from the AC → lint → **Zephyr, Excel (.xlsx) or CSV** |
| "check these test cases" (paste or Excel) | lint findings per case |
| "run my Excel test cases" + attach the .xlsx/.csv | import the sheet (shows which columns it understood) → pick cases → browser run per case → **new** results workbook (your file is never changed) |
| "automate my test case sheet" | Playwright specs per case ID in your suite's style, each run 3×, plus a case → spec map |
| "run the test" / "hand test this" | browser steps with a screenshot per step → result.md |
| "record what I do into a case" | walkthrough → draft case |
| "mark it passed / failed / blocked" | Jira comment + screenshots + app version (+ Zephyr result) |
| "file a bug" | dupe check → six headings → **you pick priority** → create → attach evidence |
| "retest my bugs" | your retest queue → pick one → rerun → result → optional transition |
| "test cycle for 4.2" | Zephyr cycle → run cases → record each |
| "does BWS-123 have its tests?" | linked cases, last results, uncovered AC |
| "automate this case" / "fix this spec" | reads your suite first, reuses login, page objects and fixtures, generates only new code, runs it 3× |
| "is this test flaky?" / "autoclose automation bugs" / "can't reproduce" | N reruns + pass rate / proposed close / CNR comment draft |
| "a11y check this page" | keyboard, focus, labels, headings, contrast, optional axe scan |
| "release readiness 4.2" / "QA sign-off 4.2" | evidence report. **You** make the release call. |
| "QA standup" | filed, closed, reopened, retests, blockers |

## What the agent will always do
- **Pin one ticket per chat.** It checks whether Jira changed before any write.
- **Show every write first** and wait for your **1) Yes**. Silence never counts as yes.
- Warn you that **Zephyr can't delete** cases, cycles or results created here.
- Read the **app version from the app** (`appversion.sh`) and attach **screenshots** to every result.
- Ask you the **bug priority**. Never read a ticket key from a screenshot.
- Test on **test environments only**. Production hosts are blocked.

## What you do
- Type ticket keys. Answer numbered options. Make the judgement calls (UX, "bug or intended?").
- Complete MFA or captcha in the browser window when asked.
- Paste tokens into `.qa/config.env` yourself, never into chat.
- Make the release call.

## First-time setup (5 min)
1. Say *"set up QA"* to fill `.qa/config.env` (Jira, Zephyr) and `.qa/platform.env` (test URL, prod hosts, version source, suite command).
2. Turn on the **playwright** MCP server (Cursor: Settings → MCP. VS Code: `.vscode/mcp.json` → Start).
3. Say *"guide me"*.

## Where things land
`.qa/runs/<KEY>/<run>/` evidence and result.md · `.qa/cases/<KEY>.json` cases (also imported sheets) · `.qa/exports/` Excel and CSV, including `*-results-<date>.xlsx` · `.qa/reports/` readiness, sign-off, flaky logs
