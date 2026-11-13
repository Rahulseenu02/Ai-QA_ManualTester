# Bug template: six headings

Every bug QA files uses these six headings, in this order. Fill them from the run log (`steps.jsonl` / `result.md`), not from memory.

```
h3. 1. Environment
App version: <from appversion.sh>   Env/URL: <APP_URL>   Browser/Device: <e.g. Chrome 131 / macOS>   User role: <test account role>

h3. 2. Preconditions
<data, settings, feature flags needed before step 1>

h3. 3. Steps to reproduce
# <step>
# <step>
# <step>

h3. 4. Expected result
<observable expected, quoting the AC where possible: "AC2: ...">

h3. 5. Actual result
<what actually happened, with exact error text, and console or network errors if any>

h3. 6. Evidence & frequency
Screenshots: attached after create (<file names>)
Reproducible: <3/3 | 1/5 | once>   Story: <STORY-KEY>   Test case: <ZEPHYR-KEY if any>
```

## Draft JSON for `jira.sh create-bug`
```json
{
  "summary": "Add User: Create User button stays disabled after all mandatory fields are filled",
  "priority": "High",
  "labels": ["qa-found"],
  "components": ["User Management"],
  "affects": ["4.2.1"],
  "linkTo": "BWS-123",
  "description": "h3. 1. Environment\n..."
}
```

## Rules
- **The summary says where and what is wrong:** "<Area>: <symptom> when <condition>". Never "test", "issue" or "bug in page".
- **Ask the priority** with numbered options before creating. Never pick one yourself.
- Run the dupe check first (`qa.sh dupes "Create User disabled"`).
- Preview → explicit yes → `--yes`. Then attach the evidence (a separate preview and yes).
- One defect per bug. Split unrelated symptoms.
