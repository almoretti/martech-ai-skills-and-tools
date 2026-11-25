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

- **Backlog repositories** (the repo has `docs/backlog/`: an index `README.md` and one item file per improvement, `IMP-NN-<slug>.md`): tickets live in `docs/backlog/tickets/` and are committed with the work; they are the record. `export TICKETS_DIR=docs/backlog/tickets` in the architect session and put the same assignment at the start of every developer task text, because subagents call `tk` by name. The ticket tree is cut from one backlog item; every ticket title starts with the item id (`IMP-NN: ...`); when the work ships, the item file gets the date, the commit and the ticket ids, and its row in the index changes to done. **Lanes**, when the backlog README declares them (a short `Lanes` list of
  the system's areas, for example serving, compliance, pricing): each item belongs to exactly one lane, shown in a
  **Lane** column of the index; every ticket cut from it carries that lane's tag (`tk create ... --tags lane-<area>`).
  An item that spans two lanes is split into two items. Items say the outcome; lanes say the area. The item id follows
  its lane: each lane in the list has a short code (`serving (SRV)`), its items are `<CODE>-NN-<slug>.md` numbered per
  lane, and their tickets are titled `<CODE>-NN: ...`; an item that moves lane takes the new lane's next id. Without
  the list, no lanes, and items stay `IMP-NN`.
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
7. Write the final-validation ticket as exact ordered commands, one per step. Dispatch it to `nah:nah-test-runner`, which runs the steps as written and reports `PASS` or `FAIL` per step. Task text: `Run the validation steps of tk ticket <id>. Run \`tk show <id>\` first.` (in a backlog repository it starts with `export TICKETS_DIR=docs/backlog/tickets`). A `FAIL` goes to `nah:nah-developer` as a fix dispatch, then the whole ticket runs again. Close the ticket when every step reports `PASS`.

### Validation surfaces

A **surface** is a place where the change is set up, observed working, or leaves a trace. The catalogue is `${CLAUDE_PLUGIN_ROOT}/skills/nah/SURFACES.md`, in four groups: setup (runtime, test data, flags, time), observe (browser, emulator, CLI, API, database, logs), outbound (tracking, messages, integrations, jobs, pipelines, content) and quality (visual, accessibility, security, CI, evidence). Read it when you plan a final-validation ticket.

1. **Name** the surfaces in the ticket, from what the change touches: the setup it needs, where it shows, what it sends out, the quality bars it could move.
2. **Read the reach file**: `~/.config/nah/surfaces/<parent>-<folder>.md`, named from the working root and the folder that holds it (`Code-the-frontend`). The working root is the main checkout of a git repository (so its worktrees share one file), else the folder the session works in. It is this machine's record of how each surface of this project is reached, one line per surface: `<surface> | <route> | reached / not reached | <what is missing> | <date probed>`. It holds routes and dates; credentials and connection strings stay out of it.
3. **Find a route** to each named surface that has no line in the file, or whose saved route fails its probe, and only to those. Two sources, in this order:
   - your own tool list, read by name from what is already in context (a browser MCP, a database connector). No calls.
   - one `nah:nah-repo-scout` dispatch for the rest. Task text: `Surface reach for <surfaces>. Catalogue: <absolute path of SURFACES.md>.` It searches the PATH and the repo's scripts and test setup, probes, and returns one line per surface; the search output stays in its context.
4. **Probe** each route before the ticket-tree gate, saved or new, with the cheapest call that proves reach: the tool answers, the page loads, a device is listed, the database answers a trivial query. The scout's lines carry its probe results; probe the saved routes and the routes from your own tool list yourself.
5. **Assign** each step to who can run it:
   - `runner`: a shell command `nah:nah-test-runner` runs as written.
   - `architect`: needs a tool only this session holds (an MCP browser, a connector); you run it after the runner passes and record the result with `tk add-note`.
   - `user`: the probe failed, or the step needs access or judgement the session lacks; write what to check and what passing looks like.
6. **Offer a route** for each surface no route reached: the cheapest way to get one (what to install, connect or log into) and what it would then automate. The user chooses: set it up now, then you probe again and the step moves to `runner` or `architect`; or keep the check as a `user` step for this change. A check that needs the user's judgement stays a `user` step.
7. **Show** the surfaces, the route and probe result for each, every offer and every `user` step with the ticket tree, so the approval covers them. A surface with no step is stated as a gap, with the reason.
8. **Order** the ticket: setup steps first, then the checks, then a step that stops what setup started. A setup step that leaves something running (a dev server, containers) is an `architect` step: start it in the background before you dispatch the runner.
9. **Save** each probed surface's line to the reach file with today's date, replacing its old line; again after the user sets up an offered route and the new probe passes.

The ticket closes when every `runner` and `architect` step passed and each `user` step is confirmed by the user or recorded as a `waiting-on:` note.

## Implementation loop

For each ready ticket:

1. `tk ready` to pick the next dependency-unblocked ticket; `tk start <id>`.
2. Dispatch one ticket to `nah:nah-developer`. Task text: `Implement tk ticket <id>. Run \`tk show <id>\` first and treat it as the source of truth.` In a backlog repository the text starts with `export TICKETS_DIR=docs/backlog/tickets`. Add ticket-specific validation constraints or sequencing; with a developer ledger, the ledger command for the ticket's files ("Docs after a landing").
3. The developer cannot ask questions mid-run. If its report is a blocker, answer it and re-dispatch with the decision included.
4. The ticket is met when every acceptance criterion shows in the diff; read the diff yourself when the report is thin.
5. Send focused corrections back as a new dispatch when a criterion is missing.
5b. Run the lean pass (below), then send its items with your corrections in one dispatch.
6. `tk close <id>` when the ticket's intent is met, and not while its notes hold a fact of a ledger kind that is in neither the ledger nor a new ticket. Record decisions with `tk add-note`.
7. `codex-role.sh code-reviewer` as a checkpoint for high-risk tickets.

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
- **The integrator** (`nah:nah-integrator`, optional): when the project has a `.nah/integrator.md` (its merge worktree,
  landing branch, check commands per platform, remote runner, known-flaky list, mirrors, trailers and machine rules;
  example: `${CLAUDE_PLUGIN_ROOT}/examples/integrator.example.md`), the architect may hand a reviewed stack to it
  instead of merging itself. It merges, runs the project's one check on each platform, judges any failure by its
  fixed table, and lands (push, mirrors, and a note and `tk close` on each ticket the dispatch lists) or stops with
  the evidence. The architect still decides, and writes in the dispatch: which branches merge and in what order, the
  resolution of each conflict it expects, and which tickets land with the stack; and, on a stop, what it means (a fix
  ticket, a reorder, a known-flaky entry). A small fix at merge time is the architect's written instruction in the dispatch, never the integrator's
  idea; an uncovered conflict or a failure the table does not clear comes back as a stop. Its mechanical checks are
  `scripts/integrator.sh check-clean|markers|land` (`land --dry-run` checks without pushing). Dispatch text:
  `Integrate stack <label>: <branch> (<id>: <title>), …; conflicts: <file>: <resolution>; …; script: <absolute path of
  integrator.sh>.` One integrator per merge worktree; its full check is the machine's one full gate. Its report
  ends with `docs owed: yes|no, tickets: …` (see "Docs after a landing").
- When more than one session works a repository, `docs/LANES.md` names each session's branch, paths and ports, one
  line each, updated at dispatch; a session touches nothing in another lane. In a backlog repository with lanes, a
  session claims a lane (or one item in it) on its line, so parallel sessions are split by area first. When the
  repository is not ours to commit to, the lanes file lives in that repo's notes folder outside the clone (for
  dev-contribution: `dev-contribution/<repo>/LANES.md`), each extra session works in its own git worktree
  (`<clone>-<ticket>`), never in another session's checkout, and a shared notes file is edited per lane: only your own
  ticket's lines, re-read right before writing.

