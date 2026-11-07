import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { assertDocId, assertText } from "./validate";

/**
 * Admin-only operations for the Trega admin panel.
 *
 * The Firestore rules intentionally block clients from writing server-managed
 * fields (kycStatus, order status, …), so the admin panel performs these
 * privileged mutations through callables guarded by the `admin` custom claim.
 *
 * The very first admin bootstraps their own claim via `bootstrapAdmin`,
 * which only succeeds when the caller's verified phone number matches the
 * ADMIN_BOOTSTRAP_PHONE secret.
 */

export type AdminKycStatus = "verified" | "rejected";

const ORDER_STATUSES = [
  "placed",
  "pickup_scheduled",
  "picked_up",
  "in_transit",
  "delivered",
  "cancelled",
  "returned",
] as const;

/**
 * One-shot self-service admin bootstrap. Grants `{admin: true}` to the
 * caller when, and only when, their verified Firebase Auth phone number
 * matches the ADMIN_BOOTSTRAP_PHONE secret (E.164, e.g. +919876543210).
 *
 * The phone number comes from the verified ID token, so it cannot be
 * spoofed. After this returns, the client must refresh its ID token
 * (`getIdToken(true)`) before the claim is visible.
 */
export async function bootstrapAdminHandler(
  uid: string,
  callerPhone: unknown,
  bootstrapPhone: string
): Promise<{ admin: true }> {
  if (typeof callerPhone !== "string" || callerPhone.length === 0) {
    throw new HttpsError(
      "permission-denied",
      "Admin bootstrap requires phone sign-in."
    );
  }
  if (!bootstrapPhone || callerPhone !== bootstrapPhone.trim()) {
    throw new HttpsError(
      "permission-denied",
      "This number is not authorized for admin access."
    );
  }
  await admin.auth().setCustomUserClaims(uid, { admin: true });
  return { admin: true as const };
}

/** Admin-only: mark a user's KYC as verified (badges them as a verified
 * seller) or rejected with an optional note.
 *
 * Writes:
 * - `users/{uid}`: kycStatus, verifiedSeller, kycNote (shown in the panel)
 * - `kycVerifications/{uid}` (merge): method 'manual' audit trail so the
 *   panel can tell a manual verification apart from an Aadhaar one
 * - `users/{uid}/notifications`: tells the user what happened, this is
 *   what unlocks selling / making offers in the app, so they get told.
 */
export async function setUserKycStatusHandler(
  isAdmin: boolean,
  adminUid: string,
  input: { uid?: string; status?: string; note?: string }
): Promise<{ kycStatus: AdminKycStatus }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const { uid, status, note } = input;
  assertDocId(uid, "uid");
  if (status !== "verified" && status !== "rejected") {
    throw new HttpsError(
      "invalid-argument",
      "status must be 'verified' or 'rejected'."
    );
  }

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "User not found.");

  const cleanNote =
    note === undefined ||
    note === null ||
    (typeof note === "string" && note.trim() === "")
      ? null
      : assertText(note, "note", 1, 1000);
  const batch = db.batch();
  batch.update(userRef, {
    kycStatus: status,
    verifiedSeller: status === "verified",
    kycNote: cleanNote ?? admin.firestore.FieldValue.delete(),
  });
  // Audit trail (merge, never clobbers an Aadhaar fingerprint if one exists).
  batch.set(
    db.collection("kycVerifications").doc(uid),
    {
      status: status === "verified" ? "verified" : "failed",
      method: "manual",
      verifiedBy: adminUid,
      note: cleanNote,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(status === "verified"
        ? { verifiedAt: admin.firestore.FieldValue.serverTimestamp() }
        : {}),
    },
    { merge: true }
  );
  // Tell the user.
  batch.set(userRef.collection("notifications").doc(), {
    type: status === "verified" ? "kyc_verified" : "kyc_rejected",
    title: status === "verified" ? "KYC verified" : "KYC rejected",
    body:
      status === "verified"
        ? "The Trega team verified your account. You can now sell items and make offers."
        : `The Trega team rejected your verification.${cleanNote ? ` Reason: ${cleanNote}` : ""}`,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { kycStatus: status };
}

/** Admin-only: advance order fulfillment (status / tracking note).
 * Payment status is owned by the Cashfree webhook and cannot be set here. */
export async function updateOrderFulfillmentHandler(
  isAdmin: boolean,
  input: { orderId?: string; status?: string; trackingNote?: string }
): Promise<{ status: string }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const { orderId, status, trackingNote } = input;
  assertDocId(orderId, "orderId");
  if (
    status !== undefined &&
    !(ORDER_STATUSES as readonly string[]).includes(status)
  ) {
    throw new HttpsError("invalid-argument", `Invalid order status: ${status}`);
  }

  const ref = admin.firestore().collection("orders").doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Order not found.");

  const update: Record<string, unknown> = {};
  if (status !== undefined) update.status = status;
  if (trackingNote !== undefined) {
    if (typeof trackingNote !== "string") {
      throw new HttpsError("invalid-argument", "Invalid tracking note.");
    }
    const trimmedNote = trackingNote.trim();
    if (trimmedNote.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "Tracking note must be under 500 characters."
      );
    }
    update.trackingNote = trimmedNote;
  }
  if (Object.keys(update).length === 0) {
    throw new HttpsError("invalid-argument", "Nothing to update.");
  }
  await ref.update(update);
  return { status: (snap.data()?.status as string) ?? "placed" };
}

