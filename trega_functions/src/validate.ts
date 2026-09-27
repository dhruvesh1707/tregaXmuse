import { HttpsError } from "firebase-functions/v2/https";

/**
 * Strict input validation for every callable.
 *
 * Every external value is checked against a schema (type, length, format)
 * and REJECTED when it doesn't match — never sanitized-and-hoped. All
 * failures throw `invalid-argument` with a user-safe message.
 */

/**
 * Firestore document IDs. Rejects anything that isn't a plain ID —
 * notably `/`, `.` and whitespace, so path-traversal style values like
 * `../../users/x` can never reach `collection().doc()`.
 */
const DOC_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
export function assertDocId(id: unknown, name: string): asserts id is string {
  if (typeof id !== "string" || !DOC_ID_RE.test(id)) {
    throw new HttpsError("invalid-argument", `Invalid ${name}.`);
  }
}

/** Digits with optional leading `+`, 8–15 digits (E.164 range). */
const PHONE_RE = /^\+?[1-9]\d{7,14}$/;
export function assertPhone(phone: unknown, name = "phone number"): string {
  const p = typeof phone === "string" ? phone.replace(/[\s-]/g, "") : "";
  if (!PHONE_RE.test(p)) {
    throw new HttpsError("invalid-argument", `Enter a valid ${name}.`);
  }
  return p;
}

/** Trimmed string within [min, max] characters. Returns the trimmed value. */
export function assertText(
  v: unknown,
  name: string,
  min: number,
  max: number
): string {
  if (typeof v !== "string") {
    throw new HttpsError("invalid-argument", `Invalid ${name}.`);
  }
  const t = v.trim();
  if (t.length < min || t.length > max) {
    throw new HttpsError(
      "invalid-argument",
      min <= 1
        ? `${name} must be under ${max} characters.`
        : `${name} must be between ${min} and ${max} characters.`
    );
  }
  return t;
}

/**
 * Money amounts: finite, positive, capped. The cap keeps absurd values
 * (typos, tampered clients) away from Cashfree and the order ledger.
 */
const MAX_AMOUNT = 100_000_000; // ₹10 crore — above any real listing
export function assertAmount(n: unknown, name = "amount"): number {
  if (
    typeof n !== "number" ||
    !Number.isFinite(n) ||
    n <= 0 ||
    n > MAX_AMOUNT
  ) {
    throw new HttpsError("invalid-argument", `Enter a valid ${name}.`);
  }
  return n;
}
