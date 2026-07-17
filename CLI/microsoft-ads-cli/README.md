# microsoft-ads-cli

Microsoft Advertising (Bing Ads) CLI & Skills for AI agents (and humans). Pull campaign, ad group, ad, and keyword stats, navigate account hierarchies, audit conversion tracking (UET), and more — 1:1 functional parity with its sibling [google-ads-cli](https://github.com/almoretti/google-ads-cli).

**Works with:** OpenClaw, Claude Code, Cursor, Codex, and any agent that can run shell commands.

## Installation

Tell your AI agent (e.g. OpenClaw):

> Install this CLI and skills from https://github.com/almoretti/microsoft-ads-cli

Or install manually:

```bash
npm install -g microsoft-ads-cli

# Add skills for AI agents (Claude Code, Cursor, Codex, etc.)
npx skills add almoretti/microsoft-ads-cli
```

Or run directly: `npx microsoft-ads-cli --help`

## How it works

Built on the official [Bing Ads REST API v13](https://learn.microsoft.com/en-us/advertising/guides/get-started), this CLI authenticates via OAuth2 user credentials and a developer token, providing **read-only** access to the Microsoft Advertising API.

Core endpoints covered:

- **Accounts** -- list accessible ad accounts, inspect individual accounts, browse manager (customer) hierarchies
- **Campaigns & budgets** -- list campaigns with type/status filtering, shared budgets, portfolio bid strategies
- **Ad groups & ads** -- browse ad groups and ads per campaign/ad group
- **Keywords** -- list keywords and negative keywords (entity-level and shared lists)
- **Performance stats** -- campaign, ad group, ad, and keyword-level stats with date ranges and segment breakdowns (synchronous: the CLI submits the report, polls, downloads, and returns parsed JSON rows)
- **Audiences & user lists** -- audience segments and remarketing lists
- **Extensions** -- the account extension library and campaign/ad group associations
- **Conversions** -- conversion goals and UET tags
- **Raw API** -- call any read-only REST operation for data not covered by built-in commands
- **Raw reports** -- run any of the ~40 Bing report types with custom columns

## Setup

### Google-federated accounts (e.g. Google Workspace sign-in)

If you sign in to Microsoft Advertising **with a Google account**, skip Entra entirely — authenticate via Google OAuth using a Google Desktop-type OAuth client (the same one used for google-ads-cli works):

```bash
microsoft-ads-cli auth login \
  --identity-provider google \
  --developer-token=xxx \
  --client-id=xxx.apps.googleusercontent.com \
  --client-secret=xxx
```

The Google token only proves identity (scope `openid email profile`); Microsoft enforces its own authorization and the CLI sends `IdentityProvider: Google` on every request. Attempting Microsoft OAuth with a Google-federated user fails with error 126 `GoogleAccountIsRequired`.

### Microsoft accounts

```bash
microsoft-ads-cli auth login \
  --developer-token=xxx \
  --client-id=xxx
```

**How to get the values:**

1. **developer_token**: Sign in to the [Microsoft Advertising Developer Portal](https://developers.ads.microsoft.com/Account) and request a Developer Token (universal token recommended).
2. **client_id**: Go to [Microsoft Entra admin center > App registrations](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade), create a **New registration**, and under **Authentication** add a **Mobile and desktop applications** platform with redirect URI `http://localhost`. Copy the **Application (client) ID**. No client secret is needed for this public-client flow (pass `--client-secret` only if you registered a web app instead).
3. **customer_id / account_id** (optional defaults): your manager account (customer) ID and ad account ID, saved into the credentials file with `--customer-id` / `--account-id`. Most campaign commands take the account ID as an argument anyway.

This opens your browser for Microsoft authorization. Sign in with an account that has access to the Microsoft Advertising data you want to use. After you approve, credentials are saved to `~/.config/microsoft-ads-cli/credentials.json` and all subsequent commands work automatically. Tokens are refreshed as needed.

### Alternative: Environment variables

For CI/CD or automation, you can set credentials via environment variables (no auto-refresh):

```bash
export MICROSOFT_ADS_ACCESS_TOKEN="your_oauth2_access_token"
export MICROSOFT_ADS_DEVELOPER_TOKEN="your_developer_token"
export MICROSOFT_ADS_CUSTOMER_ID="123456789"   # optional
export MICROSOFT_ADS_ACCOUNT_ID="987654321"    # optional
```

## Entity hierarchy

Microsoft Advertising uses this hierarchy:

```
Customer (manager account)
 └── Ad Account (AccountId)
      ├── Campaign
      │    └── Ad Group
      │         ├── Ad
      │         └── Keyword
      ├── Shared Budget
      ├── Conversion Goal (via UET Tag)
      ├── Audience (remarketing lists etc.)
      └── Ad Extension (sitelinks, callouts, images, etc.)
```

Two IDs matter: the **customer ID** (manager account) and the **account ID** (ad account). Most commands take the account ID as the first argument; the customer ID is read from your credentials file when needed.

## Monetary values

Unlike Google Ads (micros), Bing reports return monetary values (Spend, AverageCpc, Revenue) as **plain decimal amounts** in the account currency. No conversion needed.

## Usage

All commands output pretty-printed JSON by default. Use `--format compact` for single-line JSON.

### accounts

List accessible ad accounts (Active + Paused by default).

```bash
microsoft-ads-cli accounts
microsoft-ads-cli accounts --all-statuses
```

### account

Get a specific ad account.

```bash
microsoft-ads-cli account 987654321
```

### account-hierarchy

List advertiser accounts under a manager account (customer).

```bash
microsoft-ads-cli account-hierarchy 123456789
```

### user

Get the authenticated user (a good credentials check).

```bash
microsoft-ads-cli user
```

### campaigns

List campaigns for an ad account.

```bash
microsoft-ads-cli campaigns 987654321
microsoft-ads-cli campaigns 987654321 --type Search --status Active
```

Options:
- `--type <type>`: Search, Shopping, Audience, DynamicSearchAds, PerformanceMax (default all)
- `--status <status>`: Active, Paused, BudgetPaused, BudgetAndManualPaused, Suspended

### campaign

Get a specific campaign.

```bash
microsoft-ads-cli campaign 987654321 111222333
```

### campaign-budgets

List shared campaign budgets.

```bash
microsoft-ads-cli campaign-budgets 987654321
```

### bid-strategies

List portfolio bid strategies.

```bash
microsoft-ads-cli bid-strategies 987654321
```

### ad-groups

List ad groups for a campaign (Bing requires the campaign ID).

```bash
microsoft-ads-cli ad-groups 987654321 111222333
```

### ad-group

Get a specific ad group.

```bash
microsoft-ads-cli ad-group 987654321 111222333 444555666
```

### ads

List ads for an ad group.

```bash
microsoft-ads-cli ads 987654321 444555666
microsoft-ads-cli ads 987654321 444555666 --type ResponsiveSearch
```

### ad

Get a specific ad.

```bash
microsoft-ads-cli ad 987654321 444555666 777888999
```

### campaign-stats

Get campaign performance stats. The CLI submits a Bing report, polls until it completes, downloads it, and outputs parsed JSON rows.

```bash
microsoft-ads-cli campaign-stats 987654321 --start 2026-01-01 --end 2026-01-31
microsoft-ads-cli campaign-stats 987654321 --start 2026-01-01 --end 2026-01-31 --campaign 111222333 --segments device
```

Options:
- `--start <date>` / `--end <date>`: date range (YYYY-MM-DD) **required**
- `--campaign <id>`: filter by campaign ID
- `--segments <segs>`: additional segments (comma-separated): device, network, device_os, top_vs_other
- `--granularity <gran>`: Daily (default), Weekly, Monthly, Summary, Hourly
- `--columns <cols>`: override the report columns entirely
- `--timeout <seconds>`: max wait (default 120)

Default columns: TimePeriod, AccountId, CampaignId, CampaignName, CampaignStatus, Impressions, Clicks, Ctr, Spend, AverageCpc, Conversions, ConversionRate, CostPerConversion, Revenue

### ad-group-stats / ad-stats / keyword-stats

Same pattern at ad group, ad, and keyword level. All support `--campaign`, `--ad-group` (requires `--campaign`), `--segments`, `--granularity`, `--columns`, `--timeout`.

```bash
microsoft-ads-cli ad-group-stats 987654321 --start 2026-01-01 --end 2026-01-31
microsoft-ads-cli ad-stats 987654321 --start 2026-01-01 --end 2026-01-31 --campaign 111222333
microsoft-ads-cli keyword-stats 987654321 --start 2026-01-01 --end 2026-01-31 --segments delivered_match_type
```

### keywords

List keywords for an ad group.

```bash
microsoft-ads-cli keywords 987654321 444555666
```

### audiences

List audience segments (all types by default).

```bash
microsoft-ads-cli audiences 987654321
microsoft-ads-cli audiences 987654321 --type InMarket,Custom
```

### user-lists

List remarketing lists.

```bash
microsoft-ads-cli user-lists 987654321
```

### negative-keywords

List shared negative keyword lists, or entity-level negative keywords.

```bash
microsoft-ads-cli negative-keywords 987654321                       # shared lists
microsoft-ads-cli negative-keywords 987654321 --campaign 111222333  # attached to a campaign
microsoft-ads-cli negative-keyword-items 987654321 555              # items in a shared list
```

### extensions

List ad extensions in the account library.

```bash
microsoft-ads-cli extensions 987654321
microsoft-ads-cli extensions 987654321 --type SitelinkAdExtension,CalloutAdExtension
```

### extension-associations

List which extensions are attached to which campaigns/ad groups.

```bash
microsoft-ads-cli extension-associations 987654321 --ids 111222333 --entity Campaign
```

### conversion-goals

List conversion goals.

```bash
microsoft-ads-cli conversion-goals 987654321
microsoft-ads-cli conversion-goals 987654321 --type Event,Url
```

### uet-tags

List UET (Universal Event Tracking) tags.

```bash
microsoft-ads-cli uet-tags 987654321
```

### labels

List account labels.

```bash
microsoft-ads-cli labels 987654321
```

### api

Call any **read-only** Bing Ads REST operation. This is the escape hatch for data not covered by built-in commands (Bing has no query language like GAQL, so raw operations fill that role). Write operations are refused.

```bash
microsoft-ads-cli api customer User/Query --body '{"UserId": null}'
microsoft-ads-cli api campaign Campaigns/QueryByAccountId --account-id 987654321 \
  --body '{"AccountId": "987654321", "CampaignType": "Search"}'
```

Services: `campaign`, `customer`, `reporting`, `adInsight`, `bulk`. See the [operation reference](https://learn.microsoft.com/en-us/advertising/campaign-management-service/campaign-management-service-operations) (each operation page's REST tab shows the path).

### report

Run any Bing report type with custom columns (see [report types](https://learn.microsoft.com/en-us/advertising/reporting-service/reporting-service-reference)).

```bash
microsoft-ads-cli report 987654321 \
  --type SearchQueryPerformanceReportRequest \
  --columns TimePeriod,CampaignName,SearchQuery,Impressions,Clicks,Spend \
  --start 2026-01-01 --end 2026-01-31
```

Options: `--granularity`, `--timeout`, `--async` (submit only, returns the report ID for later `report-status` / `report-download`).

### report-status / report-download

Manage async reports submitted with `report --async`.

```bash
microsoft-ads-cli report-status 12345_abcdef
microsoft-ads-cli report-download 12345_abcdef
```

## Command mapping vs google-ads-cli

| google-ads-cli | microsoft-ads-cli | Notes |
| --- | --- | --- |
| `customers` | `accounts` | |
| `customer` | `account` | |
| `account-hierarchy` | `account-hierarchy` | |
| `campaigns` / `campaign` | `campaigns` / `campaign` | |
| `campaign-budgets` | `campaign-budgets` | Bing budgets are shared budgets |
| `ad-groups` / `ad-group` | `ad-groups` / `ad-group` | Bing requires the campaign ID |
| `ads` / `ad` | `ads` / `ad` | Bing requires the ad group ID |
| `*-stats` | `*-stats` | Bing runs async reports under the hood; the CLI makes them synchronous |
| `keywords` | `keywords` | |
| `audiences` / `user-lists` | `audiences` / `user-lists` | |
| `negative-keywords` | `negative-keywords` (+ `negative-keyword-items`) | |
| `assets` / `extensions` | `extensions` / `extension-associations` | Bing models these as ad extensions |
| `conversion-actions` | `conversion-goals` (+ `uet-tags`) | |
| `query` (GAQL) | `api` + `report` | Bing has no query language |
| `billing` | — | No REST equivalent in Bing Ads API v13 |
| `change-status` | — | No change-history API in Bing Ads API v13 |

## Error output

All errors are JSON to stderr:

```json
{"error": "No credentials found. Provide one of: ..."}
```

## API Reference

- [Microsoft Advertising API Overview](https://learn.microsoft.com/en-us/advertising/guides/get-started)
- [Campaign Management Service](https://learn.microsoft.com/en-us/advertising/campaign-management-service/campaign-management-service-reference)
- [Customer Management Service](https://learn.microsoft.com/en-us/advertising/customer-management-service/customer-management-service-reference)
- [Reporting Service](https://learn.microsoft.com/en-us/advertising/reporting-service/reporting-service-reference)
- [Authentication with OAuth](https://learn.microsoft.com/en-us/advertising/guides/authentication-oauth)

## Attribution

This is an personal rebuild of [microsoft-ads-cli](https://github.com/Bin-Huang/microsoft-ads-cli)
by Benn Huang, used under the Apache-2.0 license. See [`NOTICE`](./NOTICE) for the
list of modifications. The original copyright and license are retained in [`LICENSE`](./LICENSE).

## Related

- [google-ads-cli](https://github.com/almoretti/google-ads-cli) -- the sibling Google Ads CLI this one mirrors

## License

Apache-2.0
