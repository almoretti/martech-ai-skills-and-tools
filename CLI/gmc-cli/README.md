# gmc-cli — Google Merchant Center CLI

[![CI](https://github.com/almoretti/gmc-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/almoretti/gmc-cli/actions/workflows/ci.yml)
[![PyPI](https://img.shields.io/pypi/v/gmc-cli)](https://pypi.org/project/gmc-cli/)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

A standalone command-line client for the **Google Merchant API v1**
(`merchantapi.googleapis.com`) — the GA replacement for the Content API for
Shopping, which Google retires in August 2026.

Drive your Merchant Center from the terminal (or from an AI agent): products,
feeds, performance reports, price benchmarks, promotions, account settings.
One auditable codebase, credentials never leave your machine, all output is
JSON on stdout — pipe it to `jq`.

```bash
pipx install gmc-cli

gmc auth login --client-id=… --client-secret=… --merchant-id=1234567890
gmc register-gcp          # one-time Google requirement, see below

gmc products issues-summary | jq '.top_issue_codes'
gmc report performance --start 2026-06-01 --end 2026-06-30 --order-by clicks
```

## Why

- **CLI, not SaaS**: no third-party service proxies your Merchant Center data.
- **Merchant API v1**: built on the new GA API, not the deprecated Content API v2.1.
- **Read-first safety model**: only three write commands exist, deletes require
  `--yes`, and a global `--dry-run` prints the exact HTTP request instead of
  sending it.
- **Agent-friendly**: predictable JSON output and one flat command tree make it
  easy to hand to Claude/other AI agents as a tool.

## Install

```bash
pipx install gmc-cli        # recommended (isolated)
# or: pip install gmc-cli
```

From source:

```bash
git clone https://github.com/almoretti/gmc-cli && cd gmc-cli
./setup.sh                  # local venv + editable install; run via ./gmc
```

## Setup

### 1. Create an OAuth client (one-time, ~3 minutes)

1. Go to [Google Cloud Console](https://console.cloud.google.com) → pick or create a project.
2. Enable the [Merchant API](https://console.cloud.google.com/apis/library/merchantapi.googleapis.com).
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID → Desktop app.** Copy the client ID and secret.
4. If the OAuth consent screen is in *Testing* mode, add yourself as a test
   user (and note refresh tokens expire after 7 days until you publish the app
   to *In production*).

### 2. Log in

```bash
gmc auth login --client-id=xxx --client-secret=xxx --merchant-id=1234567890
```

Opens a browser — sign in with a Google account that has access to your
Merchant Center (the numeric merchant ID is in the top-right of
[merchants.google.com](https://merchants.google.com)). Credentials are saved
to `~/.config/gmc-cli/credentials.json` (chmod 600) and refresh automatically.

### 3. Register your GCP project (one-time, mandatory)

Google requires the GCP project behind your OAuth client to be registered as a
developer with the merchant account, or **every API call returns 401**:

```bash
gmc register-gcp --developer-email you@example.com
gmc auth check    # should print your account name and "ok": true
```

Idempotent — safe to re-run.

### Alternative credentials

- **Service account** (headless automation): set `GMC_SERVICE_ACCOUNT_KEY` to a
  JSON key path, and add the service account's email as a user in Merchant
  Center → Settings → People and access.
- **Env/dotenv**: `GMC_ACCOUNT_ID`, `GMC_SUBACCOUNT_ID` (act on an MCA
  sub-account), `GMC_OAUTH_TOKEN`. A `.env` in the working directory is read.
- **ADC fallback**: `gcloud auth application-default login` with the
  `content` scope.

Resolution order: `GMC_SERVICE_ACCOUNT_KEY` → `GMC_OAUTH_TOKEN` →
`~/.config/gmc-cli/credentials.json` → ADC. Merchant ID: `--merchant-id` →
`GMC_SUBACCOUNT_ID`/`GMC_ACCOUNT_ID` → saved config.

## Commands

```
gmc auth login | check | init --client-secrets FILE
gmc register-gcp [--developer-email EMAIL]        # one-time per GCP project
gmc account get | list | issues | users | programs | shipping | homepage | business-info
gmc products list [--limit N] [--full]
gmc products get|status ID                        # ID = contentLanguage~feedLabel~offerId
gmc products disapproved                          # all disapproved products (via Reports)
gmc products issues-summary                       # issue codes ranked by frequency
gmc products insert --product @p.json --data-source accounts/…/dataSources/…   (WRITE)
gmc products delete ID --data-source … --yes                                   (WRITE)
gmc report query "SELECT … FROM product_performance_view WHERE …"
gmc report performance --start YYYY-MM-DD --end YYYY-MM-DD [--order-by clicks] [--top N]
gmc report zero-clicks [--min-impressions N] [--start …] [--end …]
gmc report price-competitiveness | price-insights | demoted
gmc report best-sellers [--country GB] [--granularity WEEKLY|MONTHLY]
gmc report competitors [--country GB] [--category 469] [--traffic-source ALL|ADS|ORGANIC]
gmc datasources list | get ID | fetch ID          # fetch = WRITE, triggers feed re-crawl
gmc promotions list | get ID
gmc regions | quotas | return-policies
gmc raw GET|POST|PATCH|PUT|DELETE <path> [--body JSON] [--param k=v]   # escape hatch
```

Global flags: `--merchant-id ID`, `--dry-run` (print writes instead of
sending), `-v` (retry diagnostics), `--version`.

Defaults note: report shortcuts default to `--country GB` and `--category 469`
(Health & Beauty) — override for your market
([category IDs](https://support.google.com/merchants/answer/6324436)).

## Examples

```bash
# What's broken in my feed, ranked by issue code?
gmc products issues-summary | jq '.top_issue_codes'

# Top products by clicks, last 30 days, as TSV
gmc report performance --start 2026-06-09 --end 2026-07-08 \
  | jq -r '.results[].productPerformanceView | [.offerId, .clicks, .impressions] | @tsv'

# Where am I priced above the market benchmark?
gmc report price-competitiveness | jq '.results[].priceCompetitivenessProductView
  | select((.price.amountMicros|tonumber) > (.benchmarkPrice.amountMicros|tonumber))'

# Force an immediate re-fetch of a scheduled feed
gmc datasources list | jq -r '.dataSources[].dataSourceId'
gmc datasources fetch 123456789

# Preview a product upsert without sending it
gmc --dry-run products insert --product @sku.json --data-source accounts/…/dataSources/…

# Anything the built-ins don't cover
gmc raw GET conversions/v1/accounts/1234567890/conversionSources
```

## Safety model

- Reads are unrestricted; **writes** exist only for `products insert/delete`
  and `datasources fetch`; delete requires `--yes`.
- Global `--dry-run` short-circuits any write and prints the exact request.
- Retries with exponential backoff + `Retry-After` on 429/5xx.
- `gmc raw` can perform any method — use deliberately.
- Product inserts only work against API-type data sources; feeds fetched from
  files/Sheets can't be written via the API (use `datasources fetch` to
  trigger re-crawls instead, or overlay a supplemental API data source).

## Merchant API v1 notes (learned the hard way)

- Product IDs: `contentLanguage~feedLabel~offerId` (e.g. `en~GB~SKU123`).
- Product writes go through `productInputs:insert` (upsert — full body
  overwrites) and always require a `dataSource`.
- v1 vs v1beta field changes: `gtin` → `gtins` (list), `attributes` →
  `productAttributes`, enums are UPPER_CASE strings, `channel`/`taxes` removed.
- Report dialect rules (all verified live; the built-in shortcuts handle them):
  - `ctr` → `click_through_rate`; `conversion_value_micros` → `conversion_value`
  - `product_performance_view` **requires** a `date` condition in WHERE
  - `price_competitiveness_product_view` requires `report_country_code` + `id` in SELECT
  - `price_insights_product_view` requires `id` in SELECT
  - `best_sellers_*` requires `report_date`, `report_granularity`,
    `report_country_code`, `report_category_id` in SELECT and a
    `report_granularity` WHERE condition
  - `competitive_visibility_*` requires `report_country_code`,
    `report_category_id`, `traffic_source` in SELECT and WHERE conditions on
    `date`, `report_category_id`, `traffic_source`

## Testing

`./test.sh` runs a 45-check functional suite against whatever merchant account
you're logged into: every read command live, every write in `--dry-run` only,
plus the guard rails. It never mutates your feed.

## Acknowledgements

Endpoint conventions were originally mapped out by studying
[kiwoongeom/gmc-mcp](https://github.com/kiwoongeom/gmc-mcp) (MIT), an MCP
server for the same API. No code was copied; this project exists for people
who want a plain CLI with no MCP layer.

## License

Apache-2.0
