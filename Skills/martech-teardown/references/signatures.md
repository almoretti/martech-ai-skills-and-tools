# Martech signature lookup

How to read the artifacts the scripts produce. Use this to turn raw hits into named vendors and to assign a confidence level.

## Confidence levels (use these in the report)

- **Confirmed** — direct signature: a live tag/pixel ID, a cookie the vendor sets, a DNS/SPF/DKIM record, a platform header, or a vendor-published case study naming the company.
- **Inferred** — strong circumstantial signal: a hub ID in SPF, a tool named in the company's own job posts, a subdomain convention.
- **Assumed** — typical-for-stage but unverified. Always label these; never present as fact.

## Cookie → vendor map (the highest-signal source)

Cookies are the most reliable tell — a vendor's cookie means their code actually ran.

| Cookie name (pattern) | Vendor | Category |
|---|---|---|
| `_ga`, `_ga_*`, `_gid` | Google Analytics 4 | Web analytics |
| `_gcl_aw`, `_gcl_au`, `GCL_AW_P` | Google Ads | Paid search / click storage |
| `_fbp` | Meta | Paid social — browser ID (match rate) |
| `_fbc` | Meta | Paid social — click ID (from `fbclid`) |
| `_ttp`, `_tt_enable_cookie`, `ttcsid*` | TikTok | Paid social |
| `_rdt_uuid` | Reddit | Paid social |
| `_uetsid`, `_uetvid`, `MUID` | Microsoft Bing UET | Paid search |
| `li_gc`, `bcookie`, `lidc`, `_linkedin_partner_id` | LinkedIn | Paid social / B2B |
| `_twpid`, `guest_id_ads`, `personalization_id` | X / Twitter | Paid social |
| `__obref` | Outbrain | Native advertising |
| `guid @ *.mountain.com` | MNTN | Connected-TV advertising |
| `__spdt` | Spotify Ads | Audio advertising |
| `_vwo_uuid*`, `_vis_opt_*`, `_vwo_sn` | VWO | A/B testing |
| `ph_phc_*`, first-party `anon_distinct_id`/`distinct_id` | PostHog | Product analytics / flags |
| `amp_*`, `amplitude_*` | Amplitude | Product analytics |
| `ajs_anonymous_id`, `ajs_user_id` | Segment | CDP |
| `_cio`, `_cioanonid` | Customer.io | Lifecycle messaging |
| `_hp2_*` | Heap | Product analytics |
| `_hjSession*`, `_hjid` | Hotjar | Session/UX analytics |
| `_clck`, `_clsk` | Microsoft Clarity | Session replay |
| `dd_anonymous_id`, `_dd_s` | Datadog RUM | Frontend observability |
| `claydar_device_id` | Clay ("Claydar") | Enrichment / de-anonymization |
| `koala_*`, `ko_id` | Koala | Intent / de-anon |
| `_6senseCompanyDetails`, `sn_*` | 6sense | ABM / intent |
| `__stripe_mid`, `__stripe_sid` | Stripe | Payments |
| `__ps_*`, `pscd` | PartnerStack | Affiliate / partner |
| `_fprom_*`, `rewardful.referral` | FirstPromoter / Rewardful | Affiliate (SMB) |
| `hubspotutk`, `__hstc`, `__hssc` | HubSpot | Marketing automation / CRM |
| `_mkto_trk` | Marketo | Marketing automation (enterprise) |
| `sequelUserId/SessionId` | Sequel.io | Webinars |
| `intercom-*` | Intercom | Support / chat |
| `drift_*` | Drift | Conversational sales |
| `CookieConsent` | Cookiebot | Consent (decode for region + granted categories) |
| `OptanonConsent`, `OptanonAlertBoxClosed` | OneTrust | Consent |
| `usercentrics` | Usercentrics | Consent |

**Consent cookies decode well** — `CookieConsent` contains `region:` and per-category `marketing/statistics/preferences` booleans and `method:explicit`. Worth quoting in the report.

## Beware false positives (context-check every homepage hit)

