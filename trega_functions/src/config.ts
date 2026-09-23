import { defineSecret } from "firebase-functions/params";

// Firebase secrets — set with:
//   firebase functions:secrets:set CASHFREE_APP_ID
//   firebase functions:secrets:set CASHFREE_SECRET_KEY
//   firebase functions:secrets:set CASHFREE_ENV          # "sandbox" | "production"
//   firebase functions:secrets:set BULKPE_API_TOKEN
export const CASHFREE_APP_ID = defineSecret("CASHFREE_APP_ID");
export const CASHFREE_SECRET_KEY = defineSecret("CASHFREE_SECRET_KEY");
export const CASHFREE_ENV = defineSecret("CASHFREE_ENV");
export const BULKPE_API_TOKEN = defineSecret("BULKPE_API_TOKEN");

export const BULKPE_BASE = "https://api.bulkpe.in";

export function cashfreeBase(env: string): string {
  return env === "production"
    ? "https://api.cashfree.com/pg"
    : "https://sandbox.cashfree.com/pg";
}

// Cashfree PG API version header. Bump if Cashfree releases a newer
// version you want to adopt; keep in sync with their changelog.
export const CASHFREE_API_VERSION = "2025-01-01";
