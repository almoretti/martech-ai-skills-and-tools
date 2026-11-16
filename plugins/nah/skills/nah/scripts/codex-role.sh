#!/usr/bin/env bash
# Run one nah role through the OpenAI Codex CLI directly.
#
# Inside Herdr (HERDR_ENV=1): a real Codex SESSION in its own background tab, started and driven through Herdr's agent
# commands and named nah-<role>. The session is kept and reused, so a second call (a re-review of the fixes, a question
# about a finding) goes to the same Codex with its memory of the earlier passes, and the user can talk to it too.
# Clean-up is built in: there is never more than one tab per role in a workspace; every call first closes tabs this
# script opened earlier whose session has ended; --close ends the session and closes its tab.
# Outside Herdr: one headless `codex exec` run, no memory between calls.
#
# Codex may read anywhere and may write only in its own state folder (sandbox workspace-write with that folder as its
# working directory), where it leaves its report. The repository under review is named in the prompt and stays untouched.
# Back-up: when codex is missing, not signed in, or leaves no report, the same role runs through pi (pi-role.sh),
# unless --no-fallback is given.
#
# Usage: codex-role.sh <role> [--model id] [--cwd dir] [--out file] [--timeout secs] [--fresh] [--no-fallback] <task...>
#        echo "task" | codex-role.sh <role>
#        codex-role.sh <role> --close        end the role's session and close its tab (run it when the review cycle ends)
#        codex-role.sh --sweep               close every tab this script opened whose session has ended
# Roles = files in ../roles/<role>.md (system prompt), as for pi-role.sh. ROLES_DIR overrides the folder.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES="${ROLES_DIR:-$HERE/../roles}"
STATE_ROOT="${NAH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/nah}/codex"
TABS="$STATE_ROOT/tabs.list"          # one line per tab this script opened: <workspace> <tab_id> <agent-name>
in_herdr() { [[ "${HERDR_ENV:-}" == 1 ]] && command -v herdr >/dev/null; }
jget() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" | head -1; }
winpath() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
alive() { herdr agent get "$1" >/dev/null 2>&1; }

# Close the tabs of ours whose session is gone (or all of one name when asked), and forget them.
sweep() {  # sweep [name-to-close-even-if-alive]
  [[ -f "$TABS" ]] || return 0
  local keep ws tab nm; keep="$(mktemp)"       # locals: the loop must not overwrite the caller's variables
  while read -r ws tab nm; do
    [[ -n "${tab:-}" && -n "${nm:-}" ]] || continue
    if [[ "$nm" == "${1:-}" ]] || ! alive "$nm" || [[ "$(herdr agent get "$nm" 2>/dev/null | jget tab_id)" != "$tab" ]]; then
      herdr tab close "$tab" >/dev/null 2>&1 || true
    else
      printf '%s %s %s\n' "$ws" "$tab" "$nm" >> "$keep"
    fi
  done < "$TABS"
  mv "$keep" "$TABS"
}

if [[ "${1:-}" == "--sweep" ]]; then in_herdr && sweep; exit 0; fi
role="${1:-}"; shift || true
[[ -z "$role" || ! -f "$ROLES/$role.md" ]] && { echo "usage: codex-role.sh <role> [opts] <task> | <role> --close | --sweep; roles in $ROLES" >&2; exit 2; }
name="nah-$role"; name="${name:0:32}"
model=""; cwd="$PWD"; out=""; timeout="${CODEX_ROLE_TIMEOUT:-2700}"; fallback=1; fresh=""; close=""
while [[ $# -gt 0 ]]; do case "$1" in
  --model) model="$2"; shift 2;; --cwd) cwd="$2"; shift 2;; --out) out="$2"; shift 2;;
  --timeout) timeout="$2"; shift 2;; --fresh) fresh=1; shift;; --close) close=1; shift;;
  --no-fallback) fallback=""; shift;; --keep-tab) shift;; --) shift; break;; *) break;; esac; done
