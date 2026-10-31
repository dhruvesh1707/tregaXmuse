import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { createHash, randomInt, timingSafeEqual } from "node:crypto";
import {
  MSG91_AUTH_KEY,
  MSG91_BASE,
  MSG91_SENDER_ID,
  MSG91_TEMPLATE_ID,
} from "./config";

/**
 * Branded login OTP — the replacement for Firebase-sent phone-auth SMS.
 *
 * Firebase's built-in phone auth sends a fixed Google-templated SMS from a
 * Google sender ID; the text cannot carry Trega branding. Here the OTP is
 * generated and verified by these callables and the SMS goes out through
 * MSG91 under Trega's own DLT-approved sender header + template (secrets:
 * MSG91_AUTH_KEY / MSG91_SENDER_ID / MSG91_TEMPLATE_ID). On a successful
 * verify the handler mints a Firebase custom token, so the rest of the
 * auth stack (Auth users, users/{uid} docs, claims) is unchanged.
 *
 * These callables are PRE-AUTH by design — they are how a signed-out user
 * signs in — so `index.ts` cannot gate them behind requireAuthUid. The
 * abuse controls live here plus the `loginOtp` / `loginVerify` rate-limit
 * tiers (per-IP, see rateLimit.ts):
 * - codes are 6 digits, stored ONLY as SHA-256(phone + ":" + code);
 * - the Firestore doc id is SHA-256(phone) — raw numbers are never keys;
 * - 60s resend throttle and a rolling 6-per-24h cap per phone;
 * - 10-minute code life; 5 verify attempts, then the code is destroyed;
 * - single use: a successful verify deletes the doc.
 *
 * Existing accounts keep their uid: verify looks the phone up in Firebase
 * Auth first and mints the token for that uid; only a genuinely new phone
 * creates a new Auth user.
 */

// Play-review test login (same number as the old Firebase test number).
// Never sends an SMS; the fixed code is accepted so store reviewers can
// still sign in after the switch from Firebase phone auth.
const TEST_PHONE_E164 = "+919876543210";
const TEST_CODE = "123456";

const CODE_TTL_MS = 10 * 60_000;
const RESEND_THROTTLE_MS = 60_000;
const MAX_SENDS_PER_DAY = 6;
const MAX_VERIFY_ATTEMPTS = 5;
const DAY_MS = 24 * 60 * 60_000;

/** Canonical +91 E.164 for an Indian mobile, or reject. */
export function normalizeIndianPhone(raw: unknown): string {
  const digits = typeof raw === "string" ? raw.replace(/[\s-]/g, "") : "";
  const m = digits.match(/^(?:\+91|91)?([6-9]\d{9})$/);
  if (!m) {
    throw new HttpsError(
      "invalid-argument",
      "Enter a valid 10-digit mobile number."
    );
  }
  return `+91${m[1]}`;
}