The `stack_scan.sh` signature counts are raw substring matches in the homepage HTML — treat them as *leads, not conclusions*. A high count often means the word appears in **content**, not that the tool is installed. Real-world traps seen in the wild:

- A vendor name in an **integrations marketplace or customer story** (e.g. a site that integrates *with* PostHog/Intercom/Zendesk/HubSpot will mention all of them without running any) — the ElevenLabs-vs-Linear lesson: Linear's homepage matched `posthog`, `hotjar`, `klaviyo`, `zendesk`, `intercom`, `hubspot` purely as integration/customer-story content while running **none** of them client-side.
- A **CSS class or JS identifier** that contains the substring (e.g. `stripe` matched `_timelineStripe`; `heap` matched "cheap"; `pendo` matched "Opendoor").
- **Image-CDN URLs** matching a tool name by coincidence.

Confirm every hit by grepping its surrounding context (`grep -oiE ".{0,30}<tool>.{0,45}" home.html`) and by checking whether it corresponds to an actual `<script src>`, cookie, network call, or DNS record. **A tool is only "Confirmed" if it runs or the company operates it** — not if it's merely named on the page. When the browser audit fires nothing but DNS shows real tooling, the correct conclusion is "no *client-side* tracking on the marketing site," never "no martech."

## HTML / header signatures

| Signal | Meaning |
|---|---|
| `x-powered-by: Next.js` + `x-nextjs-prerender`/`x-nextjs-stale-time` | Next.js with ISR (static + timed revalidation) → publishing decoupled from deploys |
| `x-vercel-*` | Hosted on Vercel |
| `via: 1.1 google`, `x-region: europe-west*` | Google Cloud |
| `server: cloudflare`, `cf-ray` | Cloudflare in front |
| 400+ `payloadcms` asset refs | Payload CMS (self-hosted headless) |
| `contentful`, `sanity`, `storyblok`, `webflow`, `wp-content`/`wordpress` | Respective CMS |
| `fern`, `mintlify`, `readme`, `docusaurus`, `gitbook` | Docs platform |
| `shopify`, `cdn.shopify`, `recharge` | Commerce stack |
| `Content-Signal: ai-train=yes` in robots.txt | Explicitly invites AI crawler training (SEO/AI-distribution posture) |

## DNS / SPF / DKIM → email + SaaS

SPF `include:` and DKIM selectors reveal who sends mail as the domain — often the clearest CRM/ESP tell.

| Record fragment | Vendor |
|---|---|
| `include:_spf.salesforce.com` | Salesforce |
| `include:*.hubspotemail.net` (hub id in the label) | HubSpot |
| `include:mail.zendesk.com` | Zendesk |
| `include:_spf.google.com` | Google Workspace |
| `include:sendgrid.net`, `s1/s2._domainkey → *.sendgrid.net` | SendGrid |
| `k2/k3._domainkey → dkim2/3.mcsv.net` | Mailchimp |
| `include:mailgun.org`, `krs._domainkey` | Mailgun |
| `include:spf.mtasv.net` | Postmark (transactional email) |
| `include:*.customeriomail.com`, `cio._domainkey` | Customer.io |
| `include:_spf.brevo.com` / `sendinblue` | Brevo |
| `include:spf.mandrillapp.com` | Mandrill |
| `include:amazonses.com` | Amazon SES |
| `include:_spf.intercom.io` | Intercom |
| `include:mktomail.com` | Marketo (marketing automation) |
| `include:servers.mcsv.net` / `mcsv.net` / `mcdlv.net` | Mailchimp |
| `_spf.salesforce.com` + `cpmails`/`exacttarget`/`et._spf` | Salesforce Marketing Cloud / Pardot |
| `include:*.mailgun.<domain>` or `mailgun.org` | Mailgun (often self-hosted subdomain) |
| `include:spf.protection.outlook.com` | Microsoft 365 (corporate mail) |
| `redirect=_hspf.hubspot.com` | HubSpot (whole domain delegated — heavy HubSpot user) |
| `include:*.vali.email`, `smp.ne.jp`, regional ESPs | deliverability/regional ESP — note but low-signal |

