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
exports.setUserKycStatusHandler = setUserKycStatusHandler;
exports.updateOrderFulfillmentHandler = updateOrderFulfillmentHandler;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const ORDER_STATUSES = [
    "placed",
    "pickup_scheduled",
    "picked_up",
    "in_transit",
    "delivered",
    "cancelled",
    "returned",
];
/** Admin-only: mark a user's KYC as verified (badges them as a verified
 * seller) or rejected with an optional note. */
async function setUserKycStatusHandler(isAdmin, input) {
    if (!isAdmin) {
        throw new https_1.HttpsError("permission-denied", "Admin access required.");
    }
    const { uid, status, note } = input;
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid is required.");
    if (status !== "verified" && status !== "rejected") {
        throw new https_1.HttpsError("invalid-argument", "status must be 'verified' or 'rejected'.");
    }
    const ref = admin.firestore().collection("users").doc(uid);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "User not found.");
    await ref.update({
        kycStatus: status,
        verifiedSeller: status === "verified",
        kycNote: note?.trim() || admin.firestore.FieldValue.delete(),
    });
    return { kycStatus: status };
}
/** Admin-only: advance order fulfillment (status / tracking note).
 * Payment status is owned by the Cashfree webhook and cannot be set here. */
async function updateOrderFulfillmentHandler(isAdmin, input) {
    if (!isAdmin) {
        throw new https_1.HttpsError("permission-denied", "Admin access required.");
    }
    const { orderId, status, trackingNote } = input;
    if (!orderId)
        throw new https_1.HttpsError("invalid-argument", "orderId is required.");
    if (status !== undefined &&
        !ORDER_STATUSES.includes(status)) {
        throw new https_1.HttpsError("invalid-argument", `Invalid order status: ${status}`);
    }
    const ref = admin.firestore().collection("orders").doc(orderId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Order not found.");
    const update = {};
    if (status !== undefined)
        update.status = status;
    if (trackingNote !== undefined)
        update.trackingNote = trackingNote.trim();
    if (Object.keys(update).length === 0) {
        throw new https_1.HttpsError("invalid-argument", "Nothing to update.");
    }
    await ref.update(update);
    return { status: snap.data()?.status ?? "placed" };
}
//# sourceMappingURL=admin.js.map