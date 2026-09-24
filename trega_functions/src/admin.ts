import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

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
 * caller when — and only when — their verified Firebase Auth phone number
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
 * - `users/{uid}/notifications`: tells the user what happened — this is
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
  if (!uid) throw new HttpsError("invalid-argument", "uid is required.");
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

  const cleanNote = note?.trim() || null;
  const batch = db.batch();
  batch.update(userRef, {
    kycStatus: status,
    verifiedSeller: status === "verified",
    kycNote: cleanNote ?? admin.firestore.FieldValue.delete(),
  });
  // Audit trail (merge — never clobbers an Aadhaar fingerprint if one exists).
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
  if (!orderId) throw new HttpsError("invalid-argument", "orderId is required.");
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
  if (trackingNote !== undefined) update.trackingNote = trackingNote.trim();
  if (Object.keys(update).length === 0) {
    throw new HttpsError("invalid-argument", "Nothing to update.");
  }
  await ref.update(update);
  return { status: (snap.data()?.status as string) ?? "placed" };
}
