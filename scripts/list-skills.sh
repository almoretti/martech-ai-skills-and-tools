#!/usr/bin/env bash
# List every skill in the repo (dirs with a SKILL.md) + the install hint.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

echo "Skills in this marketplace:"
find Skills CLI -name SKILL.md -not -path '*/node_modules/*' 2>/dev/null | sed 's|/SKILL.md||; s|^|  - |' | sort

echo
echo "Install all of them in Claude Code:"
echo "  /plugin marketplace add almoretti/martech-ai-skills-and-tools"
echo "  /plugin install martech-ai-skills@martech-ai"
