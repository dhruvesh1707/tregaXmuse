import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { assertAmount, assertDocId, assertText } from "./validate";
import { minListPrice, readFeeConfig } from "./payments";

export type ListingStatus = "draft" | "pending" | "live" | "sold" | "archived" | "rejected";
export type BidStatus = "open" | "accepted" | "rejected" | "expired" | "countered";

/** Notification kinds written to `users/{uid}/notifications`. */
export const NotificationType = {
  bidReceived: "bid_received",
  outbid: "outbid",
  bidAccepted: "bid_accepted",
  bidRejected: "bid_rejected",
  listingFlagged: "listing_flagged",
} as const;

/** Queues one inbox notification on a write batch. The matching FCM
 * push is delivered asynchronously by the `onNotificationCreate`
 * trigger firing on this doc, never awaited by the caller, so
 * accept/reject return the moment the batch commits. */
function queueNotification(
  batch: admin.firestore.WriteBatch,
  uid: string,
  n: {
    type: string;
    title: string;
    body: string;
    /** Deep-link payload, the app opens the matching screen on tap. */
    data?: { listingId?: string; bidId?: string; orderId?: string };
  }
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

/** One FCM push job, built from an inbox notification doc by the
 * `onNotificationCreate` trigger. */
type PushJob = {
  uid: string;
  title: string;
  body: string;
  type: string;
  listingId?: string;
  bidId?: string;
  orderId?: string;
};

/** Sends one push via FCM. Never throws, a push must not fail the callable. */
async function sendPush(job: PushJob): Promise<void> {
  try {
    const snap = await admin.firestore().collection("users").doc(job.uid).get();
    const tokens = (snap.data()?.fcmTokens as string[] | undefined) ?? [];
    if (!tokens.length) return;
    // FCM data values must be strings.
    const data: Record<string, string> = { type: job.type };
    if (job.listingId) data.listingId = job.listingId;
    if (job.bidId) data.bidId = job.bidId;
    if (job.orderId) data.orderId = job.orderId;
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: job.title, body: job.body },
      data,
      // Android: post to the app's high-importance channel (banner +
      // sound) instead of FCM's silent fallback channel. The id must
      // match the channel created in the app's main.dart and the
      // manifest's default_notification_channel_id.
      android: {
        priority: "high",
        notification: { channelId: "trega_alerts" },
      },
    });
    // Prune dead tokens so the array doesn't rot over time.
    const dead: string[] = [];
    res.responses.forEach((r, i) => {
      if (r.success) return;
      const code = (r.error as { code?: string } | undefined)?.code;
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        dead.push(tokens[i]);
      }
    });
    if (dead.length) {
      await admin.firestore().collection("users").doc(job.uid).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead),
      });
    }
  } catch (e) {
    console.warn(`FCM push to ${job.uid} failed:`, e);
  }
}

/** Commits a batch. Push delivery is async (see the
 * `onNotificationCreate` trigger), so committing is all this does. */
async function commitBatch(batch: admin.firestore.WriteBatch): Promise<void> {
  await batch.commit();
}

function formatINR(amount: number): string {
  return `₹${Math.round(amount).toLocaleString("en-IN")}`;
}

/** Runs on every new listing: flips it live immediately (reactive
 * moderation, the team reviews new listings and flags suspicious ones
 * after the fact) and notifies the admin inbox. */
