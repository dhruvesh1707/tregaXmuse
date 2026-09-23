import * as admin from "firebase-admin";
import { createHmac, timingSafeEqual } from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import {
  CASHFREE_API_VERSION,
  CASHFREE_APP_ID,
  CASHFREE_ENV,
  CASHFREE_SECRET_KEY,
  cashfreeBase,
} from "./config";

export type PaymentStatus = "PENDING" | "SUCCESS" | "FAILED" | "USER_DROPPED";
export type OrderStatus =
  | "placed"
  | "pickup_scheduled"
  | "picked_up"
  | "in_transit"
  | "delivered"
  | "cancelled"
  | "returned";

interface CashfreeOrderResponse {
  cf_order_id: number;
  order_id: string;
  payment_session_id: string;
  order_status: string;
}

function cashfreeHeaders(): Record<string, string> {
  const appId = CASHFREE_APP_ID.value();
  const secret = CASHFREE_SECRET_KEY.value();
  if (!appId || !secret) {
    throw new HttpsError("failed-precondition", "Payments are not configured.");
  }
  return {
    "Content-Type": "application/json",
    "x-api-version": CASHFREE_API_VERSION,
    "x-client-id": appId,
    "x-client-secret": secret,
  };
}

/**
 * Creates a Cashfree order for a live listing (or an accepted bid).
 * The amount is ALWAYS read from Firestore — the client-supplied value,
 * if any, is ignored.
 */
export async function createCashfreeOrderHandler(
  uid: string,
  input: { listingId?: string; bidId?: string; customerPhone?: string }
): Promise<{ paymentSessionId: string; orderId: string; cfOrderId: number }> {
  const db = admin.firestore();
  const { listingId, bidId } = input;
  if ((listingId ? 1 : 0) + (bidId ? 1 : 0) !== 1) {
    throw new HttpsError(
      "invalid-argument",
      "Provide exactly one of listingId or bidId."
    );
  }

  let listingRef: admin.firestore.DocumentReference;
  let amount: number;
  let sellerId: string;

  if (bidId) {
    const bidSnap = await db.collection("bids").doc(bidId).get();
    const bid = bidSnap.data();
    if (!bidSnap.exists || !bid) throw new HttpsError("not-found", "Bid not found.");
    if (bid.buyerId !== uid) {
      throw new HttpsError("permission-denied", "This bid is not yours.");
    }
    if (bid.status !== "accepted") {
      throw new HttpsError("failed-precondition", "Bid is not accepted yet.");
    }
    listingRef = db.collection("listings").doc(bid.listingId as string);
    amount = bid.amount as number;
    sellerId = bid.sellerId as string;
  } else {
    listingRef = db.collection("listings").doc(listingId as string);
    const listingSnap = await listingRef.get();
    const listing = listingSnap.data();
    if (!listingSnap.exists || !listing) {
      throw new HttpsError("not-found", "Listing not found.");
    }
    if (listing.status !== "live") {
      throw new HttpsError("failed-precondition", "Listing is not available.");
    }
    if (listing.sellerId === uid) {
      throw new HttpsError("failed-precondition", "You cannot buy your own listing.");
    }
    amount = listing.price as number;
    sellerId = listing.sellerId as string;
  }

  if (typeof amount !== "number" || amount <= 0) {
    throw new HttpsError("failed-precondition", "Invalid order amount.");
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
    paymentStatus: "PENDING" satisfies PaymentStatus,
    status: "placed" satisfies OrderStatus,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 2. Create the Cashfree order.
  const base = cashfreeBase(CASHFREE_ENV.value() || "sandbox");
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
        customer_phone:
          input.customerPhone ??
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
    await orderRef.update({ paymentStatus: "FAILED" satisfies PaymentStatus });
    throw new HttpsError("unavailable", `Payment provider error (${res.status}): ${text}`);
  }
  const cf = (await res.json()) as CashfreeOrderResponse;

  await orderRef.update({
    cfOrderId: cf.cf_order_id,
    cfOrderRef: cfOrderIdStr,
    paymentSessionId: cf.payment_session_id,
  });

  return {
    paymentSessionId: cf.payment_session_id,
    orderId,
    cfOrderId: cf.cf_order_id,
  };
}

/**
 * Verifies a Cashfree PG webhook signature.
 * Cashfree signs webhooks as base64(HMAC_SHA256(secretKey, rawRequestBody)).
 */
export function verifyWebhookSignature(
  rawBody: Buffer,
  signatureHeader: string | undefined
): boolean {
  const secret = CASHFREE_SECRET_KEY.value();
  if (!secret || !signatureHeader) return false;
  const expected = createHmac("sha256", secret).update(rawBody).digest("base64");
  const a = Buffer.from(expected);
  const b = Buffer.from(signatureHeader);
  return a.length === b.length && timingSafeEqual(a, b);
}

interface CashfreeWebhookPayload {
  data?: {
    order?: { order_id?: string; order_amount?: number };
    payment?: { payment_status?: string; cf_payment_id?: number };
  };
  type?: string;
}

export async function handleCashfreeWebhook(
  rawBody: Buffer,
  signatureHeader: string | undefined
): Promise<{ ok: boolean; reason?: string }> {
  if (!verifyWebhookSignature(rawBody, signatureHeader)) {
    return { ok: false, reason: "bad_signature" };
  }
  const payload = JSON.parse(rawBody.toString("utf8")) as CashfreeWebhookPayload;
  const cfOrderRef = payload.data?.order?.order_id;
  const paymentStatus = payload.data?.payment?.payment_status;
  if (!cfOrderRef) return { ok: false, reason: "missing_order" };

  const db = admin.firestore();
  const q = await db
    .collection("orders")
    .where("cfOrderRef", "==", cfOrderRef)
    .limit(1)
    .get();
  if (q.empty) return { ok: false, reason: "unknown_order" };
  const orderRef = q.docs[0].ref;
  const order = q.docs[0].data();

  if (paymentStatus === "SUCCESS") {
    const batch = db.batch();
    batch.update(orderRef, {
      paymentStatus: "SUCCESS" satisfies PaymentStatus,
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection("listings").doc(order.listingId as string), {
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
  } else if (paymentStatus === "FAILED" || paymentStatus === "USER_DROPPED") {
    await orderRef.update({
      paymentStatus: paymentStatus as PaymentStatus,
    });
  }
  return { ok: true };
}
