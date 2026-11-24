#!/usr/bin/env bash
# Run a nah developer on another machine through Herdr, so its builds and browser tests use that machine's memory.
#
# The other machine is a Herdr saved machine (`herdr machine list`) that has a clone of the repository and the agent
# CLI signed in. The developer gets its own Herdr worktree and workspace there, a brief folder with PROMPT.md, and
# writes HANDBACK.md into that folder when it is done. The architect is told the Herdr way (`agent wait`), then
# fetches the branch back over ssh and reviews it like any hand-back. The developer never pushes.
#
# Usage:
#   remote-dev.sh doctor --machine <herdr machine> --ssh <user@host> --repo <clone path there> [--back <machine>]
#                 checks that machine's prerequisites, read-only, one line each (ok / warn / MISSING: what to do);
#                 exit 0 only when nothing is MISSING. Run it before the first start on a machine. --back <name> also
#                 checks the Herdr saved machine on that side that leads back here, when the project uses one.
#   remote-dev.sh start <name> --machine <herdr machine> --ssh <user@host> --repo <clone path on that machine>
#                 --base <local ref> --branch <new branch> (--ticket <tk id> [--notes <file>] | --brief <folder>)
#                 [--kind claude|codex|pi] [--agent name] [--model id] [--skip-permissions] [--dry-run]
#
# --ticket is the normal way: the developer is the same nah developer as a local dispatch (Claude Code started with
# --agent nah:nah-developer, so the plugin must be installed on that machine) and gets the same one-line dispatch:
# "Implement tk ticket <id>". The ticket, its parent and its dependencies are copied from this clone's TICKETS_DIR
# (default .tickets) into the brief folder, and TICKETS_DIR points there, so `tk show <id>` works on that machine
# even when the tickets are not on the base branch. --notes adds ticket-specific validation notes, as a local
# dispatch would. --brief <folder with PROMPT.md> remains for work that is not a ticket.
# start first runs the cheap part of doctor (ssh, the clone, the nah plugin when it starts a nah agent, the name, the
# worktree path, the brief folder and the branch still free) and creates nothing when one is MISSING. When a later
# step fails, Ctrl-C included, it removes what this run created and only that (the workspace, the worktree, the branch
# while it has no commits beyond the base, the pushed base ref, the brief, the state file) and exits non-zero. It checks that the pane sits in the worktree before it
# starts the agent there.
#   remote-dev.sh status [name...] [--placeholder <text>] [--json]
#                 every open developer (or the named ones), one line each, hand-backs first: machine, agent state
#                 (working / idle / blocked / done, or gone), HANDBACK.md time and checksum, READY when it ends with
#                 HANDBACK-READY, NEW when it changed since the last status, and "placeholder left" when it still
#                 holds the project's template marker (--placeholder or NAH_HANDBACK_PLACEHOLDER). The plain form
#                 marks what it showed as seen; --json never does, so a monitoring script does not hide a new
#                 hand-back from the next plain status. A dead machine costs a timeout and reads "unreachable".
#                 Always exits 0.
#   remote-dev.sh prompt <name> <text...>        send a follow-up (a correction round) to the same session
#   remote-dev.sh wait <name> [--timeout ms]     block until the developer settles (done, idle or blocked)
#   remote-dev.sh report <name>                  print HANDBACK.md (or the pane's recent output when there is none)
#   remote-dev.sh fetch <name>                   fetch its branch into this clone as <branch>
#   remote-dev.sh close <name>                   end the session and remove its worktree and workspace
#
# Names follow Herdr's agent names: [a-z][a-z0-9_-]{0,31}. State: ~/.local/state/nah/remote/<name>.env.
# --skip-permissions starts Claude with --dangerously-skip-permissions: only when the user chose it for this run.
# The one prompt the script answers: at start only, Claude Code's folder-trust dialog for the worktree that start has
# just created and checked the pane is in, by sending Down and Enter ("Yes, I trust this folder"). Every other dialog,
# trust or permission prompt is left to the user: prompt stops and prints what is on screen. Wait for "settled",
# never --until done: a seen agent reports idle.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows would rewrite the remote's /Users/... paths
STATE="${NAH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/nah}/remote"
die() { echo "remote-dev: $*" >&2; exit 1; }
jget() { sed -n "s/.*\"$1\":\"\\([^\"]*\\)\".*/\\1/p" | head -1; }
run() { if [[ -n "${DRY:-}" ]]; then printf 'DRY:'; printf ' %q' "$@"; echo; else "$@"; fi; }

