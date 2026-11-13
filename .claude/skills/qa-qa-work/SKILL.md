---
name: qa-qa-work
description: Runs the items on the QA menu. It reviews a Jira ticket and hand-tests it with Playwright MCP, writes and lints test cases into Zephyr or Excel, records walkthroughs, submits Pass/Fail/Blocked results with screenshots and app version, files and retests bugs, runs test cycles, checks coverage and ready-to-test, writes or fixes Playwright automation that follows the existing suite, handles flaky and could-not-reproduce checks, does accessibility quick-checks, and builds release-readiness and sign-off evidence. Used when qa-qa-guide routes here, or when the person asks for one of these QA tasks directly.
disable-model-invocation: true
---

# QA work

Scripts are in `scripts/` next to this file (`$QA`). Before the first action in a chat, read [reference/rules.md](reference/rules.md). Deep detail: [reference/qa.md](reference/qa.md), test design: [reference/qa-methods.md](reference/qa-methods.md), browser: [reference/playwright-mcp.md](reference/playwright-mcp.md).

**Every item:** pin first (`$QA/qa.sh anchor KEY`) → `qa.sh drift KEY` before any write, run or submit → preview → numbered yes/no → `--yes` only on an explicit yes.

## Command table

| Need | Command |
|---|---|
| Pin, show, check drift | `qa.sh anchor KEY` · `qa.sh anchor` · `qa.sh drift KEY` |
| Read the ticket | `jira.sh view KEY` · `jira.sh search "JQL"` |
| Lane check before a browser run | `qa.sh laneguard [URL]` |
| Hand-run | `qa.sh run start [CASEKEY]` → `qa.sh steprun …` → `qa.sh snap FILE label` → `qa.sh handresult pass\|fail\|blocked` |
| Submit | `qa.sh submit --case CASEKEY --cycle CYCLEKEY` (preview) → same command with `--yes` |
| Cases | `qa.sh cases lint F` · `qa.sh cases export F --xlsx` · `qa.sh cases push F` |
| Zephyr | `zephyr.sh cases-for KEY` · `case CASEKEY` · `create-cycle NAME` · `cycle CYCLEKEY` · `statuses` |
| Bugs | `qa.sh dupes "words"` · `jira.sh create-bug F.json` · `jira.sh attach KEY files` · `qa.sh retest` |
| Reports | `qa.sh coverage KEY` · `qa.sh ready KEY` · `qa.sh readiness VER` · `qa.sh signoff VER [CYCLE]` |
| Automation bugs | `qa.sh autoclose-candidates` · `qa.sh flaky N -- <cmd>` · `qa.sh cnr-draft KEY N` |
| Version | `appversion.sh` (through `qa.sh appversion`) |

---

## §1 Ticket → review → test (the main path)
- [ ] `qa.sh anchor KEY`, then `jira.sh view KEY`
- [ ] Review the ticket against [qa-methods.md § Ticket review](reference/qa-methods.md). List the AC, gaps, ambiguities, risks and questions for the PO or dev.
- [ ] `qa.sh ready KEY` and show the checklist. If items are missing, ask: `1) Test anyway  2) Comment the gaps on the ticket  3) Stop`
- [ ] `qa.sh coverage KEY`. If there are no cases, offer §4 first, or test from the AC.
- [ ] Pick **one scenario** (one case) for this chat. Ask which if there are several.
- [ ] Run §5, then §7. On a failure, offer §8.

## §2 Explore a story
- [ ] Anchor, `jira.sh view KEY`, and look at linked issues and attachments
- [ ] Produce: what changed, a risk map, test ideas by heuristic (qa-methods.md), open questions, and data needed
- [ ] Offer: `1) Write cases from this (§4)  2) Timed exploratory session with Playwright MCP (§5, charter mode)  3) Post the questions as a Jira comment (preview)`

## §3 Ready-to-test check
- [ ] Anchor → `qa.sh ready KEY` → show the [x] and [ ] items
- [ ] Report only. The tester decides whether to start. Offer to comment the gaps (preview, then yes).

