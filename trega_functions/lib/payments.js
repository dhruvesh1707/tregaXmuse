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
exports.createCashfreeOrderHandler = createCashfreeOrderHandler;
exports.verifyWebhookSignature = verifyWebhookSignature;
exports.handleCashfreeWebhook = handleCashfreeWebhook;
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
const https_1 = require("firebase-functions/v2/https");
const config_1 = require("./config");
function cashfreeHeaders() {
    const appId = config_1.CASHFREE_APP_ID.value();
    const secret = config_1.CASHFREE_SECRET_KEY.value();
    if (!appId || !secret) {
        throw new https_1.HttpsError("failed-precondition", "Payments are not configured.");
    }
    return {
        "Content-Type": "application/json",
        "x-api-version": config_1.CASHFREE_API_VERSION,
        "x-client-id": appId,
        "x-client-secret": secret,
    };
}
/**
 * Creates a Cashfree order for a live listing (or an accepted bid).
 * The amount is ALWAYS read from Firestore — the client-supplied value,
 * if any, is ignored.
 */
async function createCashfreeOrderHandler(uid, input) {
    const db = admin.firestore();
    const { listingId, bidId } = input;
    if ((listingId ? 1 : 0) + (bidId ? 1 : 0) !== 1) {
        throw new https_1.HttpsError("invalid-argument", "Provide exactly one of listingId or bidId.");
    }
    let listingRef;
    let amount;
    let sellerId;
    if (bidId) {
        const bidSnap = await db.collection("bids").doc(bidId).get();
        const bid = bidSnap.data();
        if (!bidSnap.exists || !bid)
            throw new https_1.HttpsError("not-found", "Bid not found.");
        if (bid.buyerId !== uid) {
            throw new https_1.HttpsError("permission-denied", "This bid is not yours.");
        }
        if (bid.status !== "accepted") {
            throw new https_1.HttpsError("failed-precondition", "Bid is not accepted yet.");
        }
        listingRef = db.collection("listings").doc(bid.listingId);
        amount = bid.amount;
        sellerId = bid.sellerId;
    }
    else {
        listingRef = db.collection("listings").doc(listingId);
        const listingSnap = await listingRef.get();
        const listing = listingSnap.data();
        if (!listingSnap.exists || !listing) {
            throw new https_1.HttpsError("not-found", "Listing not found.");
        }
        if (listing.status !== "live") {
            throw new https_1.HttpsError("failed-precondition", "Listing is not available.");
        }
        if (listing.sellerId === uid) {
            throw new https_1.HttpsError("failed-precondition", "You cannot buy your own listing.");
        }
        amount = listing.price;
        sellerId = listing.sellerId;
    }
    if (typeof amount !== "number" || amount <= 0) {
        throw new https_1.HttpsError("failed-precondition", "Invalid order amount.");
    }
    // 1. Create the order doc first (payment PENDING).
    const orderRef = db.collection("orders").doc();
    const orderId = orderRef.id;
    const cfOrderIdStr = `trega_${orderId}`;
    await orderRef.set({
        listingId: listingRef.id,
        ...(bidId ? { bidId } : {}),
        buyerId: uid,
        sellerId,
        amount,
        currency: "INR",
        paymentStatus: "PENDING",
        status: "placed",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // 2. Create the Cashfree order.
    const base = (0, config_1.cashfreeBase)(config_1.CASHFREE_ENV.value() || "sandbox");
    const res = await fetch(`${base}/orders`, {
        method: "POST",
        headers: cashfreeHeaders(),
        body: JSON.stringify({
            order_id: cfOrderIdStr,
            order_amount: amount,
            order_currency: "INR",
            customer_details: {
                customer_id: uid,
                // Cashfree requires a phone; fall back to the user's stored phone.
                customer_phone: input.customerPhone ??
                    (await db.collection("users").doc(uid).get()).data()?.phone ??
                    "9999999999",
            },
            order_meta: {
                // Registered webhook URL (see README).
                notify_url: `https://${process.env.GCLOUD_PROJECT}.cloudfunctions.net/cashfreeWebhook`,
            },
        }),
    });
    if (!res.ok) {
        const text = await res.text();
        await orderRef.update({ paymentStatus: "FAILED" });
        throw new https_1.HttpsError("unavailable", `Payment provider error (${res.status}): ${text}`);
    }
    const cf = (await res.json());
    await orderRef.update({
        cfOrderId: cf.cf_order_id,
        cfOrderRef: cfOrderIdStr,
        paymentSessionId: cf.payment_session_id,
    });
    return {
        paymentSessionId: cf.payment_session_id,
        orderId,
        cfOrderId: cf.cf_order_id,
        // Merchant order id the SDK needs (echoed so the app never hardcodes
        // the `trega_` prefix itself).
        cfOrderRef: cfOrderIdStr,
    };
}
/**
 * Verifies a Cashfree PG webhook signature.
 * Cashfree signs webhooks as base64(HMAC_SHA256(secretKey, rawRequestBody)).
 */
function verifyWebhookSignature(rawBody, signatureHeader) {
    const secret = config_1.CASHFREE_SECRET_KEY.value();
    if (!secret || !signatureHeader)
        return false;
    const expected = (0, crypto_1.createHmac)("sha256", secret).update(rawBody).digest("base64");
    const a = Buffer.from(expected);
    const b = Buffer.from(signatureHeader);
    return a.length === b.length && (0, crypto_1.timingSafeEqual)(a, b);
}
async function handleCashfreeWebhook(rawBody, signatureHeader) {
    if (!verifyWebhookSignature(rawBody, signatureHeader)) {
        return { ok: false, reason: "bad_signature" };
    }
    const payload = JSON.parse(rawBody.toString("utf8"));
    const cfOrderRef = payload.data?.order?.order_id;
    const paymentStatus = payload.data?.payment?.payment_status;
    if (!cfOrderRef)
        return { ok: false, reason: "missing_order" };
    const db = admin.firestore();
    const q = await db
        .collection("orders")
        .where("cfOrderRef", "==", cfOrderRef)
        .limit(1)
        .get();
    if (q.empty)
        return { ok: false, reason: "unknown_order" };
    const orderRef = q.docs[0].ref;
    const order = q.docs[0].data();
    if (paymentStatus === "SUCCESS") {
        const batch = db.batch();
        batch.update(orderRef, {
            paymentStatus: "SUCCESS",
            paidAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        batch.update(db.collection("listings").doc(order.listingId), {
            status: "sold",
            soldAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // Reject any other open bids on the listing.
        const openBids = await db
            .collection("bids")
            .where("listingId", "==", order.listingId)
            .where("status", "==", "open")
            .get();
        for (const b of openBids.docs) {
            batch.update(b.ref, { status: "rejected" });
        }
        await batch.commit();
    }
    else if (paymentStatus === "FAILED" || paymentStatus === "USER_DROPPED") {
        await orderRef.update({
            paymentStatus: paymentStatus,
        });
    }
    return { ok: true };
}
//# sourceMappingURL=payments.js.map