cmd="${1:-}"; shift || die "usage: see the header of $0"
name= NAMES=()
case "$cmd" in
  doctor) ;;
  status) while [[ $# -gt 0 && "$1" != --* ]]; do NAMES+=("$1"); shift; done;;
  *) name="${1:-}"; shift || die "usage: see the header of $0"
     [[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "name must match [a-z][a-z0-9_-]{0,31}";;
esac
TEXT=; [[ "$cmd" == prompt ]] && { TEXT="$*"; [[ -n "$TEXT" ]] || die "prompt needs the text"; set --; }
MACHINE= SSHH= REPO= BASE= BRANCH= BRIEF= KIND=claude MODEL= SKIP= DRY= TIMEOUT= TICKET= NOTES= AGENT= BACK= JSON=
PLACEHOLDER="${NAH_HANDBACK_PLACEHOLDER:-}"
while [[ $# -gt 0 ]]; do case "$1" in
  --machine) MACHINE=$2; shift 2;; --ssh) SSHH=$2; shift 2;; --repo) REPO=$2; shift 2;;
  --base) BASE=$2; shift 2;; --branch) BRANCH=$2; shift 2;; --brief) BRIEF=$2; shift 2;;
  --kind) KIND=$2; shift 2;; --model) MODEL=$2; shift 2;; --timeout) TIMEOUT=$2; shift 2;;
  --ticket) TICKET=$2; shift 2;; --notes) NOTES=$2; shift 2;; --agent) AGENT=$2; shift 2;;
  --back) BACK=$2; shift 2;; --placeholder) PLACEHOLDER=$2; shift 2;; --json) JSON=1; shift;;
  --skip-permissions) SKIP=1; shift;; --dry-run) DRY=1; shift;;
  *) die "unknown option $1";; esac; done
