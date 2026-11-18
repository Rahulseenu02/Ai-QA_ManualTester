# Test case file format

One file per story: `.qa/cases/<STORY>.json`. The same file feeds the lint, Excel/CSV export and Zephyr push.

```json
{
  "story": "BWS-123",
  "story_ac": ["AC1", "AC2", "AC3"],
  "cases": [
    {
      "id": "TC1",
      "name": "Verify admin can create a user with valid mandatory fields",
      "objective": "New user appears in User Management after creation",
      "precondition": "Logged in as Admin on staging; dealer code D001 exists",
      "priority": "High",
      "type": "Functional",
      "labels": ["regression"],
      "ac": ["AC1"],
      "steps": [
        {"action": "Open Administration > Users", "data": "", "expected": "Heading 'Manage platform users and permissions' is visible"},
        {"action": "Click 'Add User'", "data": "", "expected": "Add User form opens with First name, Last name, Email, Dealer code and Role fields"},
        {"action": "Fill the form and click 'Create User'", "data": "Test / John / testjohn@yopmail.com / D001 / Viewer", "expected": "Success toast 'User created'; testjohn@yopmail.com is listed in the users table"}
      ]
    }
  ]
}
```

## Field rules
- `name`: starts with "Verify …" and covers **one scenario**. No "and also". Max 120 chars.
- `precondition`: the role, data and environment needed before step 1.
- `priority`: Critical, High, Normal, Medium or Low (it maps to the Zephyr priority name).
- `ac`: which acceptance criteria this case proves. The lint warns about uncovered `story_ac`.
- `steps[].expected`: **observable** (text, state, URL, count). "Works", "correct" and "as expected" are flagged.
- Keep cases to 15 steps or fewer, and split longer ones.

## Lint
`qa.sh cases lint FILE`
- **Errors** (block a push): missing story key, no cases, duplicate names, no steps, a step without an action or expected, placeholder names like "test BWS-12".
- **Warnings**: vague expected, no precondition, no AC mapping, uncovered AC, long names or cases, unknown priority, two scenarios in one.

## Destinations
| Destination | Command | Notes |
|---|---|---|
| Excel | `qa.sh cases export FILE --xlsx [OUT]` | one row per step. Columns: Case ID, Story, Title, Objective, Precondition, Priority, Type, AC, Step #, Action, Test Data, Expected, Actual, Status, Case Result, Evidence, App Version. Header is frozen and filtered. |
| CSV | `qa.sh cases export FILE --csv [OUT]` | same columns, UTF-8 with BOM so Excel opens it cleanly |
| Zephyr | `qa.sh cases push FILE` → `--yes` | creates each case, sets its steps, and links it to the story. **Can't be deleted from here.** |

## Importing the tester's own sheet
`qa.sh cases import SHEET.xlsx|SHEET.csv [--sheet NAME]` writes `.qa/cases/<file>[-sheet].json` in this format, adds a `source` block (file, sheet, header row, columns used), then lints.
- Both common layouts work: **one row per step** (case ID only on the first row, or merged cells) and **one row per case** with numbered steps and expected results in one cell (`1. … 2. …`).
- The header row is found automatically in the first 15 rows from common names (Test Case ID/TC ID, Title/Test Scenario, Pre-Condition, Test Steps/Action, Test Data, Expected Result, Priority, Module, Story/Jira ID, Automation). Unknown columns are listed as ignored.
- Priority P1–P4, Blocker, Major and Minor are mapped to Critical, High, Normal and Low.
- On import, a missing Jira story is a warning, not an error. Intermediate steps without an expected result are also warnings; only the last step must have one.
- `.xls` (old binary) isn't read. Save it as `.xlsx` or `.csv`.
- **Results:** `qa.sh cases results FILE.json [OUT.xlsx]` builds a **new** workbook with Actual, Status, Case Result, Evidence and App Version taken from the latest run of each case. The original file stays untouched.
