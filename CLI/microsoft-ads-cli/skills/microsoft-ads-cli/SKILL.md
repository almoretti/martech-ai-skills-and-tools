---
name: microsoft-ads-cli
description: >
  Microsoft Ads (Bing Ads) data analysis and reporting via microsoft-ads-cli.
  Use when the user wants to check Microsoft/Bing ad performance, pull campaign/ad group/keyword stats,
  explore ad account structure, inspect audiences, audit UET conversion tracking, or retrieve performance reports.
  Triggers: "Microsoft Ads", "Bing Ads", "Microsoft Advertising", "bing ad performance", "microsoft campaign stats",
  "microsoft ad spend", "bing keywords", "microsoft audiences", "UET tags", "microsoft conversion goals",
  "bing search ads", "microsoft shopping ads", "microsoft performance max".
---

# Microsoft Ads CLI Skill

You have access to `microsoft-ads-cli`, a read-only CLI for the Bing Ads REST API v13. It mirrors `google-ads-cli` 1:1 — same command names and shapes wherever the Bing API allows. Use it to query ad accounts, pull performance stats (parsed to JSON rows), inspect audiences and extensions, and audit UET conversion tracking across Search, Shopping, Audience, DynamicSearchAds, and PerformanceMax campaigns.

## Quick start

```bash
# Check if the CLI is available
microsoft-ads-cli --help

# Verify credentials (authenticated user info)
microsoft-ads-cli user

# List accessible ad accounts
microsoft-ads-cli accounts
```

If the CLI is not installed, install it:

```bash
npm install -g microsoft-ads-cli
```

## Authentication

The CLI uses OAuth2 user credentials plus a Microsoft Advertising **Developer Token**. Credentials are stored in `~/.config/microsoft-ads-cli/credentials.json` with auto-refreshing tokens.

Before running any command, verify credentials by running `microsoft-ads-cli user`. If it fails with a credentials error, ask the user to set up authentication:

```bash
microsoft-ads-cli auth login \
  --developer-token=xxx \
  --client-id=xxx
```

How to get the values:

