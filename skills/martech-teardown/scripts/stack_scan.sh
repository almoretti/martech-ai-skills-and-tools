#!/usr/bin/env bash
# martech-teardown :: static passive scan of a public website
# Usage: bash stack_scan.sh <domain> [out_dir]
#   <domain>  bare host, e.g. example.com  (no scheme)
#   [out_dir] where to drop artifacts (default: ./teardown-<domain>)
#
# Does NOT log in, POST, or touch anything private. Pure GET + DNS.
# Produces: home.html, gtm.js, signatures.txt, dns.txt, sitemap-index.txt,
#           sitemap-counts.txt, scan-summary.txt
set -uo pipefail

DOMAIN="${1:?usage: stack_scan.sh <domain> [out_dir]}"
DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
OUT="${2:-./teardown-$DOMAIN}"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
mkdir -p "$OUT"
echo "==> scanning $DOMAIN -> $OUT"

# ---------- 1. homepage ----------
curl -sL --max-time 40 -A "$UA" "https://$DOMAIN/" -o "$OUT/home.html"
HB=$(wc -c < "$OUT/home.html" 2>/dev/null || echo 0)
echo "home.html: $HB bytes"
if [ "${HB:-0}" -lt 2000 ]; then
  echo "  WARNING: homepage is tiny/empty ($HB bytes) — likely bot protection or a JS challenge."
  echo "  Homepage signatures will be unreliable; lean on DNS (below) and the dynamic browser audit."
fi
# bot-wall/challenge pages are often 3-10KB (past the size gate) — fingerprint them so the
# scan doesn't silently emit empty artifacts as if they were real (Canva, OpenAI, Booking, Calm).
if grep -qiE 'Access to this page has been denied|Client Challenge|px-captcha|_px[A-Za-z]|aws-waf-token|awswaf|cf-mitigated|cf_chl|Just a moment\.\.\.|Attention Required|challenge-platform|Turnstile|enable JavaScript and cookies to continue' "$OUT/home.html" 2>/dev/null; then
  echo "  WARNING: BOT-WALL / CHALLENGE page detected — this is NOT the real site HTML."
  echo "  Homepage signatures are meaningless here; rely on DNS + the dynamic browser audit."
fi

# ---------- 2. tool signatures ----------
SIGS="googletagmanager gtm.js gtag segment.com segment.io analytics.js posthog amplitude \
mixpanel heap hotjar fullstory clarity.ms hubspot hs-scripts intercom drift zendesk crisp \
fbevents fbq connect.facebook tiktok ttq analytics.tiktok linkedin licdn lintrk snaptr \
twq ads-twitter reddit rdt redditstatic pinterest bat.bing uetq mutiny 6sense demandbase \
clearbit koala getkoala rb2b vector warmly qualified zoominfo customer.io braze iterable \
klaviyo marketo pardot salesforce dreamdata hockeystack attribution cookiebot onetrust osano \
usercentrics consentmanager optimizely vwo _vis_opt launchdarkly statsig growthbook sentry \
datadog dd_anonymous rudderstack jitsu plausible fathom matomo doubleclick adsrvr criteo \
outbrain __obref taboola mountain.com stripe __stripe partnerstack __ps_ impact.com rewardful \
firstpromoter tolt dub.co webflow framer contentful sanity storyblok payloadcms wordpress \
mintlify fern readme docusaurus gitbook shopify recharge revenuecat sequel navattic storylane \
arcade appcues pendo chilipiper calendly default.com apollo outreach salesloft unify"
: > "$OUT/signatures.txt"
for s in $SIGS; do
  c=$(grep -oiF "$s" "$OUT/home.html" 2>/dev/null | wc -l | tr -d ' ')
  [ "$c" != "0" ] && printf "%-24s %s\n" "$s" "$c" >> "$OUT/signatures.txt"
done
echo "-- signatures --"; cat "$OUT/signatures.txt"

