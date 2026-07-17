#!/usr/bin/env bash
# Full functional test of gmc-cli. Reads run live; writes run --dry-run only.
PASS=0; FAIL=0; RESULTS=""

check() { # check <name> <jq-ish python assertion> ... runs command, validates JSON + assertion
  local name="$1"; shift
  local assertion="$1"; shift
  local out
  if out="$("$@" 2>/tmp/gmc_test_err)"; then
    if echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert $assertion, 'assertion failed'
" 2>/tmp/gmc_test_err2; then
      PASS=$((PASS+1)); RESULTS+="PASS  $name"$'\n'; return
    fi
  fi
  FAIL=$((FAIL+1))
  RESULTS+="FAIL  $name :: $(tail -1 /tmp/gmc_test_err 2>/dev/null)$(tail -1 /tmp/gmc_test_err2 2>/dev/null)"$'\n'
}

expect_fail() { # command must exit non-zero (guard rails)
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); RESULTS+="FAIL  $name :: expected refusal but succeeded"$'\n'
  else
    PASS=$((PASS+1)); RESULTS+="PASS  $name (correctly refused)"$'\n'
  fi
}

# ---- discover merchant + real IDs to use
MERCHANT=$(gmc auth check 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)['merchant_id'])")
[ -n "$MERCHANT" ] || { echo "no merchant configured — run gmc auth login first"; exit 1; }
ACCOUNT_NAME=$(gmc account get 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('accountName',''))")
echo "testing against merchant $MERCHANT ($ACCOUNT_NAME)"
# ---- discover real IDs to use
PRODUCT_ID=$(gmc products list --limit 1 2>/dev/null | python3 -c "import json,sys
p=json.load(sys.stdin)['products']
print(p[0]['id'] if p else '')")
DS_NAME=$(gmc datasources list 2>/dev/null | python3 -c "import json,sys
ds=json.load(sys.stdin)['dataSources']
print(ds[0]['name'] if ds else '')")
DS_ID="${DS_NAME##*/}"
PROMO_ID=$(gmc promotions list 2>/dev/null | python3 -c "import json,sys
pr=json.load(sys.stdin).get('promotions') or []
print(pr[0]['name'].split('/')[-1] if pr else '')")
echo "using product=$PRODUCT_ID ds=$DS_ID promo=$PROMO_ID"

# ---- auth
check "auth check"                    "d['ok'] and d['merchant_id']=='$MERCHANT'" gmc auth check
# ---- account
check "account get"                   "d.get('name')"                             gmc account get
check "account list"                  "len(d['accounts'])>=1"                     gmc account list
check "account issues"                "'count' in d"                              gmc account issues
check "account users"                 "len(d['users'])>=1"                        gmc account users
check "account programs"              "len(d['programs'])>=1"                     gmc account programs
check "account shipping"              "isinstance(d,dict)"                        gmc account shipping
check "account homepage"              "'uri' in d or 'name' in d"                 gmc account homepage
check "account business-info"         "isinstance(d,dict)"                        gmc account business-info
# ---- products (read)
check "products list"                 "d['count']>0 and d['products'][0]['id']"   gmc products list --limit 5
check "products list --full"          "'productAttributes' in d['products'][0]"   gmc products list --limit 2 --full
if [ -n "$PRODUCT_ID" ]; then
check "products get"                  "d.get('name')"                             gmc products get "$PRODUCT_ID"
check "products status"               "'status' in d"                             gmc products status "$PRODUCT_ID"
fi
check "products disapproved"          "'count' in d"                              gmc products disapproved
check "products issues-summary"       "'scanned' in d"                            gmc products issues-summary
# ---- products (write, dry-run only)
if [ -n "$DS_NAME" ]; then
check "products insert (dry-run)"     "d.get('_dry_run')==True"                   gmc --dry-run products insert --product '{"offerId":"TEST","contentLanguage":"en","feedLabel":"GB"}' --data-source "$DS_NAME"
check "products delete (dry-run)"     "d.get('_dry_run')==True"                   gmc --dry-run products delete "${PRODUCT_ID:-en~GB~TEST}" --data-source "$DS_NAME"
expect_fail "products delete w/o --yes refused"                                   gmc products delete "${PRODUCT_ID:-en~GB~TEST}" --data-source "$DS_NAME"
fi
# ---- reports
check "report query (raw)"            "d['count']>0"                              gmc report query "SELECT id FROM product_view LIMIT 5"
check "report performance"            "'count' in d"                              gmc report performance --start 2026-07-01 --end 2026-07-08 --top 5
check "report performance order-by"   "'count' in d"                              gmc report performance --start 2026-07-01 --end 2026-07-08 --order-by impressions --top 3
check "report zero-clicks"            "'count' in d"                              gmc report zero-clicks --min-impressions 500
check "report price-competitiveness"  "'count' in d"                              gmc report price-competitiveness --top 5
check "report price-insights"         "'count' in d"                              gmc report price-insights --top 5
check "report best-sellers"           "'count' in d"                              gmc report best-sellers --top 5
check "report best-sellers MONTHLY"   "'count' in d"                              gmc report best-sellers --granularity MONTHLY --top 3
check "report demoted"                "'count' in d"                              gmc report demoted
check "report competitors"            "'count' in d"                              gmc report competitors --top 5
check "report competitors ADS"        "'count' in d"                              gmc report competitors --traffic-source ADS --top 5
# ---- datasources
check "datasources list"              "len(d['dataSources'])>=1"                  gmc datasources list
if [ -n "$DS_ID" ]; then
check "datasources get"               "d.get('name')"                             gmc datasources get "$DS_ID"
check "datasources fetch (dry-run)"   "isinstance(d,dict)"                        gmc --dry-run datasources fetch "$DS_ID"
fi
# ---- promotions / regions / quotas / return-policies
check "promotions list"               "isinstance(d,dict)"                        gmc promotions list
if [ -n "$PROMO_ID" ]; then
check "promotions get"                "d.get('name')"                             gmc promotions get "$PROMO_ID"
fi
check "regions"                       "'regions' in d"                            gmc regions
check "quotas"                        "len(d['quotaGroups'])>0"                   gmc quotas
check "return-policies"               "'onlineReturnPolicies' in d"         gmc return-policies
# ---- raw escape hatch
check "raw GET"                       "d.get('name')"             gmc raw GET accounts/v1/accounts/$MERCHANT
check "raw GET with --param"          "len(d.get('products',[]))==2"              gmc raw GET products/v1/accounts/$MERCHANT/products --param pageSize=2
check "raw POST (dry-run)"            "d.get('_dry_run')==True"                   gmc --dry-run raw POST reports/v1/accounts/$MERCHANT/reports:search --body '{"query":"SELECT id FROM product_view LIMIT 1"}'
# ---- flag / guard behaviour
check "--merchant-id override"        "d['merchant_id']=='$MERCHANT'"             gmc --merchant-id "$MERCHANT" auth check
check "--account alias still works"   "d['merchant_id']=='$MERCHANT'"             gmc --account "$MERCHANT" auth check
expect_fail "non-numeric merchant-id refused"                                     gmc --merchant-id abc account get
expect_fail "bad report query errors cleanly"                                     gmc report query "SELECT bogus_field FROM product_view"
expect_fail "products get bad id errors cleanly"                                  gmc products get "en~GB~does-not-exist-xyz"

echo
echo "$RESULTS"
echo "---- $PASS passed, $FAIL failed ----"
[ "$FAIL" -eq 0 ]
