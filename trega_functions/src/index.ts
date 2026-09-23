/**
 * Trega marketplace Cloud Functions (Firebase project: tregaxmuse).
 *
 * - KYC: Aadhaar OTP via BulkPe (token from the BULKPE_API_TOKEN secret).
 * - Payments: Cashfree PG (CASHFREE_APP_ID / CASHFREE_SECRET_KEY / CASHFREE_ENV).
 * - Marketplace: listing review queue, structured bids/offers, orders.
 * - No buyer-seller chat anywhere by design.
 */
import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

import {
  BULKPE_API_TOKEN,
  CASHFREE_APP_ID,
  CASHFREE_ENV,
  CASHFREE_SECRET_KEY,
} from "./config";
import { requestAadhaarOtpHandler, verifyAadhaarOtpHandler } from "./kyc";
import {
  createCashfreeOrderHandler,
  handleCashfreeWebhook,
} from "./payments";
import {
  acceptBidHandler,
  onBidCreateHandler,
  onListingCreateHandler,
  placeBidHandler,
  reviewListingHandler,
} from "./marketplace";
import {
  setUserKycStatusHandler,
  updateOrderFulfillmentHandler,
} from "./admin";

admin.initializeApp();
setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

const secrets = [BULKPE_API_TOKEN, CASHFREE_APP_ID, CASHFREE_SECRET_KEY, CASHFREE_ENV];

function requireAuthUid(req: { auth?: { uid: string } | null }): string {
  if (!req.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  return req.auth.uid;
}

// ---------------------------------------------------------------- KYC ------
export const requestAadhaarOtp = onCall({ secrets }, async (request) => {
  const uid = requireAuthUid(request);
  return requestAadhaarOtpHandler(uid, request.data?.aadhaarNumber);
});

export const verifyAadhaarOtp = onCall({ secrets }, async (request) => {
  const uid = requireAuthUid(request);
  return verifyAadhaarOtpHandler(uid, request.data?.refId, request.data?.otp);
});

// --------------------------------------------------------- Payments ---------
export const createCashfreeOrder = onCall({ secrets }, async (request) => {
  const uid = requireAuthUid(request);
  return createCashfreeOrderHandler(uid, {
    listingId: request.data?.listingId,
    bidId: request.data?.bidId,
    customerPhone: request.data?.customerPhone,
  });
});

/**
 * Cashfree PG webhook. Register this URL in the Cashfree dashboard:
 * https://asia-south1-tregaxmuse.cloudfunctions.net/cashfreeWebhook
 */
export const cashfreeWebhook = onRequest(
  { secrets: [CASHFREE_SECRET_KEY] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }
    // Use the raw body for signature verification (available on the
    // Express request that firebase-functions v2 provides).
    const rawBody: Buffer = (req as unknown as { rawBody?: Buffer }).rawBody
      ?? Buffer.from(JSON.stringify(req.body ?? {}), "utf8");

    const result = await handleCashfreeWebhook(
      rawBody,
      req.header("x-webhook-signature")
    );
    if (!result.ok) {
      logger.warn("cashfreeWebhook rejected", { reason: result.reason });
      res.status(400).send(result.reason ?? "rejected");
      return;
    }
    res.status(200).send("ok");
  }
);

// ------------------------------------------------------- Marketplace -------
export const onListingCreate = onDocumentCreated(
  "listings/{listingId}",
  async (event) => {
    await onListingCreateHandler(event.params.listingId, event.data?.data());
  }
);

export const reviewListing = onCall(async (request) => {
  const isAdmin = request.auth?.token?.admin === true;
  return reviewListingHandler(isAdmin, {
    listingId: request.data?.listingId,
    decision: request.data?.decision,
    reason: request.data?.reason,
  });
});

export const placeBid = onCall(async (request) => {
  const uid = requireAuthUid(request);
  return placeBidHandler(uid, {
    listingId: request.data?.listingId,
    amount: request.data?.amount,
  });
});

/**
 * New bid → notifies the seller ("new bid") and the previous highest
 * bidder if outbid. Single-field query inside; no composite index needed.
 */
export const onBidCreate = onDocumentCreated(
  "bids/{bidId}",
  async (event) => {
    await onBidCreateHandler(event.params.bidId, event.data?.data());
  }
);

export const acceptBid = onCall(async (request) => {
  const uid = requireAuthUid(request);
  return acceptBidHandler(uid, { bidId: request.data?.bidId });
});

// ------------------------------------------------------------- Admin ------
// Privileged mutations for the admin panel (admin custom claim required).
// Categories are managed directly through Firestore rules (`isAdmin()`).
export const setUserKycStatus = onCall(async (request) => {
  const isAdmin = request.auth?.token?.admin === true;
  return setUserKycStatusHandler(isAdmin, {
    uid: request.data?.uid,
    status: request.data?.status,
    note: request.data?.note,
  });
});

export const updateOrderFulfillment = onCall(async (request) => {
  const isAdmin = request.auth?.token?.admin === true;
  return updateOrderFulfillmentHandler(isAdmin, {
    orderId: request.data?.orderId,
    status: request.data?.status,
    trackingNote: request.data?.trackingNote,
  });
});
