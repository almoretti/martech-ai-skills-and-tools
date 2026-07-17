# Changelog

## 0.1.0 — 2026-07-09

Initial release.

- Full read surface for Merchant API v1: accounts, products, data sources,
  promotions, regions, quotas, return policies.
- Reports API with raw queries plus shortcuts: performance, zero-clicks,
  price-competitiveness, price-insights, best-sellers, demoted, competitors —
  all query shapes verified against the live API (v1 field renames and
  required-field rules handled).
- Minimal, guarded write surface: `products insert/delete` (delete requires
  `--yes`), `datasources fetch`; global `--dry-run` prints the exact HTTP
  request instead of sending it.
- `gmc auth login` browser OAuth flow storing credentials in
  `~/.config/gmc-cli/credentials.json`; service-account and ADC fallbacks.
- `gmc register-gcp` for the mandatory one-time developer registration of the
  GCP project with the merchant account.
- `gmc raw` escape hatch for any Merchant API endpoint.
- Retries with exponential backoff + `Retry-After` on 429/5xx; automatic
  pagination; JSON-only output.
