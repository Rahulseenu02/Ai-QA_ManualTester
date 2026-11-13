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
| Excel | `qa.sh cases export FILE --xlsx [OUT]` | one row per step. Columns: Case ID, Story, Title, Objective, Precondition, Priority, Type, AC, Step #, Action, Test Data, Expected, Actual, Status, Evidence, App Version. Header is frozen and filtered. |
| CSV | `qa.sh cases export FILE --csv [OUT]` | same columns, UTF-8 with BOM so Excel opens it cleanly |
| Zephyr | `qa.sh cases push FILE` → `--yes` | creates each case, sets its steps, and links it to the story. **Can't be deleted from here.** |

Importing from Excel ("check these test cases"): read the sheet, map the columns to this format, then lint.
