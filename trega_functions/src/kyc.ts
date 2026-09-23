import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { BULKPE_API_TOKEN, BULKPE_BASE } from "./config";

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
    throw new HttpsError(
      "unavailable",
      `KYC provider error (HTTP ${res.status}). Please try again.`
    );
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

  // Store only what the app/admin need. Never persist photo_link / xml blobs.
  const db = admin.firestore();
  const batch = db.batch();
  const kycRef = db.collection("kycVerifications").doc(uid);
  batch.set(
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
  batch.set(
    db.collection("users").doc(uid),
    {
      kycStatus: "verified" satisfies KycStatus,
      kycName: data?.name ?? null,
      kycDob: data?.dob ?? null,
    },
    { merge: true }
  );
  await batch.commit();

  return { verified: true, name: data?.name ?? "" };
}