envf="$STATE/$name.env"
load() { [[ -f "$envf" ]] || die "no remote developer named $name ($envf)"; source "$envf"; }
h() { herdr --machine "$MACHINE" "$@"; }
# The report's state: its checksum when it ends with HANDBACK-READY, else 0. A new report (appended or rewritten) changes it.
ready_count() { ssh "$SSHH" "f=~/$BDIR/HANDBACK.md; tail -n1 \$f 2>/dev/null | grep -q '^HANDBACK-READY' && cksum < \$f | cut -d' ' -f1 || echo 0" 2>/dev/null | tail -1; }
screen() { h agent read "$name" --source visible --lines 40 2>/dev/null || true; }
# Claude Code's folder-trust dialog, matched by its own option lines: "No, exit" (or "No, continue without these
# permissions") first, with the cursor on it, and "Yes, I trust this folder" second (read in Claude Code 2.1.331).
trust_dialog() { grep -q "Yes, I trust this folder" <<<"$1" && grep -qE "No, exit|No, continue without these permissions" <<<"$1"; }
# Called by start only, after it checked that the pane is in the worktree this start created: answers that one
# dialog with Down (cursor from "No, exit" to "Yes, I trust this folder") then Enter. Nothing else is ever answered.
answer_trust() {
  local i s
  for i in 1 2 3 4 5; do
    s=$(screen); trust_dialog "$s" || return 0
    sleep 1   # the dialog ignores keys for a moment after it opens
    h agent send-keys "$name" down >/dev/null; h agent send-keys "$name" enter >/dev/null; sleep 2
  done
  die "the folder-trust dialog of $name did not close; look: herdr --machine $MACHINE agent read $name"
}
# Prompt and make sure the agent took it. A dialog in front of the input box is never answered here: say what is on
# screen and stop, for the architect (or the user) to read.
send() {
  local out
  out=$(h agent prompt "$name" "$1" --wait --timeout 30000 2>&1 || true)
  if grep -qE "agent_prompt_stalled|agent_blocked" <<<"$out"; then
    echo "remote-dev: $name did not take the prompt; on its screen:" >&2
    screen | grep -v '^[[:space:]]*$' | tail -n 15 >&2
    die "nothing was answered; look: herdr --machine $MACHINE agent read $name"
  fi
  return 0   # a timeout here means it is working
}
SSHO=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2)   # never wait on a prompt or a dead link
# Run "$@" for at most $1 seconds (macOS has no timeout(1)); its exit code, or non-zero when it was killed.
tmo() {
  local s=$1 p k rc=0; shift
  "$@" & p=$!
  ( sleep "$s"; kill "$p" 2>/dev/null ) >/dev/null 2>&1 & k=$!
  wait "$p" || rc=$?
  kill "$k" 2>/dev/null || true
  return $rc
}
# The plugins the developer needs in Claude Code on that machine: nah and the dependencies in its plugin.json.
plugin_ids() {
  local pj; pj="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/.claude-plugin/plugin.json"
  echo nah; sed -n '/"dependencies"/,/]/p' "$pj" 2>/dev/null | grep -o '"[^"]*@[^"]*"' | tr -d '"'
}
# Prerequisite checks, one line each: "ok: ...", "warn: ..." or "MISSING: ...: what to do"; plus "home: <dir>".
# $1 = full (doctor) or quick (start's subset). Read-only: nothing is installed, started or created.
checks() {
  local mode=$1 plug=${2:-1} out
  if ! command -v herdr >/dev/null; then echo "MISSING: herdr on this machine: install it (herdr.dev)"
  elif [[ "$(herdr machine status "$MACHINE" 2>/dev/null | awk '{print $3}' | head -1)" == reachable ]]; then
    echo "ok: herdr machine $MACHINE reachable"
    if [[ "$mode" == full ]]; then
      local s; s=$(herdr --machine "$MACHINE" status server 2>&1 || true)
      if grep -q 'endpoint_compatible: yes' <<<"$s" && grep -q 'private_protocol_compatible: yes' <<<"$s"; then
        echo "ok: herdr server there $(sed -n 's/^version: //p' <<<"$s"), compatible with $(herdr --version 2>/dev/null)"
      else echo "MISSING: a herdr server there compatible with this client: update herdr on both machines (herdr status there)"; fi
    fi
  else echo "MISSING: herdr machine $MACHINE reachable: check herdr machine list / status (herdr machine reconnect is for the user)"; fi
  if ! ssh "${SSHO[@]}" "$SSHH" true 2>/dev/null; then
    echo "MISSING: ssh $SSHH without a prompt: set up key login (and accept the host key once by hand)"; return 0
  fi
  echo "ok: ssh $SSHH"; out=$(mktemp)
  # Run in an interactive login shell there: the PATH a Herdr pane gets (node managers live in the rc files).
  { printf 'REPO=%q MODE=%q PLUG=%q BACK=%q WT=%q BRANCH=%q\n' "$REPO" "$mode" "$plug" "$BACK" \
      "${name:+nah-wt/$name}" "$BRANCH"
    printf 'IDS=%q\n' "$(plugin_ids | tr '\n' ' ')"
    cat <<'EOF'
ok() { echo "ok: $*"; }; miss() { echo "MISSING: $*"; }; warn() { echo "warn: $*"; }
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then ok "clone $REPO"
else miss "clone $REPO: clone the repository there (an absolute path)"; fi
if [ -n "$WT" ]; then
  [ -e "$HOME/$WT" ] && miss "~/$WT already exists: close that developer first (remote-dev.sh close) or pick another name"
  [ -e "$HOME/$WT-brief" ] && miss "~/$WT-brief already exists: close that developer first (remote-dev.sh close) or pick another name"
  git -C "$REPO" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 && miss "branch $BRANCH already exists in the clone there: pick another branch name"
fi
if [ "$MODE" = full ]; then
  if command -v git >/dev/null; then ok "$(git --version)"; else miss "git: install it"; fi
  if command -v node >/dev/null; then
    need=$(node -p '((require(process.argv[1]).engines||{}).node)||""' "$REPO/package.json" 2>/dev/null)
    # ponytail: the first version in the range is the minimum (fits ">=x.y.z"); a range with an upper bound is not read
    if node -e 'const w=(process.argv[1].match(/\d+(\.\d+)*/)||[""])[0].split(".").map(Number),h=process.versions.node.split(".").map(Number);for(let i=0;i<3;i++){if((h[i]||0)!==(w[i]||0))process.exit((h[i]||0)>(w[i]||0)?0:1)}' "$need"
    then ok "node $(node --version)${need:+ (the repository asks $need)}"
    else miss "node $need (found $(node --version)): install it there"; fi
    pm=$(node -p 'require(process.argv[1]).packageManager||""' "$REPO/package.json" 2>/dev/null); want=${pm#*@}; want=${want%%+*}
    if [ -n "$pm" ]; then
      have=$(cd "$REPO" 2>/dev/null && COREPACK_ENABLE_NETWORK=0 "${pm%%@*}" --version 2>/dev/null | tail -1)
      if [ "$have" = "$want" ]; then ok "${pm%%@*} $have"
      else miss "${pm%%@*} $want, as packageManager asks (found ${have:-none}): install it there"; fi
    fi
  else miss "node: install it there (the version the repository's package.json engines ask)"; fi
fi
if ! command -v claude >/dev/null; then miss "claude (Claude Code): install it there and sign in"
else
  [ "$MODE" = full ] && ok "claude $(claude --version 2>/dev/null | head -1)"
  if [ "$PLUG" = 1 ]; then
    if command -v node >/dev/null; then
      list=$(cd "$REPO" 2>/dev/null; claude plugin list --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{for(const p of JSON.parse(s))if(p.enabled)console.log(p.id)}catch(e){}})')
      for id in $IDS; do
        case "$id" in *@*) pat="^$id\$";; *) pat="^$id@";; esac
        if echo "$list" | grep -q "$pat"; then ok "plugin $(echo "$list" | grep "$pat" | head -1) enabled in Claude Code"
        else miss "plugin $id installed and enabled in Claude Code there: /plugin install it (its marketplace first), then check claude plugin list"; fi
      done
    else miss "the Claude Code plugins cannot be checked without node"; fi
    # an installed plugin that does not load still reads enabled in the JSON: the text form says so on its Status line
    (cd "$REPO" 2>/dev/null; claude plugin list 2>/dev/null) | awk 'NF==2 && $2 ~ /@/ {id=$2}
      tolower($0) ~ /failed to load/ {l=$0; n=""; getline n; sub(/^[ \t]+/, "", l); sub(/^[ \t]+/, "", n)
        print "MISSING: plugin " id " loads in Claude Code there (" l ((n != "" && n !~ /^[^ ]+ [^ ]+@[^ ]+$/) ? " / " n : "") "): fix or reinstall it"}'
  fi
