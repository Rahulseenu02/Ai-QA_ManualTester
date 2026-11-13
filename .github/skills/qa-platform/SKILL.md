---
name: qa-platform
description: Holds thin pointers QA needs about the app under test. That means which test environment URL, which hosts are production (blocked for hand-runs), where the app version is read from, and which automation repo and command run the suite. Used when laneguard or appversion has nothing configured, or when a tester asks "which environment do I test on" or "where is the automation suite".
disable-model-invocation: true
---

# QA platform pointers (thin)

Settings live in `.qa/platform.env`. Template: [platform.example.env](platform.example.env). Scripts: `../qa-qa-work/scripts/`.

## Steps
1. If `.qa/platform.env` is missing, copy the template there.
2. Ask the person, one question at a time:
   1. Test environment URL (staging, QA or dev). That becomes `APP_URL`.
   2. Production hostnames to block. That becomes `PROD_HOSTS` (comma-separated).
   3. Where the app shows its version: `1) A version endpoint (URL)  2) A command  3) Only on screen (I'll ask each time)`. That sets `APP_VERSION_URL` or `APP_VERSION_CMD`.
   4. Automation suite path and the command to run one spec. Those become `AUTOMATION_REPO` and `AUTOMATION_RUN`.
3. Check with `qa.sh appversion` and `qa.sh laneguard`.

## Multiple apps or lines
Keep one block per app in `platform.env` and comment out the others, or keep `platform.<app>.env` files and copy the one in use to `platform.env`. Ask the person which app a ticket belongs to. Never guess from the ticket key.
