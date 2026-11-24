<!--
EXAMPLE ONLY. The shape of a project's `.nah/integrator.md`, read by `nah:nah-integrator`. Copy it to your
repository's `.nah/integrator.md` and replace every <placeholder>; the check commands are an illustration for a pnpm
monorepo, not a default.
-->
# Integrator: <project>

Read by `nah:nah-integrator`. Everything project-specific lives here; the role's rules are in the plugin.

## Where

- Main checkout: `<main checkout>`. Never checked out, stashed or reset; commit there only the ticket files, by
  pathspec, and never `<tickets that are not the integrator's>`.
- Merge worktree: `<merge worktree>` (detached). One integrator at a time.
- Branches come from the main checkout: `git fetch -q "<main checkout>" +<branch>:refs/remotes/local/<short>`, then
  merge `refs/remotes/local/<short>`.
- Landing branch: `<landing branch>` on `origin`. Not the default branch: never `--to-default`.
- Tickets: `TICKETS_DIR=<tickets dir>` in the main checkout.

## Formatting

Any file edited at a merge gets `<formatter> <file>` before its commit.

## Checks, this machine, in order

Stop at the first failure; log each to `<log dir>/intg-<label>-<step>.log`.

1. `pnpm install --frozen-lockfile`
2. `pnpm typecheck`
3. `pnpm -s lint`
4. `pnpm -s build`
5. Start the remote run (below), then, while it runs:
6. `<package a>`: `npx vitest run`
7. `<web app>`: `npx vitest run`
8. `<server app>`: `npx vitest run`
9. `<e2e dir>`: `npx playwright test --workers=1 --reporter=list`

Skips: a web-only stack (no file under `<server app>/` or `<packages>/`) may skip steps 6 and 8 here. The remote run
never skips.

## Checks, remote runner

- Start: `git push -q <runner>:<runner repo> HEAD:refs/heads/merge/<label>-<epoch>`, then
  `ssh <runner> "<start command for merge/<label>-<epoch>, in the background, output to <label>.out>"`.
- Only one remote run at a time, and none while `<what else uses the runner>`.
- Done when `<the runner's result file>` shows the last suite (or an early failure). Wait inside ssh; no foreground
  sleep on this machine.

## Known flaky

The notes of ticket `<known-flaky ticket>` hold the list. Name each entry as the test reports it (file, or file and line).

## Landing and mirrors

1. `integrator.sh land <merge worktree> origin <landing branch>` (prints `<landing branch>=<tip>`).
2. Note and close the tickets (the role's step 6).
3. Push the tip to each mirror: `git push <mirror url> <tip>:refs/heads/<mirror branch>` (no `--force`, no `+`).
4. Commit the changed ticket files in the main checkout by pathspec with a `tickets: …` message.
5. Optional second landing branch: `integrator.sh land <merge worktree> origin <second branch>`; when it refuses,
   report it and stop there.

## Commit trailers

Every commit ends with `<the trailer lines this project uses>`.

## Machine rules

`<shell, script naming, interpreter flags this machine needs>`.
