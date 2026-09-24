import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

export type ListingStatus = "draft" | "pending" | "live" | "sold" | "rejected";
export type BidStatus = "open" | "accepted" | "rejected" | "expired" | "countered";

/** Notification kinds written to `users/{uid}/notifications`. */
export const NotificationType = {
  bidReceived: "bid_received",
  outbid: "outbid",
  bidAccepted: "bid_accepted",
  bidRejected: "bid_rejected",
  listingFlagged: "listing_flagged",
} as const;

/** Queues one inbox notification on a write batch. */
function queueNotification(
  batch: admin.firestore.WriteBatch,
  uid: string,
  n: { type: string; title: string; body: string }
): void {
  batch.set(
    admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("notifications")
      .doc(),
    {
      ...n,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }
  );
}

function formatINR(amount: number): string {
  return `₹${Math.round(amount).toLocaleString("en-IN")}`;
}

/** Runs on every new listing: flips it live immediately (reactive
 * moderation — the team reviews new listings and flags suspicious ones
 * after the fact) and notifies the admin inbox. */
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
      status: "live" satisfies ListingStatus,
      liveAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  batch.set(db.collection("adminNotifications").doc(), {
    type: "listing_review",
    listingId,
    title: data.title ?? "New listing",
    message: `New listing "${data.title ?? listingId}" is live — review and flag if suspicious.`,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

/**
 * Admin-only: flag/takedown flow for the reactive moderation model.
 * Listings go live on publish; this callable lets the team pull a
 * suspicious live listing (`reject`) — `approve` is a no-op on listings
 * that are already live.
 */
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
  const current = snap.data()?.status as ListingStatus | undefined;
  // `pending` is kept for legacy docs; live listings are flagged from `live`.
  if (current !== "pending" && current !== "live") {
    throw new HttpsError("failed-precondition", "Listing is not reviewable.");
  }

  const status: ListingStatus = decision === "approve" ? "live" : "rejected";
  const batch = db.batch();
  batch.update(ref, {
    status,
    ...(decision === "approve"
      ? { liveAt: admin.firestore.FieldValue.serverTimestamp() }
      : { rejectionReason: reason!.trim() }),
  });
  if (decision === "reject") {
    const sellerId = snap.data()?.sellerId as string | undefined;
    if (sellerId) {
      queueNotification(batch, sellerId, {
        type: NotificationType.listingFlagged,
        title: "Your listing was flagged",
        body: `“${snap.data()?.title ?? "Your listing"}” was taken down${
          reason?.trim() ? `: ${reason!.trim()}` : "."
        } Fix the issue and publish it again.`,
      });
    }
  }
  await batch.commit();
  return { status };
}

/**
 * Runs on every new bid: notifies the seller, and notifies the previous
 * highest bidder if they have just been outbid.
 */
export async function onBidCreateHandler(
  bidId: string,
  data: admin.firestore.DocumentData | undefined
): Promise<void> {
  if (!data) return;
  const { listingId, buyerId, sellerId, amount } = data as {
    listingId?: string;
    buyerId?: string;
    sellerId?: string;
    amount?: number;
  };
  if (!listingId || !buyerId || typeof amount !== "number") return;

  const db = admin.firestore();
  const listingSnap = await db.collection("listings").doc(listingId).get();
  const listingTitle =
    (listingSnap.data()?.title as string | undefined) ?? "your listing";
  const ownerId = (listingSnap.data()?.sellerId as string | undefined) ?? sellerId;

  // Previous open bids on this listing (single-field query — no composite
  // index needed; bid counts per listing are small).
  const othersSnap = await db
    .collection("bids")
    .where("listingId", "==", listingId)
    .get();
  let prevHighest: { buyerId: string; amount: number } | null = null;
  for (const doc of othersSnap.docs) {
    if (doc.id === bidId) continue;
    const b = doc.data();
    if (b.status !== "open" || b.buyerId === buyerId) continue;
    const amt = b.amount as number;
    if (!prevHighest || amt > prevHighest.amount) {
      prevHighest = { buyerId: b.buyerId as string, amount: amt };
    }
  }

  const batch = db.batch();
  if (ownerId && ownerId !== buyerId) {
    queueNotification(batch, ownerId, {
      type: NotificationType.bidReceived,
      title: "New bid on your listing",
      body: `${formatINR(amount)} offered on “${listingTitle}” — review it in Bids & offers.`,
    });
  }
  if (prevHighest && amount > prevHighest.amount) {
    queueNotification(batch, prevHighest.buyerId, {
      type: NotificationType.outbid,
      title: "You've been outbid",
      body: `Someone bid ${formatINR(amount)} on “${listingTitle}” — place a higher bid to stay in the race.`,
    });
  }
  await batch.commit();
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

  // Aadhaar gate: only verified users may make offers.
  const userSnap = await db.collection("users").doc(uid).get();
  if (userSnap.data()?.kycStatus !== "verified") {
    throw new HttpsError(
      "failed-precondition",
      "Verify your Aadhaar to make an offer."
    );
  }

  // One open offer per buyer per listing. A rejected buyer may offer again,
  // but an open offer must be accepted/rejected first.
  // (buyerId + listingId composite index; no status filter needed.)
  const mineSnap = await db
    .collection("bids")
    .where("buyerId", "==", uid)
    .where("listingId", "==", listingId)
    .get();
  if (mineSnap.docs.some((d) => d.data().status === "open")) {
    throw new HttpsError(
      "failed-precondition",
      "You already have an open offer on this listing."
    );
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
  // Collected inside the transaction, written after it commits.
  let winnerId = "";
  let winnerAmount = 0;
  let listingTitle = "the item";
  const losers: Array<{ buyerId: string; amount: number }> = [];

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
      if (doc.id !== bidId) {
        tx.update(doc.ref, { status: "rejected" satisfies BidStatus });
        losers.push({
          buyerId: doc.data().buyerId as string,
          amount: doc.data().amount as number,
        });
      }
    }

    winnerId = bid.buyerId as string;
    winnerAmount = bid.amount as number;
    listingTitle = (listing.title as string | undefined) ?? listingTitle;
  });

  const batch = db.batch();
  queueNotification(batch, winnerId, {
    type: NotificationType.bidAccepted,
    title: "Your offer was accepted!",
    body: `The seller accepted your ${formatINR(winnerAmount)} offer on “${listingTitle}” — open the listing to pay ${formatINR(winnerAmount)} and complete your purchase.`,
  });
  for (const loser of losers) {
    queueNotification(batch, loser.buyerId, {
      type: NotificationType.bidRejected,
      title: "Bid not accepted",
      body: `Your ${formatINR(loser.amount)} bid on “${listingTitle}” wasn't accepted — the item went to someone else.`,
    });
  }
  await batch.commit();
  return { accepted: true as const };
}

