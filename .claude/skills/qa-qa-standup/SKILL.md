---
name: qa-qa-standup
description: Builds a QA-only standup update from Jira and Zephyr. It covers bugs filed, closed or verified, and reopened, bugs waiting for retest, Zephyr results recorded, and blockers. Used when a tester says "QA standup", "standup", "what did I test yesterday", or picks standup from the QA menu. No Dev or PMO sections.
disable-model-invocation: true
---

# QA standup

Scripts: `../qa-qa-work/scripts/` (`$QA`). Rules: [../qa-qa-work/reference/rules.md](../qa-qa-work/reference/rules.md). This skill is read-only and writes nothing.

## Steps
1. `$QA/qa.sh preflight`. If Jira fails, send the person to qa-config.
2. Ask the window: `1) Since last working day (default)  2) Last 3 days  3) Last 7 days`, which becomes `-1d` (`-3d` on Mondays), `-3d` or `-7d`.
3. Run `$QA/qa.sh standup <window>`.
4. Write the update in this shape, using only what the queries returned. If a section is empty, write "none".

```
QA standup — <date>
Yesterday
- Filed: <n> bugs (<KEY prio summary>, …)
- Verified/closed: <n> (<KEYs>)
- Reopened: <n> (<KEYs and one-line why from last comment if known>)
- Zephyr results: <Pass n / Fail n / Blocked n>
Today
- Retest queue: <n> (<top 3 by priority>)
- <what the tester says they'll do; ask if unknown>
Blockers
- <KEY — reason> or none
```

5. Ask: `1) Looks right  2) Add something  3) Rewrite shorter`. Posting it anywhere (Slack, a Jira comment) is not part of this pack. The person copies it.

## Notes
- "Closed by me" means bugs whose status **I** changed into a Done category in the window.
- Zephyr counts are executions where `executedById` is the current Jira user. They show as status ids, so map them with `zephyr.sh statuses`.
- Status names and the blocker JQL can be tuned in `.qa/config.env` (`QA_REOPEN_STATUS`, `QA_RETEST_STATUSES`, `QA_BLOCKER_JQL`).
