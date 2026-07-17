# MartechAITools — martech skills & CLIs for AI agents

A personal, vendor-neutral collection of marketing-technology tooling for AI agents (and humans).
Two kinds of tool live here, one per subfolder:

- **`skills/`** — Claude skills (self-contained instruction packages: `SKILL.md` + bundled scripts/references/assets).
- **`CLI/`** — standalone command-line tools (read-only ad-platform / merchant clients), each installable on its own.

Everything here is generic and personal — no employer-specific accounts, secrets, or branding.
Credentials are always supplied at runtime (env vars / local credential files), never committed.

---

## skills/

### `martech-teardown`
Reverse-engineer any company's marketing-technology stack from public signals and produce a
structured teardown report — what tools they run across every martech space (CMS, analytics, CDP,
CRM, ads/pixels, consent, email, enrichment, affiliate, payments) and how their tracking, identity,
and ad-measurement work.
- **How it works:** static passive scan (`scripts/stack_scan.sh` — curl + GTM container + DNS/SPF/DKIM
  + sitemap) → discovery-first browser audit (`scripts/tracking_audit.mjs` — Playwright; captures the
  dataLayer, every host, first-party-proxied analytics, cookies, and a per-platform CAPI matrix) →
  multi-surface sweep (docs/careers/help/status/pricing) → public enrichment (job posts + case studies)
  → evidence-tagged report (`references/report-structure.md`, neutral HTML template in `assets/`).
- **Principle:** discovery over checklist — capture everything and classify; never read "0 hits" as
  "no tracking"; tag every claim Confirmed / Inferred / Assumed with its evidence.
- **Entry point:** `skills/martech-teardown/SKILL.md`.

---

## CLI/

Read-only clients that pull data from ad / merchant platforms as JSON — built for AI agents, each
with a bundled skill under its own `skills/` folder. All authenticate at runtime; none carries secrets.

| CLI | Platform | Stack | Auth |
|---|---|---|---|
| `google-ads-cli` | Google Ads API | Node ESM + commander (TS) | OAuth2 + developer token (env or `~/.config/google-ads-cli/credentials.json`) |
| `microsoft-ads-cli` | Microsoft Advertising (Bing Ads) REST v13 | Node ESM + commander (TS) | `auth login` browser OAuth2 (Google or Entra) with token refresh |
| `gmc-cli` | Google Merchant Center (Merchant API) | Python + `pyproject.toml` | Google OAuth (application-default / service account) |

Each is a **standard CLI** — no proxy/gateway/broker layer. Build/run per its own README
(`CLI/<name>/README.md`). `node_modules`, build output, virtualenvs and any secrets were intentionally
excluded from this copy — install deps fresh (`npm i` / `pnpm i` / `uv`/`pip`).

---

## Open-source attribution

These tools are derivative works / were inspired by open-source projects — credit where due:

- **`google-ads-cli`** — derivative of **[google-ads-open-cli](https://github.com/Bin-Huang/google-ads-open-cli)**
  by Benn Huang, Apache-2.0. See `CLI/google-ads-cli/NOTICE`.
- **`microsoft-ads-cli`** — rebuild of **[microsoft-ads-cli](https://github.com/Bin-Huang/microsoft-ads-cli)**
  by Benn Huang, Apache-2.0. See `CLI/microsoft-ads-cli/NOTICE`.
- **`gmc-cli`** — endpoint conventions mapped out by studying **[kiwoongeom/gmc-mcp](https://github.com/kiwoongeom/gmc-mcp)** (MIT).

Upstream licenses are retained in each tool's `LICENSE`/`NOTICE`.

---

## Notes for Claude working here
- Each subfolder is its own self-contained tool — read its `SKILL.md` / `README.md` before changing it.
- Keep everything **generic**: no employer accounts, IDs, tokens, or branding. Credentials stay at runtime.
- When adding a tool that derives from OSS, add its attribution to the tool's `NOTICE` **and** the list above.
- New skills go in `skills/<name>/`; new CLIs go in `CLI/<name>/`.
- The repo is a **Claude Code plugin marketplace**: `.claude-plugin/marketplace.json` is *generated*
  from every `SKILL.md` present. After adding/renaming/removing a skill, run
  `node scripts/build-marketplace.mjs` and commit — the `marketplace-in-sync` GitHub Action fails if
  it drifts. Install flow: `/plugin marketplace add almoretti/martech-ai-skills-and-tools` →
  `/plugin install <skill>@martech-ai-skills-and-tools`.
