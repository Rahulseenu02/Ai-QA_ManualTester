# Excel-driven testing (§17)

The tester keeps the test cases in their own Excel or CSV file. The AI reads the file, runs the cases in the browser with Playwright MCP or writes Playwright automation for them, and returns the results in a new workbook.

```
Tester's sheet (.xlsx/.csv)
   │  qa.sh cases import        → .qa/cases/<name>.json   (columns used/ignored shown)
   │  qa.sh anchor --sheet F    (or anchor KEY if linked to a Jira story)
   ├─ Manual:     cases show F ID → run start ID → Playwright MCP + steprun/snap → handresult
   │              → qa.sh cases results F → .qa/exports/<name>-results-<date>.xlsx
   └─ Automation: cases show F ID → read suite (automation.md) → confirm locators with MCP
                  → spec per case tagged with the ID → run + flaky 3 → automation-map.md
```

## 1. Import
- `qa.sh cases import "<path>" [--sheet "Regression"]`
- Check the output with the tester:
  - **Columns used** — e.g. `id='TC ID', name='Test Scenario', action='Test Steps', expected='Expected Result'`
  - **Columns ignored** — if a column they care about is ignored (e.g. "Remarks", "URL"), tell them. Then add the value to the JSON by hand or ask them to rename the header.
  - **Other sheets** — ask which one, as numbered options
- Lint warnings are fine for a manual run. Before automating, fix the **errors** (no steps, a last step with no expected result).

## 2. Pin
| Sheet has | Ask | Then |
|---|---|---|
| one Jira story key, Jira configured | `1) Link to KEY  2) Sheet only` | 1 → `qa.sh anchor KEY` (submit posts to Jira and Zephyr as usual) |
| no key, or Jira not configured | — | `qa.sh anchor --sheet .qa/cases/<name>.json` |

With a sheet pin, `drift` checks whether the Excel file was saved again after import. If it was, re-import it before running more cases.

## 3. Manual run with Playwright MCP
Per case:
1. `qa.sh cases show F ID` and read the steps aloud to the tester in a short form
2. Precondition from the sheet. Log in with the project's test account, or the tester signs in; never use their personal password.
3. `qa.sh laneguard` → `qa.sh run start ID` (use the sheet's case ID exactly, so the results map back)
4. For each step, follow the loop in [playwright-mcp.md](playwright-mcp.md): act, snapshot, compare with the sheet's expected result, screenshot, `snap`, `steprun`
5. `qa.sh handresult pass|fail|blocked`, then ask `1) Next case  2) Stop here`

Steps written loosely in the sheet ("check the page", "(see title)") need the tester to say what passing looks like. Ask before you run, and note their answer as the expected result in the `steprun`.

## 4. Results back to Excel
- `qa.sh cases results .qa/cases/<name>.json` creates `.qa/exports/<name>-results-<date>.xlsx`
- Per step it fills Actual Result, Status, Evidence (path to the screenshot) and App Version. Case Result goes on the first row of each case.
- Cases not run yet stay blank. **The original sheet is never edited.** If the tester wants the results in their own file, they copy the columns across.
- Linked to Jira? Also run `qa.sh submit` per case (preview → yes) as in §7.

## 5. Automation from the sheet
Follow [automation.md](automation.md) steps 1–5. Specific to sheets:
- One `test()` per sheet case. Put the ID in the title and tag, e.g. `test('TC_UM_01 @TC_UM_01 Verify admin can add a user', …)`, unless the suite has another convention.
- Use the sheet's Test Data column for the values. Swap unique fields (email, username) to the suite's random-data helper so reruns don't collide, and say you did it.
- Group the specs by the sheet's Module column if the suite is organised by feature
- Skip cases labelled `automated` (from an "Automation" column of Yes or Automated) unless the tester asks
- After generating: run each spec, then `qa.sh flaky 3 -- <cmd>`, and write `.qa/reports/<name>-automation-map.md`:

| Case ID | Title | Spec file | Test name | Result (3 runs) | Notes |
|---|---|---|---|---|---|

- "Both" mode: run by hand first, then automate **only the cases that passed** by hand. Failed cases are possible bugs, not automation work.
