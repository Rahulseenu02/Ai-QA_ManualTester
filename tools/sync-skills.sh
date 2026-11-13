#!/usr/bin/env bash
# Copy the QA skill pack from .cursor/skills (source of truth) to the folders other agents read:
#   .github/skills  -> VS Code (GitHub Copilot agent skills)
#   .claude/skills  -> Claude Code
# Re-run after editing anything under .cursor/skills.
set -euo pipefail
cd "$(dirname "$0")/.."
for dest in .github/skills .claude/skills; do
  mkdir -p "$dest"
  for s in .cursor/skills/qa-*; do
    rm -rf "$dest/$(basename "$s")"; cp -R "$s" "$dest/"
  done
  echo "synced -> $dest"
done
