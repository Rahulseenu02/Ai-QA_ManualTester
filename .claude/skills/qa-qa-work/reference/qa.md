# QA reference (deep detail)

## Files the pack keeps (`.qa/`, gitignored)
| Path | What |
|---|---|
| `config.env` | Jira and Zephyr tokens (qa-config) |
| `platform.env` | app URL, prod hosts, version source, suite command (qa-platform) |
| `anchor` | pinned ticket: `KEY\|updated\|status\|summary\|pinned_at` |
| `runs/KEY/<run>/` | `meta.env`, `steps.jsonl`, `evidence/`, `result.md`, `status` |
| `runs/current` | path of the open run |
| `cases/KEY.json` | test cases (format: test-case-format.md) |
| `bugs/*.json` | bug drafts |
| `exports/` | Excel and CSV |
| `reports/` | readiness, sign-off, CNR drafts, flaky logs |
| `mcp-output/` | Playwright MCP screenshots before `snap` |

## Exit codes
| Code | Meaning | Do |
|---|---|---|
| 0 | ok | — |
| 1 | error | read the message, fix or ask |
| 2 | preview shown, nothing written | ask `1) Yes 2) Change 3) Cancel`, and re-run with `--yes` only on 1 |
| 3 | drift: key differs from the pin | `qa.sh anchor NEWKEY` (suggest a fresh chat) |
| 4 | drift: ticket changed in Jira | `jira.sh view KEY`, tell the person what changed, re-anchor |
| 5 | drift check couldn't reach Jira | stop writes, check qa-config |

## Zephyr (Scale Cloud API v2) notes
- Base `https://api.zephyrscale.smartbear.com/v2` (override with `ZEPHYR_BASE_URL` for EU or self-hosted)
- Executions belong to a cycle, so `submit` needs `--cycle`. Create one with `zephyr.sh create-cycle`.
- Status names come from `zephyr.sh statuses` (usually Pass, Fail, Blocked, In Progress, Not Executed)
- Zephyr's public API has no attachment upload for executions. Evidence is attached to the **Jira** ticket, and the execution comment lists the files.
- **Nothing is deleted.** Tell the person before every create.

## Jira notes
- Reads use REST v3 `search/jql`. Writes use v2 so descriptions and comments can be wiki text (`h3.`, `#` lists, `{code}`).
- Acceptance criteria may live in a custom field. Set `JIRA_AC_FIELD=customfield_XXXXX` in config.env so `view` and `ready` read it.
- Status names vary by project. Set `QA_RETEST_STATUSES`, `QA_READY_STATUSES` and `QA_REOPEN_STATUS` in config.env.

## Accessibility quick-check (§14)
Do this with Playwright MCP on one page or flow. Log each check with `steprun`.
1. **Keyboard:** Tab through the page with `browser_press_key Tab` repeatedly and `browser_snapshot`. Every control should be reachable in a logical order, with no trap, and Enter or Space should activate it.
2. **Focus visible:** take a screenshot after tabbing. The focus ring must be visible.
3. **Names:** in the snapshot, buttons, links and inputs have accessible names. Inputs have labels, not placeholder only.
4. **Headings:** one h1 and a logical h2/h3 order.
5. **Images:** meaningful images have alt text, and decorative ones are hidden.
6. **Errors:** submit an empty form. Errors should be announced as text, tied to their fields, and not shown by colour only.
7. **Zoom and reflow:** `browser_resize` to 320 wide. There should be no horizontal scroll or clipped content.
8. **Contrast:** check suspicious text with `browser_evaluate` (computed colours). Normal text needs 4.5:1.
9. **Optional axe scan** (test env only, read-only):
   `browser_evaluate`: load `https://cdnjs.cloudflare.com/ajax/libs/axe-core/4.10.2/axe.min.js` with a script tag, then return `(await axe.run()).violations.map(v=>({id:v.id,impact:v.impact,nodes:v.nodes.length}))`
Report as: check, result, evidence, suggested severity. State: "Quick-check, not a full WCAG audit."

## Retest list query
`project = $JIRA_PROJECT AND issuetype = Bug AND status in ($QA_RETEST_STATUSES) AND (reporter = currentUser() OR assignee = currentUser())`

## Release readiness / sign-off contents
- Scope (all issues in fixVersion), open bugs by priority, cycle status counts, test env version
- The person adds: risks, untested areas, environment caveats
- The footer is always *"This is evidence, not a verdict. The tester makes the release call."*