export async function onListingCreateHandler(
  listingId: string,
  data: admin.firestore.DocumentData | undefined
): Promise<void> {
  if (!data) return;
  const db = admin.firestore();
  const batch = db.batch();

  const listingRef = db.collection("listings").doc(listingId);
  // Price floor: with the flat delivery fee split 50-50, a listing below
  // the seller's delivery share can never be checked out (the seller would
  // lose money). Reject it at creation instead of letting it go live,
  // the app blocks this in the sell flow, this covers direct writes.
  const minPrice = minListPrice(await readFeeConfig(db));
  if (typeof data.price === "number" && data.price < minPrice) {
    batch.update(listingRef, {
      status: "rejected" satisfies ListingStatus,
      rejectionReason: `Below the minimum listing price of ₹${minPrice}.`,
    });
  } else {
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
      message: `New listing "${data.title ?? listingId}" is live. Review and flag if suspicious.`,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

/**
 * Admin-only: flag/takedown flow for the reactive moderation model.
 * Listings go live on publish; this callable lets the team pull a
 * suspicious live listing (`reject`), `approve` is a no-op on listings
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
  assertDocId(listingId, "listingId");
  if (decision !== "approve" && decision !== "reject") {
    throw new HttpsError("invalid-argument", "decision must be approve or reject.");
  }
  const reasonText =
    decision === "reject"
      ? assertText(reason, "rejection reason", 1, 500)
      : undefined;

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
      : { rejectionReason: reasonText! }),
  });
  if (decision === "reject") {
    const sellerId = snap.data()?.sellerId as string | undefined;
    if (sellerId) {
      queueNotification(batch, sellerId, {
        type: NotificationType.listingFlagged,
        data: { listingId },
        title: "Your listing was flagged",
        body: `“${snap.data()?.title ?? "Your listing"}” was taken down${
          reason?.trim() ? `: ${reason!.trim()}` : "."
        } Fix the issue and publish it again.`,
      });
    }
  }
  await commitBatch(batch);
  return { status };
}

/**
 * Deletes everything a listing owns: its bids, the doc plus the `private`
 * subcollection (recursive delete), and its media files (best-effort).
 * Shared by the admin takedown and the seller's own delete; the guards
 * and notifications differ, the deletion itself is identical.
 */
async function deleteListingRecords(
  db: admin.firestore.Firestore,
  listingId: string
): Promise<void> {
  // Bids on this listing (single-field query, no composite index needed).
  // Deleted in batch-sized chunks; bid counts per listing are small, but
  // the loop keeps a pathological case under the 500-write batch limit.
  const bidsSnap = await db
    .collection("bids")
    .where("listingId", "==", listingId)
    .get();
  for (let i = 0; i < bidsSnap.docs.length; i += 400) {
    const chunk = db.batch();
    for (const doc of bidsSnap.docs.slice(i, i + 400)) chunk.delete(doc.ref);
    await chunk.commit();
  }

  // Doc + `private` subcollection in one recursive delete.
  await db.recursiveDelete(db.collection("listings").doc(listingId));

  // Media last, best-effort: if this fails the listing is still gone from
  // the app, and orphaned files under the prefix are inert. Never fail
  // the callable over cleanup (mirrors account.ts).
  try {
    const bucket = admin.storage().bucket();
    const [files] = await bucket.getFiles({
      prefix: `listingMedia/${listingId}/`,
    });
    await Promise.all(files.map((f) => f.delete().catch(() => undefined)));
  } catch {
    // best-effort cleanup only
  }
}

/**
 * Permanent admin delete, the hard counterpart to reviewListing's reject.
 * Removes the listing doc (recursiveDelete also clears its `private`
 * subcollection), every bid placed on it, and its Storage media under
 * `listingMedia/{listingId}/`. Sold and archived listings are refused: an
 * order references them, so their record must stay. The seller is
 * notified via the same listing_flagged inbox type the app already
 * renders for takedowns, only the wording says the removal is permanent.
 */
export async function deleteListingHandler(
  isAdmin: boolean,
  input: { listingId?: string }
): Promise<{ deleted: true }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const { listingId } = input;
  assertDocId(listingId, "listingId");

  const db = admin.firestore();
  const ref = db.collection("listings").doc(listingId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Listing not found.");
  const data = snap.data()!;
  if (
    (data.status as ListingStatus | undefined) === "sold" ||
    (data.status as ListingStatus | undefined) === "archived"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Sold listings can't be deleted. An order references them."
    );
  }
  const sellerId = data.sellerId as string | undefined;
  const title = (data.title as string | undefined) ?? "Your listing";

  // Notify the seller (same commitBatch pattern as the review
  // takedown). No deep-link data, the listing is about to not exist.
  if (sellerId) {
    const batch = db.batch();
    queueNotification(batch, sellerId, {
      type: NotificationType.listingFlagged,
      title: "Your listing was removed",
      body: `“${title}” was permanently removed by the Trega team and can't be restored.`,
    });
    await commitBatch(batch);
  }

  await deleteListingRecords(db, listingId);

  return { deleted: true };
}

/**
 * Seller deletes their own listing: bids, doc, private details and media
 * all go (same deletion as the admin takedown, no seller notification,
 * the seller did it themselves).
 *
 * Guards: the caller must own the listing, it must not be sold, and it
 * must not have an accepted offer. An accepted offer reserves the
 * listing for the winning buyer until they pay, deleting it would strand
 * their checkout, so the seller must cancel the acceptance first (or let
 * the sale complete, after which the listing is sold and undeletable).
 */
export async function deleteOwnListingHandler(
  uid: string,
  input: { listingId?: string }
): Promise<{ deleted: true }> {
  const { listingId } = input;
  assertDocId(listingId, "listingId");

  const db = admin.firestore();
  const ref = db.collection("listings").doc(listingId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Listing not found.");
  const data = snap.data()!;
  if (data.sellerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "You can only delete your own listings."
    );
  }
  if (
    (data.status as ListingStatus | undefined) === "sold" ||
    (data.status as ListingStatus | undefined) === "archived"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Sold listings can't be deleted. An order references them."
    );
  }
  if (typeof data.acceptedBidId === "string" && data.acceptedBidId !== "") {
    throw new HttpsError(
      "failed-precondition",
      "This listing has an accepted offer. Cancel the acceptance before deleting it."
    );
  }

  await deleteListingRecords(db, listingId);
  return { deleted: true };
}

