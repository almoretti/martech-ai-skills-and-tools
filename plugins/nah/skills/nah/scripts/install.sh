#!/usr/bin/env bash
# One-time setup for nah: puts `tk` on PATH and checks the tools the skill shells out to.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${NAH_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN"
ln -sfn "$HERE/tk" "$BIN/tk"
echo "tk -> $BIN/tk"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "NOTE: add $BIN to your PATH";; esac
command -v jq >/dev/null || echo "MISSING: jq (brew install jq) — tk query and migrate need it"
if command -v pi >/dev/null; then
  echo "pi: $(pi --version 2>/dev/null | head -1)"
  pi --no-extensions --list-models 2>/dev/null | grep -q 'openai-codex' || echo "NOTE: no openai-codex models listed; run \`pi\` then \`/login openai-codex\` for the GPT reviewer"
else
  echo "MISSING: pi — npm install -g @earendil-works/pi-coding-agent, then \`pi\` → /login openai-codex"
fi
