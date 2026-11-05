import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/**
 * Server-rendered public listing pages + listings sitemap (SEO Phase 3).
 *
 * PUBLIC DOMAIN RULE (founder, 2026-11-05): the public domain is
 * trega.in; listing pages live on its subdomain listings.trega.in.
 * tregaxmuse.web.app is internal and must never appear in a canonical,
 * OG tag, sitemap or shared link produced here. Every public URL below
 * is built from this single constant — change it here only.
 */
export const PUBLIC_BASE_URL = "https://listings.trega.in";

/** Apex marketing site — Phase 1 category pages live here, not on the
 * listings subdomain, so category cross-links use this base. */
const SITE_BASE_URL = "https://trega.in";

const PLAY_URL =
  "https://play.google.com/store/apps/details?id=com.trega.trega";

/** Firestore categoryId (normalised) -> Phase 1 category page slug. */
const CATEGORY_PAGES: Record<string, string> = {
  gaming: "used-gaming-consoles",
  mobiles: "second-hand-mobiles",
  mobile: "second-hand-mobiles",
  laptops: "second-hand-laptops",
  laptop: "second-hand-laptops",
  cameras: "second-hand-cameras",
  camera: "second-hand-cameras",
  music: "second-hand-music-instruments",
  fashion: "pre-owned-fashion",
  furniture: "used-furniture",
  "home-appliances": "used-home-appliances",
  appliances: "used-home-appliances",
  cycles: "second-hand-cycles",
  cycle: "second-hand-cycles",
  watches: "second-hand-watches",
  watch: "second-hand-watches",
  collectibles: "collectibles",
  books: "second-hand-books",
  others: "others",
  other: "others",
};

export function categoryPageUrl(categoryId: string | null): string {
  if (!categoryId) return `${SITE_BASE_URL}/`;
  const key = categoryId.trim().toLowerCase().replace(/_/g, "-");
  const slug = CATEGORY_PAGES[key];
  return slug ? `${SITE_BASE_URL}/${slug}` : `${SITE_BASE_URL}/`;
}

const CONDITION_LABELS: Record<string, string> = {
  brand_new: "Brand new",
  like_new: "Like new",
  good: "Good",
  fair: "Fair",
};

export interface ListingView {
  id: string;
  title: string;
  description: string;
  price: number;
  conditionLabel: string;
  city: string;
  photos: string[];
  categoryId: string | null;
  status: string;
  lastmodMs: number | null;
}

export interface SimilarListing {
  id: string;
  title: string;
  price: number;
  city: string;
  photo: string;
}

function asRecord(v: unknown): Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
}

function asString(v: unknown): string {
  return typeof v === "string" ? v : "";
}

function asNumber(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function tsToMs(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === "number") return v;
  const rec = v as { toMillis?: unknown; _seconds?: unknown; seconds?: unknown };
  if (typeof rec.toMillis === "function") {
    return (rec.toMillis as () => number).call(v);
  }
  const secs = typeof rec._seconds === "number" ? rec._seconds
    : typeof rec.seconds === "number" ? rec.seconds : null;
  return secs === null ? null : secs * 1000;
}

function photoList(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  for (const item of v) {
    if (typeof item === "string" && item.startsWith("http")) out.push(item);
    else {
      const url = asString(asRecord(item).url);
      if (url.startsWith("http")) out.push(url);
    }
  }
  return out;
}

function conditionLabel(raw: unknown, product: Record<string, unknown>): string {
  const candidates: unknown[] = [raw, product.condition];
  for (const c of candidates) {
    if (typeof c === "string" && c) {
      return CONDITION_LABELS[c] ?? c;
    }
    const rec = asRecord(c);
    const label = asString(rec.label) || asString(rec.value);
    if (label) return CONDITION_LABELS[label] ?? label;
  }
  return "";
}

/**
 * Normalise a raw listings/{id} document into the public view model.
 * Handles BOTH the canonical FIRESTORE_MODEL shape (top-level title /
 * description / condition / categoryId) and the legacy `product` map the
 * old share-preview page was written against. Only fields the public
 * preview already exposes are read — never sellerId, addresses or
 * anything private.
 */
export function normalizeListing(
  id: string,
  data: Record<string, unknown> | undefined
): ListingView | null {
  if (!data) return null;
  const product = asRecord(data.product);
  const title = asString(data.title) || asString(product.title);
  if (!title) return null;
  const status = (asString(data.status) || asString(product.status)).toLowerCase();
  const lastmodMs =
    tsToMs(data.soldAt) ?? tsToMs(data.updatedAt) ?? tsToMs(data.liveAt) ??
    tsToMs(data.createdAt);
  return {
    id,
    title,
    description: asString(data.description) || asString(product.description),
    price: asNumber(data.price ?? product.price),
    conditionLabel: conditionLabel(data.condition, product),
    city: asString(data.city) || asString(product.city),
    photos: photoList(data.photos ?? product.photos),
    categoryId:
      asString(data.categoryId) || asString(product.categoryId) ||
      asString(data.category) || null,
    status,
    lastmodMs,
  };
}

