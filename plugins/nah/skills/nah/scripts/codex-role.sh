#!/usr/bin/env bash
# Run one nah role through the OpenAI Codex CLI directly. Inside Herdr (HERDR_ENV=1) the run happens in its own
# background tab, where the user can watch it; outside Herdr it runs headless. Either way Codex is read-only and its last
# message (the report) is written to a file and printed. Back-up: when codex is missing, not signed in, or returns no
# report, the same role runs through pi (pi-role.sh), unless --no-fallback is given.
# Usage: codex-role.sh <role> [--model id] [--cwd dir] [--out file] [--timeout secs] [--keep-tab] [--no-fallback] <task...>
#        echo "task" | codex-role.sh <role>
# Roles = files in ../roles/<role>.md (system prompt), as for pi-role.sh. ROLES_DIR overrides the folder.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES="${ROLES_DIR:-$HERE/../roles}"
role="${1:-}"; shift || true
[[ -z "$role" || ! -f "$ROLES/$role.md" ]] && { echo "usage: codex-role.sh <role> [opts] <task>; roles in $ROLES" >&2; exit 2; }
model=""; cwd="$PWD"; out=""; timeout="${CODEX_ROLE_TIMEOUT:-2700}"; keep=""; fallback=1
while [[ $# -gt 0 ]]; do case "$1" in
  --model) model="$2"; shift 2;; --cwd) cwd="$2"; shift 2;; --out) out="$2"; shift 2;;
  --timeout) timeout="$2"; shift 2;; --keep-tab) keep=1; shift;; --no-fallback) fallback=""; shift;;
  --) shift; break;; *) break;; esac; done
if [[ $# -gt 0 ]]; then task="$*"; else task="$(cat)"; fi
via_pi() {  # the back-up runner; pi picks its model from roles/models.env
  [[ -n "$fallback" ]] || { echo "$1" >&2; exit "${2:-2}"; }
  echo "$1; falling back to pi" >&2
  exec "$HERE/pi-role.sh" "$role" --cwd "$cwd" ${out:+--out "$out"} --timeout "$timeout" "$task"
}
CODEX="${CODEX_BIN:-$(command -v codex || true)}"
[[ -n "$CODEX" ]] || via_pi "codex not found on PATH" 2
"$CODEX" login status >/dev/null 2>&1 || via_pi "AUTH ERROR: codex is not signed in (run \`codex login\`)" 3

work="$(mktemp -d "${TMPDIR:-${TEMP:-.}}/nah-codex.XXXXXX")"; trap 'rm -rf "$work"' EXIT
{ cat "$ROLES/$role.md"; printf '\n\n---\n\n'; [[ "$task" == Task:* ]] || printf 'Task: '; printf '%s\n' "$task"; } > "$work/prompt.md"
report="$work/report.md"
args=(exec --sandbox read-only --skip-git-repo-check -C "$cwd" -o "$report")
[[ -n "$model" ]] && args+=(-m "$model")

if [[ "${HERDR_ENV:-}" == 1 ]] && command -v herdr >/dev/null; then
  # The pane's shell may be PowerShell or bash: hand it one script and call bash by its full path where that exists.
  printf '#!/usr/bin/env bash\n%q' "$CODEX" > "$work/run.sh"; printf ' %q' "${args[@]}" >> "$work/run.sh"
  printf ' - < %q\necho "NAH_CODEX_DONE rc=$?"\n' "$work/prompt.md" >> "$work/run.sh"
  tab="$(herdr tab create ${HERDR_WORKSPACE_ID:+--workspace "$HERDR_WORKSPACE_ID"} --cwd "$cwd" --label "nah $role" --no-focus)"
  pane="$(printf '%s' "$tab" | sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p' | head -1)"
  tabid="$(printf '%s' "$tab" | sed -n 's/.*"tab_id":"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$pane" ]] || { echo "herdr did not return a pane" >&2; exit 2; }
  gitbash="C:/Program Files/Git/bin/bash.exe"
  if [[ -x "$gitbash" ]]; then cmd="& \"$gitbash\" \"$(cygpath -m "$work/run.sh" 2>/dev/null || echo "$work/run.sh")\""; else cmd="bash \"$work/run.sh\""; fi
  herdr pane run "$pane" "$cmd" >/dev/null
  rc=0; herdr pane wait-output "$pane" --match "NAH_CODEX_DONE rc=" --timeout "$((timeout * 1000))" >/dev/null || rc=124
  [[ $rc -eq 124 ]] && echo "WATCHDOG: role $role exceeded ${timeout}s in herdr tab $tabid (left open)" >&2
  [[ -z "$keep" && $rc -eq 0 ]] && herdr tab close "$tabid" >/dev/null 2>&1 || true
else
  rc=0; ( cd "$cwd" && timeout "$timeout" "$CODEX" "${args[@]}" - < "$work/prompt.md" >"$work/log" 2>&1 ) || rc=$?
  [[ $rc -ne 0 ]] && { echo "codex exited $rc" >&2; tail -20 "$work/log" >&2; }
fi
[[ -s "$report" ]] || via_pi "codex wrote no report (exit ${rc:-1})" "${rc:-1}"
{ echo "<!-- nah role=$role runner=codex model=${model:-default} cwd=$cwd -->"; cat "$report"; } | tee -a "${out:-/dev/null}"
exit "$rc"