mkdir -p "$STATE_ROOT/$role"; state="$STATE_ROOT/$role"
if [[ -n "$close" ]]; then in_herdr && sweep "$name"; exit 0; fi
if [[ $# -gt 0 ]]; then task="$*"; else task="$(cat)"; fi
[[ "$task" == Task:* ]] || task="Task: $task"

via_pi() {  # the back-up runner; pi picks its model from roles/models.env
  [[ -n "$fallback" ]] || { echo "$1" >&2; exit "${2:-2}"; }
  echo "$1; falling back to pi" >&2
  exec "$HERE/pi-role.sh" "$role" --cwd "$cwd" ${out:+--out "$out"} --timeout "$timeout" "$task"
}
CODEX="${CODEX_BIN:-$(command -v codex || true)}"
[[ -n "$CODEX" ]] || via_pi "codex not found on PATH" 2
"$CODEX" login status >/dev/null 2>&1 || via_pi "AUTH ERROR: codex is not signed in (run \`codex login\`)" 3

stamp="$(date +%Y%m%d-%H%M%S)"; report="$state/report-$stamp.md"; prompt="$state/prompt-$stamp.md"
repo="$(winpath "$cwd")"
rules="The repository to work on is $repo (use it as the directory of every git and file command; do not change anything in it). Write your full report as the file report-$stamp.md in your current working directory, and answer here with one line when it is written. Do not ask questions; if something is unclear, say so in the report."

if in_herdr; then
  sweep "${fresh:+$name}"
  how="herdr session $name"
  if alive "$name"; then                                   # a follow-up: the session remembers the earlier passes
    { printf 'Follow-up in the same review. %s\n\n---\n\n%s\n' "$rules" "$task"; } > "$prompt"
    how="$how, follow-up"
  else
    tab="$(herdr tab create ${HERDR_WORKSPACE_ID:+--workspace "$HERDR_WORKSPACE_ID"} --cwd "$(winpath "$state")" --label "nah $role" --no-focus)"
    pane="$(printf '%s' "$tab" | jget pane_id)"; tabid="$(printf '%s' "$tab" | jget tab_id)"
    [[ -n "$pane" ]] || via_pi "herdr did not return a pane" 2
    printf '%s %s %s\n' "${HERDR_WORKSPACE_ID:-}" "$tabid" "$name" >> "$TABS"
    herdr agent start "$name" --kind codex --pane "$pane" --timeout 90000 -- \
      --sandbox workspace-write --ask-for-approval never ${model:+-m "$model"} >/dev/null 2>&1 \
      || { sweep "$name"; via_pi "codex did not start in herdr" 2; }
    { cat "$ROLES/$role.md"; printf '\n\n---\n\n%s\n\n---\n\n%s\n' "$rules" "$task"; } > "$prompt"
  fi
  rc=0
  herdr agent prompt "$name" "Read the file prompt-$stamp.md in your current working directory and do exactly what it says." \
    --wait --timeout "$((timeout * 1000))" >/dev/null 2>&1 || rc=$?
  st="$(herdr agent get "$name" 2>/dev/null | jget agent_status)"
  [[ "$st" == blocked ]] && echo "codex is waiting for an answer in the herdr tab of $name (status blocked)" >&2
  [[ $rc -ne 0 && ! -s "$report" ]] && echo "codex did not finish within ${timeout}s or the prompt failed; the session $name is left open for inspection" >&2
else
  how="headless"
  { cat "$ROLES/$role.md"; printf '\n\n---\n\n%s\n\n---\n\n%s\n' "$rules" "$task"; } > "$prompt"
  rc=0; ( cd "$state" && timeout "$timeout" "$CODEX" exec --sandbox workspace-write --skip-git-repo-check ${model:+-m "$model"} \
      "Read the file prompt-$stamp.md in your current working directory and do exactly what it says." >"$state/log-$stamp.txt" 2>&1 ) || rc=$?
  [[ $rc -ne 0 ]] && { echo "codex exited $rc" >&2; tail -20 "$state/log-$stamp.txt" >&2; }
fi
[[ -s "$report" ]] || via_pi "codex left no report (exit ${rc:-1})" "${rc:-1}"
# keep the state folder small: the last ten reports and prompts
ls -1t "$state"/report-*.md 2>/dev/null | tail -n +11 | xargs -r rm -f; ls -1t "$state"/prompt-*.md 2>/dev/null | tail -n +11 | xargs -r rm -f
{ echo "<!-- nah role=$role runner=codex ($how) model=${model:-default} cwd=$cwd -->"; cat "$report"; } | tee -a "${out:-/dev/null}"
exit 0
