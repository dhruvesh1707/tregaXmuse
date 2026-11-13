import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { assertDocId, assertText } from "./validate";
import { queueNotification, NotificationType } from "./notify";

/**
 * Post-delivery support: the 72-hour dispute window and seller payout
 * settlement.
 *
 * Disputes: after delivery, the buyer has 72 hours to report a problem
 * from the tracking screen (one report per order, doc id = order id).
 * Filing freezes the seller's settlement (`held`) until the admin
 * resolves the report. Resolution in the buyer's favor records a refund
 * (the money itself is returned through the Cashfree dashboard, the
 * reference is recorded here); resolution in the seller's favor releases
 * the settlement immediately, the window's purpose is served once the
 * single allowed report is resolved.
 *
 * Settlement: the payout amount is computed at checkout (`fees.
 * sellerPayout` on the order doc) and the seller's UPI is snapshotted
 * on the listing's private details. The money moves by a manual UPI
 * transfer from the team; this module is the record of that workflow:
 * `pending` (delivered, inside the window) → `eligible` (window passed
 * with no open report, flipped hourly by `releaseSettlements`) → `paid`
 * (admin marks it with a payment reference). `held` while a report is
 * open, `cancelled` when a report resolves in the buyer's favor.
 * Orders delivered before this shipped have no `settlementStatus`; the
 * admin may mark those paid directly from the panel (the legacy path
 * in `markSettlementPaidHandler`).
 */

/** The buyer has 72 hours after delivery to report a problem. */
const DISPUTE_WINDOW_MS = 72 * 60 * 60 * 1000;

const DISPUTE_REASONS = [
  "not_as_described",
  "damaged",
  "wrong_item",
  "other",
] as const;

function formatINR(amount: number): string {
  return `₹${Math.round(amount).toLocaleString("en-IN")}`;
}

function orderTitle(order: admin.firestore.DocumentData): string {
  return (order.listingTitle as string | undefined) || "the item";
}

function sellerPayoutOf(order: admin.firestore.DocumentData): number {
  const fees = order.fees as { sellerPayout?: number } | undefined;
  return typeof fees?.sellerPayout === "number"
    ? fees.sellerPayout
    : (order.amount as number);
}

/** Buyer files a report against a delivered order, inside the window. */
export async function fileDisputeHandler(
  uid: string,
  input: {
    orderId?: string;
    reason?: string;
    description?: string;
    photoUrls?: unknown;
  }
): Promise<{ filed: true }> {
  const { orderId, reason } = input;
  assertDocId(orderId, "orderId");
  if (
    reason === undefined ||
    !(DISPUTE_REASONS as readonly string[]).includes(reason)
  ) {
    throw new HttpsError("invalid-argument", "Choose a valid reason.");
  }
  const description = assertText(input.description, "description", 10, 1000);
  let photoUrls: string[] = [];
  if (input.photoUrls !== undefined && input.photoUrls !== null) {
    if (!Array.isArray(input.photoUrls) || input.photoUrls.length > 4) {
      throw new HttpsError(
        "invalid-argument",
        "Attach at most 4 photos."
      );
    }
    for (const u of input.photoUrls) {
      if (
        typeof u !== "string" ||
        !u.startsWith("https://") ||
        u.length > 1000
      ) {
        throw new HttpsError("invalid-argument", "Invalid photo URL.");
      }
      photoUrls.push(u);
    }
  }

  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();
  const order = orderSnap.data();
  if (!orderSnap.exists || !order) {
    throw new HttpsError("not-found", "Order not found.");
  }
  if (order.buyerId !== uid) {
    throw new HttpsError("permission-denied", "This order is not yours.");
  }
  if (order.status !== "delivered") {
    throw new HttpsError(
      "failed-precondition",
      "Only delivered orders can be reported."
    );
  }
  const deliveredAt = order.deliveredAt as
    | admin.firestore.Timestamp
    | undefined;
  const deliveredMs = deliveredAt?.toMillis?.() ?? 0;
  if (deliveredMs === 0) {
    throw new HttpsError(
      "failed-precondition",
      "This order has no delivery record. Write to contact@trega.in and we will help."
    );
  }
  if (Date.now() - deliveredMs > DISPUTE_WINDOW_MS) {
    throw new HttpsError(
      "failed-precondition",
      "The 72 hour support window for this order has closed."
    );
  }

  // Hold the settlement only when it has not already been paid: a
  // payout that already went out is history, the report still opens
  // and the resolution records the refund without rewriting it.
  const settlementStatus = order.settlementStatus as string | undefined;
  const holdSettlement =
    settlementStatus === undefined ||
    settlementStatus === "pending" ||
    settlementStatus === "eligible";

  const disputeRef = db.collection("disputes").doc(orderId);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(disputeRef);
    if (existing.exists) {
      throw new HttpsError(
        "failed-precondition",
        "A report already exists for this order."
      );
    }
    tx.set(disputeRef, {
      orderId,
      listingId: order.listingId as string,
      buyerId: uid,
      sellerId: order.sellerId as string,
      amount: order.amount as number,
      reason,
      description,
      photoUrls,
      status: "open",
      filedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(orderRef, {
      disputeStatus: "open",
      ...(holdSettlement ? { settlementStatus: "held" } : {}),
    });
    tx.set(
      db
        .collection("users")
        .doc(order.sellerId as string)
        .collection("notifications")
        .doc(),
      {
        type: NotificationType.disputeFiled,
        title: "A buyer reported a problem",
        body: `The buyer reported a problem with “${orderTitle(order)}”. Your payout for this order is on hold while the Trega team reviews it.`,
        data: { orderId },
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }
    );
  });
  return { filed: true as const };
}