## §4 Write or lint test cases (Zephyr or Excel)
- [ ] Anchor, `jira.sh view KEY`, and extract the AC as `AC1..n`
- [ ] Draft `.qa/cases/KEY.json` in [test-case-format.md](reference/test-case-format.md) format: one scenario per case, observable expected results, mapped to AC, with positive, negative and boundary cases
- [ ] `qa.sh cases lint .qa/cases/KEY.json`. Fix the errors and show the warnings.
- [ ] Show the cases as a table and ask for edits
- [ ] Ask the destination: `1) Zephyr  2) Excel (.xlsx)  3) Both  4) CSV`
  - Excel: `qa.sh cases export F --xlsx` writes to `.qa/exports/KEY-cases.xlsx` (local, no Jira write)
  - Zephyr: `qa.sh cases push F` (preview, lists cases already linked so you can spot dupes) → say Zephyr can't delete → yes → same command with `--yes`
- **Lint mode** ("check these test cases"): convert the pasted text or Excel rows to the JSON format, lint, and report findings per case. Don't push unless asked.

## §5 Manual hand-run with evidence (Playwright MCP)
- [ ] `qa.sh drift KEY` → `qa.sh laneguard [URL]`. If blocked, stop.
- [ ] `qa.sh run start CASEKEY`. If the version is UNKNOWN, ask the tester and set `VERSION=` in the run's meta.env.
- [ ] For each step: do it with Playwright MCP, `browser_snapshot` to read the page, `browser_take_screenshot` to save evidence, `qa.sh snap .qa/mcp-output/<file> step-N`, then `qa.sh steprun N "action" "expected" "actual" pass|fail|blocked <evidence-path>`
- [ ] Ask the person whenever a step needs judgement, such as visual or UX calls, test data choice, or a captcha or MFA. Hand MFA and captcha back to the person; never bypass them.
- [ ] Also capture `browser_console_messages` and failed `browser_network_requests` on any failure
- [ ] `qa.sh handresult pass|fail|blocked` and show result.md. Confirm the overall status with the person.
- Details: [playwright-mcp.md](reference/playwright-mcp.md)

## §6 Record a walkthrough into a case
- [ ] Anchor → `qa.sh run start` → the person describes or does the flow, and you mirror each step with Playwright MCP and `steprun`
- [ ] `qa.sh walkthrough` writes the draft `.qa/cases/KEY.walkthrough.json`
- [ ] Rename it, add the precondition and AC mapping, lint, then go to §4 for the destination

## §7 Submit (Pass, Fail or Blocked)
- [ ] `qa.sh drift KEY`
- [ ] Make sure result.md exists (§5), it has screenshots, and the version came from `appversion.sh` or the tester
- [ ] Blocked → ask for the reason and the blocking key (typed by the person)
- [ ] `qa.sh submit --case CASEKEY --cycle CYCLEKEY` → show the preview (Jira comment, attachments, Zephyr result) and the Zephyr no-delete note → yes → re-run with `--yes`
- [ ] No Zephyr case or cycle → `qa.sh submit` posts the Jira comment and evidence only

