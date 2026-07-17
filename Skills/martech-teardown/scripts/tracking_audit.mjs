// martech-teardown :: dynamic tracking audit via headless browser
// Captures the dataLayer, analytics/CDP/pixel network calls, cookies set, and
// decodes the Meta /tr/ payload so you can see match-rate identifiers (_fbp/_fbc)
// and any CAPI event_id dedup keys.
//
// Requires: playwright (run from a dir that has it, or `npm i playwright` first;
//   the SKILL tells the agent how to guarantee this).
//
// Usage:
//   node tracking_audit.mjs <domain> [out.json] [cookies.json]
//     <domain>        bare host, e.g. example.com
//     [out.json]      where to write results (default ./audit-<domain>.json)
//     [cookies.json]  OPTIONAL array of {name,value,domain,path,secure,sameSite}
//                     to observe the AUTHENTICATED dataLayer. Only ever use the
//                     operator's OWN account cookies — never someone else's.
//
// Simulates an ad click by appending utm + fbclid + gclid so click-ID handling
// is observable. Purely observational: it does not submit forms or mutate state.

import { chromium } from 'playwright';
import fs from 'node:fs';
import zlib from 'node:zlib';

const RAW = (process.argv[2] || '').replace(/^https?:\/\//, '');
if (!RAW) { console.error('usage: node tracking_audit.mjs <domain[/path] | sub.domain> [out.json] [cookies.json]'); process.exit(1); }
const DOMAIN = RAW.replace(/\/.*$/, '');          // host only — used for origin / first-party checks
const PATHQ = RAW.slice(DOMAIN.length) || '/';    // optional path(+query) so a specific surface can be audited
const OUT = process.argv[3] || `./audit-${DOMAIN}.json`;
const COOKIE_FILE = process.argv[4];

const TEST_FBCLID = 'TEARDOWNFBCLID123';
const TEST_GCLID = 'TEARDOWNGCLID456';

const phEvents = [];   // analytics / CDP / flag calls
const adBeacons = [];  // ad-platform pixels
const allHosts = {};   // EVERY host hit (so we never silently report a false zero)
const fpCandidates = new Set(); // first-party subdomains that look like proxied analytics
const pixelMatrix = {}; // per-ad-platform: click-id / browser-id / dedup-key / advanced-matching / CAPI signal

// Match on PATH patterns too, not just vendor hosts — first-party proxying (e.g.
// e.linear.app/array/phc_… for PostHog, /hog/ for ElevenLabs) hides the vendor host,
// so host-only detection reports a false zero. phc_ = PostHog project token.
// GA4 is analytics, not an ad pixel — and it also fires from regional hosts
// (region1.analytics.google.com / region1.google-analytics.com) that the old pattern missed.
const ANALYTICS_RE = /posthog|\/hog\/|\/dachshund\/|\/array\/|\/decide|\/flags\/?|\/feature-flags\/|\/e\/|\/i\/v\d\/e|\/ingest|\/static\/(surveys|recorder|array)|phc_|amplitude|\/2\/httpapi|segment\.(com|io)|cdn\.segment|\/v1\/(track|identify|page|batch)|rudder|mixpanel|api\.heap|\.mparticle|june\.so|vercel\.com\/insights|\/_vercel\/insights|plausible|fathom|(region\d*\.)?(analytics\.google|google-analytics)\.com\/(g\/)?collect|contentsquare|\/api\/(event|track|collect|analytics)/i;
const AD_RE = /facebook\.com\/tr|connect\.facebook|analytics\.tiktok|px\.ads\.linkedin|snap\.licdn|tr\.snapchat|sc-static\.net|bat\.bing|googleadservices|googleads\.g\.doubleclick|google\.com\/pagead|redditstatic|alb\.reddit|reddit\.com\/rp|ct\.pinterest|pinterest\.com\/v3|s\.pinimg\.com\/ct|adsrvr\.org|amazon-adsystem|t\.co\/|ads-twitter|analytics\.twitter|snaptr|clarity\.ms|outbrain|taboola|criteo|mountain\.com/i;

// Symmetric ad-platform scrutiny — every major platform has a server-side Conversions API
// with its own click-id, browser-id, dedup key, and hashed advanced-matching fields. Classify
// each ad beacon by platform, then flag whether a dedup key (=> CAPI/server-side wired),
// advanced matching (=> hashed PII being sent), and a click-id were present.
const AD_PLATFORMS = [
  { k: 'Meta',            re: /facebook\.com\/tr|connect\.facebook/i },
  { k: 'Google Ads/GA4',  re: /googleads\.g\.doubleclick|google\.com\/pagead|googleadservices|(region\d*\.)?google-analytics\.com\/(g\/)?collect/i },
  { k: 'TikTok',          re: /analytics\.tiktok/i },
  { k: 'Reddit',          re: /reddit\.com\/rp|alb\.reddit|redditstatic/i },
  { k: 'Microsoft/Bing',  re: /bat\.bing/i },
  { k: 'LinkedIn',        re: /px\.ads\.linkedin|snap\.licdn|linkedin\.com\/(px|collect)/i },
  { k: 'Snapchat',        re: /tr\.snapchat|sc-static\.net|snaptr/i },
  { k: 'Pinterest',       re: /ct\.pinterest|pinterest\.com\/v3/i },
  { k: 'X/Twitter',       re: /ads-twitter|analytics\.twitter|t\.co\/i\/adsct/i },
];
// dedup/event-id key => the browser pixel and a server CAPI event share it => server-side wired
const DEDUP_RE = /(event_?id|[?&_.\[]eid[=\]]|conversion_?id|client_dedup_id|dedup|transaction_id|\bcid=)/i;
// hashed advanced matching / user-data being sent client-side
const ADV_MATCH_RE = /(ud\[|user_data|[?&](em|ph|fn|ln|hashed_email|hashed_phone)=|sha256|_hem=|\bhashed)/i;
// click-ids across platforms (in url, body, or a cookie)
const CLICKID_RE = /(fbclid|fbc=|gclid|gbraid|wbraid|ttclid|rdt_cid|msclkid|li_fat_id|sccid|sccid|_epik|epik=|twclid)/i;

function parseBody(buf, headers, url) {
  if (!buf) return null;
  try {
    let raw = buf;
    if (url.includes('compression=gzip-js') || headers['content-encoding'] === 'gzip' || (buf[0] === 0x1f && buf[1] === 0x8b)) raw = zlib.gunzipSync(buf);
    const t = raw.toString('utf8');
    if (t.startsWith('{') || t.startsWith('[')) return JSON.parse(t);
    if (t.startsWith('data=')) return JSON.parse(Buffer.from(decodeURIComponent(t.slice(5).split('&')[0]), 'base64').toString('utf8'));
    // multipart (Meta /tr) -> pull name=value fields
    if (/name="/.test(t)) {
      const fields = {};
      for (const m of t.matchAll(/name="([^"]+)"\s*\r?\n\r?\n([\s\S]*?)\r?\n------/g)) fields[m[1]] = m[2].trim().slice(0, 300);
      return Object.keys(fields).length ? fields : t.slice(0, 1500);
    }
    return t.slice(0, 1500);
  } catch (e) { return `<unparsed:${e.message}>`; }
}

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  locale: 'en-US',
});
let authed = false;
if (COOKIE_FILE && fs.existsSync(COOKIE_FILE)) {
  const raw = JSON.parse(fs.readFileSync(COOKIE_FILE, 'utf8'));
  const cookies = raw.map((c) => ({
    name: c.name, value: c.value,
    domain: c.domain || `.${DOMAIN}`, path: c.path || '/',
    secure: c.secure !== false, sameSite: ({ no_restriction: 'None', lax: 'Lax', strict: 'Strict' }[c.sameSite] || c.sameSite || 'Lax'),
  }));
  await ctx.addCookies(cookies);
  authed = true;
}

