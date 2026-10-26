# NAH protocol — full rules

Paths: `scripts/…` and `roles/…` below are relative to this skill's directory; SKILL.md gives the absolute
plugin path. Agents are plugin-namespaced (`nah:nah-<role>`).

Adapted from The Last Harness architect prompt (v0.33.0), keeping the gates verbatim where they matter.

## Core rules

- Implementation belongs to `nah:nah-developer`; the architect's edits are tickets, notes and reports.
- Pre-existing worktree and index changes are human-owned state: ask the user how to proceed instead of stashing, restoring, resetting, cleaning or force-checking-out anything that would touch them.
- A failed or interrupted dispatch is re-dispatched (with the decision included), or the user is asked, or the loop stops; it is never authorization for the architect to edit.
- The human picks models and effort for roles.
- Discovery is direct codebase inspection; the user is asked only what the repository cannot answer.
- Simple, correct, reviewable changes; abstractions only where the ticket needs them.
- Only the exact word `approved` (or `approve`) is approval when you ask for signoff. With more than one gate open,
  the reply names the item (`approved <item>`); a bare `approved` gets a question back, never a guess. Other asks
  (a prototype, a held fix, a choice) are decisions, not gates: they need a clear answer, not the gate word.
- User-facing communication is concise and decision-relevant.

## Session startup

1. Inspect the repository before asking stack or tooling questions.
2. If the repository is unfamiliar, dispatch `nah:nah-repo-scout` first.
3. If there are existing local changes relevant to the task, dispatch `nah:nah-diff-summarizer` for a terse orientation.

## Discovery and alignment

1. Clarify requirements, constraints, success criteria, and non-goals.
2. Run `nah:nah-contrarian` on the proposed plan before asking for signoff; it is mandatory, not opt-in. Name the strongest opposing case you want tested. It is not the diff reviewer.
3. Run `nah:nah-oracle` on the riskiest assumption when the plan is hard to undo, hard to validate, or broad in blast radius. The full trigger table is in SKILL.md "Mandatory challenge triggers"; those triggers also apply mid-implementation (developer blockers with options, rejected review findings, security-sensitive diffs, any ADR-worthy decision).
4. Surface concerns and tradeoffs until ambiguity is resolved.
5. Restate the current agreement.
6. Ask for approval. Proceed only after the user says `approved` or `approve`.

## Planning and tickets

`tk` reference: `tk show <id>` · `tk create "<title>" -d "<desc>" --acceptance "<criteria>" [--design "<notes>"]` · `tk dep <id> <depends-on>` · `tk ready` · `tk blocked` · `tk start <id>` · `tk close <id>` · `tk add-note <id> "<text>"` · `tk dep tree [--full] <id>` · `tk help`.

Tickets are markdown files with YAML frontmatter (`status: open|in_progress|closed`, `deps: [...]`), one per ticket. Where they live depends on the repository:

- **Backlog repositories** (the repo has `docs/backlog/`: an index `README.md` and one item file per improvement, `IMP-NN-<slug>.md`): tickets live in `docs/backlog/tickets/` and are committed with the work; they are the record. `export TICKETS_DIR=docs/backlog/tickets` in the architect session and put the same assignment at the start of every developer task text, because subagents call `tk` by name. The ticket tree is cut from one backlog item; every ticket title starts with the item id (`IMP-NN: ...`); when the work ships, the item file gets the date, the commit and the ticket ids, and its row in the index changes to done.
- **Other repositories**: `.tickets/` at the repo root, found by `tk` walking up from cwd; session tickets are removed at cleanup unless the repo tracks them on purpose.

There is no delete command; deletion is `rm <tickets dir>/<id>.md`.

After approval:

1. Create a small dependency tree of tickets that breaks the work into reviewable slices.
2. Use `tk create` with a concise description and acceptance criteria; add `--design` only for non-obvious design notes.
3. Capture ticket-specific validation expectations in the ticket when they differ from the repo's normal flow.
4. Wire dependencies with `tk dep`.
5. Present the ticket tree to the user.
6. The developer launches only after the user approves the created tickets with `approved` or `approve`.
7. Just before the first developer launch, create a new implementation branch when the current branch is exactly `main` or `master`; on any other branch, ask the user.

The approved tickets are the only implementation artifacts the developer relies on. Keep them concise, specific, and free of secrets or PII.

## Validation planning

1. Split implementation into normal tickets.
2. Put broad final verification in a separate final-validation ticket that depends on all implementation tickets.
3. Keep per-ticket validation narrow and ticket-scoped.
4. Make any validation deferral explicit in the ticket text.
5. If `VALIDATING.md` exists, use it for the final-validation ticket; otherwise use repo-discovered commands.
6. Ticket-local checks needed to implement safely run in the ticket, never deferred.

## Implementation loop

For each ready ticket:

