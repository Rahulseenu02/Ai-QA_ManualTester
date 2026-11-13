# Manual testing with Playwright MCP

The agent drives a real browser through the Playwright MCP server. The tester watches, makes the judgement calls, and owns the verdict.

## Setup
- MCP config ships in `.cursor/mcp.json` and `.vscode/mcp.json`:
  `npx @playwright/mcp@latest --output-dir .qa/mcp-output` (add `--browser chrome|firefox|webkit`, `--headless`, or `--viewport-size 1280,800` if needed)
- Screenshots land in `.qa/mcp-output/`. Run `qa.sh snap` on each one to move it into the run's evidence folder.
- Check the server is on: the tools `browser_navigate`, `browser_snapshot` and the rest should be listed. If they aren't, ask the person to enable the "playwright" MCP server in Cursor or VS Code settings.

## Tools you'll use

| Tool | Use |
|---|---|
| `browser_navigate` | open the test URL (only after `qa.sh laneguard URL` passes) |
| `browser_snapshot` | accessibility tree: read the page, find elements by role and name. **Prefer this to screenshots for deciding what to click.** |
| `browser_click`, `browser_type`, `browser_fill_form`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_file_upload`, `browser_handle_dialog` | act |
| `browser_wait_for` | wait for text to appear or disappear, or for a time. Use it instead of guessing sleeps. |
| `browser_take_screenshot` | evidence (`filename: "BWS-123-step3.png"`, `fullPage` when useful) |
| `browser_console_messages`, `browser_network_requests` | on failure, capture JS errors and failing calls (4xx/5xx) |
| `browser_resize` | responsive checks (375x812, 768x1024, 1440x900) |
| `browser_evaluate` | read-only page checks (axe scan, computed styles). Never change app data through it. |
| `browser_tabs`, `browser_navigate_back`, `browser_close` | housekeeping |

## Hand-run loop (per step)
```
1. Act        browser_click / browser_type ... (target from the latest browser_snapshot)
2. Observe    browser_snapshot (and browser_wait_for if async)
3. Compare    actual vs the case's expected result: quote what's on the page
4. Evidence   browser_take_screenshot → qa.sh snap .qa/mcp-output/<file> step-N
5. Log        qa.sh steprun N "action" "expected" "actual" pass|fail|blocked <evidence path> ["data"]
```
- One screenshot per step that has a visible expected result, plus one of the final state.
- When a step fails, keep going only if the remaining steps are independent. Otherwise mark the rest `blocked`.
- Record the **actual** text you saw, not "as expected".

## When to stop and ask the person
- Login needs MFA or a captcha. The person completes it in the browser window; never bypass it.
- A credential is needed. Use the project's test accounts (seed or fixture files) or ask the person to sign in themselves. Never type their real personal passwords.
- Visual or UX judgement (layout, copy, colour), or "is this a bug or intended?"
- The page lands somewhere unexpected (a different host, a production URL). Run laneguard again.

## Exploratory (charter) mode
- Charter: *Explore <area> with <resources> to discover <risk>*. Agree a timebox (e.g. 30 min).
- Use heuristics from qa-methods.md (CRUD, boundaries, interrupts, back button, refresh, double-submit, slow network, roles).
- Log the notable observations with `steprun` (status `pass` for an observation, `fail` for a problem). Bugs found go to §8.
- At the end, summarise what was covered, what wasn't, bugs, questions and follow-up cases.

## Evidence rules
- The result comment includes the screenshots and the app version (`appversion.sh` at run start, re-checked at handresult).
- Mask or avoid personal data in screenshots. Use test accounts.