## §8 File a bug
- [ ] Anchor the parent story or the ticket under test
- [ ] `qa.sh dupes "key words"` → show matches → `1) It's new  2) It's a dupe of one of these (comment on it instead)  3) Not sure, show me more`
- [ ] Draft with the **six headings** ([bug-template.md](reference/bug-template.md)). Steps, expected and actual come from the run log, and the version comes from `appversion.sh`.
- [ ] **Ask the priority** as numbered options (Highest, High, Medium, Low, Lowest, or the project's set)
- [ ] Write `.qa/bugs/draft.json` → `jira.sh create-bug .qa/bugs/draft.json` (preview) → yes → `--yes`
- [ ] **After create:** `jira.sh attach NEWKEY <evidence files>` (preview → yes). Link to the story using `linkTo` in the JSON.
- Access requests use the same flow with `jira.sh create-access`, and don't need a dupe check against defects.

## §9 Retest bugs / retest cycle
- [ ] `qa.sh retest` → show the list → ask which bug (numbered). One bug per chat, so suggest a fresh chat for each of the others.
- [ ] `qa.sh anchor BUGKEY` → `jira.sh view BUGKEY` → take the repro steps from the bug
- [ ] §5 hand-run of the original steps, plus a small regression around the fix (qa-methods.md § Retest)
- [ ] Result → §7 comment. Ask whether to transition: `1) Move to Done/Verified  2) Reopen  3) Leave status`, then preview with `jira.sh transition`, then yes.
- [ ] Retest cycle: `zephyr.sh create-cycle "Retest <date>"` (preview, no-delete note, yes). Each bug's linked case is recorded with `--cycle`.

## §10 Run a sprint or release test cycle
- [ ] Ask for the scope: `1) Sprint (give the sprint name)  2) Release fixVersion  3) A list of keys`
- [ ] Gather the cases: `zephyr.sh cases-for KEY` per story. Show the plan as a count per story, with the gaps.
- [ ] `zephyr.sh create-cycle "NAME" VERSION` → preview → no-delete note → yes
- [ ] Run each case with §5 (manual) or §12's suite command (automated). Record each with §7 `--cycle`.
- [ ] Progress: `zephyr.sh cycle CYCLEKEY`. At the end, offer §15 or §16.

## §11 Coverage
- [ ] `qa.sh coverage KEY` → show linked cases, last results, never-run and failing
- [ ] Map the cases to the AC (from the case JSON or by reading the case names) and list the **uncovered AC**
- [ ] Offer §4 for the gaps

## §12 Write or fix automated tests
Follow [automation.md](reference/automation.md). In short:
- [ ] Find the suite (`playwright.config.*`, `tests/`, `pages/`, fixtures). Read 2 or 3 existing specs and the page objects before writing anything.
- [ ] Reuse the existing login, fixtures, helpers, assertions and reporting. **Don't introduce a new framework design.**
- [ ] Source of steps: the Zephyr case (`zephyr.sh case CASEKEY`), `.qa/cases/KEY.json`, or a recorded walkthrough. Use Playwright MCP to confirm locators on the live test env (`browser_snapshot` gives the role and name).
- [ ] Generate only the files and methods that need to be added or changed. Tag the spec with the case key.
- [ ] Run the single spec with the suite's own command, then `qa.sh flaky 3 -- <that command>`
- [ ] Show the diff. Committing or opening PRs is outside this pack; the person handles that.

## §13 Automation bugs: autoclose, flaky check, could-not-reproduce
- **Autoclose candidates:** `qa.sh autoclose-candidates` → for each bug the person picks, find the failing test and run `qa.sh flaky 5 -- <cmd>`. All pass → draft the comment ("passes 5/5 on version X, run log …") → preview → yes. Then ask `1) Close  2) Leave open`, preview the transition, then yes. Never bulk-close.
- **Flaky check:** `qa.sh flaky N -- <cmd>` → report the pass rate, the first failing log lines, and the suspected cause (timing, data, order). Suggest the fix, and do it under §12 if asked.
- **Could not reproduce:** anchor the bug → run its steps with §5 at least 3 times (vary browser or data if relevant) → `qa.sh cnr-draft KEY 3` → `jira.sh comment KEY file` (preview → yes). The status change is the team's call.

## §14 Accessibility quick-check
- [ ] Laneguard → Playwright MCP on the page. Follow the checklist in [qa.md § Accessibility](reference/qa.md): keyboard path, focus visible, names and labels, headings, alt text, contrast, zoom 200%, error messages, and an optional axe scan via `browser_evaluate`.
- [ ] Record findings with steprun and screenshots. File serious ones through §8 (priority asked).
- [ ] This is a quick-check, not a WCAG audit. Say so in the report.

## §15 Release readiness evidence
- [ ] Ask for the fixVersion (typed) and the cycle key if there is one
- [ ] `qa.sh readiness "VER" [CYCLE]` → show the report saved under `.qa/reports/`
- [ ] Add coverage per story if asked (`qa.sh coverage` for each). Evidence only.

## §16 Sign-off summary (report only)
- [ ] `qa.sh signoff "VER" [CYCLE]` → add a short narrative: scope tested, results, open bugs by priority, known risks, untested areas
- [ ] **Never write "ready", "approved", "go" or "ship".** End with: *"Release call: yours."*
- [ ] Posting it anywhere (a Jira comment on the release ticket) is a write, so preview → yes
