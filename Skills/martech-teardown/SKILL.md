---
name: martech-teardown
description: >-
  Reverse-engineer any company's marketing-technology stack from public signals
  and produce a structured teardown report — what tools they run across every
  martech space (CMS, analytics, CDP, CRM, ads/pixels, consent, email, enrichment,
  affiliate, payments) and how their tracking, identity, and ad-measurement actually
  work. Use this WHENEVER the user names a brand, competitor, or website and wants
  to understand, audit, map, analyze, or "tear down" its martech / adtech / growth
  stack — including phrasings like "what tools does X use", "analyze X's marketing
  stack", "how is X tracking users", "do a martech teardown of X", "what CMS/CDP/
  analytics does X run", "reverse engineer X's tracking", or "compare our stack to X".
  Trigger even if the user only gives a domain and says "audit this". Personal skill;
  keep every report generic and vendor-neutral unless the user supplies their own org
  context to compare against.
---

# Martech teardown

Turn a bare brand name or URL into an evidence-backed picture of the company's entire
marketing-technology stack, plus how their tracking, identity resolution, and ad
measurement are wired. The output is a competitive-intelligence report built from
**public pages, the live tag container, DNS records, the sitemap, and the running
site's own network traffic** — never from anything private.

## Operating principle

A teardown is only as good as its evidence. Every tool you name must trace back to a
concrete signal — a cookie, a header, a DNS record, a tag ID, a network request, or a
vendor-published case study. Always separate **what you observed** from **what you
infer**, and tag every claim Confirmed / Inferred / Assumed. That honesty is the whole
value; a confident-but-wrong stack list is worse than a short accurate one.

## Ethics & scope (read once, hold throughout)

- Passive, public signals only: GET requests, DNS, sitemaps, and observing what the
  site itself loads in a normal browser. This is standard competitive intelligence.
- **Do not** attempt logins, submit forms, hit private/authenticated APIs, probe for
  vulnerabilities, or scrape behind a paywall.
- The authenticated audit path exists ONLY for the operator's **own** account on a
  service they use, to see how *their own* dataLayer changes when logged in. Never use
  anyone else's credentials, and never use it to harvest personal data — the point is
  the tracking architecture, not the account contents.

## Inputs to confirm

1. **Target** — brand name or domain (derive the apex domain if given a name).
2. **Depth** — default to **comprehensive, and aim for the same breadth every run**:
   static scan + multi-surface coverage + dynamic audit + public enrichment (Steps 1–4,
   all of them). Only drop to a "quick" static-only pass if the operator explicitly asks —
   and if you do, add a **scope note** to the report so a lean output reads as "this pass
   didn't look there", never "the company has less tech". Run the coverage checklist below
   before writing.
3. **Output** — Markdown (default) or a self-contained HTML report (the neutral
   *MartechTearDown* template at `assets/report-template.html`).
4. **Comparison context** (optional) — if the operator wants "vs. us" takeaways, ask
   for their own stack + any constraints (e.g. regulated-industry PII rules) and honor
   them in the lessons section. Absent that, keep the report vendor-neutral.

### Coverage checklist (hit all of these before writing, so runs are consistent)
- [ ] Static scan of the **real marketing host** (follow redirects / robots `Sitemap:` host)
- [ ] **Multi-surface** sweep: docs · careers/ATS · help · blog · pricing/contact-sales · checkout/cart
- [ ] DNS / SPF / DKIM (the CRM/MAP/ESP layer — invisible client-side)
- [ ] Dynamic browser audit (dataLayer, all hosts, first-party proxy, per-platform CAPI matrix)
- [ ] Public **enrichment**: job posts + vendor case studies (Step 3)
- [ ] (Optional) authenticated pass on the operator's own account
Anything you couldn't cover → say so explicitly in the report rather than implying absence.

## Workflow

### Step 1 — Static passive scan
Run the bundled script; it fetches the homepage, greps ~120 tool signatures, pulls and
parses the live GTM container for pixel/account IDs, reads platform headers, probes
DNS/SPF/DKIM for email + SaaS vendors, and walks the sitemap to reveal the CMS page model.

