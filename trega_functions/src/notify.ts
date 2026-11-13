import * as admin from "firebase-admin";

/**
 * Shared inbox-notification plumbing, used by every module that tells a
 * user something happened (marketplace, payments, admin, Shiprocket,
 * disputes). It lives in its own module because `payments.ts` needs to
 * queue payment notifications and `marketplace.ts` imports fee helpers
 * from `payments.ts`: defining the notifier in `marketplace.ts` would
 * make the two modules import each other.
 *
 * Delivery is async: callables only write the inbox doc and return; the
 * `onNotificationCreate` trigger fires on the new doc and sends the
 * matching FCM push, claimed via `pushSent` (see marketplace.ts).
 */

/** Notification kinds written to `users/{uid}/notifications`. */
export const NotificationType = {
  bidReceived: "bid_received",
  outbid: "outbid",
  bidAccepted: "bid_accepted",
  bidRejected: "bid_rejected",
  listingFlagged: "listing_flagged",
  shipmentUpdate: "shipment_update",
  paymentReceived: "payment_received",
  fulfillmentUpdate: "fulfillment_update",
  disputeFiled: "dispute_filed",
  disputeResolved: "dispute_resolved",
  settlementPaid: "settlement_paid",
  acceptanceExpired: "acceptance_expired",
} as const;

/** Queues one inbox notification on a write batch. The matching FCM
 * push is delivered asynchronously by the `onNotificationCreate`
 * trigger firing on this doc, never awaited by the caller, so
 * accept/reject/payment return the moment the batch commits. */
export function queueNotification(
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