/**
 * Hourly archiver: a sold listing leaves the public view 48 hours after
 * the sale. It flips to `archived`, after which single-doc reads are
 * restricted to the seller, the buyer (`soldTo`) and admins (see
 * firestore.rules). The feed, search and category queries already
 * exclude non-live listings, so nothing else changes.
 *
 * Single-field query + in-code time filter (no composite index): sold
 * counts are small, and the job is idempotent, a listing already
 * archived is never matched again. Listings with no `soldAt` clock are
 * skipped and stay public.
 */
export async function archiveSoldListingsHandler(): Promise<{
  archived: number;
}> {
  const db = admin.firestore();
  const cutoff = Date.now() - 48 * 60 * 60 * 1000;
  const snap = await db
    .collection("listings")
    .where("status", "==", "sold")
    .limit(200)
    .get();
  let archived = 0;
  const batch = db.batch();
  for (const doc of snap.docs) {
    const soldAt = doc.data()?.soldAt as admin.firestore.Timestamp | undefined;
    const soldMs = soldAt?.toMillis?.() ?? 0;
    if (soldMs === 0 || soldMs > cutoff) continue;
    batch.update(doc.ref, { status: "archived" satisfies ListingStatus });
    archived++;
  }
  if (archived > 0) await batch.commit();
  return { archived };
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

  // Previous open bids on this listing (single-field query, no composite
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
      data: { listingId, bidId },
      title: "New bid on your listing",
      body: `${formatINR(amount)} offered on “${listingTitle}”. Review it in Bids & offers.`,
    });
  }
  if (prevHighest && amount > prevHighest.amount) {
    queueNotification(batch, prevHighest.buyerId, {
      type: NotificationType.outbid,
      data: { listingId, bidId },
      title: "You've been outbid",
      body: `Someone bid ${formatINR(amount)} on “${listingTitle}”. Place a higher bid to stay in the race.`,
    });
  }
  await commitBatch(batch);
}

/**
 * Runs on every new inbox notification doc: sends the matching FCM
 * push. Callables only write the inbox doc and return; this trigger
 * owns delivery, so no user ever waits on a push send (perf fix,
 * 2026-11-13). Covers every server-written notification, including
 * the KYC verdicts written by admin.ts.
 *
 * Delivery is claimed in a transaction first: Firestore triggers can
 * redeliver, and the `pushSent` marker stops a second push. The claim
 * happens before the send; sendPush never throws, so a claimed push
 * is always attempted. A doc without title/body/type is skipped, it
 * was never meant to be a push.
 */
export async function onNotificationCreateHandler(
  uid: string,
  notificationId: string,
  doc: admin.firestore.DocumentData | undefined
): Promise<void> {
  if (!doc) return;
  const title = doc.title as string | undefined;
  const body = doc.body as string | undefined;
  const type = doc.type as string | undefined;
  if (!title || !body || !type) return;
  const link = (doc.data as
    | { listingId?: string; bidId?: string; orderId?: string }
    | undefined) ?? {};

  const db = admin.firestore();
  const ref = db
    .collection("users")
    .doc(uid)
    .collection("notifications")
    .doc(notificationId);
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    if (snap.data()?.pushSent === true) return false;
    tx.update(ref, { pushSent: true });
    return true;
  });
  if (!claimed) return;

  await sendPush({
    uid,
    title,
    body,
    type,
    listingId: link.listingId,
    bidId: link.bidId,
    orderId: link.orderId,
  });
}

