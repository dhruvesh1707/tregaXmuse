/**
 * Trega marketplace Cloud Functions (Firebase project: tregaxmuse).
 *
 * - KYC: Aadhaar OTP via BulkPe (token from the BULKPE_API_TOKEN secret).
 * - Payments: Cashfree PG (CASHFREE_APP_ID / CASHFREE_SECRET_KEY / CASHFREE_ENV).
 * - Marketplace: listing review queue, structured bids/offers, orders.
 * - No buyer-seller chat anywhere by design.
 *
 * Security layers (see SECURITY.md notes in each module):
 * - `rateLimit.ts`: per-IP + per-account rate limiting with exponential
 *   backoff on every callable + the webhook; thresholds configurable via
 *   the console-only `config/rateLimits` doc (clients can't read it).
 * - `validate.ts`: strict schema validation on every external input.
 * - `storageCheck.ts`: magic-byte content check on uploads (Storage rules
 *   enforce content-type + size at upload time; this closes the
 *   fake-content-type hole).
 */
import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import {
  BULKPE_API_TOKEN,
  CASHFREE_APP_ID,
  CASHFREE_ENV,
  CASHFREE_SECRET_KEY,
  KYC_SALT,
  ADMIN_BOOTSTRAP_PHONE,
} from "./config";
import { clientIp, rateLimit } from "./rateLimit";
import { requestAadhaarOtpHandler, verifyAadhaarOtpHandler } from "./kyc";
import {
  createCashfreeOrderHandler,
  handleCashfreeWebhook,
  verifyPaymentHandler,
} from "./payments";
import {
  acceptBidHandler,
  archiveSoldListingsHandler,
  cancelAcceptanceHandler,
  deleteListingHandler,
  deleteOwnListingHandler,
  onBidCreateHandler,
  onListingCreateHandler,
  onNotificationCreateHandler,
  placeBidHandler,
  recordListingViewHandler,
  rejectBidHandler,
  reviewListingHandler,
} from "./marketplace";
import {
  bootstrapAdminHandler,
  sendCampaignHandler,
  setUserKycStatusHandler,
  updateOrderFulfillmentHandler,
} from "./admin";
import { deleteAccountHandler } from "./account";
import {
  listingPageHandler,
  listingsSitemapHandler,
} from "./listingPage";
import { checkUploadedImage } from "./storageCheck";

admin.initializeApp();
setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

// Warm instances (perf fix, 2026-11-13): functions scale to zero by
// default, so the first offer or payment after idle paid a multi-second
// cold start. The six callables a user waits on (createCashfreeOrder,
// verifyPayment, placeBid, acceptBid, rejectBid, cancelAcceptance)
// carry minInstances: 1 + 512MiB, so one instance stays awake and
// answers at once. Billed idle time, roughly $6-10 per function per
// month, approved by the founder. Applied per function, never
// globally: triggers, admin callables, and recordListingView (the app
// never waits on it) still scale to zero.

const secrets = [BULKPE_API_TOKEN, CASHFREE_APP_ID, CASHFREE_SECRET_KEY, CASHFREE_ENV, KYC_SALT];

function requireAuthUid(req: { auth?: { uid: string } | null }): string {
  if (!req.auth?.uid) {
    throw new HttpsError("unauthenticated", "Sign in to continue.");
  }
  return req.auth.uid;
}

const ipOf = (request: { rawRequest?: unknown }) => clientIp(request.rawRequest);

// ---------------------------------------------------------------- KYC ------
export const requestAadhaarOtp = onCall({ secrets }, async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("kycOtp", { uid, ip: ipOf(request) });
  return requestAadhaarOtpHandler(uid, request.data?.aadhaarNumber);
});

export const verifyAadhaarOtp = onCall({ secrets }, async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("kycVerify", { uid, ip: ipOf(request) });
  return verifyAadhaarOtpHandler(uid, request.data?.refId, request.data?.otp);
});

// --------------------------------------------------------- Payments ---------
export const createCashfreeOrder = onCall(
  { secrets, minInstances: 1, memory: "512MiB" },
  async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("payments", { uid, ip: ipOf(request) });
  return createCashfreeOrderHandler(uid, {
    bidId: request.data?.bidId,
    customerPhone: request.data?.customerPhone,
    deliveryAddress: request.data?.deliveryAddress,
    deliveryType: request.data?.deliveryType,
  });
});