fi
if [ "$MODE" = full ]; then
  if t=$(command -v tk); then
    if [ ! -x "$t" ]; then miss "tk executable ($t): chmod +x it"
    elif head -1 "$t" | od -c | grep -q '\\r'; then miss "tk without CRLF line endings ($t fails with 'env: bash\\r'): strip them (tr -d '\\r'), or link it with the nah plugin's scripts/install.sh"
    else ok "tk $t"; fi
  else miss "tk on PATH: run the nah plugin's scripts/install.sh there"; fi
  kb=$(df -Pk "$HOME" | awk 'NR==2{print $4}')
  gb=$(awk -v k="$kb" 'BEGIN{printf "%.1f", k/1048576}')
  if [ "${kb:-0}" -ge 10485760 ]; then ok "disk $gb GB free"; else warn "disk $gb GB free (under 10 GB): builds may fail"; fi
  if [ -r /proc/meminfo ]; then mk=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  else mk=$(vm_stat 2>/dev/null | awk '/page size of/{p=$8} /^Pages (free|inactive|speculative)/{n+=$NF} END{printf "%d", n*p/1024}'); fi
  mg=$(awk -v k="${mk:-0}" 'BEGIN{printf "%.1f", k/1048576}')
  if [ "${mk:-0}" -ge 1572864 ]; then ok "memory $mg GB available"; else warn "memory $mg GB available (under 1.5 GB): wait or free some before a start"; fi
  if [ -n "$BACK" ]; then
    if command -v herdr >/dev/null && [ "$(herdr machine status "$BACK" 2>/dev/null | awk '{print $3}' | head -1)" = reachable ]
    then ok "link back: herdr machine $BACK reachable from there"
    else miss "link back: herdr machine $BACK reachable from there (herdr machine list there; the user reconnects it)"; fi
  fi
