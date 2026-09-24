import * as admin from "firebase-admin";
import { createHash, createHmac } from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { BULKPE_API_TOKEN, BULKPE_BASE, KYC_SALT } from "./config";

export type KycStatus = "unverified" | "pending" | "verified" | "rejected";

interface BulkPeResponse {
  status: boolean;
  statusCode: number;
  message?: string;
  data?: {
    ref_id?: string;
    status?: string;
    // fields returned by verifyAadharOtp on VALID
    name?: string;
    dob?: string;
    gender?: string;
    care_of?: string;
    address?: string;
    year_of_birth?: string;
    mobile_hash?: string;
    split_address?: Record<string, string>;
  };
}

async function bulkpePost(
  path: string,
  payload: Record<string, unknown>
): Promise<BulkPeResponse> {
  const token = BULKPE_API_TOKEN.value();
  if (!token) {
    throw new HttpsError("failed-precondition", "KYC provider is not configured.");
  }
  const res = await fetch(`${BULKPE_BASE}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    // BulkPe usually returns a JSON {message} even on errors — surface it
    // instead of a generic failure so the app can tell the user what
    // actually happened (bad number, provider outage, bad token, ...).
    let detail = "";
    try {
      detail = (await res.text()).slice(0, 300);
    } catch {
      /* ignore */
    }
    logger.warn("BulkPe KYC provider error", { path, status: res.status, detail });
    let message = `KYC provider error (HTTP ${res.status}). Please try again.`;
    try {
      const parsed = JSON.parse(detail) as { message?: string };
      if (parsed?.message) message = parsed.message;
    } catch {
      /* keep default */
    }
    throw new HttpsError("unavailable", message);
  }
  return (await res.json()) as BulkPeResponse;
}

/** UIDAI-issued Aadhaar numbers are 12 digits and never start with 0 or 1. */
export function assertValidAadhaar(aadhaar: unknown): asserts aadhaar is string {
  if (typeof aadhaar !== "string" || !/^[2-9]\d{11}$/.test(aadhaar.trim())) {
    throw new HttpsError("invalid-argument", "Enter a valid 12-digit Aadhaar number.");
  }
}

const OTP_THROTTLE_MS = 60_000;

/**
 * Non-reversible fingerprint of an Aadhaar number, used ONLY to detect the
 * same Aadhaar being verified on two different Trega accounts. The number
 * itself is never stored anywhere.
 *
 * HMAC with the KYC_SALT secret when set; falls back to a domain-separated
 * plain hash (with a loud warning) so verification keeps working if the
 * secret was never configured — dedupe still works, hashes are just weaker
 * against offline brute force.
 */
export function aadhaarFingerprint(aadhaar: string): string {
  const digits = aadhaar.trim();
  const salt = KYC_SALT.value();
  if (!salt) {
    logger.warn(
      "KYC_SALT secret is not set; Aadhaar dedupe hashes are unsalted. " +
        "Run: firebase functions:secrets:set KYC_SALT"
    );
    return createHash("sha256").update(`trega-aadhaar:${digits}`).digest("hex");
  }
  return createHmac("sha256", salt).update(digits).digest("hex");
}

export async function requestAadhaarOtpHandler(
  uid: string,
  aadhaarNumber: string
): Promise<{ refId: string }> {
  assertValidAadhaar(aadhaarNumber);
  const db = admin.firestore();
  const kycRef = db.collection("kycVerifications").doc(uid);

  // Lightweight throttle: one OTP request per minute per user.
  const snap = await kycRef.get();
  const last = snap.data()?.requestedAt?.toMillis?.() as number | undefined;
  if (last && Date.now() - last < OTP_THROTTLE_MS) {
    throw new HttpsError(
      "resource-exhausted",
      "Please wait a minute before requesting another OTP."
    );
  }

  const out = await bulkpePost("/client/verifyAadhar", {
    aadhaar: aadhaarNumber.trim(),
  });
  const refId = out.data?.ref_id;
  if (!out.status || !refId) {
    throw new HttpsError(
      "failed-precondition",
      out.message || "Could not initiate Aadhaar verification."
    );
  }

  await kycRef.set(
    {
      refId,
      status: "otp_sent",
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      // The app gates the Aadhaar field behind an explicit consent
      // checkbox, so reaching this call means consent was given.
      consentAt: admin.firestore.FieldValue.serverTimestamp(),
      // Fingerprint (salted hash, never the number) so verify time can
      // reject the same Aadhaar on a second account.
      aadhaarFingerprint: aadhaarFingerprint(aadhaarNumber),
    },
    { merge: true }
  );
  await db
    .collection("users")
    .doc(uid)
    .set({ kycStatus: "pending" satisfies KycStatus }, { merge: true });

  // refId is an opaque provider reference, safe to return to the client.
  return { refId };
}

export async function verifyAadhaarOtpHandler(
  uid: string,
  refId: string,
  otp: string
): Promise<{ verified: boolean; name: string }> {
  if (typeof refId !== "string" || !refId) {
    throw new HttpsError("invalid-argument", "Missing verification reference.");
  }
  if (typeof otp !== "string" || !/^\d{4,8}$/.test(otp.trim())) {
    throw new HttpsError("invalid-argument", "Enter the OTP you received.");
  }

  const out = await bulkpePost("/client/verifyAadharOtp", {
    ref_id: refId,
    otp: otp.trim(),
  });

  const data = out.data;
  if (!out.status || data?.status !== "VALID") {
    await admin
      .firestore()
      .collection("kycVerifications")
      .doc(uid)
      .set(
        {
          status: "failed",
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    throw new HttpsError(
      "failed-precondition",
      "OTP verification failed. Check the code and try again."
    );
  }

  // ── Duplicate-KYC guard ──────────────────────────────────────────
  // The same Aadhaar must never verify two different Trega accounts.
  // The fingerprint was stored (salted hash, never the number) when the OTP
  // was requested. Claim it in a transaction so two simultaneous
  // verifications with the same Aadhaar can't both succeed; the loser gets
  // a clear "already verified on another account" error.
  // NOTE: the check runs at VERIFY time (not OTP-request time) so typing an
  // Aadhaar number alone can't be used to probe whether it's taken — you
  // need the OTP from the Aadhaar-linked mobile too.
  const db = admin.firestore();
  const kycRef = db.collection("kycVerifications").doc(uid);
  const pendingSnap = await kycRef.get();
  const fingerprint = pendingSnap.data()?.aadhaarFingerprint as string | undefined;
  if (!fingerprint) {
    // Legacy in-flight verification from before fingerprints existed.
    logger.warn("verifyAadhaarOtp: no aadhaarFingerprint on pending KYC doc", { uid });
  }

  // Store only what the app/admin need. Never persist photo_link / xml blobs.
  await db.runTransaction(async (tx) => {
    if (fingerprint) {
      const idxRef = db.collection("aadhaarIndex").doc(fingerprint);
      const idxSnap = await tx.get(idxRef);
      const ownerUid = idxSnap.data()?.uid as string | undefined;
      if (idxSnap.exists && ownerUid !== uid) {
        throw new HttpsError(
          "already-exists",
          "This Aadhaar number is already verified on another Trega account. " +
            "Each Aadhaar number can verify only one account."
        );
      }
      tx.set(
        idxRef,
        {
          uid,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    tx.set(
      kycRef,
      {
        status: "verified",
        refId,
        name: data?.name ?? null,
        dob: data?.dob ?? null,
        gender: data?.gender ?? null,
        careOf: data?.care_of ?? null,
        address: data?.address ?? null,
        yearOfBirth: data?.year_of_birth ?? null,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    tx.set(
      db.collection("users").doc(uid),
      {
        kycStatus: "verified" satisfies KycStatus,
        kycName: data?.name ?? null,
        kycDob: data?.dob ?? null,
      },
      { merge: true }
    );
  });

  return { verified: true, name: data?.name ?? "" };
}
