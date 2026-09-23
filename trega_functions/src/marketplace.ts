import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

export type ListingStatus = "draft" | "pending" | "live" | "sold" | "rejected";
export type BidStatus = "open" | "accepted" | "rejected" | "expired" | "countered";

/** Runs on every new listing: moves it into the admin review queue. */
export async function onListingCreateHandler(
  listingId: string,
  data: admin.firestore.DocumentData | undefined
): Promise<void> {
  if (!data) return;
  const db = admin.firestore();
  const batch = db.batch();

  const listingRef = db.collection("listings").doc(listingId);
  if ((data.status as ListingStatus | undefined) === "draft") {
    batch.update(listingRef, {
      status: "pending" satisfies ListingStatus,
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
export async function reviewListingHandler(
  isAdmin: boolean,
  input: { listingId?: string; decision?: string; reason?: string }
): Promise<{ status: ListingStatus }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const { listingId, decision, reason } = input;
  if (!listingId) throw new HttpsError("invalid-argument", "listingId is required.");
  if (decision !== "approve" && decision !== "reject") {
    throw new HttpsError("invalid-argument", "decision must be approve or reject.");
  }
  if (decision === "reject" && !reason?.trim()) {
    throw new HttpsError("invalid-argument", "A rejection reason is required.");
  }

  const db = admin.firestore();
  const ref = db.collection("listings").doc(listingId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Listing not found.");
  if (snap.data()?.status !== "pending") {
    throw new HttpsError("failed-precondition", "Listing is not awaiting review.");
  }

  const status: ListingStatus = decision === "approve" ? "live" : "rejected";
  await ref.update({
    status,
    ...(decision === "approve"
      ? { liveAt: admin.firestore.FieldValue.serverTimestamp() }
      : { rejectionReason: reason!.trim() }),
  });
  return { status };
}

/** Buyer places a structured offer/bid on a live listing. No chat involved. */
export async function placeBidHandler(
  uid: string,
  input: { listingId?: string; amount?: number }
): Promise<{ bidId: string }> {
  const { listingId, amount } = input;
  if (!listingId) throw new HttpsError("invalid-argument", "listingId is required.");
  if (typeof amount !== "number" || amount <= 0) {
    throw new HttpsError("invalid-argument", "Enter a valid offer amount.");
  }

  const db = admin.firestore();
  const listingSnap = await db.collection("listings").doc(listingId).get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "Listing not found.");
  }
  if (listing.status !== "live") {
    throw new HttpsError("failed-precondition", "Listing is not available for offers.");
  }
  if (listing.sellerId === uid) {
    throw new HttpsError("failed-precondition", "You cannot bid on your own listing.");
  }

  const bidRef = db.collection("bids").doc();
  await bidRef.set({
    listingId,
    buyerId: uid,
    sellerId: listing.sellerId,
    amount,
    status: "open" satisfies BidStatus,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { bidId: bidRef.id };
}

/**
 * Seller accepts one bid; every other open bid on the same listing is
 * auto-rejected. The buyer then pays via createCashfreeOrder({bidId}).
 */
export async function acceptBidHandler(
  uid: string,
  input: { bidId?: string }
): Promise<{ accepted: true }> {
  const { bidId } = input;
  if (!bidId) throw new HttpsError("invalid-argument", "bidId is required.");

  const db = admin.firestore();
  await db.runTransaction(async (tx) => {
    const bidRef = db.collection("bids").doc(bidId);
    const bidSnap = await tx.get(bidRef);
    const bid = bidSnap.data();
    if (!bidSnap.exists || !bid) throw new HttpsError("not-found", "Bid not found.");
    if (bid.status !== "open") {
      throw new HttpsError("failed-precondition", "Bid is no longer open.");
    }

    const listingRef = db.collection("listings").doc(bid.listingId as string);
    const listingSnap = await tx.get(listingRef);
    const listing = listingSnap.data();
    if (!listingSnap.exists || !listing) {
      throw new HttpsError("not-found", "Listing not found.");
    }
    if (listing.sellerId !== uid) {
      throw new HttpsError("permission-denied", "Only the seller can accept bids.");
    }
    if (listing.status !== "live") {
      throw new HttpsError("failed-precondition", "Listing is not available.");
    }

    tx.update(bidRef, {
      status: "accepted" satisfies BidStatus,
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(listingRef, { acceptedBidId: bidId });

    const others = await tx.get(
      db
        .collection("bids")
        .where("listingId", "==", bid.listingId)
        .where("status", "==", "open")
    );
    for (const doc of others.docs) {
      if (doc.id !== bidId) tx.update(doc.ref, { status: "rejected" satisfies BidStatus });
    }
  });
  return { accepted: true as const };
}