## Docs after a landing

- **The documenter** (`nah:nah-documenter`, optional): when the project has a `.nah/docs.md` (example:
  `${CLAUDE_PLUGIN_ROOT}/examples/docs.example.md`), the architect dispatches it after every landed stack
  that changed something a person or an operator meets: the integrator's `docs owed: yes` line names the tickets (a
  stack merged by the architect: the architect writes that line itself). Once more at the end of a wave, with
  `end of wave: yes`, for the index, the guides and the change summary.
- It has two outputs: the docs a person or an operator reads, and the project's **developer ledger** (when
  `.nah/docs.md` names one: where it lives, its entry format, the command that lists the entries for a set of
  paths): the facts an agent needs before touching an area (invariants, traps, decisions with their reason, accepted
  risks, known limits, where something is decided), each tied to its paths and carrying how to check it.
  Without a ledger it does the docs half and says so.
- The ledger is used, not only kept: implementation loop steps 2 and 6, and the developer and code-reviewer roles.
- It writes only docs and ledger entries, ties every added or changed sentence to a `file:line` at the landed tip in its hand-back's
  claim table, and turns every doubt into a question. Its diff gets the one review and no lean pass, by a reviewer
  who checks each claim against the code at the landed tip, not against the hand-back; then it merges in the next
  stack, or alone at the end of a wave. Docs never block a landing.
