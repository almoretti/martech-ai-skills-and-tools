#!/usr/bin/env bash
# Run a nah developer on another machine through Herdr, so its builds and browser tests use that machine's memory.
#
# The other machine is a Herdr saved machine (`herdr machine list`) that has a clone of the repository and the agent
# CLI signed in. The developer gets its own Herdr worktree and workspace there, a brief folder with PROMPT.md, and
# writes HANDBACK.md into that folder when it is done. The architect is told the Herdr way (`agent wait`), then
# fetches the branch back over ssh and reviews it like any hand-back. The developer never pushes.
#
# Usage:
#   remote-dev.sh start <name> --machine <herdr machine> --ssh <user@host> --repo <clone path on that machine>
#                 --base <local ref> --branch <new branch> --brief <local folder with PROMPT.md>
#                 [--kind claude|codex|pi] [--model id] [--skip-permissions] [--dry-run]
#   remote-dev.sh prompt <name> <text...>        send a follow-up (a correction round) to the same session
#   remote-dev.sh wait <name> [--timeout ms]     block until the developer settles (done, idle or blocked)
#   remote-dev.sh report <name>                  print HANDBACK.md (or the pane's recent output when there is none)
#   remote-dev.sh fetch <name>                   fetch its branch into this clone as <branch>
#   remote-dev.sh close <name>                   end the session and remove its worktree and workspace
#
# Names follow Herdr's agent names: [a-z][a-z0-9_-]{0,31}. State: ~/.local/state/nah/remote/<name>.env.
# --skip-permissions starts Claude with --dangerously-skip-permissions: only when the user chose it for this run.
# Every prompt first answers the agent's own startup and housekeeping questions that would swallow it: Claude Code's
# "trust this folder" (yes: it is our worktree) and its "compact earlier?" offer (Keep auto, the default). Anything
# else blocking is left alone and reported. Wait for "settled", never --until done: a seen agent reports idle.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows would rewrite the remote's /Users/... paths
STATE="${NAH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/nah}/remote"
die() { echo "remote-dev: $*" >&2; exit 1; }
jget() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" | head -1; }
run() { if [[ -n "${DRY:-}" ]]; then printf 'DRY:'; printf ' %q' "$@"; echo; else "$@"; fi; }

cmd="${1:-}"; name="${2:-}"; shift 2 || die "usage: see the header of $0"
[[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "name must match [a-z][a-z0-9_-]{0,31}"
TEXT=; [[ "$cmd" == prompt ]] && { TEXT="$*"; [[ -n "$TEXT" ]] || die "prompt needs the text"; set --; }
MACHINE= SSHH= REPO= BASE= BRANCH= BRIEF= KIND=claude MODEL= SKIP= DRY= TIMEOUT=
while [[ $# -gt 0 ]]; do case "$1" in
  --machine) MACHINE=$2; shift 2;; --ssh) SSHH=$2; shift 2;; --repo) REPO=$2; shift 2;;
  --base) BASE=$2; shift 2;; --branch) BRANCH=$2; shift 2;; --brief) BRIEF=$2; shift 2;;
  --kind) KIND=$2; shift 2;; --model) MODEL=$2; shift 2;; --timeout) TIMEOUT=$2; shift 2;;
  --skip-permissions) SKIP=1; shift;; --dry-run) DRY=1; shift;;
  *) die "unknown option $1";; esac; done
envf="$STATE/$name.env"
load() { [[ -f "$envf" ]] || die "no remote developer named $name ($envf)"; source "$envf"; }
h() { herdr --machine "$MACHINE" "$@"; }
# Answer the known questions that sit in front of the input box (see the header); up to three in a row.
clear_dialogs() {
  local i screen
  for i in 1 2 3; do
    screen=$(h agent read "$name" --source visible --lines 40 2>/dev/null || true)
    if grep -qi "trust this folder" <<<"$screen"; then
      h agent send-keys "$name" down >/dev/null; h agent send-keys "$name" enter >/dev/null
    elif grep -qiE "recommend compacting earlier|/autocompact" <<<"$screen" && grep -qi "Keep auto" <<<"$screen"; then
      h agent send-keys "$name" up >/dev/null; h agent send-keys "$name" enter >/dev/null   # Keep auto: no change
    else
      return 0
    fi
    sleep 2
  done
}
# Prompt and make sure the agent took it: a stalled prompt gets one retry after clearing the questions again.
send() {
  local out
  clear_dialogs
  out=$(h agent prompt "$name" "$1" --wait --timeout 30000 2>&1 || true)
  if grep -qE "agent_prompt_stalled|agent_blocked" <<<"$out"; then
    clear_dialogs
    out=$(h agent prompt "$name" "$1" --wait --timeout 30000 2>&1 || true)
    if grep -qE "agent_prompt_stalled|agent_blocked" <<<"$out"; then
      die "agent $name did not take the prompt; look: herdr --machine $MACHINE agent read $name"
    fi
  fi
  return 0   # a timeout here means it is working
}