**DNS/SPF is the most reliable *static* layer.** On JS-heavy SPAs the homepage often inlines almost nothing (GTM/GA/pixels are injected at runtime), so `signatures.txt` under-reports — but SPF still reveals the CRM/MAP/ESP because those send real email. When the homepage is thin, weight DNS heavily and rely on the dynamic browser audit for the client-side tags.
| root TXT `*-domain-verification`, `openai-domain-verification`, `docusign=`, `MS=` | misc SaaS in use (DocuSign, Microsoft, OpenAI, etc.) |

## De-anonymization / visitor-reveal tech (and the logged-out limit)

A recurring question in teardowns: *can they identify anonymous (logged-out) visitors, and are they personalizing for them?* Keep two things separate:

- **Known-user personalization** (e.g. splitting a pixel by `subscription_tier`/ICP flag) only works for *logged-in* users — the gating properties are empty for anonymous traffic (`person_properties:{}`). Don't claim an anonymous visitor is being segmented unless you see a reveal vendor actually fire for the anon session.
- **Client-side reveal** is the only way to segment logged-out traffic in real time. Look for these firing for the anonymous user: **Clearbit Reveal / HubSpot Breeze Intelligence, 6sense, Demandbase, Koala, RB2B, Vector, Warmly, Snitcher, Albacross, Dealfront/Leadfeeder**. They resolve visitor IP → company client-side and push it to the dataLayer. Caveats to state in the report: **company-level not person-level, ~15–40% match on B2B traffic (≈0 on consumer), probabilistic, privacy-sensitive.**
- **Server-side enrichment ≠ client reveal.** Tools like Clay (`claydar_device_id`) can log the visit and enrich it *server-side*, but that resolves too late to gate a client-side pixel or personalize the current pageview. If the only de-anon signal is server-side, the correct statement is "they can identify accounts after the fact, but are not personalizing the anonymous session live."

So when you see a pixel/audience split, check whether it's gated on known-user properties (then it's login-only) or fed by a live client reveal vendor (then it reaches anonymous traffic). Report which, and don't assume the more sophisticated one without the vendor evidence.

## dataLayer / network patterns worth calling out

- **Consent gate event** (e.g. `ready_for_pixels`, or Consent Mode `consent default`/`update`) → pixels fire post-consent, not on load. Good hygiene; note it.
- **`event_id` (UUID) attached to a `$pageview`/event** → CAPI deduplication key (same id sent to browser pixel + server Conversions API). Strong sign of a browser+server measurement setup.
- **Multiple pixels of the same platform** (e.g. two Meta pixel IDs) → usually a deliberate signal split (consumer vs enterprise) OR tag sprawl. Decide which from context.
- **First-party proxied analytics** (analytics calls to the site's own domain, not the vendor's) → deliberate ad-blocker/ITP resistance.
- **Meta `/tr/` fields**: `fbp` (browser id), `fbc` (click id), `em`/`ph`/`fn` (hashed advanced matching — PII), `ss` (SmartScrape), `ap[...]` (automatic params). Presence of hashed `em` = advanced matching on.
- **Google `1p-user-list` / `rmkt/collect`** → enhanced conversions / first-party remarketing.
- **Identity in analytics calls**: compare the `distinct_id` anonymous vs authenticated. If authenticated swaps in a stable app user_id as the distinct_id, they stitch web↔product on one key with no CDP needed.

## Turning job posts + case studies into stack facts

- Search `"<company>" careers` + role families: growth, marketing ops, RevOps, sales development, lifecycle. Job specs name CRM, sales-engagement, enrichment, and ESP tools ("experience with X").
- Search `<vendor> <company> case study` for the big ones (Clay, PostHog, Segment, HubSpot, Salesforce, RevenueCat, PartnerStack) — vendors publish named-customer stories that confirm tools and often reveal the operating model + metrics.

## Observed-in-the-wild signatures (from a 20-brand validation corpus)

Signatures confirmed across a spread of fintech, B2B SaaS, DTC, publisher and dev-infra brands. Grow this list after each teardown.

