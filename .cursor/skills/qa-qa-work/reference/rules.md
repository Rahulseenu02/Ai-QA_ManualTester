# QA standing rules

These apply to every skill in the pack. If a step conflicts with a rule, the rule wins.

## Sources of truth
- **Jira is the source of truth** for tickets, status, acceptance criteria, versions and bugs.
- **Zephyr holds the test protocols**: cases, cycles, executions. Excel is the offline or alternate home for cases when the team doesn't use Zephyr.
- The app's version comes from `appversion.sh`, never from memory or chat history.

## Who does what
- **The agent runs the commands. The person answers the questions.** Never ask the person to type a command or a skill name.
- Ask questions as **short numbered options** (`1) … 2) … 3) …`). Keep it to one question at a time where you can.
- **The tester makes the release call.** Reports present evidence only. Never write "ready", "good to go", "ship it" or "approved" in a sign-off or readiness report.

## Pin the ticket
1. Run `qa.sh anchor KEY` before any work on a ticket.
2. Run `qa.sh drift KEY` before every **write, run or submit**. Exit 3 means the key differs from the pin, so re-anchor. Exit 4 means Jira changed: re-read the ticket, tell the person what changed, and re-anchor. Exit 5 means Jira can't be reached: stop.
3. **One ticket and one scenario per chat.** If the person switches keys, re-anchor and say that a fresh chat is cleaner.
   - **Excel sheets:** one sheet per chat, pinned with `qa.sh anchor --sheet`. Cases run one at a time, each as its own run, with a "next case or stop" check between them. Drift on a sheet pin means the Excel file changed after import, so re-import it.
   - **Never overwrite the tester's own Excel file.** Results go into a new workbook in `.qa/exports/`.
4. **Never take an issue key from a screenshot** or image. Ask the person to type it, or pick it from a list you fetched from Jira.

## Writes
- Every write (Jira comment, bug, attachment, transition, link; Zephyr case, cycle, result) runs **without `--yes` first**. That run prints the preview.
- Show the preview, then ask: `1) Yes, do it  2) Change something  3) Cancel`.
- Add `--yes` only after the person answers **1** or types an explicit yes. **Silence is not approval.** Neither is "ok, looks fine?" from you, or an earlier yes given for a different write.
- Before any Zephyr create, say: **"Zephyr can't delete test cases, cycles or results from here. What we create stays."**

## Bugs
- QA files **real defects** and **access requests** only. Never create "test BWS-nnnn" or placeholder tickets (`jira.sh` refuses them).
- Before filing: run the dupe check (`qa.sh dupes "words"`) and show the matches.
- **Ask the priority** before creating (offer numbered options from the project's priorities).
- Use the six headings in [bug-template.md](bug-template.md).
- **Attach the evidence after the bug is created** (`jira.sh attach KEY files`, previewed).

## Results
- Every result comment includes **screenshots** and the **app version from `appversion.sh`**. If the version is unknown, ask the tester to read it from the app; don't guess.
- Result status is one of **Pass | Fail | Blocked**. Blocked needs a reason and the blocking ticket if one exists.

## Environments
- Hand-runs and Playwright MCP sessions go to **test environments only**. `qa.sh laneguard` refuses hosts listed in `PROD_HOSTS`.
- Use test data and test accounts from the project. Never real customer data, and never the tester's personal passwords.