fi
echo "home: $HOME"   # last: its absence means the checks did not run to the end
EOF
  } | ssh "${SSHO[@]}" "$SSHH" 'exec "$SHELL" -lic "bash -s"' 2>/dev/null | grep -E '^(ok|warn|MISSING|home):' > "$out" || true
  cat "$out"
  grep -q '^home: /' "$out" || echo "MISSING: the checks on $SSHH did not run to the end (its login shell gave no result): run bash there by hand"
  rm -f "$out"
}
fmt_time() { date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$1" '+%Y-%m-%d %H:%M'; }
# One developer's status, as "<rank>\t<name>\t<line>"; rank 0 = a new hand-back. Records the checksum it saw.
status_one() (
  n=$1 f="$STATE/$1.env"
  [[ -f "$f" ]] || { printf '9\t%s\t%s\n' "$n" "$([[ -n "$JSON" ]] && printf '{"name":"%s","open":false}' "$n" || echo "$n: not open")"; exit 0; }
  source "$f"
  tmp=$(mktemp); rc=0
  # one dead machine must not hang the command: every call has a time limit
  # (into a file, not a pipe: a killed call's leftover children must not hold the read open)
  tmo 15 herdr machine status "$MACHINE" > "$tmp" 2>/dev/null || true
  if [[ "$(awk '{print $3}' "$tmp" | head -1)" == reachable ]]; then
    tmo 15 herdr --machine "$MACHINE" agent get "$n" > "$tmp" 2>/dev/null || true
    st=$(jget agent_status < "$tmp"); st=${st:-gone}
  else st=unreachable; fi
  tmo 20 ssh "${SSHO[@]}" "$SSHH" "f=~/$BDIR/HANDBACK.md; [ -f \$f ] || exit 3; stat -c %Y \$f 2>/dev/null || stat -f %m \$f; cat \$f" > "$tmp" 2>/dev/null || rc=$?
  hb=none mt=null ck=null ready=false new=false ph=false
  if [[ $rc == 0 ]]; then
    hb=present mt=$(head -1 "$tmp"); ck=$(tail -n +2 "$tmp" | cksum | cut -d' ' -f1)
    tail -n +2 "$tmp" | tail -n 1 | grep -q '^HANDBACK-READY' && ready=true
    [[ -n "$PLACEHOLDER" ]] && tail -n +2 "$tmp" | grep -qF -- "$PLACEHOLDER" && ph=true
    if [[ "$ck" != "${SEEN:-}" ]]; then
      new=true   # only the plain form marks it seen: --json is for scripts and must not hide it from the next look
      [[ -n "$JSON" ]] || { sed -i.bak '/^SEEN=/d' "$f" && rm -f "$f.bak"; echo "SEEN=$ck" >> "$f"; }
    fi
  elif [[ $rc != 3 ]]; then hb=unreachable; fi
  rm -f "$tmp"
  rank=4; [[ $hb == present ]] && rank=3; [[ $new == true ]] && rank=2; [[ $ready == true ]] && rank=1; [[ $ready == true && $new == true ]] && rank=0
  if [[ -n "$JSON" ]]; then
    line=$(printf '{"name":"%s","open":true,"machine":"%s","agent":"%s","handback":"%s","mtime":%s,"cksum":%s,"ready":%s,"new":%s,"placeholder":%s}' \
      "$n" "$MACHINE" "$st" "$hb" "$mt" "$ck" "$ready" "$new" "$ph")
  else
    case $hb in
      present) line="HANDBACK.md $(fmt_time "$mt") cksum $ck$([[ $ready == true ]] && echo " READY")$([[ $new == true ]] && echo " NEW since last status")$([[ $ph == true ]] && echo " placeholder left")";;
      none) line="no HANDBACK.md yet";;
      *) line="HANDBACK.md unknown: $SSHH unreachable";;
    esac
    line=$(printf '%-14s %-10s agent=%-8s %s' "$n" "$MACHINE" "$st" "$line")
  fi
  printf '%s\t%s\t%s\n' "$rank" "$n" "$line"
)