# ---------- 3. IDs (GTM / GA / Ads / pixels) ----------
{
  grep -oE 'GTM-[A-Z0-9]{5,}' "$OUT/home.html"
  grep -oE 'G-[A-Z0-9]{9,}'   "$OUT/home.html"
  grep -oE 'AW-[0-9]{9,}'     "$OUT/home.html"
} 2>/dev/null | sort -u > "$OUT/ids.txt"
echo "-- ids in homepage --"; cat "$OUT/ids.txt"

# ---------- 4. GTM container (real pixel goldmine) ----------
GTM=$(grep -oE 'GTM-[A-Z0-9]{5,}' "$OUT/home.html" 2>/dev/null | head -1)
if [ -n "${GTM:-}" ]; then
  curl -s --max-time 40 "https://www.googletagmanager.com/gtm.js?id=$GTM" -o "$OUT/gtm.js"
  echo "gtm.js ($GTM): $(wc -c < "$OUT/gtm.js") bytes"
  {
    echo "# pixel/account IDs found in GTM container:"
    grep -oE 'AW-[0-9]{9,11}'          "$OUT/gtm.js" | sort | uniq -c
    grep -oE 'G-[A-Z0-9]{10}'          "$OUT/gtm.js" | sort | uniq -c
    grep -oE '"[0-9]{15,16}"'          "$OUT/gtm.js" | sort | uniq -c | head   # FB pixel ids
    grep -oiE '(fbq|ttq|twq|rdt|lintrk|uetq|snaptr|_linkedin_partner_id)' "$OUT/gtm.js" | sort | uniq -c
  } > "$OUT/gtm-ids.txt" 2>/dev/null
  echo "-- gtm ids --"; cat "$OUT/gtm-ids.txt"
fi

# ---------- 5. platform headers ----------
curl -sI --max-time 25 -A "$UA" "https://$DOMAIN/" 2>/dev/null \
  | grep -iE 'server|x-powered-by|x-nextjs|x-vercel|via|x-region|set-cookie|content-signal' \
  > "$OUT/headers.txt"
echo "-- headers --"; cat "$OUT/headers.txt"

# ---------- 6. DNS: SPF / DKIM / verification (email + SaaS vendors) ----------
{
  echo "## TXT root (verifications + SPF):"; dig +short TXT "$DOMAIN"
  echo; echo "## DMARC:"; dig +short TXT "_dmarc.$DOMAIN"
  echo; echo "## DKIM selector probes (CNAME/TXT):"
  # Guard against wildcard/catch-all _domainkey DNS, which otherwise fabricates every ESP
  # (seen on Datadog's catch-all + Netflix echoing apex SPF). Probe a random nonce first.
  NONCE="zzq7x9nonce42"
  if [ -n "$(dig +short TXT "$NONCE._domainkey.$DOMAIN" 2>/dev/null)$(dig +short CNAME "$NONCE._domainkey.$DOMAIN" 2>/dev/null)" ]; then
    echo "(catch-all/wildcard _domainkey detected — DKIM selector probing is unreliable here; skipped)"
  else
    for s in google k1 k2 k3 s1 s2 selector1 selector2 resend cio em krs mte1 scph0323 mandrill sendgrid smtp sparkpost pm-bounces mg s1024 fdm dkim; do
      r=$( { dig +short CNAME "$s._domainkey.$DOMAIN"; dig +short TXT "$s._domainkey.$DOMAIN" | head -1 | cut -c1-80; } 2>/dev/null )
      # only report records that are actually DKIM keys or CNAMEs to a known ESP — not noise
      [ -n "$r" ] && echo "$r" | grep -qiE 'DKIM1|k=rsa|p=MI|sendgrid|mcsv|mcdlv|mailgun|mandrill|customeriomail|sparkpost|mtasv|amazonses|onmicrosoft|proofpoint|ondmarc|dkim' && echo "$s => $r"
    done
  fi
} > "$OUT/dns.txt" 2>/dev/null
echo "-- dns --"; cat "$OUT/dns.txt"

