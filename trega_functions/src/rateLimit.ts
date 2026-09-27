import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

/**
 * Firestore-backed rate limiting for every callable + the Cashfree webhook.
 *
 * Tiers (stricter → looser):
 * - auth tier (`kycOtp`, `kycVerify`, `bootstrap`): OTP issuance, OTP
 *   verification, and the one-shot admin bootstrap. Per-account AND per-IP,
 *   with exponential backoff. (Trega's actual sign-in is Firebase phone
 *   auth, which Google rate-limits itself — these are our auth-adjacent
 *   routes: Aadhaar OTP is the abuse-sensitive one since BulkPe bills per
 *   OTP and OTP guessing is a real attack.)
 * - moderate (`webhook`, `adminOps`): the Cashfree webhook (per-IP) and
 *   admin-panel mutations (per-account).
 * - loose (`bids`, `payments`): normal authenticated user actions.
 * - destructive (`deleteAccount`): 3/day per account.
 *
 * Backoff, not lockout: exceeding the limit blocks for
 * `blockBaseSec * 2^(violations-1)`, capped at `blockMaxSec`. A full clean
 * window resets the violation count, so backoff can never become a
 * permanent lockout.
 *
 * Thresholds are configurable at runtime via the `config/rateLimits` doc
 * (console-only; clients cannot read it — see firestore.rules):
 *   { "<tier>": { limit, windowSec, blockBaseSec, blockMaxSec } }
 * Missing/invalid entries fall back to the bundled defaults below. The doc
 * is cached in memory for 60s so the hot path costs one Firestore
 * transaction, not two.
 */

export interface RateLimitRule {
  /** Max requests per window. */
  limit: number;
  /** Window length in seconds. */
  windowSec: number;
  /** First block duration in seconds (doubles per consecutive violation). */
  blockBaseSec: number;
  /** Block duration cap in seconds. */
  blockMaxSec: number;
}

const DEFAULT_RULES: Record<string, RateLimitRule> = {
  kycOtp: { limit: 5, windowSec: 3600, blockBaseSec: 300, blockMaxSec: 7200 },
  kycVerify: { limit: 10, windowSec: 600, blockBaseSec: 300, blockMaxSec: 7200 },
  bootstrap: { limit: 5, windowSec: 3600, blockBaseSec: 600, blockMaxSec: 7200 },
  webhook: { limit: 120, windowSec: 3600, blockBaseSec: 60, blockMaxSec: 3600 },
  adminOps: { limit: 120, windowSec: 3600, blockBaseSec: 60, blockMaxSec: 3600 },
  bids: { limit: 60, windowSec: 3600, blockBaseSec: 60, blockMaxSec: 1800 },
  payments: { limit: 30, windowSec: 3600, blockBaseSec: 120, blockMaxSec: 3600 },
  deleteAccount: { limit: 3, windowSec: 86400, blockBaseSec: 3600, blockMaxSec: 86400 },
};

const RULE_CACHE_TTL_MS = 60_000;
let ruleCache: { at: number; rules: Record<string, RateLimitRule> } | null =
  null;

function isValidRule(v: unknown): v is RateLimitRule {
  if (typeof v !== "object" || v === null) return false;
  const r = v as Record<string, unknown>;
  return (
    typeof r.limit === "number" &&
    r.limit > 0 &&
    typeof r.windowSec === "number" &&
    r.windowSec > 0 &&
    typeof r.blockBaseSec === "number" &&
    r.blockBaseSec > 0 &&
    typeof r.blockMaxSec === "number" &&
    r.blockMaxSec > 0
  );
}

