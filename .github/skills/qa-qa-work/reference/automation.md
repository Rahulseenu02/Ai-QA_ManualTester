# Writing or fixing automated tests

The aim is to add tests that look as though the existing team wrote them. Don't introduce a new framework design.

## 1. Understand the suite first (read before writing)
- [ ] Find the framework: `playwright.config.*`, `package.json` scripts, `tests/` or `e2e/`, `pages/` (page objects), `fixtures/`, `utils/` or `helpers/`, `.env.example`
- [ ] Read **2 or 3 existing specs** in the same feature area and the page objects they use
- [ ] Note the conventions: file naming, `test.describe` structure, tags (`@smoke`, `@regression`, case keys), locator style (`getByRole`, `data-testid`, CSS), assertion style, fixture usage, data builders, reporting (Allure, HTML, Zephyr reporter)
- [ ] Find the **existing login**: a fixture, a storageState setup project, or a login page object. Reuse it. Never write a new login flow.
- [ ] Find the run command for a single spec (e.g. `npx playwright test tests/users/add-user.spec.ts --project=chromium`)

Summarise these findings to the person in 5 to 8 bullets before generating code.

## 2. Source of the scenario
In priority order: the Zephyr case (`zephyr.sh case CASEKEY`), the tester's Excel sheet imported with `qa.sh cases import` (`qa.sh cases show F ID`), the local `.qa/cases/KEY.json`, a recorded walkthrough (`.qa/runs/KEY/<run>/steps.jsonl`), or steps the person types.
For a whole sheet, see [excel-driven.md](excel-driven.md).

## 3. Confirm locators on the live test env
- `qa.sh laneguard URL` → Playwright MCP `browser_navigate` → `browser_snapshot`
- Take role and name from the snapshot (e.g. `getByRole('button', { name: 'Create User' })`). Prefer the order the suite already uses: test ids first, then role, then label or text.
- If a needed element has no stable locator, say so and suggest a `data-testid` for the dev team. Don't use brittle nth-child chains.

## 4. Generate only what's needed
- Add methods to the **existing** page object (e.g. `userManagement.ts`) rather than creating a parallel one
- Add the spec in the existing folder, following the naming pattern. Tag it with the Zephyr case key (`@BWS-T123`) if the suite does that.
- Test data: use the suite's builders or faker setup. Unique emails and names per run (timestamp or faker) so reruns don't collide.
- Assertions: web-first (`await expect(locator).toBeVisible()`), no fixed `waitForTimeout`
- Clean up created data if the suite has a teardown helper

Output **only the new or changed files and methods**, as a diff or by file.

### Skeleton (only if there is no suite at all; ask first)
```
playwright.config.ts   tests/<feature>/<name>.spec.ts   pages/<Feature>Page.ts   fixtures/auth.setup.ts
```
```ts
// pages/UsersPage.ts
import { Page, expect } from '@playwright/test';
export class UsersPage {
  constructor(private page: Page) {}
  async open() { await this.page.getByRole('link', { name: 'Users' }).click(); }
  async expectLoaded() { await expect(this.page.getByText('Manage platform users and permissions')).toBeVisible(); }
}
// tests/users/add-user.spec.ts
import { test } from '@playwright/test';
import { UsersPage } from '../../pages/UsersPage';
test('@BWS-T123 admin creates a user', async ({ page }) => {
  const users = new UsersPage(page);
  await page.goto('/');
  await users.open();
  await users.expectLoaded();
});
```

## 5. Prove it
- [ ] Run the single spec with the suite's command and show the pass or fail output
- [ ] `qa.sh flaky 3 -- <same command>`. It must be 3/3 before you call it done.
- [ ] When fixing a broken test, show the root cause (locator change, timing, data, real defect). **If the app is wrong, it's a bug (§8), not a test fix.**
- [ ] Git commit, push and PR are outside this pack. Leave the changes for the person to review.