/**
 * Seller rejects one open offer. The buyer is notified and may send a new
 * offer afterwards (the listing stays live).
 */
export async function rejectBidHandler(
  uid: string,
  input: { bidId?: string }
): Promise<{ rejected: true }> {
  const { bidId } = input;
  if (!bidId) throw new HttpsError("invalid-argument", "bidId is required.");

  const db = admin.firestore();
  const bidRef = db.collection("bids").doc(bidId);
  const bidSnap = await bidRef.get();
  const bid = bidSnap.data();
  if (!bidSnap.exists || !bid) {
    throw new HttpsError("not-found", "Offer not found.");
  }
  if (bid.status !== "open") {
    throw new HttpsError("failed-precondition", "Offer is no longer open.");
  }

  const listingSnap = await db
    .collection("listings")
    .doc(bid.listingId as string)
    .get();
  const listing = listingSnap.data();
  if (!listingSnap.exists || !listing) {
    throw new HttpsError("not-found", "Listing not found.");
  }
  if (listing.sellerId !== uid) {
    throw new HttpsError("permission-denied", "Only the seller can reject offers.");
  }

  await bidRef.update({ status: "rejected" satisfies BidStatus });
  const listingTitle = (listing.title as string | undefined) ?? "the item";

  const batch = db.batch();
  queueNotification(batch, bid.buyerId as string, {
    type: NotificationType.bidRejected,
    title: "Offer not accepted",
    body: `Your ${formatINR(bid.amount as number)} offer on “${listingTitle}” wasn't accepted — you can send a new offer.`,
  });
  await batch.commit();
  return { rejected: true as const };
}

/**
 * Seller cancels an accepted offer (e.g. the buyer never paid). The offer
 * goes back to `rejected` so the buyer may offer again, the listing's
 * `acceptedBidId` reservation is cleared, and the buyer is notified.
 */
export async function cancelAcceptanceHandler(
  uid: string,
  input: { bidId?: string }
): Promise<{ cancelled: true }> {
  const { bidId } = input;
  if (!bidId) throw new HttpsError("invalid-argument", "bidId is required.");

  const db = admin.firestore();
  let buyerId = "";
  let listingTitle = "the item";

  await db.runTransaction(async (tx) => {
    const bidRef = db.collection("bids").doc(bidId);
    const bidSnap = await tx.get(bidRef);
    const bid = bidSnap.data();
    if (!bidSnap.exists || !bid) {
      throw new HttpsError("not-found", "Offer not found.");
    }
    if (bid.status !== "accepted") {
      throw new HttpsError("failed-precondition", "Offer is not accepted.");
    }

    const listingRef = db.collection("listings").doc(bid.listingId as string);
    const listingSnap = await tx.get(listingRef);
    const listing = listingSnap.data();
    if (!listingSnap.exists || !listing) {
      throw new HttpsError("not-found", "Listing not found.");
    }
    if (listing.sellerId !== uid) {
      throw new HttpsError("permission-denied", "Only the seller can do this.");
    }
    if (listing.status !== "live") {
      throw new HttpsError("failed-precondition", "Listing is not available.");
    }

    tx.update(bidRef, { status: "rejected" satisfies BidStatus });
    tx.update(listingRef, {
      acceptedBidId: admin.firestore.FieldValue.delete(),
    });

    buyerId = bid.buyerId as string;
    listingTitle = (listing.title as string | undefined) ?? listingTitle;
  });

  const batch = db.batch();
  queueNotification(batch, buyerId, {
    type: NotificationType.bidRejected,
    title: "Accepted offer cancelled",
    body: `The seller cancelled your accepted offer on “${listingTitle}” — the listing is open for offers again.`,
  });
  await batch.commit();
  return { cancelled: true as const };
}