case "$cmd" in
start)
  for v in MACHINE SSHH REPO BASE BRANCH; do [[ -n "${!v}" ]] || die "start needs --machine, --ssh, --repo, --base and --branch"; done
  [[ -n "$TICKET" || -n "$BRIEF" ]] || die "start needs --ticket <id> (or --brief <folder> for work that is not a ticket)"
  [[ "$MACHINE" != *" "* ]] || die "machine label with spaces: use its id"
  [[ "$REPO" == /* ]] || die "--repo must be an absolute path on that machine"
  [[ "$name" != *-brief ]] || die "a name may not end in -brief (that is where another developer's brief goes)"
  [[ ! -f "$envf" ]] || die "$name is already open ($envf): close it first, or pick another name"
  git rev-parse --verify -q "$BASE^{commit}" >/dev/null || die "unknown base $BASE in this clone (a local branch or commit)"
  bdir="nah-wt/$name-brief" TMPBRIEF= ws= MADE_BASE= MADE_BRIEF= MADE_WT= MADE_ENV=
  # A failed start removes what THIS run created, and only that: each MADE_ flag is set right after its create
  # succeeded, never because a path or name matches. A removal that fails is said, never hidden.
  cleanup() {
    local rc=$? keep= r=
    [[ -n "$TMPBRIEF" ]] && rm -rf "$TMPBRIEF"
    [[ $rc == 0 || -n "$DRY" ]] && return 0
    [[ -n "$MADE_BASE$MADE_BRIEF$ws$MADE_WT$MADE_ENV" ]] || return 0
    echo "remote-dev: start failed; removing what it created on $MACHINE" >&2
    if [[ -n "$ws" ]]; then
      h agent send-keys "$name" ctrl+c >/dev/null 2>&1 || true
      h worktree remove --workspace "$ws" --force >/dev/null 2>&1 || { keep=1; echo "remote-dev: could not remove workspace $ws: remote-dev.sh close $name" >&2; }
    fi
    [[ -n "$MADE_WT" ]] && r+="w=~/nah-wt/$name; [ -e \$w ] && { git worktree remove --force \$w 2>/dev/null || rm -rf \$w; git worktree prune; }
      [ \"\$(git rev-list --count 'nah/base-$name..$BRANCH' 2>/dev/null)\" = 0 ] && git branch -D '$BRANCH' >/dev/null
      "
    [[ -n "$MADE_BASE" ]] && r+="git branch -D 'nah/base-$name' >/dev/null 2>&1; "
    [[ -n "$MADE_BRIEF" ]] && r+="rm -rf ~/$bdir; "
    [[ -z "$r" ]] || ssh "${SSHO[@]}" "$SSHH" "cd '$REPO' || exit 1; $r true" ||
      echo "remote-dev: could not clean the clone on $MACHINE: check ~/nah-wt/$name, branch $BRANCH, nah/base-$name, ~/$bdir" >&2
    if [[ -z "$MADE_WT" ]] && ssh "${SSHO[@]}" "$SSHH" "[ -e ~/nah-wt/$name ]" 2>/dev/null; then
      echo "remote-dev: ~/nah-wt/$name exists but this start did not make it: left alone" >&2
    fi
    [[ -n "$keep" || -z "$MADE_ENV" ]] || rm -f "$envf"
  }
  trap cleanup EXIT
  trap 'exit 130' INT TERM   # Git Bash runs the EXIT trap with $?=0 after a signal: make it a failure
  plug=0; [[ "$KIND" == claude && ( -n "$TICKET" && -z "$AGENT" || "$AGENT" == nah:* ) ]] && plug=1
  pre=$(checks quick "$plug")
  if grep -q '^MISSING' <<<"$pre"; then
    grep '^MISSING' <<<"$pre" >&2; die "start stopped before creating anything on $MACHINE (remote-dev.sh doctor checks everything)"
  fi
  rhome=$(sed -n 's/^home: //p' <<<"$pre")
  if [[ -n "$TICKET" ]]; then
    TD="${TICKETS_DIR:-.tickets}"; [[ -f "$TD/$TICKET.md" ]] || die "no ticket $TD/$TICKET.md (set TICKETS_DIR)"
    BRIEF="$(mktemp -d)"; TMPBRIEF=$BRIEF; mkdir -p "$BRIEF/tickets"
    # the ticket, its parent and its dependencies, so tk show prints the same as here
    for id in "$TICKET" $(sed -n -e 's/^parent: *//p' -e 's/^deps: *\[\(.*\)\]/\1/p' "$TD/$TICKET.md" | tr ',' ' '); do
      [[ -f "$TD/$id.md" ]] && cp "$TD/$id.md" "$BRIEF/tickets/"
    done
    {
      echo "Implement tk ticket $TICKET. Run \`tk show $TICKET\` first and treat it as the source of truth."
      echo "The tickets are in ~/$bdir/tickets (TICKETS_DIR is set to it; if tk cannot find the ticket, export TICKETS_DIR=~/$bdir/tickets)."
      [[ -n "$NOTES" ]] && { echo; cat "$NOTES"; }
      echo
      echo "Nobody is at this keyboard: never ask. A blocker goes into your report, then stop."
      echo "Commit your work on your branch (small commits naming the ticket id): the architect fetches the branch, so uncommitted work is not handed back. Never push, merge or close the ticket. When done, write your completion report to ~/$bdir/HANDBACK.md, end it with HANDBACK-READY on its own line, and stop."
    } > "$BRIEF/PROMPT.md"
    [[ "$KIND" == claude && -z "$AGENT" ]] && AGENT="nah:nah-developer"
  fi
  [[ -f "$BRIEF/PROMPT.md" ]] || die "$BRIEF/PROMPT.md is missing (the developer's whole brief, ending with: write HANDBACK.md in this folder and stop)"
  url="ssh://$SSHH/${REPO#/}"; wt="~/nah-wt/$name"
  run git push -q "$url" "$(git rev-parse "$BASE"):refs/heads/nah/base-$name"; MADE_BASE=1
  run ssh "${SSHO[@]}" "$SSHH" "git -C '$REPO' rev-parse -q --verify 'nah/base-$name^{commit}' >/dev/null" ||
    die "the base did not arrive as nah/base-$name in $REPO there (is --repo the clone ssh reaches?)"
  # mkdir without -p fails when the folder exists: then it is not ours and is not touched
  run ssh "${SSHO[@]}" "$SSHH" "mkdir -p ~/nah-wt && mkdir ~/$bdir" || die "~/$bdir exists on $MACHINE"; MADE_BRIEF=1
  run scp -q -r "$BRIEF"/* "$SSHH:$bdir/"
  out=$(run h worktree create --cwd "$REPO" --branch "$BRANCH" --base "nah/base-$name" --path "$wt" \
        --label "nah $name (developer)" --no-focus); MADE_WT=1
  pane=$(jget pane_id <<<"$out"); ws=$(jget workspace_id <<<"$out")
  [[ -n "$DRY" ]] && { echo "$out"; pane=DRY ws=; }
  [[ -n "$pane" ]] || die "worktree create gave no pane: $out"
  mkdir -p "$STATE"   # written now so that close works even if the cleanup cannot remove the workspace
  [[ -n "$DRY" ]] || { printf 'MACHINE=%q\nSSHH=%q\nREPO=%q\nBRANCH=%q\nWS=%q\nBDIR=%q\n' "$MACHINE" "$SSHH" "$REPO" "$BRANCH" "$ws" "$bdir" > "$envf"; MADE_ENV=1; }
  # the pane must be in the worktree before the agent starts (over --machine the folder may not apply): cd if not
  if [[ -z "$DRY" ]]; then
    for i in 1 2 3 4 5; do
      [[ "$(h pane get "$pane" 2>/dev/null | jget cwd)" == "$rhome/nah-wt/$name" ]] && break
      [[ $i == 5 ]] && die "pane $pane is not in $rhome/nah-wt/$name; the agent was not started"
      h pane run "$pane" "cd ~/nah-wt/$name" >/dev/null || true; sleep 1
    done
  fi
  # the agent inherits the pane shell's environment: point tk at the copied tickets before it starts
  [[ -n "$TICKET" ]] && { run h pane run "$pane" "export TICKETS_DIR=~/$bdir/tickets" >/dev/null; [[ -n "$DRY" ]] || sleep 1; }
  args=(); [[ -n "$AGENT" ]] && args+=(--agent "$AGENT"); [[ -n "$MODEL" ]] && args+=(--model "$MODEL")
  [[ -n "$SKIP" && "$KIND" == claude ]] && args+=(--dangerously-skip-permissions)
  run h agent start "$name" --kind "$KIND" --pane "$pane" -- ${args[@]+"${args[@]}"} >/dev/null 2>&1 || true
  [[ -n "$DRY" ]] || { sleep 3; answer_trust; }   # only here: the pane was checked to be in this start's worktree
  [[ -n "$DRY" ]] || h agent wait "$name" --until idle --timeout 60000 >/dev/null || die "agent $name is not ready: herdr --machine $MACHINE agent read $name"
  if [[ -n "$TICKET" ]]; then msg="$(cat "$BRIEF/PROMPT.md")"
  else msg="Read ~/$bdir/PROMPT.md and do exactly what it says, end to end, without stopping to ask: nobody is at this keyboard. When done, write ~/$bdir/HANDBACK.md, end it with HANDBACK-READY on its own line, and stop."; fi
  if [[ -n "$DRY" ]]; then run h agent prompt "$name" "$msg"; else send "$msg"; fi
  echo "started $name on $MACHINE: workspace $ws, worktree $wt, branch $BRANCH, brief ~/$bdir"
  ;;
prompt)
  load; seen=$(ready_count); send "$TEXT"
  sed -i.bak '/^READY0=/d' "$envf" && rm -f "$envf.bak"; echo "READY0=$seen" >> "$envf"
  echo "prompted $name; remote-dev.sh wait $name"
  ;;
wait)
  # Settled is not finished: an agent that waits on its own background work (a test loop) reports idle. Wait until
  # a new HANDBACK-READY line appears (counted against the last start or prompt) or the agent is blocked.
  load; t=(); [[ -n "$TIMEOUT" ]] && t=(--timeout "$TIMEOUT"); said=
  while :; do
    st=$(h agent wait "$name" ${t[@]+"${t[@]}"} 2>&1 | grep -o '"agent_status":"[a-z]*"' | head -1)
    [[ "$st" == *blocked* ]] && { echo "$st: herdr --machine $MACHINE agent read $name"; exit 0; }
    c=$(ready_count); [[ "$c" != 0 && "$c" != "${READY0:-0}" ]] && { echo "$st"; echo "HANDBACK ready: remote-dev.sh report $name"; exit 0; }
    [[ -n "$TIMEOUT" ]] && { echo "$st, no new HANDBACK-READY yet (timeout)"; exit 0; }
    [[ -n "$said" ]] || { echo "$st without a new HANDBACK-READY (background work?); still waiting"; said=1; }
    sleep 60
  done
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
doctor)
  for v in MACHINE SSHH REPO; do [[ -n "${!v}" ]] || die "doctor needs --machine, --ssh and --repo"; done
  [[ "$REPO" == /* ]] || die "--repo must be an absolute path on that machine"
  res=$(checks full); grep -v '^home:' <<<"$res"
  ! grep -q '^MISSING' <<<"$res"
  ;;
status)
  if [[ ${#NAMES[@]} -eq 0 ]]; then
    for f in "$STATE"/*.env; do [[ -f "$f" ]] && NAMES+=("$(basename "$f" .env)"); done
  fi
  rows=; for n in ${NAMES[@]+"${NAMES[@]}"}; do rows+="$(status_one "$n" || true)"$'\n'; done
  rows=$(printf '%s' "$rows" | grep . | sort -t$'\t' -k1,1n -k2,2 | cut -f3- || true)
  if [[ -n "$JSON" ]]; then echo "[$(paste -sd, - <<<"$rows")]"
  elif [[ -z "$rows" ]]; then echo "no open remote developers ($STATE)"
  else echo "$rows"; fi
  exit 0
  ;;
*) die "unknown command $cmd (doctor, start, status, prompt, wait, report, fetch, close)";;
esac