### Server-side / first-party Google tagging (the highest-value tell)
Modern sites proxy GTM+GA server-side for ITP/adblock resistance — the client-side host is a first-party subdomain, so host-based detection misses it. Tells:
- Cookies **`FPID` / `FPAU` / `FPLC` / `FPGCLAW` / `FPGSID`** (the `FP` = first-party GA/Ads).
- sGTM host conventions: `sst.<domain>`, `tags.<domain>` / `tags.js`, `t-antenna.<domain>`, `growth-performance.<domain>`, `ct.<domain>`, `cdp-api.<domain>` proxying `/gtm.js` and `/g/collect`.
- **GA4 regional collect hosts**: `region1.analytics.google.com`, `region1.google-analytics.com` (EU) — treat as analytics, not ad.

### Ad platforms — client identifiers (for the CAPI matrix, §6)
| Platform | Beacon host | Browser/user cookie | Click-id | Advanced-matching (hashed PII) | Dedup / CAPI key |
|---|---|---|---|---|---|
| Meta | `facebook.com/tr` | `_fbp` | `_fbc`←`fbclid` | `ud[em]`,`em`,`ph` | `eid`/`event_id` |
| Google Ads | `googleads.g.doubleclick`, `google.com/pagead/1p-user-list` | `_gcl_aw`,`_gcl_au` | `gclid`/`gbraid`/`wbraid` | `em`/user_data (Enhanced Conv.) | `transaction_id` |
| TikTok | `analytics.tiktok.com` | `_ttp` | `ttclid` | hashed `email`/`phone` | `event_id` |
| Reddit | `alb.reddit.com/rp.gif` | `_rdt_uuid` | `rdt_cid` | hashed em | `conversion_id` |
| Microsoft/Bing | `bat.bing.com` | `_uetsid`,`_uetvid`,`MUID` | `msclkid` | `edi`/hashed | UET enhanced conv. |
| LinkedIn | `px.ads.linkedin.com`, `snap.licdn.com` | `li_gc`,`bcookie` | `li_fat_id` | hashed em | conversion event id |
| Snapchat | `tr.snapchat.com`, `sc-static.net` | `_scid`,`_scid_r`,`sc_at` | `ScCid` | `u_hem`,`u_hpn` | `client_dedup_id` |
| Pinterest | `ct.pinterest.com`, `s.pinimg.com/ct` | `_pin_unauth`,`_pinterest_ct_ua` | `_epik`←`epik` | hashed em | `event_id` |
| The Trade Desk | `insight/js/match.adsrvr.org` | `TDID`,`TDCPM` | — | — | (DSP, no CAPI) |
| Amazon Ads/DSP | `c.amazon-adsystem.com`, `aax` | — | — | — | `ara`/reporting |
| Others seen | Criteo (`cto_bundle`), AppLovin/AXON (`axcrt`/`_axwrt`), StackAdapt (`sa-user-id`), Outbrain (`sync.outbrain.com`), Beeswax (`bito`@`bidr.io`) |

### Enterprise CDP / personalization / experience
- **Adobe Experience Platform / Alloy Web SDK**: cookies `kndctr_*_AdobeOrg_identity` / `_cluster`, edge path `ee/irl1/v1/interact`; **Adobe Target** `at_lp_exp` (a whole enterprise stack — e.g. Nike).
- **mParticle** `mprtcl-v4*` / `*.mparticle.com`; **Dynamic Yield** `_dyid`/`_dyjsession`; **Algolia** `_ALGOLIA`/`*.algolia.net`; **Contentsquare** `_cs_id`/`_cs_c`/`_cs_s`.

### B2B de-anon / intent (fire on ANONYMOUS traffic — the SaaS tell)
- **Demandbase** `tag.demandbase.com`/`company-target.com`, `Demandbase_Loaded`; **ZoomInfo** `_zitok`/`ws.zoominfo.com`/`js.zi-scripts.com`; **6sense** `6suuid`/`b.6sc.co`/`epsilon.6sense.com`; **Qualified** `__q_state`/`assets.qualified.com`; **G2** `tracking.g2crowd.com`; plus Vector / Influ2 / CaliberMind. (See the reveal caveats above — company-level, ~15–40% match.)

