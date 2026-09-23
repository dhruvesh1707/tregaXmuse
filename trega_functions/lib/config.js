"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CASHFREE_API_VERSION = exports.BULKPE_BASE = exports.BULKPE_API_TOKEN = exports.CASHFREE_ENV = exports.CASHFREE_SECRET_KEY = exports.CASHFREE_APP_ID = void 0;
exports.cashfreeBase = cashfreeBase;
const params_1 = require("firebase-functions/params");
// Firebase secrets — set with:
//   firebase functions:secrets:set CASHFREE_APP_ID
//   firebase functions:secrets:set CASHFREE_SECRET_KEY
//   firebase functions:secrets:set CASHFREE_ENV          # "sandbox" | "production"
//   firebase functions:secrets:set BULKPE_API_TOKEN
exports.CASHFREE_APP_ID = (0, params_1.defineSecret)("CASHFREE_APP_ID");
exports.CASHFREE_SECRET_KEY = (0, params_1.defineSecret)("CASHFREE_SECRET_KEY");
exports.CASHFREE_ENV = (0, params_1.defineSecret)("CASHFREE_ENV");
exports.BULKPE_API_TOKEN = (0, params_1.defineSecret)("BULKPE_API_TOKEN");
exports.BULKPE_BASE = "https://api.bulkpe.in";
function cashfreeBase(env) {
    return env === "production"
        ? "https://api.cashfree.com/pg"
        : "https://sandbox.cashfree.com/pg";
}
// Cashfree PG API version header. Bump if Cashfree releases a newer
// version you want to adopt; keep in sync with their changelog.
exports.CASHFREE_API_VERSION = "2025-01-01";
//# sourceMappingURL=config.js.map