export function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function inr(n: number): string {
  return n > 0 ? `₹${Math.round(n).toLocaleString("en-IN")}` : "";
}

function truncate(s: string, max: number): string {
  const flat = s.replace(/\s+/g, " ").trim();
  return flat.length <= max ? flat : `${flat.slice(0, max - 1).trimEnd()}…`;
}

const PAGE_CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #faf8f4; color: #1c1917; min-height: 100vh; }
  header { padding: 18px 20px; display: flex; align-items: center; gap: 10px; max-width: 880px; margin: 0 auto; width: 100%; }
  header .logo { font-weight: 800; font-size: 22px; letter-spacing: -0.5px; color: #1c1917; text-decoration: none; }
  header .logo .dot { color: #e8a020; }
  main { width: 100%; max-width: 880px; margin: 0 auto; padding: 12px 20px 48px; display: flex; flex-direction: column; gap: 18px; }
  .card { background: #fff; border-radius: 20px; overflow: hidden; box-shadow: 0 8px 30px rgba(0,0,0,.08); }
  .photo { width: 100%; aspect-ratio: 4/3; background: #e7e2d9; object-fit: cover; display: block; }
  .thumbs { display: flex; gap: 8px; padding: 10px; overflow-x: auto; }
  .thumbs img { width: 84px; height: 64px; object-fit: cover; border-radius: 10px; }
  .body { padding: 20px; display: flex; flex-direction: column; gap: 9px; }
  .price { font-size: 28px; font-weight: 800; }
  h1 { font-size: 21px; font-weight: 650; line-height: 1.35; }
  .meta { font-size: 14.5px; color: #78716c; }
  .desc { font-size: 15.5px; line-height: 1.55; color: #292524; white-space: pre-wrap; }
  .sold { display: inline-block; font-size: 13px; font-weight: 800; letter-spacing: .08em;
    color: #fff; background: #8B3A1C; border-radius: 999px; padding: 5px 14px; width: fit-content; }
  .trust { font-size: 14px; color: #57534e; background: #fef9ec; border: 1px solid #f3e3b3;
    border-radius: 12px; padding: 12px 14px; line-height: 1.5; }
  .cta { display: block; text-align: center; text-decoration: none; background: #1c1917; color: #fff;
    font-weight: 700; font-size: 17px; border-radius: 16px; padding: 16px; }
  .cta small { display: block; font-weight: 400; font-size: 12px; color: #d6d3d1; margin-top: 4px; }
  .play { display: block; text-align: center; text-decoration: none; color: #8B3A1C; font-weight: 700; font-size: 15px; padding: 6px; }
  h2.more { font-size: 18px; font-weight: 750; margin-top: 8px; }
  .simgrid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 12px; }
  .sim { background: #fff; border-radius: 14px; overflow: hidden; text-decoration: none; color: inherit;
    box-shadow: 0 4px 16px rgba(0,0,0,.06); }
  .sim img { width: 100%; aspect-ratio: 4/3; object-fit: cover; display: block; background: #e7e2d9; }
  .sim .sbody { padding: 10px 12px; display: flex; flex-direction: column; gap: 3px; }
  .sim .st { font-size: 14px; font-weight: 600; line-height: 1.3; }
  .sim .sp { font-size: 14.5px; font-weight: 800; color: #8B3A1C; }
  .sim .sc { font-size: 12.5px; color: #78716c; }
  .catlink { font-size: 15px; font-weight: 650; color: #8B3A1C; }
  .error { text-align: center; padding: 60px 20px; color: #78716c; }
  .hint { text-align: center; font-size: 13px; color: #a8a29e; }
`;

/** Pure renderer: complete SEO HTML for one listing page. */
export function renderListingPage(
  vm: ListingView,
  similar: SimilarListing[]
): string {
  const url = `${PUBLIC_BASE_URL}/l/${encodeURIComponent(vm.id)}`;
  const sold = vm.status === "sold";
  const titleTag = vm.city
    ? `Second hand ${vm.title} for sale in ${vm.city} | Trega`
    : `Second hand ${vm.title} for sale | Trega`;
  const priceText = inr(vm.price);
  const descParts = [
    `${vm.title}${priceText ? ` for sale at ${priceText}` : " for sale"} on Trega.`,
    vm.conditionLabel ? `Condition: ${vm.conditionLabel}.` : "",
    vm.city ? `Located in ${vm.city}.` : "",
    "Every seller on Trega is KYC verified. No chat, only offers.",
  ].filter(Boolean);
  const metaDesc = truncate(descParts.join(" "), 160);
  const firstPhoto = vm.photos.length ? vm.photos[0] : "";

  const schema = {
    "@context": "https://schema.org",
    "@type": "Product",
    name: vm.title,
    ...(vm.photos.length ? { image: vm.photos } : {}),
    ...(vm.description ? { description: truncate(vm.description, 500) } : {}),
    offers: {
      "@type": "Offer",
      url,
      priceCurrency: "INR",
      price: vm.price,
      availability: sold
        ? "https://schema.org/SoldOut"
        : "https://schema.org/InStock",
      itemCondition: "https://schema.org/UsedCondition",
    },
  };

  const metaBits = [vm.conditionLabel, vm.city].filter(Boolean).map(esc).join(" · ");
  const thumbs = vm.photos.length > 1
    ? `<div class="thumbs">${vm.photos.slice(1).map((p) =>
        `<img src="${esc(p)}" alt="${esc(vm.title)}" loading="lazy">`).join("")}</div>`
    : "";
  const simCards = similar.map((s) => `
      <a class="sim" href="${PUBLIC_BASE_URL}/l/${encodeURIComponent(s.id)}">
        ${s.photo ? `<img src="${esc(s.photo)}" alt="${esc(s.title)}" loading="lazy">` : ""}
        <span class="sbody"><span class="st">${esc(s.title)}</span>
        ${inr(s.price) ? `<span class="sp">${inr(s.price)}</span>` : ""}
        ${s.city ? `<span class="sc">${esc(s.city)}</span>` : ""}</span>
      </a>`).join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(titleTag)}</title>
<meta name="description" content="${esc(metaDesc)}">
<link rel="canonical" href="${url}">
<meta property="og:title" content="${esc(titleTag)}">
<meta property="og:description" content="${esc(metaDesc)}">
<meta property="og:type" content="website">
<meta property="og:url" content="${url}">
${firstPhoto ? `<meta property="og:image" content="${esc(firstPhoto)}">` : ""}
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">${JSON.stringify(schema)}</script>
<style>${PAGE_CSS}</style>
</head>
<body>
<header><a class="logo" href="${PUBLIC_BASE_URL}/">trega<span class="dot">.</span></a></header>
<main>
  <div class="card">
    ${firstPhoto ? `<img class="photo" src="${esc(firstPhoto)}" alt="${esc(vm.title)}">` : ""}
    ${thumbs}
    <div class="body">
      ${sold ? `<span class="sold">SOLD</span>` : ""}
      ${priceText ? `<div class="price">${priceText}</div>` : ""}
      <h1>${esc(vm.title)}</h1>
      ${metaBits ? `<div class="meta">${metaBits}</div>` : ""}
      ${vm.description ? `<p class="desc">${esc(vm.description)}</p>` : ""}
      <p class="trust">The seller of this listing is KYC (Aadhaar) verified on Trega.
      Trega has no chat — buyers place offers in the app, and the seller accepts the one they like.
      Payment goes through Cashfree when a deal is accepted.</p>
    </div>
  </div>
  <a class="cta" href="trega://listing/${encodeURIComponent(vm.id)}">Make an Offer in the Trega app<small>Tap to open this listing in the app</small></a>
  <p class="hint">Offers and checkout happen only in the Trega app.</p>
  <a class="play" href="${PLAY_URL}">No app yet? Get Trega on Google Play</a>
  ${similar.length ? `<h2 class="more">Similar live listings</h2><div class="simgrid">${simCards}</div>` : ""}
  <p><a class="catlink" href="${categoryPageUrl(vm.categoryId)}">Browse more pre-owned listings on Trega</a></p>
  <p class="hint">Trega — pre-owned gear, verified sellers, offers only.</p>
</main>
<script>
(function () {
  var ua = navigator.userAgent || "";
  if (/Android|iPhone|iPad|iPod/i.test(ua)) {
    // If the app is installed, hand over to it. If not, nothing happens
    // and this page (with the button above) stays fully usable.
    window.location.href = "trega://listing/${"${encodeURIComponent(vm.id)}"}";
  }
})();
</script>
</body>
</html>`;
}

/** 404 page for draft / pending / rejected / deleted / unknown listings. */
export function renderNotFoundPage(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Listing not available | Trega</title>
<meta name="robots" content="noindex">
<style>${PAGE_CSS}</style>
</head>
<body>
<header><a class="logo" href="${PUBLIC_BASE_URL}/">trega<span class="dot">.</span></a></header>
<main>
  <div class="error">
    <p style="font-size:19px;font-weight:700;margin-bottom:8px">This listing is not available</p>
    <p>It may have been sold, removed, or is still under review.</p>
  </div>
  <a class="cta" href="trega://">Open the Trega app<small>Browse live pre-owned listings</small></a>
  <a class="play" href="${PLAY_URL}">Get Trega on Google Play</a>
</main>
</body>
</html>`;
}

/** Pure builder: listings sitemap XML (trega.in URLs only). */
export function buildListingsSitemap(items: ListingView[]): string {
  const rows = items.map((vm) => {
    const lastmod = vm.lastmodMs
      ? `<lastmod>${new Date(vm.lastmodMs).toISOString().slice(0, 10)}</lastmod>`
      : "";
    return `  <url><loc>${PUBLIC_BASE_URL}/l/${encodeURIComponent(vm.id)}</loc>${lastmod}<changefreq>daily</changefreq></url>`;
  });
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...rows,
    "</urlset>",
    "",
  ].join("\n");
}

// ------------------------------------------------------------- handlers ----

interface MinimalResponse {
  status: (code: number) => MinimalResponse;
  set: (field: string, value: string) => MinimalResponse;
  send: (body: string) => void;
}

interface MinimalRequest {
  path?: string;
  url?: string;
  query?: Record<string, unknown>;
}

function listingIdFromRequest(req: MinimalRequest): string {
  const path = (req.path ?? req.url ?? "").split("?")[0];
  const segments = path.split("/").filter(Boolean);
  const lIdx = segments.indexOf("l");
  let id = "";
  if (lIdx >= 0 && segments.length > lIdx + 1) id = segments[lIdx + 1];
  else if (typeof req.query?.id === "string") id = req.query.id;
  else if (segments.length && segments[segments.length - 1] !== "listingPage") {
    id = segments[segments.length - 1];
  }
  return /^[A-Za-z0-9_-]{6,64}$/.test(id) ? id : "";
}

export async function listingPageHandler(
  req: MinimalRequest,
  res: MinimalResponse
): Promise<void> {
  const id = listingIdFromRequest(req);
  res.set("Content-Type", "text/html; charset=utf-8");
  if (!id) {
    res.status(404).send(renderNotFoundPage());
    return;
  }
  try {
    const db = admin.firestore();
    const snap = await db.collection("listings").doc(id).get();
    const vm = snap.exists ? normalizeListing(id, snap.data()) : null;
    if (!vm || (vm.status !== "live" && vm.status !== "sold")) {
      res.set("Cache-Control", "public, max-age=300");
      res.status(404).send(renderNotFoundPage());
      return;
    }
    let similar: SimilarListing[] = [];
    if (vm.categoryId) {
      try {
        const simSnap = await db.collection("listings")
          .where("categoryId", "==", vm.categoryId)
          .where("status", "==", "live")
          .limit(12)
          .get();
        similar = simSnap.docs
          .map((d) => normalizeListing(d.id, d.data()))
          .filter((s): s is ListingView => s !== null && s.id !== vm.id)
          .slice(0, 6)
          .map((s) => ({
            id: s.id, title: s.title, price: s.price, city: s.city,
            photo: s.photos.length ? s.photos[0] : "",
          }));
      } catch (e) {
        logger.warn("listingPage: similar listings query failed", { id, e });
      }
    }
    res.set("Cache-Control", "public, max-age=300");
    res.status(200).send(renderListingPage(vm, similar));
  } catch (e) {
    logger.error("listingPage failed", { id, e });
    res.status(500).send(renderNotFoundPage());
  }
}

export async function listingsSitemapHandler(
  res: MinimalResponse
): Promise<void> {
  try {
    const db = admin.firestore();
    const byId = new Map<string, ListingView>();
    for (const status of ["live", "sold"]) {
      const snap = await db.collection("listings")
        .where("status", "==", status)
        .limit(5000)
        .get();
      for (const doc of snap.docs) {
        const vm = normalizeListing(doc.id, doc.data());
        if (vm) byId.set(vm.id, vm);
      }
    }
    res.set("Content-Type", "application/xml; charset=utf-8");
    res.set("Cache-Control", "public, max-age=3600");
    res.status(200).send(buildListingsSitemap([...byId.values()]));
  } catch (e) {
    logger.error("listingsSitemap failed", { e });
    res.status(500).send("sitemap unavailable");
  }
}