function sha256Hex(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

function docIdFor(phoneE164: string): string {
  return sha256Hex(phoneE164);
}

function hashCode(phoneE164: string, code: string): string {
  return sha256Hex(`${phoneE164}:${code}`);
}

/**
 * Send `code` via MSG91's SendOTP API using Trega's DLT template.
 * Fails closed: a missing secret or a non-success response throws, and no
 * code is stored, so an undelivered code can never be verified.
 */
async function sendViaMsg91(phoneE164: string, code: string): Promise<void> {
  const authKey = MSG91_AUTH_KEY.value();
  const sender = MSG91_SENDER_ID.value();
  const templateId = MSG91_TEMPLATE_ID.value();
  if (!authKey || !sender || !templateId) {
    throw new HttpsError(
      "failed-precondition",
      "Login SMS is not configured yet."
    );
  }
  const mobile = phoneE164.replace("+", "");
  const url =
    `${MSG91_BASE}/otp?template_id=${encodeURIComponent(templateId)}` +
    `&mobile=${mobile}&otp=${code}&sender=${encodeURIComponent(sender)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { authkey: authKey, "Content-Type": "application/json" },
  });
  if (!res.ok) {
    logger.error("loginOtp: MSG91 HTTP error", { status: res.status });
    throw new HttpsError(
      "unavailable",
      `SMS provider error (HTTP ${res.status}). Please try again.`
    );
  }
  const body = (await res.json().catch(() => null)) as
    | { type?: string; message?: string }
    | null;
  if (!body || body.type !== "success") {
    logger.error("loginOtp: MSG91 rejected the send", {
      message: body?.message ?? "no response body",
    });
    throw new HttpsError(
      "unavailable",
      "Could not send the OTP SMS. Please try again."
    );
  }
}

export async function requestLoginOtpHandler(
  phoneRaw: unknown
): Promise<{ sent: true; resendAfterSec: number }> {
  const phone = normalizeIndianPhone(phoneRaw);
  const db = admin.firestore();
  const ref = db.collection("loginOtps").doc(docIdFor(phone));
  const now = Date.now();

  const snap = await ref.get();
  const d = snap.data() as
    | {
        lastSentAtMs?: number;
        sendCount?: number;
        sendWindowStartMs?: number;
      }
    | undefined;

  if (d?.lastSentAtMs && now - d.lastSentAtMs < RESEND_THROTTLE_MS) {
    throw new HttpsError(
      "resource-exhausted",
      "Please wait a minute before requesting another code."
    );
  }
  const windowStart = d?.sendWindowStartMs ?? now;
  const inWindow = now - windowStart < DAY_MS;
  const sendCount = inWindow ? (d?.sendCount ?? 0) : 0;
  if (sendCount >= MAX_SENDS_PER_DAY) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many codes requested for this number today. Try again tomorrow."
    );
  }

  const isTest = phone === TEST_PHONE_E164;
  const code = isTest
    ? TEST_CODE
    : String(randomInt(0, 1_000_000)).padStart(6, "0");
  if (!isTest) {
    await sendViaMsg91(phone, code);
  }

  await ref.set({
    codeHash: hashCode(phone, code),
    attempts: 0,
    lastSentAtMs: now,
    expiresAtMs: now + CODE_TTL_MS,
    sendCount: sendCount + 1,
    sendWindowStartMs: inWindow ? windowStart : now,
    requestedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { sent: true, resendAfterSec: RESEND_THROTTLE_MS / 1000 };
}

export async function verifyLoginOtpHandler(
  phoneRaw: unknown,
  otpRaw: unknown
): Promise<{ token: string }> {
  const phone = normalizeIndianPhone(phoneRaw);
  if (typeof otpRaw !== "string" || !/^\d{6}$/.test(otpRaw.trim())) {
    throw new HttpsError("invalid-argument", "Enter the 6-digit code.");
  }
  const code = otpRaw.trim();

  const db = admin.firestore();
  const ref = db.collection("loginOtps").doc(docIdFor(phone));
  const snap = await ref.get();
  const d = snap.data() as
    | { codeHash?: string; attempts?: number; expiresAtMs?: number }
    | undefined;
  if (!d?.codeHash) {
    throw new HttpsError("failed-precondition", "Request a new code first.");
  }
  if (typeof d.expiresAtMs === "number" && Date.now() > d.expiresAtMs) {
    await ref.delete();
    throw new HttpsError(
      "failed-precondition",
      "That code has expired. Request a new one."
    );
  }
  const attempts = d.attempts ?? 0;
  if (attempts >= MAX_VERIFY_ATTEMPTS) {
    await ref.delete();
    throw new HttpsError(
      "failed-precondition",
      "Too many incorrect attempts. Request a new code."
    );
  }

  const expected = Buffer.from(d.codeHash, "utf8");
  const actual = Buffer.from(hashCode(phone, code), "utf8");
  const match =
    expected.length === actual.length && timingSafeEqual(expected, actual);
  if (!match) {
    await ref.set({ attempts: attempts + 1 }, { merge: true });
    throw new HttpsError(
      "failed-precondition",
      "Incorrect code. Check the code and try again."
    );
  }

  // Single use — destroy the code before minting anything.
  await ref.delete();

  // Keep an existing account's uid (their users/{uid} doc, listings and
  // KYC all hang off it); only a phone Firebase Auth has never seen gets
  // a fresh user.
  const auth = admin.auth();
  let uid: string;
  try {
    uid = (await auth.getUserByPhoneNumber(phone)).uid;
  } catch {
    uid = (await auth.createUser({ phoneNumber: phone })).uid;
  }
  const token = await auth.createCustomToken(uid);
  return { token };
}