const page = await ctx.newPage();
// DISCOVERY-FIRST capture: record EVERYTHING, never filter down to a known list.
// The regexes below only *highlight* likely trackers; the full host list + first-party
// proxy candidates + loaded scripts are always emitted so the agent can classify novel
// or first-party-proxied tools the patterns don't know about.
page.on('request', (req) => {
  const u = req.url();
  let host = '', path = '';
  try { const url = new URL(u); host = url.host; path = url.pathname; } catch { return; }
  allHosts[host] = (allHosts[host] || 0) + 1;
  const isAsset = u.includes('/_next/static/') || /\.(png|jpe?g|webp|gif|avif|svg|woff2?|ttf|otf|eot|mp3|mp4|webm|css|ico)(\?|$)/i.test(u);
  const isOrigin = host === DOMAIN || host === `www.${DOMAIN}`;
  const isFirstPartySub = host.endsWith('.' + DOMAIN) && !isOrigin;
  const isPH = ANALYTICS_RE.test(u);
  const isAd = AD_RE.test(u);
  // first-party proxied analytics: a target subdomain fetching a script or POSTing to a
  // non-asset path is a prime proxy candidate (e.g. e.linear.app/array/phc_… = PostHog).
  if (isFirstPartySub && !isAsset && (isPH || /\.js(\?|$)/.test(path) || req.method() === 'POST')) {
    fpCandidates.add(`${host}${path}`.slice(0, 90));
  }
  if (isAd) {
    // parse GET query (most pixels fire as GET) AND any POST body — earlier versions only
    // decoded Meta POST bodies, so non-Meta / GET-style beacons lost their identifiers.
    const q = {};
    try { for (const [k, v] of new URL(u).searchParams) { if (Object.keys(q).length < 40) q[k] = String(v).slice(0, 90); } } catch {}
    const bodyObj = req.method() === 'POST' ? parseBody(req.postDataBuffer(), req.headers(), u) : null;
    const blob = u + ' ' + (bodyObj ? JSON.stringify(bodyObj) : '');
    const plat = (AD_PLATFORMS.find((p) => p.re.test(u)) || { k: 'Other/unknown' }).k;
    const m = pixelMatrix[plat] || (pixelMatrix[plat] = { platform: plat, fired: true, dedupIdSeen: false, advancedMatchingSeen: false, clickIdSeen: false, hosts: new Set(), sampleParams: null });
    m.hosts.add(host);
    if (DEDUP_RE.test(blob)) m.dedupIdSeen = true;              // => CAPI / server-side dedup likely wired
    if (ADV_MATCH_RE.test(blob)) m.advancedMatchingSeen = true; // => hashed PII sent client-side
    if (CLICKID_RE.test(blob)) m.clickIdSeen = true;
    if (!m.sampleParams) m.sampleParams = Object.keys(q).slice(0, 30);
    adBeacons.push({ url: u.slice(0, 200), method: req.method(), platform: plat, query: q, body: bodyObj || undefined });
  } else if (isPH) {
    phEvents.push({ url: u.slice(0, 220), method: req.method(), body: parseBody(req.postDataBuffer(), req.headers(), u) });
  }
});

