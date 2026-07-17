# Report structure

The teardown output. Default to Markdown; produce a self-contained HTML report if the operator asks. Keep the same section order in either format so reports are comparable across targets.

**HTML output uses the neutral house template** at `assets/report-template.html` — the *MartechTearDown* brand (its own invented logo + teal/slate theme), never a target company's or the operator's employer's branding. Clone the template, keep its `<style>`/header/footer, fill the section bodies, replace `__TARGET__` and `__DATE__`. The one exception: if the operator *explicitly* asks for their own brand skin and a brand-specific design skill exists, use that instead — otherwise always the neutral house style.

Every claim carries a **confidence tag** (Confirmed / Inferred / Assumed) and, for Confirmed items, the **evidence** (the cookie, header, DNS record, tag ID, or case-study URL). Evidence is what makes a teardown trustworthy — never drop it.

## Sections (in order)

### 1. Executive summary
2–4 sentences: what kind of company this is (business model, GTM motion) and the single defining trait of their stack. Then a one-line "headline takeaway". Optionally 3–4 stat tiles (page count, vendor count, pixel count, a standout number).

### 2. Full stack by category
A table: **Space | Tool | Confidence | Evidence**. Cover every martech space you found signal for:
web platform · CMS · tag management · consent/CMP · product analytics · web analytics · experimentation · CRM · marketing automation · CDP · enrichment/intent · sales engagement · email (newsletter + transactional) · support/chat · affiliate/partner · payments · mobile subs/attribution · webinars/events · observability · docs · ATS · data warehouse · SEO tooling.
List the **paid-media pixel suite** separately with IDs and account counts.

### 3. CMS & landing-page model
Which CMS, self-hosted vs SaaS, and the **page-model shape** from the sitemap counts (collections × locales, biggest clusters). Note the rendering strategy (SSG / SSR / ISR from headers) and what it implies for how the marketing team ships pages. If they run programmatic SEO at scale, frame it as the "catalogue + template + JIT rendering" model and categorize the page types (TOFU free tools, BOFU commercial-intent, product/solution, content/demand-gen, UGC, competitive).

### 4. Tracking & data layer
The custom dataLayer events (with what each does), the analytics implementation (tool, first-party proxying, identity minting, session replay, flags/experiments), and the consent choreography. This is the empirical heart — quote actual event names and request shapes.

### 5. Identity model
How anonymous vs authenticated identity works (from the two audit runs). The key question: **what is the join key, and does it unify web ↔ product?** Call out first-touch attribution storage, account/workspace grain, and whether property targeting is client- or server-side.

### 6. Match-rate & ad measurement — a PER-PLATFORM matrix, not a Meta-only writeup
Every major ad platform (Meta, Google, TikTok, Reddit, Microsoft/Bing, LinkedIn, Snap, Pinterest, X) has a server-side Conversions API and its own identifiers — apply **symmetric scrutiny**. The audit's `pixelMatrix` gives you, per platform: whether it fired, whether a **click-id** was captured, whether a **dedup/event-id** was present (→ browser+server CAPI likely wired), and whether **advanced matching** (hashed email/phone) was seen. Present it as a table:

| Platform | Pixel fired | Click-id captured | Advanced matching (hashed PII) | Dedup/CAPI signal |
|---|---|---|---|---|

Then a short "match-rate playbook" reading the pattern: first-party click-id cookieing on landing, `event_id`-style dedup across browser+server, pixel-splitting by business line, consent gating. Two rules learned in validation:
- **Server-side GTM detected ⇒ conversions are delivered server-side and are browser-invisible.** Say exactly that ("CAPI conversions run server-side via sGTM; not observable client-side") rather than under-reporting the measurement layer. Presence of `FPID/FPAU/FPGCLAW` cookies or an sGTM subdomain is the tell.
- A pixel with hashed `em`/`u_hem`/`ud[em]` in its payload is doing **advanced matching** — call it out per platform (e.g. "Snap is sending hashed email; Reddit is not"), which is the symmetric insight the Meta-only version used to miss.

### 7. Vendor inventory (evidence appendix)
The full cookie→vendor and DNS→vendor tables, so every vendor named above is traceable to a raw signal. This is what lets a reader audit the teardown.

### 8. Where the gaps are (critical read)
The most valuable section for a sophisticated reader. Genuinely critique the implementation — don't pad. Look for: inconsistencies, tool overlap, governance smells, privacy surface, cheaper-but-weaker choices, and key-person/bespoke-system risk. Number them; explain the failure mode of each, not just its name. If the implementation is genuinely strong, say so and make the gaps appropriately subtle rather than inventing weaknesses.

**Discipline for this section — a client-side audit cannot see the server side.** The browser shows you what loads and fires in the page; it does NOT show server-to-server flows. Before writing any gap, ask whether the thing you're about to criticize could be handled on a path you can't observe. In particular:

- **Don't call ad measurement "exposed / client-side-only" just because pixels fire in the browser.** Conversions may be delivered server-side via a CDP *destination* (PostHog/Segment/RudderStack → Meta CAPI / Google enhanced conversions), via a warehouse (events → BigQuery/Snowflake → reverse-ETL to ad platforms), or via server-side GTM. You usually cannot see any of these from a browser. Write it as *"no server-side delivery was observable; if they lack one, X is exposed — but a CDP destination would close it."*
- **Don't frame a redundant-looking tool as a smell without asking what job it does that the other can't.** Two experimentation tools often = two personas (e.g. a visual/WYSIWYG editor for marketers vs. code-level flags for engineers). Two of the same pixel often follow a deliberate audience/business split (consumer vs. enterprise), not sprawl — apply that generosity *consistently* across platforms, not just to the one you happened to explain.
- **Consider that observed client behavior may be part of a more sophisticated whole.** A pixel split + a client-side enrichment/de-anon cookie (e.g. Clay's `claydar`) can mean real-time identity resolution at landing feeding live routing — credit the mechanism before assuming a limitation.

The rule: **state what you observed, then offer the most and least charitable reading, and label which parts are unobservable.** A hedged, correct gap beats a confident, wrong one — the same honesty rule as the rest of the report.

### 9. Lessons / so-what
What's worth adopting and why.

**Always attempt the operator-comparison.** Before writing this section, check whether you already know the operator's own martech stack — from the conversation, from an org profile they've given, from project docs (e.g. a CLAUDE.md), or from memory. If you do, make this a two-column **"worth stealing" vs "where you must diverge"** comparison: concrete things the target does that the operator could adopt, set against the operator's real constraints (regulated-industry PII rules, existing tools, scale). This is the highest-value section for the operator — the whole point of a teardown is what *they* do differently on Monday. Draw on what you genuinely know about their stack; don't invent it, and say when a recommendation depends on a detail you're unsure of.

If you don't know the operator's stack and none is supplied, keep this a vendor-neutral "notable patterns worth knowing" list, and note that supplying their stack would let you tailor it.

### Method appendix
Bullet the exact steps run (static scan, GTM parse, DNS, sitemap walk, both audit runs, case studies read) so the sourcing is auditable and repeatable.

## Style
- Lead with the conclusion; put evidence after.
- Prefer prose + a few well-chosen tables over walls of bullets.
- Distinguish what you *observed* from what you *infer* — the credibility of a teardown rests on that line staying visible.
- This is competitive intelligence from public/own-account signals only. State that scope in a disclaimer line.
