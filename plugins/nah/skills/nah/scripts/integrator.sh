#!/usr/bin/env bash
# The mechanical checks of the nah integrator (agents/nah-integrator.md). No project paths here: the project's
# merge worktree, landing branch and remote come from its .nah/integrator.md and are passed as arguments.
#
# Usage:
#   integrator.sh check-clean <worktree>
#       exit 0 when the worktree has no changes, no untracked files and no merge, rebase, cherry-pick or revert in
#       progress.
#   integrator.sh markers <worktree> [file...]
#       exit 0 when git lists no unmerged path and no file holds a conflict marker line. Files are paths relative to
#       the worktree; without files it checks every file that differs from HEAD (the merge being committed). A line
#       starting `<<<<<<< `, `>>>>>>> ` or `||||||| ` always counts; a line that is exactly `=======` counts only when
#       the file has more of them than HEAD's copy and, during a merge, MERGE_HEAD's copy (so a Markdown heading
#       underline that was already there passes). Run it in its own step, after resolving and before committing.
#   integrator.sh land <worktree> <remote> <branch> [--to-default] [--dry-run]
#       fetch <remote> <branch>; push HEAD to it only when the fetched tip is an ancestor of HEAD (a fast-forward,
#       never a force). <branch> is a branch name, not a refs/ path. Refuses the remote's default branch, and any
#       branch when the remote does not say which is its default, unless --to-default (the project file says the
#       stack lands there). --dry-run runs every check and prints the push instead of pushing.
#
# Exit codes: 0 pass, 1 check failed (the reason on stderr), 2 usage.
set -euo pipefail
die() { echo "integrator: $*" >&2; exit 1; }
usage() { echo "usage: see the header of $0" >&2; exit 2; }

cmd="${1:-}"; [[ $# -ge 2 ]] || usage
wt="$2"; shift 2
command -v git >/dev/null 2>&1 || die "git is missing (not on the PATH)"
git -C "$wt" rev-parse --git-dir >/dev/null 2>&1 || die "$wt is not a git worktree"
# Lines that are exactly ======= (a CRLF checkout ends them with \r), read from stdin.
CR=$'\r'; EQ="^=======${CR}?\$"
count_eq() { grep -c -E "$EQ" || true; }

case "$cmd" in
  check-clean)
    [[ $# -eq 0 ]] || usage
    dirty=$(git -C "$wt" status --porcelain --untracked-files=all)
    [[ -z "$dirty" ]] || die "$wt is not clean:"$'\n'"$dirty"
    for r in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
      ! git -C "$wt" rev-parse -q --verify "$r" >/dev/null || die "$wt has $r (an operation is in progress)"
    done
    for d in rebase-merge rebase-apply; do
      p=$(git -C "$wt" rev-parse --git-path "$d")   # relative to $wt in a main worktree
      [[ "$p" = /* || "$p" =~ ^[A-Za-z]: ]] || p="$wt/$p"
      [[ ! -e "$p" ]] || die "$wt has a rebase in progress ($d)"
    done
    echo "clean: $wt at $(git -C "$wt" rev-parse --short HEAD)"
    ;;
  markers)
    unmerged=$(git -C "$wt" diff --name-only --diff-filter=U)
    [[ -z "$unmerged" ]] || die "unmerged paths:"$'\n'"$unmerged"
    files=("$@")   # bash 3.2 (macOS): no mapfile, and an empty array needs the ${a[@]+...} form under set -u
    if [[ $# -eq 0 ]]; then
      while IFS= read -r -d '' f; do files+=("$f"); done < <(git -C "$wt" -c core.quotePath=false diff --name-only -z HEAD)
    fi
    merging=; git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null && merging=1
    found=0
    for f in ${files[@]+"${files[@]}"}; do
      p="$wt/$f"
      [[ -f "$p" ]] || continue   # deleted by the merge
      if grep -n -E '^(<<<<<<<|>>>>>>>|\|\|\|\|\|\|\|)( |$)' "$p" >&2; then
        echo "  ^ conflict markers in $f" >&2; found=1; continue
      fi
      now=$(count_eq < "$p")
      [[ $now -gt 0 ]] || continue
      ours=$( { git -C "$wt" show "HEAD:./$f" 2>/dev/null || true; } | count_eq)   # absent on a side: 0
      theirs=0; [[ -z "$merging" ]] || theirs=$( { git -C "$wt" show "MERGE_HEAD:./$f" 2>/dev/null || true; } | count_eq)
      if [[ $now -gt $ours && $now -gt $theirs ]]; then
        grep -n -E "$EQ" "$p" >&2
        echo "  ^ $now ======= line(s) in $f, HEAD has $ours${merging:+, MERGE_HEAD has $theirs}" >&2; found=1
      fi
    done
    [[ $found -eq 0 ]] || die "conflict markers remain"
    echo "no markers: ${#files[@]} file(s) checked"
    ;;
  land)
    [[ $# -ge 2 ]] || usage
    remote=$1 branch=$2; shift 2
    [[ "$branch" != refs/* ]] || die "give the branch name, not $branch"
    todefault= dry=
    for a in "$@"; do case "$a" in
      --to-default) todefault=1;; --dry-run) dry=1;; *) usage;; esac; done
    ls=$(git -C "$wt" ls-remote --symref "$remote" HEAD 2>&1) || die "cannot reach $remote: $ls"
    default=$(printf '%s\n' "$ls" | sed -n 's|^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$|\1|p')
    if [[ -z "$todefault" ]]; then
      [[ -n "$default" ]] || die "$remote does not say which branch is its default; pass --to-default only when the project file says the stack may land there"
      [[ "$branch" != "$default" ]] \
        || die "$branch is the default branch of $remote; pass --to-default only when the project file says the stack lands there"
    fi
    out=$(git -C "$wt" fetch -q "$remote" "refs/heads/$branch" 2>&1) || die "fetch $remote $branch failed: $out"
    tip=$(git -C "$wt" rev-parse FETCH_HEAD)
    git -C "$wt" merge-base --is-ancestor "$tip" HEAD \
      || die "$remote/$branch ($tip) is not an ancestor of HEAD: it moved; merge it again before landing"
    head=$(git -C "$wt" rev-parse HEAD)
    if [[ -n "$dry" ]]; then
      echo "DRY: git -C $wt push $remote HEAD:refs/heads/$branch   ($tip -> $head)"
    else
      out=$(git -C "$wt" push -q "$remote" "HEAD:refs/heads/$branch" 2>&1) || die "push to $remote $branch failed: $out"
      echo "$branch=$head"
    fi
    ;;
  *) usage;;
esac