async function getRule(tier: string): Promise<RateLimitRule> {
  const now = Date.now();
  if (!ruleCache || now - ruleCache.at > RULE_CACHE_TTL_MS) {
    let rules = DEFAULT_RULES;
    try {
      const snap = await admin
        .firestore()
        .collection("config")
        .doc("rateLimits")
        .get();
      const data = snap.data();
      if (data) {
        const merged: Record<string, RateLimitRule> = { ...DEFAULT_RULES };
        for (const [k, v] of Object.entries(data)) {
          if (isValidRule(v)) merged[k] = v;
          else logger.warn("rateLimit: ignoring invalid rule override", { tier: k });
        }
        rules = merged;
      }
    } catch (e) {
      logger.warn("rateLimit: could not load config/rateLimits, using defaults", {
        error: String(e),
      });
    }
    ruleCache = { at: now, rules };
  }
  return ruleCache.rules[tier] ?? DEFAULT_RULES[tier];
}

interface Bucket {
  count: number;
  windowStart: number;
  violations: number;
  blockedUntil: number;
}

async function checkBucket(
  tier: string,
  scope: string,
  rule: RateLimitRule
): Promise<void> {
  const db = admin.firestore();
  const ref = db.collection("rateLimits").doc(`${tier}:${scope}`);
  const windowMs = rule.windowSec * 1000;
  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const b = (snap.data() ?? {}) as Partial<Bucket>;
    const count = b.count ?? 0;
    const windowStart = b.windowStart ?? 0;
    const violations = b.violations ?? 0;
    const blockedUntil = b.blockedUntil ?? 0;

    if (blockedUntil > now) {
      const retrySec = Math.ceil((blockedUntil - now) / 1000);
      throw new HttpsError(
        "resource-exhausted",
        `Too many requests. Try again in ${retrySec}s.`
      );
    }
    if (!snap.exists || now - windowStart >= windowMs) {
      // Fresh window. A clean window also clears the violation history,
      // so backoff decays instead of becoming a permanent lockout.
      tx.set(ref, { count: 1, windowStart: now, violations: 0, blockedUntil: 0 });
      return;
    }
    if (count < rule.limit) {
      tx.set(
        ref,
        { count: count + 1, windowStart, violations, blockedUntil: 0 },
        { merge: true }
      );
      return;
    }
    // Over the limit — exponential backoff, capped.
    const nextViolations = violations + 1;
    const blockMs =
      Math.min(rule.blockBaseSec * 2 ** (nextViolations - 1), rule.blockMaxSec) *
      1000;
    tx.set(
      ref,
      {
        count,
        windowStart,
        violations: nextViolations,
        blockedUntil: now + blockMs,
      },
      { merge: true }
    );
    throw new HttpsError(
      "resource-exhausted",
      `Too many requests. Try again in ${Math.ceil(blockMs / 1000)}s.`
    );
  });
}

/**
 * Enforce the rate-limit tier for this request. Pass BOTH uid and ip for
 * auth-tier endpoints (per-account + per-IP); uid-only is fine for purely
 * authenticated actions. Missing ip is skipped, never fatal.
 */
export async function rateLimit(
  tier: string,
  opts: { uid?: string; ip?: string }
): Promise<void> {
  const rule = await getRule(tier);
  const jobs: Array<Promise<void>> = [];
  if (opts.uid) jobs.push(checkBucket(tier, `uid:${opts.uid}`, rule));
  if (opts.ip) jobs.push(checkBucket(tier, `ip:${opts.ip}`, rule));
  await Promise.all(jobs);
}

/**
 * Best-effort client IP from a callable's rawRequest or an Express req.
 * Prefers X-Forwarded-For (what Cloud Run actually sees) then req.ip.
 */
export function clientIp(req: unknown): string | undefined {
  const r = req as
    | {
        ip?: string;
        headers?: Record<string, string | string[] | undefined>;
        socket?: { remoteAddress?: string };
      }
    | undefined;
  if (!r) return undefined;
  const fwd = r.headers?.["x-forwarded-for"];
  const first = Array.isArray(fwd) ? fwd[0] : fwd?.split(",")[0]?.trim();
  return first || r.ip || r.socket?.remoteAddress || undefined;
}
