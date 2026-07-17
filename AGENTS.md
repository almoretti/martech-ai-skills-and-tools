# AGENTS.md — contributing to this repo

How this repo is organized and how to add/change a tool so everything stays consistent.

## Layout
- `Skills/<name>/` — self-contained Claude skills (a `SKILL.md` plus bundled `scripts/`/`references/`/`assets/`).
- `CLI/<name>/` — standalone command-line tools; each may ship its own skill under `CLI/<name>/skills/<name>/`.
- `.claude-plugin/` — **generated** — the Claude Code plugin (`plugin.json`) and single-plugin marketplace (`marketplace.json`).
- `scripts/` — `build-marketplace.mjs` (regenerates the manifests), `list-skills.sh`.

## The repo is a Claude Code plugin marketplace
It ships **one bundled plugin**, `martech-ai-skills`, that includes every skill in the repo. Install:
```
/plugin marketplace add almoretti/martech-ai-skills-and-tools
/plugin install martech-ai-skills@martech-ai
```

## Adding / renaming / removing a skill
1. Put the skill under `Skills/<name>/` (or a CLI's `skills/` folder). It just needs a `SKILL.md` with `name` + `description` frontmatter.
2. Regenerate the manifests: `npm run build:marketplace` (or `node scripts/build-marketplace.mjs`).
   This rewrites `.claude-plugin/plugin.json` and `marketplace.json` from the skills present — never hand-edit them.
3. Add a row to `README.md`.
4. Commit. CI (`marketplace-in-sync`) regenerates and **fails if either manifest is stale**.

## Versioning (so installed users get updates)
Claude uses `plugin.json`'s `version` to decide when to show an update. The single source of truth is
**`package.json`'s `version`** — the generator copies it into `plugin.json`. To ship an update:
1. Bump `version` in `package.json`.
2. `npm run build:marketplace` (propagates it to `plugin.json`).
3. Commit + push.

(If you later want automated releases + CHANGELOG, add `@changesets/cli` and a `release.yml` — the same
setup Matt Pocock's `mattpocock/skills` uses. Not wired up yet; the manual bump above is enough for now.)

## Validate
If you have the Claude CLI: `claude plugin validate . --strict` after touching a manifest or skill.

## Keep it generic
No employer accounts, IDs, tokens, or branding anywhere. Credentials are supplied at runtime only.
When a tool derives from OSS, credit it in the tool's `NOTICE` **and** the README attribution list.