- It needs no build machine: it runs no build or test suite, only the docs checks.
- Dispatch text: `Document stack <label>: landed tip <ref>; tickets: <id> (<title>), …; hand-backs: <paths or none>;
  end of wave: yes|no.`

## Final review

After all tickets are complete:

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/nah/scripts/codex-role.sh code-reviewer "Final review. Tickets: <ids>. Base ref: <branch-point>. Review the full diff against the tickets."` If tickets were deleted, include a self-contained brief and tell the reviewer not to run `tk`.
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

## Developers on other machines (Herdr, optional)

When the user runs Herdr with more than one saved machine (`herdr machine list`), developers can run on another machine,
so builds and browser tests use its memory and more tickets run in parallel. The user chooses this; ask before the
first remote dispatch, and check the other machine's free memory before each one.

- Needs: a Herdr saved machine with API forwarding, ssh to it from here, a clone of the repository there, the agent CLI
  signed in there. The tickets stay here; the developer gets the ticket as files in its brief.
- **Before the first start on a machine**: `remote-dev.sh doctor --machine <m> --ssh <user@host> --repo <clone path
  there> [--back <machine>]` checks, read-only, one line each (`ok` / `warn` / `MISSING: what to do`): ssh without a
  prompt, the Herdr machine and a compatible server, git, node and the package manager at the versions the
  repository's `package.json` asks, the clone, `claude` with the nah plugin and its dependencies installed and enabled,
  `tk` on the PATH, executable and without CRLF line endings, free disk and memory, and (`--back`) the saved Herdr
  machine there that leads back here. It exits 0 only when nothing is MISSING, and installs nothing: the user fixes
  what it lists. `tk` goes on that machine through the plugin's `scripts/install.sh` (a link to the plugin's copy); a
  `tk` copied by hand from a Windows checkout has CRLF line endings and fails with `env: bash\r`: strip them
  (`tr -d '\r'`) when copying.
- **Folder trust**: start agents only in a folder that is already trusted or that the script created for them. `start`
  checks that the agent's pane is in the worktree it created before it starts the agent (over `--machine` the folder
  of a new workspace may not apply). The one prompt the script answers is Claude Code's folder-trust dialog, at start
  only, for the worktree it just created, by sending Down and Enter ("Yes, I trust this folder"); every other trust,
  permission or other dialog is left to the user: nobody answers it on the user's behalf, and the architect reports it.
- `${CLAUDE_PLUGIN_ROOT}/skills/nah/scripts/remote-dev.sh start <name> --machine <herdr machine> --ssh <user@host>
  --repo <clone path there> --base <ref> --branch <branch> --ticket <id> [--notes <file>]` pushes the base, creates a
  Herdr worktree and workspace there (`~/nah-wt/<name>`), copies the ticket with its parent and dependencies, and starts
  the same developer as a local dispatch: Claude Code with `--agent nah:nah-developer` (the plugin installed there),
  `TICKETS_DIR` pointing at the copied tickets, and the standard dispatch text "Implement tk ticket <id>", plus the
  notes file for ticket-specific validation. Nothing is hand-written: the ticket is the brief. The script adds only
  "nobody is at this keyboard; never push, merge or close; write the report to HANDBACK.md". `--kind codex|pi` and
  `--brief <folder with PROMPT.md>` remain for other agents and for work that is not a ticket. `--skip-permissions` starts Claude without
  permission prompts: only when the user chose it. `start` first runs the cheap part of `doctor` (ssh, the clone, the
  plugin, the name, the worktree path, the brief folder and the branch still free) and creates nothing when one is
  MISSING; when a later step fails, Ctrl-C included, it removes what that run created and nothing else (workspace,
  worktree, the branch while it has no commits beyond the base, the pushed base ref, the brief, the state file) and
  exits non-zero.
- **Being told**: the agent's state AND the READY report together are the signal: a report alone is early, an idle
  agent alone may be waiting on its own test run. `remote-dev.sh wait <name>... [--timeout <s>] [--grace <s>]` (run
  as a background command) returns on the first named developer that has finished (agent not working, HANDBACK.md
  READY, no placeholder left; exit 0) or is gone (exit 0) or `blocked` (exit 2); an agent not working for `--grace`
  (default 10 min) without a finished report returns exit 3 for a look; at the timeout it exits 124 with "still
  working", so a caller can loop. Check `status` before any status line. Never poll folders. On `blocked`, read the pane
  (`herdr --machine <m> agent read <name>`) and decide or ask the user before sending keys.
- **Status check, before every status you give the user and whenever a developer has been quiet for longer than its
  last round took**: a notification that did not arrive is not "still working". Look, do not assume:
  `remote-dev.sh status` lists every open developer in one call, hand-backs first: machine, agent state (working,
  idle, blocked, done, or gone), the time and checksum of its HANDBACK.md, READY when it ends with HANDBACK-READY,
  NEW when it changed since the last `status`, and "placeholder left" when it still holds the project's template
  marker (`--placeholder <text>` or `NAH_HANDBACK_PLACEHOLDER`). The plain form marks what it showed as seen;
  `--json` (for scripts) never does, so a monitoring script cannot hide a new hand-back from your next look. A dead
  machine reads "unreachable" after a timeout instead of hanging the call. A developer may write
  HANDBACK.md before its last check ends: a row marked "READY but agent still working: do not take in" is judged once
  the agent is idle (the checksum shows a rewrite); "done, no hand-back" needs a look at the pane. Then the last commit on its branch. An idle developer with a report newer
  than your prompt has handed back: fetch and judge it now. Check too that this session still has the Herdr name the
  developers report to (`herdr agent list` here; `herdr agent rename <pane> <name>` restores it): a model switch or a
  restart can clear it, and then no report reaches you. Never tell the user a developer is working without this check.
- **The developer's model**: pass the full model id to `start` (`--model claude-opus-5-5`, not an alias such as
  `opus`, which another machine may resolve differently), and confirm it in the session after the start.
- `remote-dev.sh report <name>` prints HANDBACK.md (the durable report; a long final message scrolls out of the pane).
  `remote-dev.sh fetch <name>` brings the branch here; then the hand-back is judged exactly as a local one (lean
  pass, corrections, review). A correction round is `remote-dev.sh prompt <name> "<text>"` to the same session, then
  `wait` again. A prompt never answers a dialog: when the agent does not take it, the script stops and prints what is
  on its screen, for you to read and to decide or ask the user.
- `remote-dev.sh close <name>` when the ticket is merged: ends the session, removes the worktree and its workspace.
  Never touch the user's own workspaces on that machine.
- One developer per worktree still holds; one full gate per machine.

## Running the reviewer through Codex

`${CLAUDE_PLUGIN_ROOT}/skills/nah/scripts/codex-role.sh <role> [--model id] [--cwd dir] [--out file] [--timeout secs] [--fresh] [--no-fallback] "<task>"`

- Uses the `codex` CLI on the PATH and its own sign-in (`codex login`). Codex may read anywhere and may write only in its state folder (`~/.local/state/nah/codex/<role>`, sandbox `workspace-write` with that folder as its working directory); the repository under review is named in the prompt and stays untouched. The report is a file Codex writes there; the script prints it and appends it to `--out`.
- **Inside Herdr** (`HERDR_ENV=1`): a real Codex session, started and driven with `herdr agent start`, `herdr agent prompt --wait` in a new background tab labelled `nah <role>`, named `nah-<role>`. The session is KEPT: a second call with the same role is a follow-up in the same conversation (a re-review of the fixes, a question about a finding), and the user can type into the tab. `--fresh` ends the old session and starts a new one.
- **Cleaning up**, so that no dead tabs pile up: there is at most one tab per role in a workspace; every call first closes the tabs this script opened whose session has ended; `codex-role.sh <role> --close` ends the session and closes its tab; `codex-role.sh --sweep` closes every ended one. The script closes only tabs it opened itself (it records them in `~/.local/state/nah/codex/tabs.list`). **Run `--close` when the review of a change is settled, and before the session ends.**
- **Outside Herdr**: one headless `codex exec` run with the same limits; no memory between calls.
- Back-up: when `codex` is missing, not signed in, or leaves no report, the same role runs through pi (below) with the same task; `--no-fallback` turns that off. The report's first line says which runner produced it and whether it was a follow-up.
- If the session is waiting for an answer (Herdr status `blocked`) the script says so and leaves the tab open: look at it with `herdr agent read nah-<role>` before sending anything.
- Default timeout 2700 s (`CODEX_ROLE_TIMEOUT`); start a long review as a background command.

## Running roles through pi

`${CLAUDE_PLUGIN_ROOT}/skills/nah/scripts/pi-role.sh <role> [--model provider/id] [--thinking level] [--cwd dir] [--out file] [--rw] "<task>"`

- Roles are `roles/*.md`; defaults per role in `roles/models.env`. A repository overrides them in `<repo>/.nah/models.env` (the same `<ROLE>_MODEL=` / `<ROLE>_THINKING=` lines, read as data); `--model` wins over both.
- Uses the standalone `pi` at `~/.local/bin/pi` and its `~/.pi/agent` logins. On `refresh_token_invalidated` it tells you to run `pi` then `/login <provider>`.
- Read-only tool set by default; `--rw` adds write/edit (only for a developer run through pi).
- Tasks over ~8k chars are passed as a file automatically.
