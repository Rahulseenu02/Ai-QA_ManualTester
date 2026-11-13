#!/usr/bin/env bash
# Shared helpers for the QA-only skill pack. Sourced by qa.sh, jira.sh, zephyr.sh, appversion.sh.
# Bash 3.2 compatible (macOS default). Needs: curl, jq. Windows: run from Git Bash or WSL.

QA_DIR="${QA_DIR:-$PWD/.qa}"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f "$QA_DIR/config.env" ]   && . "$QA_DIR/config.env"
[ -f "$QA_DIR/platform.env" ] && . "$QA_DIR/platform.env"

JIRA_BASE_URL="${JIRA_BASE_URL%/}"
ZEPHYR_BASE_URL="${ZEPHYR_BASE_URL:-https://api.zephyrscale.smartbear.com/v2}"
QA_RETEST_STATUSES="${QA_RETEST_STATUSES:-\"Ready for Retest\",\"Resolved\",\"Ready for QA\"}"
QA_READY_STATUSES="${QA_READY_STATUSES:-\"Ready for QA\",\"In QA\",\"Ready for Test\"}"

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }
need() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing tool: $c"; done; }
need curl jq

# --yes gate. Every write calls this. Without --yes we print the preview and stop (exit 2).
# The agent may only add --yes after the person typed an explicit yes in chat. Silence is not approval.
has_yes() { for a in "$@"; do [ "$a" = "--yes" ] && return 0; done; return 1; }
strip_yes() { for a in "$@"; do [ "$a" = "--yes" ] || printf '%s\n' "$a"; done; }
gate() { # gate "<what>" "$@"
  local what="$1"; shift
  if has_yes "$@"; then return 0; fi
  echo
  echo "---- PREVIEW ONLY: nothing was written ----"
  echo "Write pending: $what"
  echo "Ask the person: 1) Yes, do it  2) Change something  3) Cancel"
  echo "Re-run the same command with --yes only after they answer 1."
  exit 2
}
zephyr_nodelete_notice() {
  echo "NOTE: Zephyr cannot delete test cases, cycles or results through this pack. Anything created stays."
}

need_jira()   { [ -n "$JIRA_BASE_URL" ] && [ -n "$JIRA_EMAIL" ] && [ -n "$JIRA_API_TOKEN" ] || die "Jira not configured. Run the qa-config skill (needs JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN in $QA_DIR/config.env)."; }
need_zephyr() { [ -n "$ZEPHYR_TOKEN" ] && [ -n "$ZEPHYR_PROJECT_KEY" ] || die "Zephyr not configured. Run the qa-config skill (needs ZEPHYR_TOKEN, ZEPHYR_PROJECT_KEY)."; }

# http METHOD URL [json-body|@file]  -> body on stdout, non-2xx = error
_http() {
  local auth="$1" method="$2" url="$3" body="$4" out code
  out="$(mktemp)"
  if [ -n "$body" ]; then
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" $auth -H 'Accept: application/json' -H 'Content-Type: application/json' --data "$body" "$url")
  else
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" $auth -H 'Accept: application/json' "$url")
  fi
  if [ "${code:0:1}" != "2" ]; then echo "HTTP $code $method $url" >&2; cat "$out" >&2; echo >&2; rm -f "$out"; return 1; fi
  cat "$out"; rm -f "$out"
}
jira_http()   { need_jira; _http "-u $JIRA_EMAIL:$JIRA_API_TOKEN" "$@"; }
# Bearer header contains a space, so it gets its own curl call rather than going through _http.
zephyr_http() {
  need_zephyr
  local method="$1" url="$2" body="$3" out code
  out="$(mktemp)"
  if [ -n "$body" ]; then
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $ZEPHYR_TOKEN" -H 'Accept: application/json' -H 'Content-Type: application/json' --data "$body" "$url")
  else
    code=$(curl -sS -o "$out" -w '%{http_code}' -X "$method" -H "Authorization: Bearer $ZEPHYR_TOKEN" -H 'Accept: application/json' "$url")
  fi
  if [ "${code:0:1}" != "2" ]; then echo "HTTP $code $method $url" >&2; cat "$out" >&2; echo >&2; rm -f "$out"; return 1; fi
  cat "$out"; rm -f "$out"
}

urlenc() { jq -rn --arg s "$1" '$s|@uri'; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
yesterday() { date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d yesterday +%Y-%m-%d; }

valid_key() { echo "$1" | grep -Eq '^[A-Z][A-Z0-9_]+-[0-9]+$'; }

# Anchor file: KEY|updated|status|summary|anchored_at
anchor_file() { echo "$QA_DIR/anchor"; }
anchor_key()  { [ -f "$(anchor_file)" ] && cut -d'|' -f1 "$(anchor_file)"; }
