#!/usr/bin/env python3
"""gmc — Google Merchant Center CLI (Merchant API v1).

A standalone, auditable CLI for the Google Merchant API v1
(https://merchantapi.googleapis.com). Credentials never leave this machine.

Auth (first match wins):
  1. GMC_SERVICE_ACCOUNT_KEY — path to a service-account JSON key
  2. GMC_OAUTH_TOKEN         — path to a user OAuth token file
  3. ~/.config/gmc-cli/credentials.json (created by `gmc auth login`)
  4. Application Default Credentials (gcloud auth application-default login)

Config via environment or a .env file in the working directory:
  GMC_ACCOUNT_ID       Merchant Center account ID
  GMC_SUBACCOUNT_ID    optional sub-account to act on (MCA setups)

All output is JSON on stdout; diagnostics go to stderr. Pipe to jq.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
import warnings
from pathlib import Path
from typing import Any

from . import __version__

# ADC-without-quota-project warning is harmless here (Merchant API bills the
# Merchant Center account, not a GCP quota project)
warnings.filterwarnings("ignore", message=".*quota project.*")

BASE_URL = "https://merchantapi.googleapis.com"
SCOPES = ["https://www.googleapis.com/auth/content"]
RETRYABLE = {429, 500, 502, 503, 504}
MAX_ATTEMPTS = 5
CONFIG_DIR = Path.home() / ".config" / "gmc-cli"
CONFIG_PATH = CONFIG_DIR / "credentials.json"
GADS_CONFIG_PATH = Path.home() / ".config" / "google-ads-cli" / "credentials.json"


def load_saved_config() -> dict[str, Any]:
    if CONFIG_PATH.is_file():
        try:
            return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except ValueError:
            die(f"corrupt config file: {CONFIG_PATH} — delete it and re-run `gmc auth login`")
    return {}


# ---------------------------------------------------------------- env / config

def load_dotenv() -> None:
    """Minimal .env loader: working directory only. Never overrides real env."""
    for candidate in (Path.cwd() / ".env",):
        if not candidate.is_file():
            continue
        for line in candidate.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip().strip("'\"")
            if key and key not in os.environ:
                os.environ[key] = value


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def account_id(args: argparse.Namespace) -> str:
    saved = load_saved_config()
    acct = (
        getattr(args, "merchant_id", None)
        or os.environ.get("GMC_SUBACCOUNT_ID", "").strip()
        or os.environ.get("GMC_ACCOUNT_ID", "").strip()
        or str(saved.get("merchant_id") or saved.get("account_id") or "")
    )
    if not acct:
        die(
            "no merchant ID configured. Run `gmc auth login --merchant-id <id>`, "
            "set GMC_ACCOUNT_ID in .env, or pass --merchant-id. (The numeric ID "
            "is in the top-right of https://merchants.google.com)"
        )
    if not acct.isdigit():
        die(f"merchant ID must be numeric, got '{acct}'")
    return acct


# ---------------------------------------------------------------------- auth

def get_credentials():
    from google.auth.transport.requests import Request  # noqa: F401 (validated import)

    sa_key = os.environ.get("GMC_SERVICE_ACCOUNT_KEY", "").strip()
    if sa_key:
        path = Path(sa_key).expanduser()
        if not path.exists():
            die(f"GMC_SERVICE_ACCOUNT_KEY points to a missing file: {path}")
        from google.oauth2 import service_account

        return service_account.Credentials.from_service_account_file(
            str(path), scopes=SCOPES
        ), f"service-account:{path.name}"

    token = os.environ.get("GMC_OAUTH_TOKEN", "").strip()
    if token:
        path = Path(token).expanduser()
        if not path.exists():
            die(f"GMC_OAUTH_TOKEN points to a missing file: {path}. Run `gmc auth init`.")
        from google.oauth2.credentials import Credentials as UserCredentials

        data = json.loads(path.read_text(encoding="utf-8"))
        creds = UserCredentials.from_authorized_user_info(data, SCOPES)
        return creds, f"oauth-user:{path.name}"

    saved = load_saved_config()
    if saved.get("refresh_token"):
        from google.oauth2.credentials import Credentials as UserCredentials

        creds = UserCredentials.from_authorized_user_info(saved, SCOPES)
        return creds, f"oauth-user:{CONFIG_PATH}"

    try:
        import google.auth

        creds, project = google.auth.default(scopes=SCOPES)
        return creds, f"adc:{project or 'unknown-project'}"
    except Exception as e:
        die(
            "no credentials found. Run `gmc auth login --client-id … "
            f"--client-secret …`, or set GMC_SERVICE_ACCOUNT_KEY in .env. ({e})"
        )


class Client:
    def __init__(self, args: argparse.Namespace):
        self.acct = account_id(args)
        self.dry_run = bool(getattr(args, "dry_run", False))
        self.verbose = bool(getattr(args, "verbose", False))
        self._creds, self.auth_label = get_credentials()
        import requests

        self._session = requests.Session()
        self._session.headers["User-Agent"] = f"gmc-cli/{__version__}"
        from google.auth.transport.requests import Request

        self._auth_request = Request()

    @property
    def base(self) -> str:
        return f"accounts/{self.acct}"

    def _token(self) -> str:
        if not self._creds.valid:
            self._creds.refresh(self._auth_request)
        return self._creds.token

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        body: Any | None = None,
    ) -> Any:
        url = f"{BASE_URL}/{path.lstrip('/')}"
        is_write = method.upper() in {"POST", "PUT", "PATCH", "DELETE"}

        if is_write and self.dry_run:
            print(f"dry-run: {method} {url}", file=sys.stderr)
            return {"_dry_run": True, "method": method, "url": url,
                    "params": params, "body": body}

        last_err = None
        for attempt in range(MAX_ATTEMPTS):
            try:
                resp = self._session.request(
                    method, url, params=params, json=body, timeout=60,
                    headers={"Authorization": f"Bearer {self._token()}"},
                )
            except Exception as e:
                last_err = str(e)
                time.sleep(min(2 ** attempt, 30) + random.uniform(0, 0.5))
                continue

            if resp.status_code in RETRYABLE and attempt < MAX_ATTEMPTS - 1:
                wait = float(resp.headers.get("Retry-After") or min(2 ** attempt, 30))
                if self.verbose:
                    print(f"retry {attempt + 1}: HTTP {resp.status_code}, "
                          f"waiting {wait:.0f}s", file=sys.stderr)
                time.sleep(wait + random.uniform(0, 0.5))
                continue

            if resp.status_code == 204:
                return {}
            try:
                payload = resp.json()
            except ValueError:
                payload = {"_raw": resp.text}

            if not (200 <= resp.status_code < 300):
                err = payload.get("error", {}) if isinstance(payload, dict) else {}
                msg = err.get("message") or json.dumps(payload)[:500]
                die(f"Merchant API HTTP {resp.status_code} on {method} {path}: {msg}")
            return payload

        die(f"exhausted retries on {method} {path}: {last_err}")

    def paginate(
        self,
        path: str,
        items_key: str,
        *,
        params: dict[str, Any] | None = None,
        limit: int | None = None,
    ) -> list[dict[str, Any]]:
        params = dict(params or {})
        params.setdefault("pageSize", 250)
        items: list[dict[str, Any]] = []
        while True:
            payload = self.request("GET", path, params=params)
            items.extend(payload.get(items_key, []) or [])
            if limit is not None and len(items) >= limit:
                return items[:limit]
            token = payload.get("nextPageToken")
            if not token:
                return items
            params["pageToken"] = token

    def report(self, query: str, max_pages: int = 20) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        body: dict[str, Any] = {"query": query}
        for _ in range(max_pages):
            payload = self.request(
                "POST", f"reports/v1/{self.base}/reports:search", body=body
            )
            results.extend(payload.get("results", []) or [])
            token = payload.get("nextPageToken")
            if not token:
                break
            body = {"query": query, "pageToken": token}
        return results


def emit(data: Any) -> None:
    json.dump(data, sys.stdout, indent=2, ensure_ascii=False)
    print()


def read_json_arg(raw: str) -> Any:
    """Accept inline JSON, @file.json, or '-' for stdin."""
    if raw == "-":
        return json.load(sys.stdin)
    if raw.startswith("@"):
        return json.loads(Path(raw[1:]).expanduser().read_text(encoding="utf-8"))
    return json.loads(raw)


# ------------------------------------------------------------------- commands

def cmd_auth_check(args):
    c = Client(args)
    info = c.request("GET", f"accounts/v1/{c.base}")
    emit({
        "auth": c.auth_label,
        "merchant_id": c.acct,
        "accountName": info.get("accountName"),
        "adultContent": info.get("adultContent"),
        "timeZone": info.get("timeZone"),
        "ok": True,
    })


def cmd_auth_login(args):
    """Browser OAuth flow, google-ads-cli style. Saves ~/.config/gmc-cli/credentials.json."""
    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError:
        die("missing dependency — run: "
            "pip install google-auth-oauthlib")

    client_id, client_secret = args.client_id, args.client_secret
    if not (client_id and client_secret):
        # reuse the saved gmc-cli client, else the google-ads-cli one
        for source in (load_saved_config(),
                       json.loads(GADS_CONFIG_PATH.read_text(encoding="utf-8"))
                       if GADS_CONFIG_PATH.is_file() else {}):
            if source.get("client_id") and source.get("client_secret"):
                client_id = client_id or source["client_id"]
                client_secret = client_secret or source["client_secret"]
                print("reusing OAuth client from saved credentials", file=sys.stderr)
                break
    if not (client_id and client_secret):
        die(
            "pass --client-id and --client-secret.\n"
            "  Create them: GCP Console → APIs & Services → Credentials → "
            "Create Credentials → OAuth client ID → Desktop app.\n"
            "  Also enable the Merchant API in the same project:\n"
            "  https://console.cloud.google.com/apis/library/merchantapi.googleapis.com"
        )

    flow = InstalledAppFlow.from_client_config(
        {
            "installed": {
                "client_id": client_id,
                "client_secret": client_secret,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "redirect_uris": ["http://localhost"],
            }
        },
        SCOPES,
    )
    creds = flow.run_local_server(port=0)

    data = json.loads(creds.to_json())
    prior = load_saved_config()
    merchant = args.merchant_id or prior.get("merchant_id") or prior.get("account_id")
    if merchant:
        data["merchant_id"] = merchant
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
    os.chmod(CONFIG_PATH, 0o600)
    print(f"credentials saved to {CONFIG_PATH}", file=sys.stderr)
    if not merchant:
        print("tip: persist your Merchant Center ID too: "
              "gmc auth login --merchant-id 1234567890 (or set GMC_ACCOUNT_ID)",
              file=sys.stderr)


def cmd_auth_init(args):
    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
    except ImportError:
        die("run: pip install google-auth-oauthlib  (only needed for `auth init`)")
    secrets = Path(args.client_secrets).expanduser()
    if not secrets.exists():
        die(f"client secrets file not found: {secrets}\n"
            "Create an OAuth 'Desktop app' client in GCP Console → Credentials "
            "and download its JSON.")
    flow = InstalledAppFlow.from_client_secrets_file(str(secrets), SCOPES)
    creds = flow.run_local_server(port=0)
    out = Path(args.output).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(creds.to_json(), encoding="utf-8")
    os.chmod(out, 0o600)
    print(f"token written to {out}", file=sys.stderr)
    print(f"add to .env: GMC_OAUTH_TOKEN={out}", file=sys.stderr)


def cmd_register_gcp(args):
    """One-time link of the OAuth client's GCP project to the merchant account.

    Required before any Merchant API v1 call works for a new project.
    Idempotent — re-running returns the existing registration.
    """
    c = Client(args)
    body = {"developerEmail": args.developer_email} if args.developer_email else {}
    emit(c.request(
        "POST", f"accounts/v1/{c.base}/developerRegistration:registerGcp",
        body=body,
    ))


def cmd_account_get(args):
    c = Client(args)
    emit(c.request("GET", f"accounts/v1/{c.base}"))


def cmd_account_list(args):
    c = Client(args)
    emit({"accounts": c.paginate("accounts/v1/accounts", "accounts")})


def cmd_account_issues(args):
    c = Client(args)
    issues = c.paginate(
        f"accounts/v1/{c.base}/issues", "accountIssues",
        params={"languageCode": args.language},
    )
    emit({"count": len(issues), "issues": issues})


def cmd_account_users(args):
    c = Client(args)
    emit({"users": c.paginate(f"accounts/v1/{c.base}/users", "users")})


def cmd_account_programs(args):
    c = Client(args)
    emit({"programs": c.paginate(f"accounts/v1/{c.base}/programs", "programs")})


def cmd_account_shipping(args):
    c = Client(args)
    emit(c.request("GET", f"accounts/v1/{c.base}/shippingSettings"))


def cmd_account_homepage(args):
    c = Client(args)
    emit(c.request("GET", f"accounts/v1/{c.base}/homepage"))


def cmd_account_business_info(args):
    c = Client(args)
    emit(c.request("GET", f"accounts/v1/{c.base}/businessInfo"))


def cmd_products_list(args):
    c = Client(args)
    items = c.paginate(f"products/v1/{c.base}/products", "products", limit=args.limit)
    if not args.full:
        slim = []
        for p in items:
            attrs = p.get("productAttributes") or {}
            price = attrs.get("price") or {}
            slim.append({
                "id": p.get("name", "").split("/")[-1],
                "offerId": p.get("offerId"),
                "title": attrs.get("title"),
                "price": f"{price.get('amountMicros', '')} {price.get('currencyCode', '')}".strip(),
                "availability": attrs.get("availability"),
                "feedLabel": p.get("feedLabel"),
                "dataSource": p.get("dataSource"),
            })
        emit({"count": len(items), "products": slim,
              "_hint": "use --full for complete product objects"})
    else:
        emit({"count": len(items), "products": items})


def cmd_products_get(args):
    c = Client(args)
    emit(c.request("GET", f"products/v1/{c.base}/products/{args.product_id}"))


def cmd_products_status(args):
    c = Client(args)
    p = c.request("GET", f"products/v1/{c.base}/products/{args.product_id}")
    emit({
        "product_id": args.product_id,
        "title": (p.get("productAttributes") or {}).get("title"),
        "status": p.get("productStatus", {}),
    })


def cmd_products_disapproved(args):
    c = Client(args)
    query = (
        "SELECT id, offer_id, title, aggregated_reporting_context_status, item_issues "
        "FROM product_view "
        "WHERE aggregated_reporting_context_status = 'NOT_ELIGIBLE_OR_DISAPPROVED'"
    )
    rows = c.report(query, max_pages=args.max_pages)
    emit({"count": len(rows), "results": rows, "_query": query})


def cmd_products_issues_summary(args):
    from collections import Counter
    c = Client(args)
    query = (
        "SELECT id, offer_id, title, aggregated_reporting_context_status, item_issues "
        "FROM product_view "
        "WHERE aggregated_reporting_context_status != 'ELIGIBLE'"
    )
    rows = c.report(query, max_pages=args.max_pages)
    status, codes, attrs, severity = Counter(), Counter(), Counter(), Counter()
    for row in rows:
        pv = row.get("productView", {})
        status[pv.get("aggregatedReportingContextStatus", "UNKNOWN")] += 1
        for issue in pv.get("itemIssues", []) or []:
            itype = issue.get("type") or {}
            codes[itype.get("code") or "unknown"] += 1
            if itype.get("canonicalAttribute"):
                attrs[itype["canonicalAttribute"]] += 1
            severity[(issue.get("severity") or {}).get("aggregatedSeverity", "UNKNOWN")] += 1
    emit({
        "scanned": len(rows),
        "status_breakdown": dict(status.most_common()),
        "severity_breakdown": dict(severity.most_common()),
        "top_issue_codes": dict(codes.most_common(30)),
        "top_affected_attributes": dict(attrs.most_common(30)),
    })


def cmd_products_insert(args):
    c = Client(args)
    product = read_json_arg(args.product)
    emit(c.request(
        "POST", f"products/v1/{c.base}/productInputs:insert",
        params={"dataSource": args.data_source}, body=product,
    ))


def cmd_products_delete(args):
    c = Client(args)
    if not args.yes and not c.dry_run:
        die("refusing to delete without --yes (or use --dry-run to preview)")
    result = c.request(
        "DELETE", f"products/v1/{c.base}/productInputs/{args.product_id}",
        params={"dataSource": args.data_source},
    )
    emit(result if c.dry_run else {"deleted": args.product_id})


def cmd_report_query(args):
    c = Client(args)
    rows = c.report(args.query, max_pages=args.max_pages)
    emit({"count": len(rows), "query": args.query, "results": rows})


def _report_shortcut(c: Client, query: str, max_pages: int = 20):
    rows = c.report(query, max_pages=max_pages)
    emit({"count": len(rows), "query": query, "results": rows})


def cmd_report_performance(args):
    c = Client(args)
    _report_shortcut(c, (
        "SELECT offer_id, title, clicks, impressions, click_through_rate, conversions, "
        "conversion_value FROM product_performance_view "
        f"WHERE date BETWEEN '{args.start}' AND '{args.end}' "
        f"ORDER BY {args.order_by} DESC LIMIT {args.top}"
    ))


def cmd_report_zero_clicks(args):
    from datetime import date, timedelta
    c = Client(args)
    start = args.start or (date.today() - timedelta(days=30)).isoformat()
    end = args.end or date.today().isoformat()
    _report_shortcut(c, (
        "SELECT offer_id, title, impressions, clicks, click_through_rate "
        "FROM product_performance_view "
        f"WHERE date BETWEEN '{start}' AND '{end}' "
        f"AND impressions >= {args.min_impressions} AND clicks = 0 "
        "ORDER BY impressions DESC LIMIT 200"
    ))


def cmd_report_price_competitiveness(args):
    c = Client(args)
    _report_shortcut(c, (
        "SELECT report_country_code, id, offer_id, title, price, benchmark_price "
        f"FROM price_competitiveness_product_view LIMIT {args.top}"
    ))


def cmd_report_price_insights(args):
    c = Client(args)
    _report_shortcut(c, (
        "SELECT id, offer_id, title, suggested_price, "
        "predicted_impressions_change_fraction, predicted_clicks_change_fraction, "
        "predicted_conversions_change_fraction "
        f"FROM price_insights_product_view LIMIT {args.top}"
    ))


def cmd_report_best_sellers(args):
    c = Client(args)
    _report_shortcut(c, (
        "SELECT report_date, report_granularity, report_country_code, "
        "report_category_id, title, brand, rank, previous_rank, relative_demand "
        "FROM best_sellers_product_cluster_view "
        f"WHERE report_country_code = '{args.country}' "
        f"AND report_granularity = '{args.granularity}' "
        f"ORDER BY rank LIMIT {args.top}"
    ))


def cmd_report_demoted(args):
    c = Client(args)
    _report_shortcut(c, (
        "SELECT id, offer_id, title, item_issues FROM product_view "
        "WHERE aggregated_reporting_context_status = 'ELIGIBLE_LIMITED' "
        f"LIMIT {args.top}"
    ))


def cmd_report_competitors(args):
    from datetime import date, timedelta
    c = Client(args)
    start = args.start or (date.today() - timedelta(days=30)).isoformat()
    end = args.end or date.today().isoformat()
    _report_shortcut(c, (
        "SELECT report_country_code, report_category_id, traffic_source, "
        "domain, rank, ads_organic_ratio, page_overlap_rate, higher_position_rate "
        "FROM competitive_visibility_top_merchant_view "
        f"WHERE report_country_code = '{args.country}' "
        f"AND traffic_source = '{args.traffic_source}' "
        f"AND report_category_id = {args.category} "
        f"AND date BETWEEN '{start}' AND '{end}' "
        f"ORDER BY rank LIMIT {args.top}"
    ))


def cmd_datasources_list(args):
    c = Client(args)
    emit({"dataSources": c.paginate(
        f"datasources/v1/{c.base}/dataSources", "dataSources")})


def cmd_datasources_get(args):
    c = Client(args)
    emit(c.request("GET", f"datasources/v1/{c.base}/dataSources/{args.datasource_id}"))


def cmd_datasources_fetch(args):
    c = Client(args)
    c.request("POST", f"datasources/v1/{c.base}/dataSources/{args.datasource_id}:fetch")
    emit({"fetch_triggered": args.datasource_id})


def cmd_promotions_list(args):
    c = Client(args)
    emit({"promotions": c.paginate(f"promotions/v1/{c.base}/promotions", "promotions")})


def cmd_promotions_get(args):
    c = Client(args)
    emit(c.request("GET", f"promotions/v1/{c.base}/promotions/{args.promotion_id}"))


def cmd_regions_list(args):
    c = Client(args)
    emit({"regions": c.paginate(f"accounts/v1/{c.base}/regions", "regions")})


def cmd_quotas_list(args):
    c = Client(args)
    emit({"quotaGroups": c.paginate(f"quota/v1/{c.base}/quotas", "quotaGroups")})


def cmd_return_policies_list(args):
    c = Client(args)
    emit({"onlineReturnPolicies": c.paginate(
        f"accounts/v1/{c.base}/onlineReturnPolicies", "onlineReturnPolicies")})


def cmd_raw(args):
    c = Client(args)
    body = read_json_arg(args.body) if args.body else None
    params = dict(kv.split("=", 1) for kv in (args.param or []))
    emit(c.request(args.method.upper(), args.path, params=params or None, body=body))


# --------------------------------------------------------------------- parser

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gmc",
        description="Google Merchant Center CLI (Merchant API v1). "
                    "JSON to stdout — pipe to jq.",
    )
    p.add_argument("--version", action="version", version=f"gmc-cli {__version__}")
    p.add_argument("--merchant-id", "--account", dest="merchant_id",
                   help="Merchant Center ID (overrides saved config / env)")
    p.add_argument("--dry-run", action="store_true",
                   help="print writes instead of sending them")
    p.add_argument("-v", "--verbose", action="store_true")
    sub = p.add_subparsers(dest="cmd", required=True)

    # auth
    auth = sub.add_parser("auth", help="credential utilities").add_subparsers(
        dest="sub", required=True)
    auth.add_parser("check", help="verify credentials + account access") \
        .set_defaults(func=cmd_auth_check)
    al = auth.add_parser(
        "login",
        help="browser OAuth flow (google-ads-cli style) → "
             "~/.config/gmc-cli/credentials.json")
    al.add_argument("--client-id", help="OAuth Desktop-app client ID")
    al.add_argument("--client-secret", help="OAuth Desktop-app client secret")
    al.add_argument("--merchant-id", "--account", dest="merchant_id",
                    help="Merchant Center ID to persist alongside")
    al.set_defaults(func=cmd_auth_login)
    ai = auth.add_parser("init", help="OAuth flow from a client-secrets JSON file")
    ai.add_argument("--client-secrets", required=True,
                    help="OAuth Desktop-app client JSON from GCP Console")
    ai.add_argument("--output", default=str(CONFIG_DIR / "token.json"))
    ai.set_defaults(func=cmd_auth_init)

    rg = sub.add_parser(
        "register-gcp",
        help="one-time: register the GCP project with the merchant account "
             "(required before v1 API calls work)")
    rg.add_argument("--developer-email",
                    help="email for Google's critical service announcements")
    rg.set_defaults(func=cmd_register_gcp)

    # account
    acct = sub.add_parser("account", help="account settings & issues") \
        .add_subparsers(dest="sub", required=True)
    acct.add_parser("get").set_defaults(func=cmd_account_get)
    acct.add_parser("list", help="all accounts your credential can access") \
        .set_defaults(func=cmd_account_list)
    ai2 = acct.add_parser("issues", help="account-level issues")
    ai2.add_argument("--language", default="en")
    ai2.set_defaults(func=cmd_account_issues)
    acct.add_parser("users").set_defaults(func=cmd_account_users)
    acct.add_parser("programs").set_defaults(func=cmd_account_programs)
    acct.add_parser("shipping").set_defaults(func=cmd_account_shipping)
    acct.add_parser("homepage").set_defaults(func=cmd_account_homepage)
    acct.add_parser("business-info").set_defaults(func=cmd_account_business_info)

    # products
    prod = sub.add_parser("products", help="product catalogue") \
        .add_subparsers(dest="sub", required=True)
    pl = prod.add_parser("list")
    pl.add_argument("--limit", type=int, default=100)
    pl.add_argument("--full", action="store_true", help="complete product objects")
    pl.set_defaults(func=cmd_products_list)
    pg = prod.add_parser("get", help="product ID: channel~lang~feedLabel~offerId")
    pg.add_argument("product_id")
    pg.set_defaults(func=cmd_products_get)
    ps = prod.add_parser("status", help="approval status + item issues")
    ps.add_argument("product_id")
    ps.set_defaults(func=cmd_products_status)
    pd = prod.add_parser("disapproved", help="all disapproved products (via Reports)")
    pd.add_argument("--max-pages", type=int, default=20)
    pd.set_defaults(func=cmd_products_disapproved)
    pi = prod.add_parser("issues-summary", help="aggregate issue codes by frequency")
    pi.add_argument("--max-pages", type=int, default=20)
    pi.set_defaults(func=cmd_products_issues_summary)
    pin = prod.add_parser("insert", help="insert/upsert a product input (WRITE)")
    pin.add_argument("--product", required=True,
                     help="inline JSON, @file.json, or - for stdin")
    pin.add_argument("--data-source", required=True,
                     help="full name: accounts/123/dataSources/456")
    pin.set_defaults(func=cmd_products_insert)
    pdel = prod.add_parser("delete", help="delete a product input (WRITE)")
    pdel.add_argument("product_id")
    pdel.add_argument("--data-source", required=True)
    pdel.add_argument("--yes", action="store_true")
    pdel.set_defaults(func=cmd_products_delete)

    # report
    rep = sub.add_parser("report", help="Reports API (SQL-like queries)") \
        .add_subparsers(dest="sub", required=True)
    rq = rep.add_parser("query", help="raw Merchant reports query")
    rq.add_argument("query")
    rq.add_argument("--max-pages", type=int, default=20)
    rq.set_defaults(func=cmd_report_query)
    rp = rep.add_parser("performance", help="clicks/impressions/conversions by product")
    rp.add_argument("--start", required=True, help="YYYY-MM-DD")
    rp.add_argument("--end", required=True, help="YYYY-MM-DD")
    rp.add_argument("--order-by", default="clicks",
                    choices=["clicks", "impressions", "click_through_rate", "conversions",
                             "conversion_value"])
    rp.add_argument("--top", type=int, default=100)
    rp.set_defaults(func=cmd_report_performance)
    rz = rep.add_parser("zero-clicks", help="impressions but no clicks")
    rz.add_argument("--min-impressions", type=int, default=100)
    rz.add_argument("--start", help="YYYY-MM-DD (default: 30 days ago)")
    rz.add_argument("--end", help="YYYY-MM-DD (default: today)")
    rz.set_defaults(func=cmd_report_zero_clicks)
    rpc = rep.add_parser("price-competitiveness")
    rpc.add_argument("--top", type=int, default=100)
    rpc.set_defaults(func=cmd_report_price_competitiveness)
    rpi = rep.add_parser("price-insights", help="Google's suggested prices")
    rpi.add_argument("--top", type=int, default=100)
    rpi.set_defaults(func=cmd_report_price_insights)
    rbs = rep.add_parser("best-sellers")
    rbs.add_argument("--country", default="GB")
    rbs.add_argument("--granularity", default="WEEKLY", choices=["WEEKLY", "MONTHLY"])
    rbs.add_argument("--top", type=int, default=100)
    rbs.set_defaults(func=cmd_report_best_sellers)
    rd = rep.add_parser("demoted", help="eligible but suppressed products")
    rd.add_argument("--top", type=int, default=200)
    rd.set_defaults(func=cmd_report_demoted)
    rc = rep.add_parser("competitors", help="who outranks you on Shopping")
    rc.add_argument("--country", default="GB")
    rc.add_argument("--category", type=int, default=469,
                    help="Google product category ID (default 469 = Health & Beauty)")
    rc.add_argument("--traffic-source", default="ALL",
                    choices=["ALL", "ADS", "ORGANIC"])
    rc.add_argument("--start", help="YYYY-MM-DD (default: 30 days ago)")
    rc.add_argument("--end", help="YYYY-MM-DD (default: today)")
    rc.add_argument("--top", type=int, default=50)
    rc.set_defaults(func=cmd_report_competitors)

    # datasources
    ds = sub.add_parser("datasources", help="feeds / data sources") \
        .add_subparsers(dest="sub", required=True)
    ds.add_parser("list").set_defaults(func=cmd_datasources_list)
    dg = ds.add_parser("get")
    dg.add_argument("datasource_id")
    dg.set_defaults(func=cmd_datasources_get)
    df = ds.add_parser("fetch", help="trigger a re-fetch of a scheduled feed (WRITE)")
    df.add_argument("datasource_id")
    df.set_defaults(func=cmd_datasources_fetch)

    # promotions / regions / quotas / return-policies
    prom = sub.add_parser("promotions").add_subparsers(dest="sub", required=True)
    prom.add_parser("list").set_defaults(func=cmd_promotions_list)
    pmg = prom.add_parser("get")
    pmg.add_argument("promotion_id")
    pmg.set_defaults(func=cmd_promotions_get)

    sub.add_parser("regions", help="list regions") \
        .set_defaults(func=cmd_regions_list)
    sub.add_parser("quotas", help="API quota usage/limits") \
        .set_defaults(func=cmd_quotas_list)
    sub.add_parser("return-policies", help="list online return policies") \
        .set_defaults(func=cmd_return_policies_list)

    # raw escape hatch
    raw = sub.add_parser(
        "raw", help="raw Merchant API call, e.g. "
        "`gmc raw GET accounts/v1/accounts/123/issues`")
    raw.add_argument("method", choices=["GET", "POST", "PATCH", "PUT", "DELETE",
                                        "get", "post", "patch", "put", "delete"])
    raw.add_argument("path", help="path under merchantapi.googleapis.com")
    raw.add_argument("--body", help="inline JSON, @file.json, or - for stdin")
    raw.add_argument("--param", action="append", help="query param key=value")
    raw.set_defaults(func=cmd_raw)

    return p


def main() -> None:
    load_dotenv()
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
