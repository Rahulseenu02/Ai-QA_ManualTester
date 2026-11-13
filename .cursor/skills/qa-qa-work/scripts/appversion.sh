#!/usr/bin/env bash
# appversion.sh — read the app version under test from the app itself, never from memory.
# Order: APP_VERSION_URL (JSON .version/.buildVersion/.appVersion, or plain text, or <meta name="version">)
#        -> APP_VERSION_CMD (any shell command that prints the version)
#        -> fail and tell the agent to ask the tester to read it from the About/footer screen.
# Output: "<version>\t<source>"
set -euo pipefail
. "$(dirname "$0")/_lib.sh"

if [ -n "${APP_VERSION_URL:-}" ]; then
  body="$(curl -sS -L --max-time 15 "$APP_VERSION_URL" || true)"
  v="$(echo "$body" | jq -r '.version // .buildVersion // .appVersion // .build // empty' 2>/dev/null || true)"
  [ -z "$v" ] && v="$(echo "$body" | grep -Eio '<meta[^>]+name="(version|app-version|build)"[^>]*content="[^"]+"' | sed -E 's/.*content="([^"]+)".*/\1/' | head -1 || true)"
  [ -z "$v" ] && [ "$(echo "$body" | wc -l)" -le 2 ] && v="$(echo "$body" | tr -d '\r' | head -1 | cut -c1-60)"
  if [ -n "$v" ]; then printf '%s\t%s\n' "$v" "$APP_VERSION_URL"; exit 0; fi
fi
if [ -n "${APP_VERSION_CMD:-}" ]; then
  v="$(bash -c "$APP_VERSION_CMD" 2>/dev/null | head -1 || true)"
  if [ -n "$v" ]; then printf '%s\t%s\n' "$v" "cmd"; exit 0; fi
fi
echo "UNKNOWN: no version source answered. Ask the tester to read the version from the app (About/footer/settings), or take a snapshot of it with Playwright MCP. Do not guess." >&2
exit 1
