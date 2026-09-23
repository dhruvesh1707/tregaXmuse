import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * Admin-only operations for the Trega admin panel.
 *
 * The Firestore rules intentionally block clients from writing server-managed
 * fields (kycStatus, order status, …), so the admin panel performs these
 * privileged mutations through callables guarded by the `admin` custom claim.
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

/** Admin-only: mark a user's KYC as verified (badges them as a verified
 * seller) or rejected with an optional note. */
export async function setUserKycStatusHandler(
  isAdmin: boolean,
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

  const ref = admin.firestore().collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "User not found.");

  await ref.update({
    kycStatus: status,
    verifiedSeller: status === "verified",
    kycNote: note?.trim() || admin.firestore.FieldValue.delete(),
  });
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