/** Buyer places a structured offer/bid on a live listing. No chat involved. */
export async function placeBidHandler(
  uid: string,
  input: { listingId?: string; amount?: number }
): Promise<{ bidId: string }> {
  const { listingId, amount } = input;
  assertDocId(listingId, "listingId");
  assertAmount(amount, "offer amount");

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

  // No Aadhaar gate for buyers (policy change, 2026-11-04): KYC is
  // sellers-only. Buyers are phone-OTP verified at login, and no money
  // or goods move until the winner pays at checkout. Aadhaar stays
  // mandatory for selling (listing creation is gated in the rules and
  // the sell flow).

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
  assertDocId(bidId, "bidId");

  const db = admin.firestore();
  // Collected inside the transaction, written after it commits.
  let winnerId = "";
  let winnerAmount = 0;
  let listingTitle = "the item";
  let acceptedListingId = "";
  const losers: Array<{ bidId: string; buyerId: string; amount: number }> = [];

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

    // Firestore transactions require ALL reads before ALL writes, the
    // other-bids query must run before the updates below, or the
    // transaction throws (surfaced to the app as INTERNAL).
    // Single-field query (no composite index needed); the "open" filter
    // is applied in code.
    const others = await tx.get(
      db.collection("bids").where("listingId", "==", bid.listingId)
    );

    tx.update(bidRef, {
      status: "accepted" satisfies BidStatus,
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(listingRef, { acceptedBidId: bidId });

    for (const doc of others.docs) {
      if (doc.id !== bidId && doc.data().status === "open") {
        tx.update(doc.ref, { status: "rejected" satisfies BidStatus });
        losers.push({
          bidId: doc.id,
          buyerId: doc.data().buyerId as string,
          amount: doc.data().amount as number,
        });
      }
    }

    winnerId = bid.buyerId as string;
    winnerAmount = bid.amount as number;
    listingTitle = (listing.title as string | undefined) ?? listingTitle;
    acceptedListingId = bid.listingId as string;
  });

  const batch = db.batch();
  queueNotification(batch, winnerId, {
    type: NotificationType.bidAccepted,
    data: { listingId: acceptedListingId, bidId },
    title: "Your offer was accepted!",
    body: `The seller accepted your ${formatINR(winnerAmount)} offer on “${listingTitle}”. Open the listing to pay ${formatINR(winnerAmount)} and complete your purchase.`,
  });
  for (const loser of losers) {
    queueNotification(batch, loser.buyerId, {
      type: NotificationType.bidRejected,
      data: { listingId: acceptedListingId, bidId: loser.bidId },
      title: "Bid not accepted",
      body: `Your ${formatINR(loser.amount)} bid on “${listingTitle}” wasn't accepted. The item went to someone else.`,
    });
  }
  await commitBatch(batch);
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
  assertDocId(bidId, "bidId");

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
    data: { listingId: bid.listingId as string, bidId },
    title: "Offer not accepted",
    body: `Your ${formatINR(bid.amount as number)} offer on “${listingTitle}” wasn't accepted. You can send a new offer.`,
  });
  await commitBatch(batch);
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
  assertDocId(bidId, "bidId");

  const db = admin.firestore();
  let buyerId = "";
  let listingTitle = "the item";
  let cancelledListingId = "";

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
    cancelledListingId = bid.listingId as string;
  });

  const batch = db.batch();
  queueNotification(batch, buyerId, {
    type: NotificationType.bidRejected,
    data: { listingId: cancelledListingId, bidId },
    title: "Accepted offer cancelled",
    body: `The seller cancelled your accepted offer on “${listingTitle}”. The listing is open for offers again.`,
  });
  await commitBatch(batch);
  return { cancelled: true as const };
}

/**
 * Instagram-style view counting for listings.
 *
 * A view counts only after the client proves real attention: the app calls
 * this after the detail screen has been continuously visible for 3 seconds
 * (IG's documented video-view threshold), never on plain screen open.
 *
 * - The seller's own views never count. (IG counts self-views; we
 *   deliberately don't, sellers could otherwise inflate their listings.)
 * - Replays count like IG, but a 1-hour per-viewer-per-listing cooldown
 *   stops open → back → open tap-spam from gaming the counter.
 * - Atomic via a transaction (reads before writes); per-viewer state lives
 *   in `listingViews/{listingId}_{uid}`.
 */
export async function recordListingViewHandler(
  uid: string,
  input: { listingId?: string }
): Promise<{ counted: boolean; viewCount: number }> {
  const { listingId } = input;
  assertDocId(listingId, "listingId");

  const db = admin.firestore();
  const listingRef = db.collection("listings").doc(listingId);
  const viewRef = db.collection("listingViews").doc(`${listingId}_${uid}`);

  const COOLDOWN_MS = 60 * 60 * 1000; // 1h per viewer per listing

  return db.runTransaction(async (tx) => {
    // All reads before all writes (Firestore transaction rule).
    const listingSnap = await tx.get(listingRef);
    const viewSnap = await tx.get(viewRef);

    const listing = listingSnap.data();
    if (!listingSnap.exists || !listing) {
      throw new HttpsError("not-found", "Listing not found.");
    }
    const current = (listing.viewCount as number | undefined) ?? 0;
    if (listing.sellerId === uid) {
      return { counted: false, viewCount: current };
    }
    const last = viewSnap.data()?.lastViewedAt as
      | admin.firestore.Timestamp
      | undefined;
    if (last && Date.now() - last.toMillis() < COOLDOWN_MS) {
      return { counted: false, viewCount: current };
    }

    tx.set(
      viewRef,
      {
        listingId,
        viewerId: uid,
        lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
        views: admin.firestore.FieldValue.increment(1),
      },
      { merge: true }
    );
    tx.update(listingRef, {
      viewCount: admin.firestore.FieldValue.increment(1),
    });
    return { counted: true, viewCount: current + 1 };
  });
}
