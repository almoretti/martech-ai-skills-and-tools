# Martech AI Skills and Tools

A personal, vendor-neutral collection of **marketing-technology tooling for AI agents** (and humans) —
Claude skills and read-only command-line clients for the martech / adtech stack.

Everything here is generic: no employer-specific accounts, IDs, secrets, or branding. Credentials are
always supplied at runtime (environment variables or local credential files) and are never committed.

## Install (Claude Code)

This repo is a **Claude Code plugin marketplace** shipping one bundled plugin (`martech-ai-skills`)
with the standalone skills under [`Skills/`](Skills). Add the marketplace once, then install:

```
/plugin marketplace add almoretti/martech-ai-skills-and-tools
/plugin install martech-ai-skills@martech-ai
```

> **CLI skills are not in this plugin.** Each CLI under [`CLI/`](CLI) ships its own skill
> (`CLI/<name>/skills/`) that installs *with the CLI* — those skills need the CLI binary and
> credentials to work, so they're intentionally not bundled into the marketplace. Install a CLI
> (and its skill) per its own README under `CLI/`.

_Maintainers:_ `.claude-plugin/plugin.json` and `marketplace.json` are **generated** from the skills
present + the `version` in `package.json`. After adding/renaming a skill or bumping the version, run
`npm run build:marketplace` and commit — CI (`marketplace-in-sync`) fails if they drift. See `AGENTS.md`.

## Contents

### `Skills/` — Claude skills
| Skill | What it does |
|---|---|
| [`martech-teardown`](Skills/martech-teardown) | Reverse-engineer any company's martech stack from public signals and produce a structured, evidence-tagged teardown report — CMS, analytics, CDP, CRM, ads/pixels + a per-platform CAPI matrix, consent, email, enrichment, affiliate, payments — plus how their tracking, identity and ad-measurement work. Static scan + discovery-first browser audit + multi-surface sweep + public enrichment. |

### `CLI/` — command-line tools
Read-only clients that pull platform data as JSON, built for AI agents; each ships a bundled skill.
All authenticate at runtime and carry no secrets. They are **standard CLIs** — no proxy/gateway layer.

| CLI | Platform | Stack | Auth |
|---|---|---|---|
| [`google-ads-cli`](CLI/google-ads-cli) | Google Ads API | Node ESM + TypeScript | OAuth2 + developer token (env or `~/.config/google-ads-cli/credentials.json`) |
| [`microsoft-ads-cli`](CLI/microsoft-ads-cli) | Microsoft Advertising (Bing Ads) REST v13 | Node ESM + TypeScript | `auth login` browser OAuth2 (Google or Entra), token refresh |
| [`gmc-cli`](CLI/gmc-cli) | Google Merchant Center (Merchant API) | Python | Google OAuth (application-default / service account) |

Install dependencies fresh per each tool's own `README.md` (`npm i` / `pnpm i` / Python env) — build
output and dependencies are intentionally not committed.

## Open-source attribution

Some of these tools are derivative works of, or were inspired by, open-source projects — credit where due:

- **`google-ads-cli`** — derivative of [google-ads-open-cli](https://github.com/Bin-Huang/google-ads-open-cli) by Benn Huang (Apache-2.0).
- **`microsoft-ads-cli`** — rebuild of [microsoft-ads-cli](https://github.com/Bin-Huang/microsoft-ads-cli) by Benn Huang (Apache-2.0).
- **`gmc-cli`** — endpoint conventions mapped out by studying [kiwoongeom/gmc-mcp](https://github.com/kiwoongeom/gmc-mcp) (MIT).

Upstream licenses are retained in each tool's `LICENSE`/`NOTICE`.

## License

MIT for the original work in this repo; vendored CLIs retain their upstream licenses. See [`LICENSE`](LICENSE).

## Responsible use

The `martech-teardown` skill is a **competitive-intelligence** tool built on passive, public signals
(page source, DNS, sitemaps, and observing what a site loads in a normal browser). It does not log in,
submit forms, hit private APIs, or scrape behind paywalls. Use it accordingly.
