# QA methods: review, design, retest

## Ticket review (before testing)
Check the ticket and list findings under four headings: **Clear**, **Gaps**, **Ambiguous**, **Questions**.
- AC exist, are numbered (AC1..n) and each one is testable (observable outcome)
- Roles and permissions named? Data and preconditions? Error and empty states?
- Non-functional: performance, accessibility, browser and device, localisation?
- Dependencies: linked stories, APIs, feature flags, migrations, config
- Fix version and environment where the change is deployed
- Out of scope stated?
Questions go to the person first. Commenting them on Jira is a write (preview → yes).

## Test design techniques (pick what fits)

| Technique | Use for | Example |
|---|---|---|
| Equivalence partitions | input fields | valid email, invalid format, empty |
| Boundary values | lengths, ranges, dates | 0, 1, max-1, max, max+1 |
| Decision table | rule combos | role × dealer × status |
| State transition | workflows | Draft → Submitted → Approved → back? |
| Error guessing | known weak spots | double-click submit, refresh mid-save, back button |
| CRUD | entities | create, read, update, delete, and audit |
| Roles | permissions | admin can, viewer can't, direct URL as viewer |
| Pairwise | many config options | browser × locale × role |

Per story aim for: **1 happy path per AC + negative + boundary + one role or permission case**. Keep each case to one scenario.

## Exploratory heuristics (charters)
- **Interrupts:** refresh, back, close the tab, session timeout, network offline (`browser_evaluate` read-only checks, or the person toggles it)
- **Data:** long strings, unicode, emoji, leading and trailing spaces, duplicates, special characters `<>'";`
- **Concurrency:** two tabs editing the same record, double submit
- **Consistency:** list vs detail vs export match; the success message matches the saved state
- **Responsiveness:** 375 / 768 / 1440 widths

## Retest a fixed bug
1. Reproduce the **original steps** exactly, on the version in the bug's fix version or later (check `appversion.sh`)
2. Vary them once (other data, other role, other browser if relevant)
3. Small regression ring: neighbouring features that share the changed component
4. Pass → evidence + version comment. Fail → comment what still happens and offer the reopen transition (preview → yes).

## Severity vs priority (helps the person choose)
- **Severity** is the impact: blocker, major, minor, trivial
- **Priority** is the order to fix it in. **The person chooses it.** You offer the options and say what the severity suggests.

## Sign-off content
Scope (stories and versions), what was executed (by cycle and status counts), open defects by priority, known risks, untested areas and why, environment and version. No verdict. "Release call: yours."