/**
 * Admin-only: broadcast a custom campaign push (Zomato-style) to every
 * user with at least one saved FCM token. Text + optional image +
 * optional deep link (a live listing, or a category), the app routes
 * the tap through its notification_router (`campaign` type). One
 * `campaigns` doc is written per send as the admin history; the push is
 * deliberately NOT copied into user inboxes (promos are tray-only).
 */
export async function sendCampaignHandler(
  isAdmin: boolean,
  createdBy: string | undefined,
  input: {
    title?: string;
    body?: string;
    imageUrl?: string;
    linkType?: string;
    listingId?: string;
    categoryId?: string;
  }
): Promise<{ recipients: number; sent: number; failed: number }> {
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
  const title = assertText(input.title, "title", 1, 100);
  const body = assertText(input.body, "body", 1, 300);

  // Optional image: a plain https URL. FCM and the devices fetch it;
  // this function never does.
  let imageUrl: string | undefined;
  if (input.imageUrl != null && input.imageUrl !== "") {
    imageUrl = assertText(input.imageUrl, "imageUrl", 1, 1000);
    if (!imageUrl.startsWith("https://")) {
      throw new HttpsError(
        "invalid-argument",
        "imageUrl must be an https URL."
      );
    }
  }

  const db = admin.firestore();

  // Optional deep link. A listing link is only as good as the listing,
  // so verify it exists and is live; a category link carries its display
  // name so the app can title the screen without a second lookup.
  const data: Record<string, string> = { type: "campaign" };
  let linkType: "none" | "listing" | "category" = "none";
  let listingId: string | undefined;
  let categoryId: string | undefined;
  let categoryName: string | undefined;
  if (input.linkType === "listing") {
    assertDocId(input.listingId, "listingId");
    const snap = await db.collection("listings").doc(input.listingId).get();
    if (!snap.exists || snap.data()?.status !== "live") {
      throw new HttpsError(
        "invalid-argument",
        "Listing not found or not live."
      );
    }
    linkType = "listing";
    listingId = input.listingId;
    data.listingId = listingId;
  } else if (input.linkType === "category") {
    assertDocId(input.categoryId, "categoryId");
    const snap = await db.collection("categories").doc(input.categoryId).get();
    if (!snap.exists) {
      throw new HttpsError("invalid-argument", "Category not found.");
    }
    linkType = "category";
    categoryId = input.categoryId;
    categoryName = (snap.data()?.name as string | undefined) ?? "Category";
    data.categoryId = categoryId;
    data.categoryName = categoryName;
  } else if (
    input.linkType != null &&
    input.linkType !== "" &&
    input.linkType !== "none"
  ) {
    throw new HttpsError(
      "invalid-argument",
      "linkType must be none, listing or category."
    );
  }
  if (imageUrl) data.imageUrl = imageUrl;

  // Reserve the history doc first so its id can ride in the tap payload.
  const campaignRef = db.collection("campaigns").doc();
  data.campaignId = campaignRef.id;

  // Fan-out: every distinct saved token, remembered against its owner so
  // dead tokens can be pruned from the right user doc afterwards.
  const usersSnap = await db.collection("users").get();
  const tokenOwner = new Map<string, string>();
  for (const doc of usersSnap.docs) {
    const tokens = (doc.data().fcmTokens as string[] | undefined) ?? [];
    for (const t of tokens) {
      if (!tokenOwner.has(t)) tokenOwner.set(t, doc.id);
    }
  }
  const tokens = [...tokenOwner.keys()];

  let sent = 0;
  let failed = 0;
  const deadByUser = new Map<string, string[]>();
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const res = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: { title, body },
      data,
      // Same high-importance channel as the transactional pushes; the
      // image renders in the tray on Android (foreground display is
      // handled in the app from data.imageUrl).
      android: {
        priority: "high",
        notification: {
          channelId: "trega_alerts",
          ...(imageUrl ? { imageUrl } : {}),
        },
      },
    });
    sent += res.successCount;
    failed += res.failureCount;
    res.responses.forEach((r, j) => {
      if (r.success) return;
      const code = (r.error as { code?: string } | undefined)?.code;
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        const uid = tokenOwner.get(chunk[j])!;
        const arr = deadByUser.get(uid) ?? [];
        arr.push(chunk[j]);
        deadByUser.set(uid, arr);
      }
    });
  }
  // Prune dead tokens, best-effort (mirrors marketplace sendPush).
  for (const [uid, dead] of deadByUser) {
    await db
      .collection("users")
      .doc(uid)
      .update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...dead),
      })
      .catch(() => undefined);
  }

  await campaignRef.set({
    title,
    body,
    imageUrl: imageUrl ?? null,
    linkType,
    listingId: listingId ?? null,
    categoryId: categoryId ?? null,
    categoryName: categoryName ?? null,
    recipients: tokens.length,
    sent,
    failed,
    createdBy: createdBy ?? null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { recipients: tokens.length, sent, failed };
}
