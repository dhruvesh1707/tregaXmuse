import { defineSecret } from "firebase-functions/params";

// Firebase secrets, set with:
//   firebase functions:secrets:set CASHFREE_APP_ID
//   firebase functions:secrets:set CASHFREE_SECRET_KEY
//   firebase functions:secrets:set CASHFREE_ENV          # "sandbox" | "production"
//   firebase functions:secrets:set BULKPE_API_TOKEN
//   firebase functions:secrets:set KYC_SALT             # random 32+ char string; salts Aadhaar dedupe hashes
//   firebase functions:secrets:set ADMIN_BOOTSTRAP_PHONE # E.164 founder number, e.g. +919876543210;
//                                                        # the ONLY number bootstrapAdmin will grant the admin claim to
//   firebase functions:secrets:set SHIPROCKET_API_EMAIL    # Shiprocket API user email (distinct from the panel login)
//   firebase functions:secrets:set SHIPROCKET_API_PASSWORD # Shiprocket API user password (shown once at creation)
//   firebase functions:secrets:set SHIPROCKET_WEBHOOK_KEY  # security token set on the Shiprocket webhook in the panel
export const CASHFREE_APP_ID = defineSecret("CASHFREE_APP_ID");
export const CASHFREE_SECRET_KEY = defineSecret("CASHFREE_SECRET_KEY");
export const CASHFREE_ENV = defineSecret("CASHFREE_ENV");
export const BULKPE_API_TOKEN = defineSecret("BULKPE_API_TOKEN");
export const KYC_SALT = defineSecret("KYC_SALT");
export const ADMIN_BOOTSTRAP_PHONE = defineSecret("ADMIN_BOOTSTRAP_PHONE");
export const SHIPROCKET_API_EMAIL = defineSecret("SHIPROCKET_API_EMAIL");
export const SHIPROCKET_API_PASSWORD = defineSecret("SHIPROCKET_API_PASSWORD");
export const SHIPROCKET_WEBHOOK_KEY = defineSecret("SHIPROCKET_WEBHOOK_KEY");

export const SHIPROCKET_BASE = "https://apiv2.shiprocket.in/v1/external";

export const BULKPE_BASE = "https://api.bulkpe.in";

export function cashfreeBase(env: string): string {
  return env === "production"
    ? "https://api.cashfree.com/pg"
    : "https://sandbox.cashfree.com/pg";
}

// Cashfree PG API version header. Bump if Cashfree releases a newer
// version you want to adopt; keep in sync with their changelog.
export const CASHFREE_API_VERSION = "2025-01-01";