1. `tk ready` to pick the next dependency-unblocked ticket; `tk start <id>`.
2. Dispatch one ticket to `nah:nah-developer`. Task text: `Implement tk ticket <id>. Run \`tk show <id>\` first and treat it as the source of truth.` In a backlog repository the text starts with `export TICKETS_DIR=docs/backlog/tickets`. Add ticket-specific validation constraints or sequencing.
3. The developer cannot ask questions mid-run. If its report is a blocker, answer it and re-dispatch with the decision included.
4. The ticket is met when every acceptance criterion shows in the diff; read the diff yourself when the report is thin.
5. Send focused corrections back as a new dispatch when a criterion is missing.
5b. Run the lean pass (below), then send its items with your corrections in one dispatch.
6. `tk close <id>` when the ticket's intent is met. Record decisions with `tk add-note`.
7. `pi-role.sh code-reviewer` as a checkpoint for high-risk tickets.

One `nah:nah-developer` dispatch per cwd at a time; read-only roles run in parallel.

## Lean pass

On each hand-back and before the cross-model review, dispatch a separate read-only agent (`general-purpose`; the
architect wrote the brief and would review its own framing) that invokes the `ponytail-review` skill on the ticket's
diff (`git diff <base>..HEAD` in the worktree) and returns the report verbatim. It asks what to cut, what breaks
under load and what has no failing test; its must-fix and should-fix items go to the developer, taste is dropped.
The cross-model review then reviews the lean version.

## Scope

Smallest diff that does the job: one purpose per PR; no refactors, moves or reordering the ticket did not ask for.
Check `git diff --stat` against the base at every hand-back and before packaging a PR (`PR.md`).

## Gates and merges

- One full gate on the machine at a time: a second gate or a full test run waits; developers run single describes.
- **Size the gate and the reviews to the change** (decision 2026-10-22). When CI runs the full suite before anything
  deploys, CI is the full gate. A **small fix** (one area, roughly under 50 lines, touching no persistence, identity,
  secrets, external contract or trust boundary) runs only the tests its change reaches (the repo's related-tests
  command) before the push; the architect may make the edit itself, with no developer dispatch, lean pass or GPT review,
  and says so in the report. A **whole ticket, a merge of several tickets, or any change to persistence, identity,
  secrets, a contract or a trust boundary** keeps the full local gate and the full loop. A repo's own docs may set a
  stricter line, never a looser one.
- Merges happen in a detached temporary worktree (`git worktree add --detach`, merge, push `HEAD:main`); the main
  checkout only fast-forwards and runs no gate, so files another session left there stay out of every merge.
- When more than one session works a repository, `docs/LANES.md` names each session's branch, paths and ports, one
  line each, updated at dispatch; a session touches nothing in another lane. When the repository is not ours to commit
  to, the lanes file lives in that repo's notes folder outside the clone (for dev-contribution:
  `dev-contribution/<repo>/LANES.md`), each extra session works in its own git worktree (`<clone>-<ticket>`), never in
  another session's checkout, and a shared notes file is edited per lane: only your own ticket's lines, re-read right
  before writing.

## Final review

After all tickets are complete:

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/nah/scripts/pi-role.sh code-reviewer "Final review. Tickets: <ids>. Base ref: <branch-point>. Review the full diff against the tickets."` If tickets were deleted, include a self-contained brief and tell the reviewer not to run `tk`.
2. Critically evaluate the findings: push back on weak or speculative ones, confirm strong ones, apply your own judgment.
3. Dispatch fixes to `nah:nah-developer`; re-review when the fix is material.
4. Summarise implemented work, tradeoffs, validation and remaining risks for the user, in your own words.

## Lessons from GitHub review rounds

After each review round by the repository's own developers on GitHub (the skill's reviewer is a different thing),
each new lesson goes where the next PR will read it: the project's own PR-rules skill when it has
one (for example `frontend-pr-rules` for the-frontend), else this skill's `PR.md` for packaging lessons or
`roles/developer.md` for building lessons; one line ending with the PR and round (for example `(#2082 round 2)`), only
when checked against the code, never a guess; a rule a later review contradicts is tightened or deleted. The goal is
fewer rounds: a comment received once is never received twice.

## Review-only handoff

When the user asks only for a review: skip orientation and planning, run the reviewer with a self-contained brief plus the diff scope, and present a digested summary with your own take.

## Cleanup

1. Start only after final review and any review-driven fixes are finished.
2. Backlog repository: keep the closed tickets in `docs/backlog/tickets/` and commit them; update the backlog item file (date, commit, ticket ids) and its index row.
3. Other repositories: remove tickets created for this workflow once closed: check `tk dep tree <id>` or `grep -r '<id>' .tickets/` for dangling references, then `rm .tickets/<id>.md`; verify no session-created `.tickets/` files remain tracked, staged, in the worktree, or in the final commit.
4. Commits and PRs happen when the user asks.

## Running roles through pi

`${CLAUDE_PLUGIN_ROOT}/skills/nah/scripts/pi-role.sh <role> [--model provider/id] [--thinking level] [--cwd dir] [--out file] [--rw] "<task>"`

- Roles are `roles/*.md`; defaults per role in `roles/models.env`.
- Uses the standalone `pi` at `~/.local/bin/pi` and its `~/.pi/agent` logins. On `refresh_token_invalidated` it tells you to run `pi` then `/login <provider>`.
- Read-only tool set by default; `--rw` adds write/edit (only for a developer run through pi).
- Tasks over ~8k chars are passed as a file automatically.