const _sep = PATHQ.includes('?') ? '&' : '?';
const landing = `https://${DOMAIN}${PATHQ}${_sep}utm_source=teardown&utm_medium=paid&utm_campaign=audit&fbclid=${TEST_FBCLID}&gclid=${TEST_GCLID}`;
await page.goto(landing, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(6000);

// accept a consent banner if present (best-effort, common selectors)
try {
  const btn = page.locator('#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll, button:has-text("Allow all"), button:has-text("Accept all"), button:has-text("Accept"), #onetrust-accept-btn-handler').first();
  await btn.click({ timeout: 4000 });
  await page.waitForTimeout(7000);
} catch { /* no banner */ }

try { await page.mouse.wheel(0, 2500); await page.waitForTimeout(1500); await page.mouse.wheel(0, 3000); await page.waitForTimeout(2500); } catch {}

// The page-state snapshot. Defined once, run on the CONSENTED landing page FIRST, then again
// after a second navigation — merged — so a 404 / cross-origin / challenge redirect on the
// second nav can no longer zero out dataLayer/globals (which was systematically wiping §4/§5).
const snapFn = () => {
  const dl = (window.dataLayer || []).map((e) => { try { return JSON.parse(JSON.stringify(e)); } catch { return String(e); } });
  const globals = ['fbq', 'ttq', 'twq', 'rdt', 'lintrk', 'uetq', 'gtag', 'snaptr', 'clarity', 'analytics', 'posthog', 'amplitude', 'mixpanel', 'heap', 'dataLayer', 'Intercom', 'drift', 'zE', '_hsq', 'va', 'vaq', '__vercel_analytics', 'june', 'Koala', 'ko', 'plausible', 'fathom', 'Sentry'].filter((g) => g in window);
  const scriptsLoaded = [...document.scripts].map((s) => s.src).filter(Boolean).map((s) => { try { const x = new URL(s); return x.host + x.pathname; } catch { return s; } });
  let analytics = null;
  try {
    if (window.posthog) {
      const p = window.posthog.persistence?.props || {};
      analytics = { tool: 'posthog', distinct_id: window.posthog.get_distinct_id?.(), device_id: p.$device_id, user_state: p.$user_state, epp: p.$epp, initial_person_info: p.$initial_person_info, props: Object.keys(p).filter((k) => !k.startsWith('$sesid')) };
    } else if (window.amplitude) { analytics = { tool: 'amplitude', exposed: true }; }
  } catch (e) { analytics = String(e); }
  return { dataLayer: dl.slice(0, 80), globals, scriptsLoaded: [...new Set(scriptsLoaded)], analytics, cookieNames: document.cookie ? document.cookie.split('; ').map((c) => c.split('=')[0]).sort() : [] };
};

let inPage = await page.evaluate(snapFn).catch(() => null);   // <-- landing snapshot (the reliable one)
// second navigation to a DISCOVERED in-site link (not a hardcoded /pricing that 404s off-SaaS)
try {
  const href = await page.evaluate(() => {
    const hs = [...document.querySelectorAll('a[href]')].map((a) => a.getAttribute('href')).filter((h) => h && /^\/(?!#|\/)/.test(h) && !/\.(pdf|zip|png|jpe?g|svg|mp4)(\?|$)/i.test(h));
    return hs.find((h) => /pricing|plans|product|features|sign[-_]?up|get[-_]?started|checkout|cart|shop|store|blog|solutions/i.test(h)) || hs[0] || null;
  });
  if (href) { await page.goto(new URL(href, `https://${DOMAIN}`).href, { waitUntil: 'domcontentloaded', timeout: 35000 }); await page.waitForTimeout(4500); }
  else { await page.mouse.wheel(0, 3000); await page.waitForTimeout(2000); }
} catch {}
try {
  const s2 = await page.evaluate(snapFn);
  if (s2 && !inPage) inPage = s2;
  else if (s2) {
    inPage.dataLayer = (inPage.dataLayer || []).length >= (s2.dataLayer || []).length ? inPage.dataLayer : s2.dataLayer;
    inPage.globals = [...new Set([...(inPage.globals || []), ...(s2.globals || [])])];
    inPage.scriptsLoaded = [...new Set([...(inPage.scriptsLoaded || []), ...(s2.scriptsLoaded || [])])];
    inPage.cookieNames = [...new Set([...(inPage.cookieNames || []), ...(s2.cookieNames || [])])].sort();
    inPage.analytics = inPage.analytics || s2.analytics;
  }
} catch {}
if (!inPage) inPage = { dataLayer: [], globals: [], scriptsLoaded: [], analytics: null, cookieNames: [] };

const cookies = await ctx.cookies();
// Everything the origin sent to third parties / first-party proxies — the raw material
// the agent classifies. NOTHING is filtered out here; the regex hits are just a starting point.
const originHostRe = new RegExp(`(^|\\.)${DOMAIN.replace(/\./g, '\\.')}$`);
const thirdPartyHosts = Object.entries(allHosts)
  .filter(([h]) => !originHostRe.test(h) && !/gstatic|fonts\.google|googlefonts/i.test(h))
  .sort((a, b) => b[1] - a[1]).map(([h, n]) => `${n}\t${h}`);
const result = {
  domain: DOMAIN, authed, landing,
  inPage,
  firstPartyProxyCandidates: [...fpCandidates],   // <-- first-party-proxied analytics hides here
  thirdPartyHosts,                                 // <-- every external host hit (classify these)
  allHostsHit: Object.entries(allHosts).sort((a, b) => b[1] - a[1]).map(([h, n]) => `${n}\t${h}`),
  allCookies: cookies.map((c) => ({ name: c.name, domain: c.domain, value: (c.value || '').slice(0, 50) })),
  analyticsRequests: phEvents.slice(0, 60),
  adBeacons: adBeacons.slice(0, 80),
  // per-platform CAPI matrix: for each ad platform seen, whether a dedup/event-id (server-side
  // signal), advanced matching (hashed PII), and a click-id were observed. Symmetric across
  // Meta / Google / TikTok / Reddit / Bing / LinkedIn / Snap / Pinterest / X — not Meta-only.
  pixelMatrix: Object.values(pixelMatrix).map((m) => ({ ...m, hosts: [...m.hosts] })),
};
fs.writeFileSync(OUT, JSON.stringify(result, null, 1));
const capi = Object.values(pixelMatrix).filter((m) => m.dedupIdSeen).map((m) => m.platform);
console.error(`wrote ${OUT}  (authed=${authed}, dataLayer=${inPage.dataLayer.length}, scripts=${inPage.scriptsLoaded.length}, 3p-hosts=${thirdPartyHosts.length}, fp-proxy=${fpCandidates.size}, adPlatforms=${Object.keys(pixelMatrix).length}, dedup/CAPI-signal: ${capi.join(',') || 'none'})`);
console.error('NOTE: regexHits are hints only — classify thirdPartyHosts + firstPartyProxyCandidates + scriptsLoaded yourself; do not treat 0 hits as "no tracking".');
await browser.close();