case "$cmd" in
start)
  for v in MACHINE SSHH REPO BASE BRANCH BRIEF; do [[ -n "${!v}" ]] || die "start needs --machine, --ssh, --repo, --base, --branch and --brief"; done
  [[ "$MACHINE" != *" "* ]] || die "machine label with spaces: use its id"
  [[ -f "$BRIEF/PROMPT.md" ]] || die "$BRIEF/PROMPT.md is missing (the developer's whole brief, ending with: write HANDBACK.md in this folder and stop)"
  git rev-parse --verify -q "$BASE^{commit}" >/dev/null || die "unknown base $BASE"
  url="ssh://$SSHH/${REPO#/}"; wt="~/nah-wt/$name"; bdir="nah-wt/$name-brief"
  run git push -q "$url" "$(git rev-parse "$BASE"):refs/heads/nah/base-$name"
  run ssh "$SSHH" "mkdir -p ~/nah-wt && rm -rf ~/$bdir"
  run scp -q -r "$BRIEF" "$SSHH:$bdir"
  out=$(run h worktree create --cwd "$REPO" --branch "$BRANCH" --base "nah/base-$name" --path "$wt" \
        --label "nah $name (developer)" --no-focus)
  pane=$(jget pane_id <<<"$out"); ws=$(jget workspace_id <<<"$out")
  [[ -n "$DRY" ]] && { echo "$out"; pane=DRY ws=DRY; }
  [[ -n "$pane" ]] || die "worktree create gave no pane: $out"
  args=(); [[ -n "$MODEL" ]] && args+=(--model "$MODEL")
  [[ -n "$SKIP" && "$KIND" == claude ]] && args+=(--dangerously-skip-permissions)
  run h agent start "$name" --kind "$KIND" --pane "$pane" -- ${args[@]+"${args[@]}"} >/dev/null 2>&1 || true
  [[ -n "$DRY" ]] || clear_dialogs
  [[ -n "$DRY" ]] || h agent wait "$name" --until idle --timeout 60000 >/dev/null || die "agent $name is not ready: herdr --machine $MACHINE agent read $name"
  msg="Read ~/$bdir/PROMPT.md and do exactly what it says, end to end, without stopping to ask: nobody is at this keyboard. When done, write ~/$bdir/HANDBACK.md and stop."
  if [[ -n "$DRY" ]]; then run h agent prompt "$name" "$msg"; else send "$msg"; fi
  mkdir -p "$STATE"
  [[ -n "$DRY" ]] || printf 'MACHINE=%q\nSSHH=%q\nREPO=%q\nBRANCH=%q\nWS=%q\nBDIR=%q\n' "$MACHINE" "$SSHH" "$REPO" "$BRANCH" "$ws" "$bdir" > "$envf"
  echo "started $name on $MACHINE: workspace $ws, worktree $wt, branch $BRANCH, brief ~/$bdir"
  ;;
prompt)
  load; send "$TEXT"; echo "prompted $name; remote-dev.sh wait $name"
  ;;
wait)
  load; t=(); [[ -n "$TIMEOUT" ]] && t=(--timeout "$TIMEOUT")
  h agent wait "$name" ${t[@]+"${t[@]}"} | grep -o '"agent_status":"[a-z]*"' | head -1
  ssh "$SSHH" "test -f ~/$BDIR/HANDBACK.md" && echo "HANDBACK ready: remote-dev.sh report $name" || echo "no HANDBACK.md yet: remote-dev.sh report $name shows the pane"
  ;;
report)
  load; ssh "$SSHH" "cat ~/$BDIR/HANDBACK.md" 2>/dev/null || h agent read "$name" --source recent-unwrapped --lines 200
  ;;
fetch)
  load; git fetch -q "ssh://$SSHH/${REPO#/}" "+$BRANCH:$BRANCH" && git log --oneline -1 "$BRANCH"
  ;;
close)
  load
  h agent send-keys "$name" ctrl+c >/dev/null 2>&1 || true
  h worktree remove --workspace "$WS" --force >/dev/null || die "could not remove workspace $WS on $MACHINE"
  ssh "$SSHH" "git -C '$REPO' branch -D 'nah/base-$name' >/dev/null 2>&1; rm -rf ~/$BDIR" || true
  rm -f "$envf"; echo "closed $name on $MACHINE (branch $BRANCH kept in the remote clone; fetch it first)"
  ;;
*) die "unknown command $cmd (start, prompt, wait, report, fetch, close)";;
esac