```bash
bash scripts/stack_scan.sh <domain> <out_dir>
```

Read the artifacts in `<out_dir>/` (`signatures.txt`, `gtm-ids.txt`, `headers.txt`,
`dns.txt`, `sitemap-counts.txt`, `robots.txt`). Interpret them with
`references/signatures.md` — the cookie/header/DNS lookup tables and confidence rubric.

**Cover more than the homepage — this is what makes a run's breadth consistent.** A single
anonymous homepage pass misses whole categories of tools that only load on other surfaces.
Fetch/scan (or at least `curl` + grep + note the host) each of these and identify whatever tool
is actually there — don't assume a vendor; discover it and trace it to `references/signatures.md`:
- **developer docs** (e.g. `docs.<domain>`) → whatever docs platform serves them
- the **careers / jobs** link in the footer → the ATS
- **support / help centre** (e.g. `help.<domain>`) → the support/chat tool
- **blog + a pricing / contact-sales page** → forms, chat, demo-booking, BOFU pixels
- **checkout / cart** (ecommerce) → the payments processor + conversion pixels
- **app store listing / mobile deep-link** → mobile subscription + attribution (MMP) tooling
The point is the *surface + category*, not a specific product — the actual tool differs every run.

**Don't assume a surface lives on the brand's own domain.** Many are hosted on the *vendor's*
domain and reached via an **outbound link** in the footer/nav — and the destination host itself
names the tool. Follow those links and read the host:
- careers/jobs often go to a third-party ATS host (e.g. `jobs.<ats>.com/<company>`,
  `boards.<ats>.io/<company>`, `<company>.<ats>.com`) — the ATS vendor is in the host, not a `careers.` subdomain
- docs, status pages, help centres, changelogs and community forums are frequently on the vendor's
  hosted domain too (a `*.<vendor>.com/<company>` or `<company>.<vendor>.com` pattern)
So resolve each surface by **following the link and identifying the host it lands on**, not by
probing `<surface>.<domain>` and giving up when that 404s.

Many of these tools already leave a **client-side trace detectable from any page** (a cookie, a
host, a script), so a homepage capture often hints at them. But **visiting the actual surface
gives a fuller, higher-confidence read** — so where a category matters, point the dynamic browser
audit at that surface, not just a static `curl` + grep, and watch what fires:

```bash
node scripts/tracking_audit.mjs docs.<domain> <out_dir>/audit-docs.json     # subdomain surface
node scripts/tracking_audit.mjs <domain>/pricing <out_dir>/audit-pricing.json  # path surface
```

The live audit confirms the tool by observing it load/fire and reveals *how* it's wired (forms,
chat, checkout pixels) in a way a static grep can't. Use the static grep as the cheap first look;
use the audit on the surface to confirm and enrich.

Marketing often lives on a different host than the product (e.g. `notion.com` vs `notion.so`,
`anthropic.com` vs `claude.com`) — follow the robots `Sitemap:` host and any top-level redirect
to the true marketing host before concluding "no ESP/CRM".

### Step 2 — Dynamic tracking audit (full depth)
This is what makes a teardown more than a tag-scanner: it captures the actual dataLayer,
analytics/CDP/pixel calls, cookies set, and decodes the Meta `/tr/` payload so you can
see match-rate identifiers and CAPI dedup keys.

Ensure Playwright is available, then run it (it simulates an ad-click landing with test
`fbclid`/`gclid`, accepts a consent banner, and records everything):

```bash
# guarantee playwright: run from a dir that already has it, or:
#   mkdir -p /tmp/mt && cd /tmp/mt && npm i playwright >/dev/null 2>&1 && npx playwright install chromium >/dev/null 2>&1
node scripts/tracking_audit.mjs <domain> <out_dir>/audit-anon.json
```

For the **anonymous vs authenticated identity diff** — *optional*, and only ever on the
**operator's own account** on a service they use (never anyone else's credentials, never to
harvest account data — the point is the tracking architecture). It reveals how identity and the
dataLayer change once logged in, e.g. the app `user_id` becoming the analytics `distinct_id`.