# ---------- 7. sitemap inventory (CMS / page-model shape) ----------
# gunzip-aware fetch (child sitemaps are often .xml.gz)
fetch_xml(){ local u="${1//&amp;/&}"; if [[ "$u" == *.gz ]]; then curl -sL --compressed --max-time 20 -A "$UA" "$u" 2>/dev/null | gunzip -c 2>/dev/null; else curl -sL --compressed --max-time 20 -A "$UA" "$u" 2>/dev/null; fi; }
# portable <loc> strip (BSD sed has no \?): matches <loc>, </loc>, and namespaced *:loc
strip_loc(){ sed -E 's/<[^>]*loc>//g'; }

SMURL="https://$DOMAIN/sitemap.xml"
curl -sL --max-time 30 -A "$UA" "$SMURL" -o "$OUT/sitemap.xml" 2>/dev/null
# fall back to a Sitemap: line in robots.txt if the conventional path is empty
if [ ! -s "$OUT/sitemap.xml" ] || ! grep -qiE '<(urlset|sitemapindex)' "$OUT/sitemap.xml" 2>/dev/null; then
  ALT=$(curl -sL --max-time 20 -A "$UA" "https://$DOMAIN/robots.txt" 2>/dev/null | grep -iE '^sitemap:' | head -1 | sed -E 's/^[Ss]itemap:[[:space:]]*//' | tr -d '\r')
  [ -n "$ALT" ] && { SMURL="$ALT"; fetch_xml "$ALT" > "$OUT/sitemap.xml"; }
fi

: > "$OUT/sitemap-counts.txt"
if grep -qi '<sitemapindex' "$OUT/sitemap.xml" 2>/dev/null; then
  # ROOT IS AN INDEX -> children are sitemaps; count locs in each (label by child)
  grep -oE '<loc>[^<]+</loc>' "$OUT/sitemap.xml" | strip_loc | sort -u > "$OUT/sitemap-index.txt"
  echo "-- sitemap is an INDEX of $(wc -l < "$OUT/sitemap-index.txt") child sitemaps; counting pages per child --"
  while read -r sm; do
    [ -z "$sm" ] && continue
    body=$(fetch_xml "$sm")
    # grep -c counts LINES (minified sitemaps are one line -> always "1"); grep -o counts TAGS.
    n=$(printf '%s' "$body" | grep -o '<loc>' | wc -l | tr -d ' ')
    # a child can itself be an index (nested) — mark it so the count isn't read as pages
    echo "$body" | grep -qi '<sitemapindex' && n="${n}(nested-index)"
    label=$(echo "$sm" | sed -E "s#https?://[^/]+/##; s/\.xml(\.gz)?$//")
    printf "%9s  %s\n" "$n" "$label" >> "$OUT/sitemap-counts.txt"
  done < <(head -150 "$OUT/sitemap-index.txt")
  sort -rn "$OUT/sitemap-counts.txt" -o "$OUT/sitemap-counts.txt"
else
  # ROOT IS A URLSET (flat) -> entries are pages; total + breakdown by first path segment
  grep -oE '<loc>[^<]+</loc>' "$OUT/sitemap.xml" | strip_loc > "$OUT/sitemap-index.txt"
  TOT=$(wc -l < "$OUT/sitemap-index.txt")
  echo "-- sitemap is a FLAT urlset with $TOT page URLs; top path segments --"
  sed -E "s#https?://[^/]+/##; s#\?.*##; s#/.*##" "$OUT/sitemap-index.txt" \
    | sed 's/^$/(root)/' | sort | uniq -c | sort -rn | head -25 > "$OUT/sitemap-counts.txt"
fi
head -25 "$OUT/sitemap-counts.txt" 2>/dev/null

# ---------- 8. robots ----------
curl -sL --max-time 20 -A "$UA" "https://$DOMAIN/robots.txt" -o "$OUT/robots.txt" 2>/dev/null

echo; echo "==> done. artifacts in $OUT/"
ls -1 "$OUT"
