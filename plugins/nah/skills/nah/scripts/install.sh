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
LAVISH_VERSION=0.1.93   # the approval board's page CLI, pinned; bump and rerun to upgrade
LAVISH="$HOME/.local/share/nah/lavish"   # a local path install: no global npm, no npx fetch on every call
grep -qs "\"version\": \"$LAVISH_VERSION\"" "$LAVISH/node_modules/lavish-axi/package.json" ||
  npm install --silent --prefix "$LAVISH" "lavish-axi@$LAVISH_VERSION" >/dev/null ||
  echo "MISSING: lavish-axi (npm install --prefix $LAVISH lavish-axi@$LAVISH_VERSION failed) — the approval board needs it"
if [[ -x "$LAVISH/node_modules/.bin/lavish-axi" ]]; then
  rm -f "$BIN/lavish-axi"   # an older install left a symlink here; writing through it would overwrite lavish itself
  # A wrapper, not a link: loopback only, so the board never opens on a Tailscale or LAN URL
  printf '#!/bin/sh\nexport LAVISH_AXI_HOST="${LAVISH_AXI_HOST:-127.0.0.1}"\nexec "%s" "$@"\n' \
    "$LAVISH/node_modules/.bin/lavish-axi" > "$BIN/lavish-axi"
  chmod +x "$BIN/lavish-axi"; echo "lavish-axi -> $BIN/lavish-axi (loopback only)"
fi
grep -qs "\"ponytail@" ~/.claude/plugins/installed_plugins.json || echo "MISSING: ponytail plugin (/plugin marketplace add DietrichGebert/ponytail, then /plugin install ponytail@ponytail) — the lean pass runs its ponytail-review"
if command -v pi >/dev/null; then
  echo "pi: $(pi --version 2>/dev/null | head -1)"
  pi --no-extensions --list-models 2>/dev/null | grep -q 'openai-codex' || echo "NOTE: no openai-codex models listed; run \`pi\` then \`/login openai-codex\` for the GPT reviewer"
else
  echo "MISSING: pi — npm install -g @earendil-works/pi-coding-agent, then \`pi\` → /login openai-codex"
fi