To get the session cookies as JSON, tell the operator to use the **Cookie-Editor** browser
extension (Chrome/Edge/Firefox — the one by `cookie-editor.com`):
1. Log in to the target site as themselves and keep that tab open.
2. Click the **Cookie-Editor** toolbar icon, then **Export** (bottom bar) → **Export as JSON**
   — it copies a JSON array of that site's cookies to the clipboard.
3. Paste it into a file, e.g. `<out_dir>/cookies.json`.

Then run a second pass and diff the identity fields against the anonymous run (the script maps
the Cookie-Editor `sameSite` values automatically):

```bash
node scripts/tracking_audit.mjs <domain> <out_dir>/audit-auth.json <out_dir>/cookies.json
```

**This is a discovery capture, not a checklist match — classify it yourself.** The script
records *everything* the page does and emits: `thirdPartyHosts` (every external host hit),
`firstPartyProxyCandidates` (target subdomains fetching scripts / POSTing — where first-party
proxied analytics hides), `scriptsLoaded` (every script the page ran), `allCookies`,
`inPage.globals`, and `inPage.dataLayer`. The `analyticsRequests`/`adBeacons` fields are only
regex *hints* — a convenience highlighter of known vendors, never the source of truth.

**Never read "0 regex hits" as "no tracking."** A brittle pattern list can't know every vendor,
and first-party proxying deliberately hides the vendor host (e.g. PostHog served from
`e.<domain>/array/phc_…` or `/hog/`, Vercel Analytics from `/_vercel/insights`). Instead, reason
over the raw capture: walk `thirdPartyHosts` and `firstPartyProxyCandidates`, look at
`scriptsLoaded` and `globals` (an `Intercom`/`posthog`/`va` global, a `phc_` token, a
`surveys.js`/`recorder.js` script), and inspect cookies. Identify what each host/script/cookie
belongs to — including tools not in `references/signatures.md` — and add anything new you learn
back into that file. The regex exists to save time on the obvious cases, not to bound the search.

Then parse for: custom dataLayer events, first-party proxying, identity minting, consent gating,
and the `_fbp`/`_fbc`/`event_id` match-rate mechanics. `references/signatures.md` explains the
patterns; treat it as a growing memory, not a closed list.

### Step 3 — Enrich from public sources (ALWAYS run — not optional)
This is how tools that never touch the marketing page get confirmed — **payments (Stripe) fire
only at checkout, mobile subs (RevenueCat) only in the app, sales-engagement (Outreach/Apollo)
appear only in job specs.** Skipping this is the single biggest cause of an under-reported stack.
- Web-search the company's **job posts** (growth / marketing-ops / RevOps / SDR roles name CRM,
  enrichment, sales-engagement, ESP tools — "experience with X").
- Search **vendor case studies** (`<vendor> <company> case study` for Clay, Segment, PostHog,
  HubSpot, Salesforce, RevenueCat, PartnerStack, etc.) — confirm tools + reveal operating model/metrics.
Delegate the broad searches to a subagent if available so this stays cheap.

### Step 4 — Write the report
Follow `references/report-structure.md` exactly (section order + confidence tagging).
The critical-gaps section (§8) is the highest-value part for a sophisticated reader — do
a genuine critical pass, don't pad. If comparison context was given, close with practical
"worth stealing vs. where you must diverge" lessons that respect the operator's constraints.

## Bundled resources

- `scripts/stack_scan.sh` — static passive scan (curl + GTM + DNS + sitemap). No deps beyond curl/dig.
- `scripts/tracking_audit.mjs` — headless-browser dataLayer/pixel/cookie capture. Needs Playwright.
- `references/signatures.md` — cookie/header/DNS→vendor lookup, dataLayer patterns, confidence rubric. Read during interpretation.
- `references/report-structure.md` — the report template and style. Read before writing.

## Improving this skill over time

This is a living personal skill. After each real teardown, fold back what you learned:
add newly-seen cookie/vendor signatures to `references/signatures.md`, extend the
`SIGS` list in `stack_scan.sh` with any tool the grep missed, and adjust
`report-structure.md` if the operator consistently wants a section shaped differently.
The scan's coverage and the report's shape should ratchet up with use.
