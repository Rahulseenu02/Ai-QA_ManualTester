---
name: qa-qa-guide
description: Front door for all QA work by manual testers and QA automation engineers. It shows a short QA guide and a numbered QA menu, or goes straight to the named task after preflight. It covers manual testing with Playwright MCP, test cases in Zephyr or Excel, running or automating the tester's own Excel test cases, reviewing and testing a Jira ticket, filing and retesting bugs, test cycles, sign-off evidence and automation scripts. Use it when the person says "guide me", "QA guide", "help me test", "retest my bugs", "file a bug", "write test cases", "test cycle", "QA sign-off", "explore jira ticket", "test this ticket", "ready to test", "release readiness", "check these test cases", "automate this", "run my Excel test cases", "automate my test case sheet", or pastes a Jira key or an .xlsx/.csv of test cases and asks to test it.
---

# QA guide (front door)

Lane is always **QA**. There is no lane picker, and there are no Dev or PMO paths. Skip anything outside QA (implementing features, code review, PRs, grooming, sprint planning): say it's outside this pack and offer the QA menu.

Scripts: `../qa-qa-work/scripts/` relative to this file (in the workspace: `.cursor/skills/qa-qa-work/scripts/`). Call it `$QA` below. Rules: [../qa-qa-work/reference/rules.md](../qa-qa-work/reference/rules.md). Read them once per chat.

## Flow

1. **Preflight.** Run `$QA/qa.sh preflight`.
   - If it fails on Jira or Zephyr config, read `../qa-config/SKILL.md` and walk the person through setup. Excel work (§4 export, §17) can go ahead without Jira or Zephyr.
   - If no app version source is set, keep going. You'll ask the tester for the version when a result needs it.
2. **Did the person already name the work?** Match their words against the menu table below.
   - **Yes:** skip the menu. If a Jira key was typed, run `$QA/qa.sh anchor KEY`. Then open `../qa-qa-work/SKILL.md` and go to that item.
   - **No:** show the guide summary, then the menu.
3. After the person picks an item, read `../qa-qa-work/SKILL.md` and follow that item's checklist. For standup, read `../qa-qa-standup/SKILL.md`.

## Guide summary (show this, keep it short)

> **QA guide.** I run the commands and you answer the questions. Jira is the source of truth, and Zephyr (or Excel) holds the test cases. I pin one ticket per chat. Every write to Jira or Zephyr is shown to you first and only happens after your "yes". I drive the browser with Playwright MCP, take screenshots as evidence, and read the app version from the app. You make the release call.

## QA menu (show as numbered options)

| # | Menu option | Say things like | Goes to (qa-qa-work) |
|---|---|---|---|
| 1 | Test a Jira ticket end to end | "test JIRA-123", "review this ticket and test it" | §1 Ticket → review → test |
| 2 | Explore a story | "explore jira ticket", "what should I test" | §2 Explore |
| 3 | Is the story ready to test? | "ready to test", "can I start" | §3 Ready check |
| 4 | Write or lint test cases (Zephyr or Excel) | "write test cases", "check these test cases" | §4 Test cases |
| 5 | Run or automate my Excel test cases | "run my Excel test cases", "automate this sheet" | §17 Excel-driven |
| 6 | Manual hand-run with evidence (Playwright MCP) | "run the test", "hand test this" | §5 Hand-run |
| 7 | Record a walkthrough into a case | "record what I do", "turn this into a case" | §6 Walkthrough |
| 8 | Submit a result (Pass, Fail or Blocked) | "mark it passed", "record result" | §7 Submit |
| 9 | File a bug | "file a bug", "log a defect" | §8 File bug |
| 10 | Retest my bugs | "retest my bugs", "retest cycle" | §9 Retest |
| 11 | Run a sprint or release test cycle | "test cycle", "regression run" | §10 Cycle |
| 12 | Coverage: does this ticket have its tests? | "coverage", "is it tested" | §11 Coverage |
| 13 | Write or fix automated tests | "automate this", "fix this spec" | §12 Automation |
| 14 | Automation bugs: autoclose, flaky check, could-not-reproduce | "flaky", "autoclose", "can't reproduce" | §13 Automation bugs |
| 15 | Accessibility quick-check | "a11y check", "accessibility" | §14 A11y |
| 16 | Release readiness evidence | "release readiness" | §15 Readiness |
| 17 | Sign-off summary (report only) | "QA sign-off" | §16 Sign-off |
| 18 | QA standup | "standup", "what did I do yesterday" | qa-qa-standup |

Ask: **"Which one? Reply with a number."** If the work needs a ticket and none is pinned, ask for the Jira key next. The person types it; never read a key from a screenshot.

## Routing notes
- A bare Jira key with "test", "check" or "look at" → item 1.
- "retest my bugs" → item 9 straight away, no menu.
- An Excel or CSV file of test cases with "run", "test", "execute" or "automate" → item 5 (§17). With "check" or "review" only → item 4 (lint mode).
- Excel-driven work doesn't need Jira. Preflight can fail on Jira and §17 still runs sheet-only.
- A Playwright spec file or a failing CI test → item 12 or 13.
- The person names a key that differs from the pinned one → re-anchor (`qa.sh anchor NEWKEY`) and suggest a fresh chat.
