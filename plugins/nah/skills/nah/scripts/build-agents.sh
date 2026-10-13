#!/usr/bin/env bash
# Regenerate agents/nah-<role>.md from roles/<role>.md: each agent file keeps its own frontmatter (name, model,
# tools, effort); its body is the role prompt, so a role edit reaches both the Claude Code agent and the pi run.
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
for role in developer contrarian oracle diff-summarizer repo-scout; do
  agent="$SRC/agents/nah-$role.md"
  fm=$(awk 'NR==1 && $0=="---" {p=1; print; next} p {print} p && $0=="---" {exit}' "$agent")
  { printf '%s\n' "$fm"; cat "$SRC/roles/$role.md"; } > "$agent.tmp" && mv "$agent.tmp" "$agent"
done
echo "agents rebuilt from roles"
