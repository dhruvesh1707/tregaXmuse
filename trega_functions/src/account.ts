import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

/**
 * Deletes a user account and EVERY record tied to it, completely:
 *
 * Firestore —
 *   `users/{uid}` and ALL its subcollections (notifications inbox,
 *   private payout/addresses, wishlist, …),
 *   listings where `sellerId == uid` (+ their `private/details` doc),
 *   bids placed BY the user and bids placed ON the user's listings,
 *   orders where the user is buyer or seller,
 *   reviews written by or about the user,
 *   reports filed by the user,
 *   `kycVerifications/{uid}`,
 *   `aadhaarIndex` docs claimed by the uid (frees the Aadhaar number so it
 *   can verify a future account — only the one-way fingerprint is stored,
 *   never the number itself).
 * Storage — `avatars/{uid}.jpg`, `listingMedia/{listingId}/…` for the
 * user's listings.
 * Auth — the Firebase Auth user itself, deleted last.
 *
 * There is no undo. The app gates this behind an explicit confirmation
 * dialog with a checklist of what disappears.
 */
export async function deleteAccountHandler(
  uid: string
): Promise<{ deleted: boolean }> {
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const docRefs: FirebaseFirestore.DocumentReference[] = [];

  const collect = async (q: FirebaseFirestore.Query): Promise<void> => {
    const snap = await q.get();
    for (const d of snap.docs) docRefs.push(d.ref);
  };

  const userRef = db.collection("users").doc(uid);

  // 1. All subcollections under users/{uid} (notifications, private,
  //    wishlist, …) — enumerated generically so nothing is missed.
  const subcollections = await userRef.listCollections();
  for (const col of subcollections) {
    await collect(col);
  }

  // 2. The user's listings (+ their private details doc).
  const listingIds: string[] = [];
  const listingsSnap = await db
    .collection("listings")
    .where("sellerId", "==", uid)
    .get();
  for (const d of listingsSnap.docs) {
    listingIds.push(d.id);
    docRefs.push(d.ref);
    docRefs.push(d.ref.collection("private").doc("details"));
  }

  // 3. Bids on the user's listings + bids the user placed.
  for (const listingId of listingIds) {
    await collect(db.collection("bids").where("listingId", "==", listingId));
  }
  await collect(db.collection("bids").where("buyerId", "==", uid));

  // 4. Orders where the user is buyer or seller.
  await collect(db.collection("orders").where("buyerId", "==", uid));
  await collect(db.collection("orders").where("sellerId", "==", uid));

  // 5. Reviews written by or about the user.
  await collect(db.collection("reviews").where("reviewerId", "==", uid));
  await collect(db.collection("reviews").where("revieweeId", "==", uid));

  // 6. Reports filed by the user.
  await collect(db.collection("reports").where("reporterId", "==", uid));

  // 7. KYC record + Aadhaar fingerprint claims.
  docRefs.push(db.collection("kycVerifications").doc(uid));
  await collect(db.collection("aadhaarIndex").where("uid", "==", uid));

  // 8. The user doc itself, last among Firestore writes.
  docRefs.push(userRef);

  // De-dupe (a bid can match two queries above) and delete in chunks —
  // Firestore batches cap at 500 writes.
  const seen = new Set<string>();
  const unique = docRefs.filter((r) => {
    if (seen.has(r.path)) return false;
    seen.add(r.path);
    return true;
  });
  for (let i = 0; i < unique.length; i += 400) {
    const batch = db.batch();
    for (const r of unique.slice(i, i + 400)) batch.delete(r);
    await batch.commit();
  }

  // 9. Storage: avatar + all media of the user's listings. Missing files
  //    are fine (user may never have uploaded).
  const storageDeletes: Array<Promise<unknown>> = [
    bucket
      .file(`avatars/${uid}.jpg`)
      .delete()
      .catch(() => undefined),
  ];
  for (const listingId of listingIds) {
    const [files] = await bucket.getFiles({
      prefix: `listingMedia/${listingId}/`,
    });
    for (const f of files) {
      storageDeletes.push(f.delete().catch(() => undefined));
    }
  }
  await Promise.all(storageDeletes);

  // 10. The Auth user itself, deleted last so a failure above never
  //     orphans data under a gone account.
  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    logger.error("deleteAccount: auth deletion failed", { uid, e });
    throw new HttpsError(
      "internal",
      "Couldn't delete the sign-in account. Please try again."
    );
  }

  logger.info("deleteAccount completed", {
    uid,
    docsDeleted: unique.length,
    listingsDeleted: listingIds.length,
  });
  return { deleted: true };
}
