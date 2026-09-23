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
exports.onListingCreateHandler = onListingCreateHandler;
exports.reviewListingHandler = reviewListingHandler;
exports.placeBidHandler = placeBidHandler;
exports.acceptBidHandler = acceptBidHandler;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
/** Runs on every new listing: moves it into the admin review queue. */
async function onListingCreateHandler(listingId, data) {
    if (!data)
        return;
    const db = admin.firestore();
    const batch = db.batch();
    const listingRef = db.collection("listings").doc(listingId);
    if (data.status === "draft") {
        batch.update(listingRef, {
            status: "pending",
            submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    batch.set(db.collection("adminNotifications").doc(), {
        type: "listing_review",
        listingId,
        title: data.title ?? "New listing",
        message: `New listing "${data.title ?? listingId}" needs review.`,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
}
/** Admin-only: approve (go live) or reject (with reason) a listing. */
async function reviewListingHandler(isAdmin, input) {
    if (!isAdmin) {
        throw new https_1.HttpsError("permission-denied", "Admin access required.");
    }
    const { listingId, decision, reason } = input;
    if (!listingId)
        throw new https_1.HttpsError("invalid-argument", "listingId is required.");
    if (decision !== "approve" && decision !== "reject") {
        throw new https_1.HttpsError("invalid-argument", "decision must be approve or reject.");
    }
    if (decision === "reject" && !reason?.trim()) {
        throw new https_1.HttpsError("invalid-argument", "A rejection reason is required.");
    }
    const db = admin.firestore();
    const ref = db.collection("listings").doc(listingId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Listing not found.");
    if (snap.data()?.status !== "pending") {
        throw new https_1.HttpsError("failed-precondition", "Listing is not awaiting review.");
    }
    const status = decision === "approve" ? "live" : "rejected";
    await ref.update({
        status,
        ...(decision === "approve"
            ? { liveAt: admin.firestore.FieldValue.serverTimestamp() }
            : { rejectionReason: reason.trim() }),
    });
    return { status };
}
/** Buyer places a structured offer/bid on a live listing. No chat involved. */
async function placeBidHandler(uid, input) {
    const { listingId, amount } = input;
    if (!listingId)
        throw new https_1.HttpsError("invalid-argument", "listingId is required.");
    if (typeof amount !== "number" || amount <= 0) {
        throw new https_1.HttpsError("invalid-argument", "Enter a valid offer amount.");
    }
    const db = admin.firestore();
    const listingSnap = await db.collection("listings").doc(listingId).get();
    const listing = listingSnap.data();
    if (!listingSnap.exists || !listing) {
        throw new https_1.HttpsError("not-found", "Listing not found.");
    }
    if (listing.status !== "live") {
        throw new https_1.HttpsError("failed-precondition", "Listing is not available for offers.");
    }
    if (listing.sellerId === uid) {
        throw new https_1.HttpsError("failed-precondition", "You cannot bid on your own listing.");
    }
    const bidRef = db.collection("bids").doc();
    await bidRef.set({
        listingId,
        buyerId: uid,
        sellerId: listing.sellerId,
        amount,
        status: "open",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { bidId: bidRef.id };
}
/**
 * Seller accepts one bid; every other open bid on the same listing is
 * auto-rejected. The buyer then pays via createCashfreeOrder({bidId}).
 */
async function acceptBidHandler(uid, input) {
    const { bidId } = input;
    if (!bidId)
        throw new https_1.HttpsError("invalid-argument", "bidId is required.");
    const db = admin.firestore();
    await db.runTransaction(async (tx) => {
        const bidRef = db.collection("bids").doc(bidId);
        const bidSnap = await tx.get(bidRef);
        const bid = bidSnap.data();
        if (!bidSnap.exists || !bid)
            throw new https_1.HttpsError("not-found", "Bid not found.");
        if (bid.status !== "open") {
            throw new https_1.HttpsError("failed-precondition", "Bid is no longer open.");
        }
        const listingRef = db.collection("listings").doc(bid.listingId);
        const listingSnap = await tx.get(listingRef);
        const listing = listingSnap.data();
        if (!listingSnap.exists || !listing) {
            throw new https_1.HttpsError("not-found", "Listing not found.");
        }
        if (listing.sellerId !== uid) {
            throw new https_1.HttpsError("permission-denied", "Only the seller can accept bids.");
        }
        if (listing.status !== "live") {
            throw new https_1.HttpsError("failed-precondition", "Listing is not available.");
        }
        tx.update(bidRef, {
            status: "accepted",
            acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.update(listingRef, { acceptedBidId: bidId });
        const others = await tx.get(db
            .collection("bids")
            .where("listingId", "==", bid.listingId)
            .where("status", "==", "open"));
        for (const doc of others.docs) {
            if (doc.id !== bidId)
                tx.update(doc.ref, { status: "rejected" });
        }
    });
    return { accepted: true };
}
//# sourceMappingURL=marketplace.js.map