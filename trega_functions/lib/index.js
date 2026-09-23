"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateOrderFulfillment = exports.setUserKycStatus = exports.acceptBid = exports.placeBid = exports.reviewListing = exports.onListingCreate = exports.cashfreeWebhook = exports.createCashfreeOrder = exports.verifyAadhaarOtp = exports.requestAadhaarOtp = void 0;
/**
 * Trega marketplace Cloud Functions (Firebase project: tregaxmuse).
 *
 * - KYC: Aadhaar OTP via BulkPe (token from the BULKPE_API_TOKEN secret).
 * - Payments: Cashfree PG (CASHFREE_APP_ID / CASHFREE_SECRET_KEY / CASHFREE_ENV).
 * - Marketplace: listing review queue, structured bids/offers, orders.
 * - No buyer-seller chat anywhere by design.
 */
const admin = __importStar(require("firebase-admin"));
const v2_1 = require("firebase-functions/v2");
const https_1 = require("firebase-functions/v2/https");
const https_2 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const logger = __importStar(require("firebase-functions/logger"));
const config_1 = require("./config");
const kyc_1 = require("./kyc");
const payments_1 = require("./payments");
const marketplace_1 = require("./marketplace");
const admin_1 = require("./admin");
admin.initializeApp();
(0, v2_1.setGlobalOptions)({ region: "asia-south1", maxInstances: 10 });
const secrets = [config_1.BULKPE_API_TOKEN, config_1.CASHFREE_APP_ID, config_1.CASHFREE_SECRET_KEY, config_1.CASHFREE_ENV];
function requireAuthUid(req) {
    if (!req.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in to continue.");
    }
    return req.auth.uid;
}
// ---------------------------------------------------------------- KYC ------
exports.requestAadhaarOtp = (0, https_1.onCall)({ secrets }, async (request) => {
    const uid = requireAuthUid(request);
    return (0, kyc_1.requestAadhaarOtpHandler)(uid, request.data?.aadhaarNumber);
});
exports.verifyAadhaarOtp = (0, https_1.onCall)({ secrets }, async (request) => {
    const uid = requireAuthUid(request);
    return (0, kyc_1.verifyAadhaarOtpHandler)(uid, request.data?.refId, request.data?.otp);
});
// --------------------------------------------------------- Payments ---------
exports.createCashfreeOrder = (0, https_1.onCall)({ secrets }, async (request) => {
    const uid = requireAuthUid(request);
    return (0, payments_1.createCashfreeOrderHandler)(uid, {
        listingId: request.data?.listingId,
        bidId: request.data?.bidId,
        customerPhone: request.data?.customerPhone,
    });
});
/**
 * Cashfree PG webhook. Register this URL in the Cashfree dashboard:
 * https://asia-south1-tregaxmuse.cloudfunctions.net/cashfreeWebhook
 */
exports.cashfreeWebhook = (0, https_2.onRequest)({ secrets: [config_1.CASHFREE_SECRET_KEY] }, async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).send("Method not allowed");
        return;
    }
    // Use the raw body for signature verification (available on the
    // Express request that firebase-functions v2 provides).
    const rawBody = req.rawBody
        ?? Buffer.from(JSON.stringify(req.body ?? {}), "utf8");
    const result = await (0, payments_1.handleCashfreeWebhook)(rawBody, req.header("x-webhook-signature"));
    if (!result.ok) {
        logger.warn("cashfreeWebhook rejected", { reason: result.reason });
        res.status(400).send(result.reason ?? "rejected");
        return;
    }
    res.status(200).send("ok");
});
// ------------------------------------------------------- Marketplace -------
exports.onListingCreate = (0, firestore_1.onDocumentCreated)("listings/{listingId}", async (event) => {
    await (0, marketplace_1.onListingCreateHandler)(event.params.listingId, event.data?.data());
});
exports.reviewListing = (0, https_1.onCall)(async (request) => {
    const isAdmin = request.auth?.token?.admin === true;
    return (0, marketplace_1.reviewListingHandler)(isAdmin, {
        listingId: request.data?.listingId,
        decision: request.data?.decision,
        reason: request.data?.reason,
    });
});
exports.placeBid = (0, https_1.onCall)(async (request) => {
    const uid = requireAuthUid(request);
    return (0, marketplace_1.placeBidHandler)(uid, {
        listingId: request.data?.listingId,
        amount: request.data?.amount,
    });
});
exports.acceptBid = (0, https_1.onCall)(async (request) => {
    const uid = requireAuthUid(request);
    return (0, marketplace_1.acceptBidHandler)(uid, { bidId: request.data?.bidId });
});
// ------------------------------------------------------------- Admin ------
// Privileged mutations for the admin panel (admin custom claim required).
// Categories are managed directly through Firestore rules (`isAdmin()`).
exports.setUserKycStatus = (0, https_1.onCall)(async (request) => {
    const isAdmin = request.auth?.token?.admin === true;
    return (0, admin_1.setUserKycStatusHandler)(isAdmin, {
        uid: request.data?.uid,
        status: request.data?.status,
        note: request.data?.note,
    });
});
exports.updateOrderFulfillment = (0, https_1.onCall)(async (request) => {
    const isAdmin = request.auth?.token?.admin === true;
    return (0, admin_1.updateOrderFulfillmentHandler)(isAdmin, {
        orderId: request.data?.orderId,
        status: request.data?.status,
        trackingNote: request.data?.trackingNote,
    });
});
//# sourceMappingURL=index.js.map