/** Admin resolves an open report: buyer favor (refund) or seller favor. */
export async function resolveDisputeHandler(
  isAdmin: boolean,
  input: {
    orderId?: string;
    decision?: string;
    note?: string;
    refundReference?: string;
  }
): Promise<{ resolved: true }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const { orderId, decision } = input;
  assertDocId(orderId, "orderId");
  if (decision !== "buyer" && decision !== "seller") {
    throw new HttpsError(
      "invalid-argument",
      "decision must be 'buyer' or 'seller'."
    );
  }
  const note =
    input.note === undefined ||
    input.note === null ||
    (typeof input.note === "string" && input.note.trim() === "")
      ? null
      : assertText(input.note, "note", 1, 500);
  const refundReference =
    input.refundReference === undefined ||
    input.refundReference === null ||
    (typeof input.refundReference === "string" &&
      input.refundReference.trim() === "")
      ? null
      : assertText(input.refundReference, "refundReference", 1, 100);

  const db = admin.firestore();
  const disputeRef = db.collection("disputes").doc(orderId);
  const disputeSnap = await disputeRef.get();
  if (!disputeSnap.exists) {
    throw new HttpsError("not-found", "No report exists for this order.");
  }
  if (disputeSnap.data()?.status !== "open") {
    throw new HttpsError(
      "failed-precondition",
      "This report is already resolved."
    );
  }
  const orderRef = db.collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();
  const order = orderSnap.data();
  if (!orderSnap.exists || !order) {
    throw new HttpsError("not-found", "Order not found.");
  }

  const buyerFavor = decision === "buyer";
  const title = orderTitle(order);
  const buyerTotal =
    typeof order.buyerTotal === "number"
      ? (order.buyerTotal as number)
      : (order.amount as number);
  // A payout already sent stays sent; the refund is recorded alongside.
  const settlementPaid = order.settlementStatus === "paid";

  const batch = db.batch();
  batch.update(disputeRef, {
    status: buyerFavor ? "resolved_buyer" : "resolved_seller",
    resolutionNote: note,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(refundReference ? { refundReference } : {}),
  });
  batch.update(orderRef, {
    disputeStatus: "resolved",
    ...(settlementPaid
      ? {}
      : {
          settlementStatus: buyerFavor ? "cancelled" : "eligible",
        }),
    ...(buyerFavor
      ? {
          refundStatus: "refunded",
          ...(refundReference ? { refundReference } : {}),
        }
      : {}),
  });
  queueNotification(batch, order.buyerId as string, {
    type: NotificationType.disputeResolved,
    data: { orderId },
    title: "Your report was resolved",
    body: buyerFavor
      ? `We found in your favor for “${title}”. A refund of ${formatINR(buyerTotal)} will reach your original payment method within 5 to 7 business days.`
      : `We reviewed your report for “${title}” and found the order was as described. The seller's payout will proceed.`,
  });
  queueNotification(batch, order.sellerId as string, {
    type: NotificationType.disputeResolved,
    data: { orderId },
    title: "A report was resolved",
    body: buyerFavor
      ? `The report on “${title}” was resolved in the buyer's favor. A refund of ${formatINR(buyerTotal)} was issued and no payout will be sent for this order.`
      : `The report on “${title}” was resolved in your favor. Your payout of ${formatINR(sellerPayoutOf(order))} will proceed.`,
  });
  await batch.commit();
  return { resolved: true as const };
}

