# QA-only skill pack (Cursor / VS Code / Claude Code)

A front door for manual testers and QA automation engineers. It has no Dev or PMO workflows. Tester guide: [QA-CHEATSHEET.md](QA-CHEATSHEET.md).

## Skills (source of truth: `.cursor/skills/`)
| Skill | Role | Auto-invoked |
|---|---|---|
| `qa-qa-guide` | front door: guide summary + QA menu, routes named work | yes |
| `qa-qa-work` | runs all QA menu items, including §17 Excel-driven manual and automation runs. Owns `scripts/` and `reference/` | no (read by the guide) |
| `qa-qa-standup` | QA standup | no |
| `qa-config` | Jira and Zephyr tokens + preflight | no |
| `qa-platform` | test URL, prod hosts, version source, suite command | no |

## Install
- **Cursor:** works as is from `.cursor/skills/` and `.cursor/mcp.json`.
- **VS Code (Copilot agent mode):** run `tools/sync-skills.sh` to copy the skills to `.github/skills/`. Turn on agent skills (`chat.useAgentSkills`) and start the playwright server in `.vscode/mcp.json`.
- **Claude Code:** the same sync also writes `.claude/skills/`.
- Requires: `bash`, `curl`, `jq`, `python3`, `node`/`npx`. On Windows, use Git Bash or WSL.

## Scripts (`.cursor/skills/qa-qa-work/scripts/`)
`qa.sh` (router: anchor, drift, laneguard, run, steprun, snap, handresult, submit, cases, coverage, ready, readiness, signoff, standup, retest, dupes, flaky, cnr-draft), `jira.sh`, `zephyr.sh`, `appversion.sh`, `cases.py` (lint, Excel/CSV import and export, results workbook; stdlib only). Every write previews and needs `--yes`.