/**
 * Server-side payment verification. The app calls this after the Cashfree
 * SDK reports success and treats the order as paid ONLY when this returns
 * `paymentStatus: "SUCCESS"`, the SDK's on-device callback alone is never
 * trusted (it only means the sheet reported success on that phone).
 */
export const verifyPayment = onCall(
  { secrets, minInstances: 1, memory: "512MiB" },
  async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("payments", { uid, ip: ipOf(request) });
  return verifyPaymentHandler(uid, request.data?.orderId);
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
    try {
      await rateLimit("webhook", { ip: clientIp(req) });
    } catch (e) {
      if (e instanceof HttpsError && e.code === "resource-exhausted") {
        res.status(429).send("Too many requests");
        return;
      }
      throw e;
    }
    // Use the raw body for signature verification (available on the
    // Express request that firebase-functions v2 provides).
    const rawBody: Buffer = (req as unknown as { rawBody?: Buffer }).rawBody
      ?? Buffer.from(JSON.stringify(req.body ?? {}), "utf8");

    const result = await handleCashfreeWebhook(
      rawBody,
      req.header("x-webhook-signature"),
      req.header("x-webhook-timestamp")
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
  await rateLimit("adminOps", { uid: request.auth?.uid, ip: ipOf(request) });
  const isAdmin = request.auth?.token?.admin === true;
  return reviewListingHandler(isAdmin, {
    listingId: request.data?.listingId,
    decision: request.data?.decision,
    reason: request.data?.reason,
  });
});

/**
 * Permanent admin delete of a listing (doc + bids + media). The hard
 * counterpart to reviewListing's reject; sold listings are refused
 * because an order references them.
 */
export const deleteListing = onCall(async (request) => {
  await rateLimit("adminOps", { uid: request.auth?.uid, ip: ipOf(request) });
  const isAdmin = request.auth?.token?.admin === true;
  return deleteListingHandler(isAdmin, {
    listingId: request.data?.listingId,
  });
});

/**
 * Seller deletes their own listing (My Listings). Refused when the
 * listing is sold or has an accepted offer; the accepted offer reserves
 * it for the winning buyer until they pay.
 */
export const deleteOwnListing = onCall(async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("listingDelete", { uid, ip: ipOf(request) });
  return deleteOwnListingHandler(uid, {
    listingId: request.data?.listingId,
  });
});

/**
 * Hourly: archive sold listings older than 48h so they leave the public
 * view (single-doc reads of archived listings are restricted to the
 * seller, the buyer and admins). Runs on the service account, no auth.
 */
export const archiveSoldListings = onSchedule(
  {
    schedule: "every 60 minutes",
    region: "asia-south1",
  },
  async () => {
    const { archived } = await archiveSoldListingsHandler();
    logger.info("archiveSoldListings: archived listings", { archived });
  }
);

export const placeBid = onCall(
  { minInstances: 1, memory: "512MiB" },
  async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("bids", { uid, ip: ipOf(request) });
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

/**
 * New inbox notification → sends the matching FCM push. Push delivery
 * used to be awaited inside the accept/reject callables, so the seller
 * waited for pushes to other people before Accept confirmed. Now the
 * callables only write the inbox doc and return; this trigger delivers
 * the push asynchronously (perf fix, 2026-11-13). Delivery is claimed
 * in a transaction inside the handler, so a trigger redelivery never
 * double-sends. No warm instance on purpose: a cold start only delays
 * a push by seconds, and the inbox doc itself is immediate.
 */
export const onNotificationCreate = onDocumentCreated(
  "users/{uid}/notifications/{notificationId}",
  async (event) => {
    await onNotificationCreateHandler(
      event.params.uid,
      event.params.notificationId,
      event.data?.data()
    );
  }
);

export const acceptBid = onCall(
  { minInstances: 1, memory: "512MiB" },
  async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("bids", { uid, ip: ipOf(request) });
  return acceptBidHandler(uid, { bidId: request.data?.bidId });
});

export const rejectBid = onCall(
  { minInstances: 1, memory: "512MiB" },
  async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("bids", { uid, ip: ipOf(request) });
  return rejectBidHandler(uid, { bidId: request.data?.bidId });
});

export const cancelAcceptance = onCall(
  { minInstances: 1, memory: "512MiB" },
  async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("bids", { uid, ip: ipOf(request) });
  return cancelAcceptanceHandler(uid, { bidId: request.data?.bidId });
});

