/**
 * Grants the Firebase Auth `admin` custom claim to a user so they can call
 * reviewListing and use the Trega admin panel.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json \
 *     node scripts/setAdminClaim.js <uid> [--revoke]
 *
 * Get the service account JSON from:
 *   Firebase Console > Project settings > Service accounts > Generate new private key
 * Never commit this file.
 */
const admin = require("firebase-admin");

async function main() {
  const uid = process.argv[2];
  const revoke = process.argv.includes("--revoke");
  if (!uid) {
    console.error("Usage: node scripts/setAdminClaim.js <uid> [--revoke]");
    process.exit(1);
  }
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
  await admin.auth().setCustomUserClaims(uid, revoke ? {} : { admin: true });
  // Mirror the role in Firestore for easy querying in the admin panel.
  await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .set({ role: revoke ? "seller" : "admin" }, { merge: true });
  console.log(`${revoke ? "Revoked admin from" : "Granted admin to"} ${uid}`);
  try {
    // Force token refresh on next sign-in by revoking refresh tokens.
    await admin.auth().revokeRefreshTokens(uid);
    console.log("Refresh tokens revoked — user must sign in again.");
  } catch (e) {
    console.warn("Could not revoke refresh tokens:", e.message);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