### Bot-mitigation cookies — recognise so you DON'T mis-tag them as martech
`__cf_bm`/`cf_clearance`/`_cfuvid` (Cloudflare) · `ak_bmsc`/`bm_sv`/`go-mpulse.net` (Akamai Bot Manager/mPulse) · `datadome` (DataDome) · `_px3`/`_pxvid`/`pxcts` (PerimeterX/HUMAN) · `aws-waf-token` (AWS WAF). These are also the fingerprints for the **bot-wall** the scan now flags.

### Consent (beyond Cookiebot/OneTrust/Usercentrics)
- **Transcend** `airgap.js`/`transcend-cdn.com`; OneTrust IAB-TCF variants `eupubconsent-v2`/`OptanonConsent`; **bespoke/first-party CMPs** invisible to SaaS-CMP detection — e.g. NYT **PURR** (`nyt-purr`), Booking `pcm_consent`, homegrown `twCookieConsent`. Absence of a SaaS CMP ≠ no consent; look for a first-party one.

### Attribution / MMP (mobile + partner)
AppsFlyer `AF_SYNC`/`afUserId`/`onelink.me` · Branch `branch_key`/`app.link` · Singular · Impact.com `IR_*`/`*.sjv.io`/`ojrq.net` · Tapad `TapAd_DID` · TVSquared/Snowplow `_tq_id`/`_sp_id` · comScore `scorecardresearch.com` · Magellan AI `mgln.ai` (podcast) · Spotify Ads `pixels.spotify.com`/AdsWizz.

### Observability & video (repeatedly missed; not marketing but worth noting)
Datadog RUM `_dd_s`/`browser-intake-datadoghq.*` · New Relic `bam.nr-data.net` · Sentry `*.ingest.sentry.io` · Mux `litix.io`/`mux.com` · Statsig · publisher SSPs `media.net`/`casalemedia`/`rubiconproject`/APS/Prebid (NYT).

### Self-hosted first-party telemetry (DON'T mistake for proxied third-party analytics)
Some companies' entire analytics spine is in-house first-party — surfaces only in `firstPartyProxyCandidates`: GitHub `collector.github.com/_/collect`, Netflix **Ichnaea** (`ichnaea-web`), NYT `jkidd`/`a.et`/`eg`, Booking `c360.booking.com`, **Stripe `r.stripe.com`/`q.stripe.com`** (product/fraud telemetry — the classic trap). Confirm it's the company's own domain doing its own thing before labelling it a vendor.

### CMS host mapping (not just the literal name string)
`images.ctfassets.net`/`videos.ctfassets.net` → **Contentful** (recurring marketing-site CMS — Stripe, and reasoned on others). `cdn.sanity.io/images/<project>` → Sanity. `cdn-cgi/imagedelivery` → Cloudflare Images.

### DNS additions
Marketo `mktomail.com` · Mailchimp `mcsv.net`/`mcdlv.net` · SFMC/Pardot (`_spf.salesforce.com` + `exacttarget`/`cpmails`; Salesforce org id TXT `00D…`) · Mailgun (`mailgun.<domain>`) · SparkPost (`_spf.e.sparkpost.com`) · **Greenhouse ATS** (`greenhouse-outbound`/`mg-spf.greenhouse.io`) · M365 (`spf.protection.outlook.com`, DKIM `selector1/2`→`*.onmicrosoft.com`) · Proofpoint (`pphosted.com`) · Red Sift **OnDMARC** (`*.smart.ondmarc.com`) · Qualtrics (`_spf.qualtrics.com`) · Fastly (`fastly-domain-delegation`) · treat `facebook-/stripe-/shopify-domain-verification` TXT as martech-relevant, not generic SaaS.

### Emerging / watch-list (log, don't over-claim)
`bzr.openai.com`/`bzrcdn.openai.com` (OpenAI ad/attribution pixel) · `pdscrb.com` · `ml314.com` · cloaked white-label de-anon fleets (`company-target.com` and lookalikes).