/**
 * Instagram-style listing view counter. The app calls this only after the
 * detail screen has been continuously visible for 3 seconds (IG's video-view
 * threshold). Seller self-views never count; replays count after a 1-hour
 * per-viewer cooldown. Replaces the old client-side `viewCount` increment.
 */
export const recordListingView = onCall(async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("views", { uid, ip: ipOf(request) });
  return recordListingViewHandler(uid, { listingId: request.data?.listingId });
});

// ------------------------------------------------------------- Admin ------
// Privileged mutations for the admin panel (admin custom claim required).
// Categories are managed directly through Firestore rules (`isAdmin()`).

/**
 * One-shot self-service admin bootstrap. The founder signs in to the admin
 * panel with their phone number, claims admin access, and this grants the
 * `admin` custom claim, but ONLY when the caller's verified phone number
 * matches the ADMIN_BOOTSTRAP_PHONE secret. Set it with:
 *   firebase functions:secrets:set ADMIN_BOOTSTRAP_PHONE   # e.g. +919876543210
 */
export const bootstrapAdmin = onCall(
  { secrets: [ADMIN_BOOTSTRAP_PHONE] },
  async (request) => {
    const uid = requireAuthUid(request);
    await rateLimit("bootstrap", { uid, ip: ipOf(request) });
    return bootstrapAdminHandler(
      uid,
      request.auth?.token?.phone_number,
      ADMIN_BOOTSTRAP_PHONE.value()
    );
  }
);

export const setUserKycStatus = onCall(async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("adminOps", { uid, ip: ipOf(request) });
  const isAdmin = request.auth?.token?.admin === true;
  return setUserKycStatusHandler(isAdmin, uid, {
    uid: request.data?.uid,
    status: request.data?.status,
    note: request.data?.note,
  });
});

/**
 * Broadcast a custom campaign push (text + optional image + optional
 * listing/category deep link) to every user with a saved FCM token.
 * Admin claim required; one `campaigns` doc is kept as history.
 */
export const sendCampaign = onCall(async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("adminOps", { uid, ip: ipOf(request) });
  const isAdmin = request.auth?.token?.admin === true;
  return sendCampaignHandler(isAdmin, uid, {
    title: request.data?.title,
    body: request.data?.body,
    imageUrl: request.data?.imageUrl,
    linkType: request.data?.linkType,
    listingId: request.data?.listingId,
    categoryId: request.data?.categoryId,
  });
});

export const updateOrderFulfillment = onCall(async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("adminOps", { uid, ip: ipOf(request) });
  const isAdmin = request.auth?.token?.admin === true;
  return updateOrderFulfillmentHandler(isAdmin, {
    orderId: request.data?.orderId,
    status: request.data?.status,
    trackingNote: request.data?.trackingNote,
  });
});

// ---------------------------------------------------------- Account --------
/**
 * Deletes the caller's account and EVERY record tied to it (listings,
 * bids, orders, reviews, reports, notifications, KYC, media, the Auth
 * user itself). No undo, the app gates this behind an explicit
 * confirmation dialog.
 */
export const deleteAccount = onCall(async (request) => {
  const uid = requireAuthUid(request);
  await rateLimit("deleteAccount", { uid, ip: ipOf(request) });
  return deleteAccountHandler(uid);
});

// ------------------------------------------------------------ Uploads ------
// Content-level upload validation: deletes any new object under
// `listingMedia/` or `avatars/` whose magic bytes aren't a real image.
// (Storage rules enforce `image/*` content-type + 10 MB at upload time;
// this closes the fake-content-type hole. See storageCheck.ts.)
export const validateUpload = onObjectFinalized(
  {
    // The Storage bucket lives in us-east1, Eventarc requires the
    // trigger in the same region as the bucket. (The global default
    // stays asia-south1 for everything else.)
    region: "us-east1",
  },
  async (event) => {
    await checkUploadedImage(event.data.name, event.data.bucket);
  },
);

// ------------------------------------------------- Public listing pages --
// SEO Phase 3: server-rendered listing pages + dynamic listings sitemap.
// Public GET endpoints (NOT callables, so no callable rate limiter); all
// canonical / sitemap URLs are built on https://trega.in inside
// listingPage.ts (PUBLIC_BASE_URL), tregaxmuse.web.app stays internal.
export const listingPage = onRequest(async (req, res) => {
  await listingPageHandler(req, res);
});

export const listingsSitemap = onRequest(async (_req, res) => {
  await listingsSitemapHandler(res);
});