1. **developer_token**: [Microsoft Advertising Developer Portal](https://developers.ads.microsoft.com/Account) → request a Developer Token.
2. **client_id**: [Microsoft Entra app registrations](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) → New registration → Authentication → add a **Mobile and desktop applications** platform with redirect URI `http://localhost`. No client secret needed (public client). Pass `--client-secret` only for web-app registrations.

This opens a browser for Microsoft authorization. After approval, credentials save automatically and tokens refresh as needed.

Optional defaults saved into the credentials file: `--customer-id` (manager account) and `--account-id` (ad account). The CustomerId header is filled from the credentials file when set.

Alternative: set `MICROSOFT_ADS_ACCESS_TOKEN` and `MICROSOFT_ADS_DEVELOPER_TOKEN` environment variables (useful for CI/CD; no auto-refresh).

## Entity hierarchy and IDs

```
Customer (manager account)         ← customer ID
 └── Ad Account                    ← account ID (first arg of most commands)
      ├── Campaign
      │    └── Ad Group
      │         ├── Ad
      │         └── Keyword
      ├── Shared Budget / Bid Strategy
      ├── Conversion Goal (via UET Tag)
      ├── Audience
      └── Ad Extension
```

- Most commands take the **ad account ID** as the first positional argument.
- Bing's API requires parent IDs: `ad-groups` needs the campaign ID, `ads`/`keywords` need the ad group ID. Walk the hierarchy: `campaigns` → `ad-groups` → `ads`/`keywords`.
- Monetary values (Spend, AverageCpc, Revenue) are **plain decimal amounts** in the account currency — no micros conversion (unlike Google Ads).

## Commands

### Account structure

```bash
microsoft-ads-cli accounts                          # list accessible ad accounts
microsoft-ads-cli accounts --all-statuses           # include Draft/Inactive/Pending
microsoft-ads-cli account <account-id>              # one account's details
microsoft-ads-cli account-hierarchy [customer-id]   # advertiser accounts under a manager account
microsoft-ads-cli user                              # authenticated user (credentials check)
```

### Campaign structure

```bash
microsoft-ads-cli campaigns <account-id> [--type Search] [--status Active]
microsoft-ads-cli campaign <account-id> <campaign-id>
microsoft-ads-cli campaign-budgets <account-id>
microsoft-ads-cli bid-strategies <account-id>
microsoft-ads-cli ad-groups <account-id> <campaign-id>
microsoft-ads-cli ad-group <account-id> <campaign-id> <ad-group-id>
microsoft-ads-cli ads <account-id> <ad-group-id> [--type ResponsiveSearch]
microsoft-ads-cli ad <account-id> <ad-group-id> <ad-id>
microsoft-ads-cli keywords <account-id> <ad-group-id>
```

Campaign types: Search, Shopping, Audience, DynamicSearchAds, PerformanceMax.
Campaign statuses: Active, Paused, BudgetPaused, BudgetAndManualPaused, Suspended.

### Performance stats

These are synchronous: the CLI submits a Bing report, polls, downloads, and outputs `{reportRequestId, rowCount, rows: [...]}` with rows as JSON objects. Expect a few seconds up to ~1 minute of wall time.

```bash
microsoft-ads-cli campaign-stats <account-id> --start 2026-01-01 --end 2026-01-31
microsoft-ads-cli campaign-stats <account-id> --start ... --end ... --campaign <id> --segments device
microsoft-ads-cli ad-group-stats <account-id> --start ... --end ... [--campaign <id>] [--ad-group <id>]
microsoft-ads-cli ad-stats <account-id> --start ... --end ...
microsoft-ads-cli keyword-stats <account-id> --start ... --end ... --segments delivered_match_type
```

Shared options:
- `--segments`: device, network, device_os, top_vs_other (keyword-stats also: bid_match_type, delivered_match_type)
- `--granularity`: Daily (default), Weekly, Monthly, Summary, Hourly
- `--columns`: override report columns entirely (comma-separated Bing report column names)
- `--timeout <seconds>`: default 120

Notes:
- `--ad-group` requires `--campaign` (Bing report scopes need the full path).
- All numeric values in rows come back as strings (CSV-sourced) — parse before doing math.
- Percentages like Ctr come formatted (e.g. "1.23%").

### Audiences, negatives, extensions, conversions

```bash
microsoft-ads-cli audiences <account-id> [--type InMarket,Custom]
microsoft-ads-cli user-lists <account-id>                              # remarketing lists
microsoft-ads-cli negative-keywords <account-id>                       # shared negative keyword lists
microsoft-ads-cli negative-keywords <account-id> --campaign <id>       # attached to a campaign
microsoft-ads-cli negative-keyword-items <account-id> <list-id>        # items in a shared list
microsoft-ads-cli extensions <account-id> [--type SitelinkAdExtension]
microsoft-ads-cli extension-associations <account-id> --ids <campaign-ids> [--entity Campaign]
microsoft-ads-cli conversion-goals <account-id> [--type Event,Url] [--tag-ids <ids>]
microsoft-ads-cli uet-tags <account-id>
microsoft-ads-cli labels <account-id>
```

### Escape hatches (no GAQL on Bing)

For anything not covered above, call raw read-only REST operations or run any Bing report type:

```bash
# Raw API call — services: campaign, customer, reporting, adInsight, bulk
microsoft-ads-cli api campaign Campaigns/QueryByAccountId --account-id <id> \
  --body '{"AccountId": "<id>", "CampaignType": "Search"}'

# Any report type + custom columns (e.g. search terms)
microsoft-ads-cli report <account-id> \
  --type SearchQueryPerformanceReportRequest \
  --columns TimePeriod,CampaignName,SearchQuery,Impressions,Clicks,Spend \
  --start 2026-01-01 --end 2026-01-31

# Async report management
microsoft-ads-cli report <account-id> --type ... --columns ... --start ... --end ... --async
microsoft-ads-cli report-status <report-id>
microsoft-ads-cli report-download <report-id>
```

The `api` command refuses write operations — only `Query*`, `Search`, and `GenerateReport/*` paths are allowed. Find operation paths in the [Campaign Management operations list](https://learn.microsoft.com/en-us/advertising/campaign-management-service/campaign-management-service-operations) (REST tab on each page).

Useful report types: `SearchQueryPerformanceReportRequest` (search terms), `AgeGenderAudienceReportRequest`, `GeographicPerformanceReportRequest`, `AudiencePerformanceReportRequest`, `ProductDimensionPerformanceReportRequest` (shopping), `BudgetSummaryReportRequest`. Column names per type: [Reporting Service reference](https://learn.microsoft.com/en-us/advertising/reporting-service/reporting-service-reference).

## Output & errors

- All output is JSON on stdout (`--format compact` for single-line).
- All errors are JSON on stderr: `{"error": "..."}` with exit code 1.
- Empty stats result (`rowCount: 0`) usually means no delivery in the date range, not an error.

## Not available on Bing

- **Billing / account budgets** — no REST equivalent; use the Microsoft Advertising UI.
- **Change history** — no API; use the UI's Change History page.

## Related docs

- [microsoft-ads-cli documentation](https://github.com/almoretti/microsoft-ads-cli)
- [Bing Ads API Getting Started](https://learn.microsoft.com/en-us/advertising/guides/get-started)
- [Authentication with OAuth](https://learn.microsoft.com/en-us/advertising/guides/authentication-oauth)
- [Campaign Management Service](https://learn.microsoft.com/en-us/advertising/campaign-management-service/campaign-management-service-reference)
- [Reporting Service](https://learn.microsoft.com/en-us/advertising/reporting-service/reporting-service-reference)
- [Customer Management Service](https://learn.microsoft.com/en-us/advertising/customer-management-service/customer-management-service-reference)
