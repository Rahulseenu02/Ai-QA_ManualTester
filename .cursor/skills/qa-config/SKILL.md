---
name: qa-config
description: Sets up and checks QA tool access, meaning the Jira API token, Zephyr Scale token, project keys and status names in .qa/config.env, then runs preflight. Used when qa.sh preflight reports missing config, or when a tester says "set up QA", "configure Jira", "Zephyr token", or "preflight".
disable-model-invocation: true
---

# QA config (thin)

Scripts: `../qa-qa-work/scripts/` (`$QA`). Template: [config.example.env](config.example.env).

## Steps
1. Run `$QA/qa.sh preflight` and show which items are missing.
2. If `.qa/config.env` doesn't exist, copy `config.example.env` to `.qa/config.env`. Check that `.qa/` is in `.gitignore`.
3. **Tokens are never typed into chat.** Tell the person:
   - Jira API token: create it at https://id.atlassian.com/manage-profile/security/api-tokens
   - Zephyr Scale token: in Jira, open Zephyr (top bar), then your profile, then **Zephyr API keys**
   - Then **open `.qa/config.env` in the editor and paste them there yourself.** Don't paste tokens in this chat.
4. You (the agent) can fill in the non-secret values once the person tells you them: `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_PROJECT`, `ZEPHYR_PROJECT_KEY`, status names, and `JIRA_AC_FIELD`. Ask as numbered options where you can (e.g. statuses fetched from `jira.sh transitions KEY`).
5. Re-run `qa.sh preflight` until Jira is green. Zephyr is optional when the team uses Excel only.
6. If the person wants app settings (test URL, version source), go to `../qa-platform/SKILL.md`.

## Never
- Echo, log or commit tokens
- Store tokens anywhere except `.qa/config.env`
