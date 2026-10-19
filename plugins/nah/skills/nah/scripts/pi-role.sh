#!/usr/bin/env bash
# Run one nah role headlessly through the standalone `pi` CLI (~/.pi/agent profile), or through
# `claude -p` when the model is claude/<model> (claude/opus, claude/sonnet, a full Claude model id).
# Usage: pi-role.sh <role> [--model provider/id] [--thinking lvl] [--cwd dir] [--out file] [--timeout secs] [--rw] <task...>
#        echo "task" | pi-role.sh <role>            (task on stdin)
# Roles = files in ../roles/<role>.md (system prompt). Defaults from ../roles/models.env, then the
# machine's own overrides from $NAH_MODELS_ENV or ~/.config/nah/models.env (outside the plugin, so
# plugin updates keep them; a machine without the file keeps the shipped defaults).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES="$HERE/../roles"
role="${1:-}"; shift || true
[[ -z "$role" || ! -f "$ROLES/$role.md" ]] && { echo "usage: pi-role.sh <role> [opts] <task>; roles: $(ls "$ROLES" | grep '\.md$' | sed 's/\.md$//' | tr '\n' ' ')" >&2; exit 2; }
# shellcheck disable=SC1091
source "$ROLES/models.env"
local_env="${NAH_MODELS_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/nah/models.env}"
# shellcheck disable=SC1090
[[ -f "$local_env" ]] && source "$local_env"
key="$(echo "$role" | tr 'a-z-' 'A-Z_')"
model="$(eval "echo \${${key}_MODEL:-}")"; thinking="$(eval "echo \${${key}_THINKING:-high}")"
cwd="$PWD"; out=""; tools="read,grep,find,ls,bash"; timeout="${PI_ROLE_TIMEOUT:-900}"
while [[ $# -gt 0 ]]; do case "$1" in
  --model) model="$2"; shift 2;; --thinking) thinking="$2"; shift 2;;
  --cwd) cwd="$2"; shift 2;; --out) out="$2"; shift 2;; --timeout) timeout="$2"; shift 2;;
  --rw) tools="read,write,edit,grep,find,ls,bash"; shift;;
  --) shift; break;; *) break;; esac; done
[[ -z "$model" ]] && { echo "no model for role $role: set ${key}_MODEL in roles/models.env or pass --model" >&2; exit 2; }
if [[ $# -gt 0 ]]; then task="$*"; else task="$(cat)"; fi
[[ "$task" == Task:* ]] || task="Task: $task"
if [[ "$model" == claude/* ]]; then
  RUNNER="${CLAUDE_BIN:-$(command -v claude || true)}"
  [[ -x "$RUNNER" ]] || { echo "claude not found on PATH (model $model)" >&2; exit 2; }
else
  RUNNER="${PI_BIN:-$(command -v pi || true)}"
  [[ -x "$RUNNER" ]] || { echo "pi not found on PATH (expected ~/.local/bin/pi)" >&2; exit 2; }
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$task" > "$tmp/task.md"
sys="$(cat "$ROLES/$role.md")"
[[ -n "${TICKETS_DIR:-}" ]] || export TICKETS_DIR="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")/.tickets"
export PATH="$HERE:$PATH"
set +e
export GIT_PAGER=cat PAGER=cat
if [[ "$model" == claude/* ]]; then
  # Same role prompt and task; read-only unless --rw. pi's off/minimal map to Claude's lowest effort.
  case "$thinking" in off|minimal) effort=low;; *) effort="$thinking";; esac
  deny="Edit Write NotebookEdit"; [[ "$tools" == *write* ]] && deny="NotebookEdit"
  ( cd "$cwd" && "$RUNNER" -p --model "${model#claude/}" --effort "$effort" --no-session-persistence \
    --allowedTools "Read Grep Glob Bash Edit Write" --disallowedTools "$deny" \
    --append-system-prompt "$sys" <"$tmp/task.md" >"$tmp/out" 2>"$tmp/err" ) &
else
  ( cd "$cwd" && "$RUNNER" -p --approve --no-session --no-extensions --no-skills --no-prompt-templates \
    --tools "$tools" --model "$model" --thinking "$thinking" \
    --system-prompt "$sys" "@$tmp/task.md" >"$tmp/out" 2>"$tmp/err" ) &
fi
pid=$!
# The watchdog keeps no handle on stdout: its orphaned sleep would hold a reader of this
# script's output (a pipe, the Bash tool) open until the timeout after the role finished.
( sleep "$timeout"; if kill -0 "$pid" 2>/dev/null; then echo "WATCHDOG: role $role exceeded ${timeout}s; killing the runner and its children" >>"$tmp/err"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; fi ) >/dev/null 2>&1 & wd=$!
wait "$pid"; rc=$?
pkill -P "$wd" 2>/dev/null; kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
result="$(cat "$tmp/out")"
set -e
if [[ "$model" != claude/* ]] && grep -q 'refresh_token_invalidated\|401\|not authenticated\|No credentials' "$tmp/err" 2>/dev/null; then
  echo "AUTH ERROR for provider ${model%%/*}: run \`pi\` then \`/login ${model%%/*}\`, quit, and retry." >&2
fi
[[ $rc -ne 0 ]] && { echo "$(basename "$RUNNER") exited $rc (model $model)" >&2; sed 's/^/  /' "$tmp/err" >&2 | tail -20; }
{ echo "<!-- nah role=$role model=$model thinking=$thinking cwd=$cwd -->"; printf '%s\n' "$result"; } | tee -a "${out:-/dev/null}"
exit $rc