/**
 * Admin marks a payout as sent (the UPI transfer itself happens outside
 * this system). Requires `eligible`, except for orders delivered before
 * settlement tracking shipped, which carry no `settlementStatus` and
 * may be marked paid directly once the admin has verified delivery.
 */
export async function markSettlementPaidHandler(
  isAdmin: boolean,
  input: { orderId?: string; reference?: string }
): Promise<{ paid: true }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const { orderId } = input;
  assertDocId(orderId, "orderId");
  const reference = assertText(input.reference, "reference", 1, 100);

  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);
  const orderSnap = await orderRef.get();
  const order = orderSnap.data();
  if (!orderSnap.exists || !order) {
    throw new HttpsError("not-found", "Order not found.");
  }
  const settlementStatus = order.settlementStatus as string | undefined;
  const legacy =
    settlementStatus === undefined &&
    order.status === "delivered" &&
    order.disputeStatus !== "open";
  if (settlementStatus !== "eligible" && !legacy) {
    throw new HttpsError(
      "failed-precondition",
      "This order's payout is not ready to be marked paid."
    );
  }

  const batch = db.batch();
  batch.update(orderRef, {
    settlementStatus: "paid",
    settlementPaidAt: admin.firestore.FieldValue.serverTimestamp(),
    settlementReference: reference,
  });
  queueNotification(batch, order.sellerId as string, {
    type: NotificationType.settlementPaid,
    data: { orderId },
    title: "Payout sent",
    body: `Your payout of ${formatINR(sellerPayoutOf(order))} for “${orderTitle(order)}” was sent to your UPI. Reference: ${reference}.`,
  });
  await batch.commit();
  return { paid: true as const };
}

/**
 * Hourly: flip delivered orders whose 72-hour support window has passed
 * (and no report is open) from `pending` to `eligible`, so the admin
 * can pay them out. Single-field query + in-code filters, no composite
 * index needed. Orders without `deliveredAt` (delivered before
 * delivery timestamps shipped) are skipped, the admin pays those via
 * the legacy path in `markSettlementPaidHandler`.
 */
export async function releaseSettlementsHandler(): Promise<{
  released: number;
}> {
  const db = admin.firestore();
  const cutoff = Date.now() - DISPUTE_WINDOW_MS;
  const snap = await db
    .collection("orders")
    .where("settlementStatus", "==", "pending")
    .limit(200)
    .get();
  let released = 0;
  const batch = db.batch();
  for (const doc of snap.docs) {
    const o = doc.data();
    if (o.status !== "delivered") continue;
    if (o.disputeStatus === "open") continue;
    const deliveredMs =
      (o.deliveredAt as admin.firestore.Timestamp | undefined)?.toMillis?.() ??
      0;
    if (deliveredMs === 0 || deliveredMs > cutoff) continue;
    batch.update(doc.ref, { settlementStatus: "eligible" });
    released++;
  }
  if (released > 0) await batch.commit();
  return { released };
}
