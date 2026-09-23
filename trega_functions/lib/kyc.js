"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.assertValidAadhaar = assertValidAadhaar;
exports.requestAadhaarOtpHandler = requestAadhaarOtpHandler;
exports.verifyAadhaarOtpHandler = verifyAadhaarOtpHandler;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const config_1 = require("./config");
async function bulkpePost(path, payload) {
    const token = config_1.BULKPE_API_TOKEN.value();
    if (!token) {
        throw new https_1.HttpsError("failed-precondition", "KYC provider is not configured.");
    }
    const res = await fetch(`${config_1.BULKPE_BASE}${path}`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(payload),
    });
    if (!res.ok) {
        throw new https_1.HttpsError("unavailable", `KYC provider error (HTTP ${res.status}). Please try again.`);
    }
    return (await res.json());
}
/** UIDAI-issued Aadhaar numbers are 12 digits and never start with 0 or 1. */
function assertValidAadhaar(aadhaar) {
    if (typeof aadhaar !== "string" || !/^[2-9]\d{11}$/.test(aadhaar.trim())) {
        throw new https_1.HttpsError("invalid-argument", "Enter a valid 12-digit Aadhaar number.");
    }
}
const OTP_THROTTLE_MS = 60_000;
async function requestAadhaarOtpHandler(uid, aadhaarNumber) {
    assertValidAadhaar(aadhaarNumber);
    const db = admin.firestore();
    const kycRef = db.collection("kycVerifications").doc(uid);
    // Lightweight throttle: one OTP request per minute per user.
    const snap = await kycRef.get();
    const last = snap.data()?.requestedAt?.toMillis?.();
    if (last && Date.now() - last < OTP_THROTTLE_MS) {
        throw new https_1.HttpsError("resource-exhausted", "Please wait a minute before requesting another OTP.");
    }
    const out = await bulkpePost("/client/verifyAadhar", {
        aadhaar: aadhaarNumber.trim(),
    });
    const refId = out.data?.ref_id;
    if (!out.status || !refId) {
        throw new https_1.HttpsError("failed-precondition", out.message || "Could not initiate Aadhaar verification.");
    }
    await kycRef.set({
        refId,
        status: "otp_sent",
        requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await db
        .collection("users")
        .doc(uid)
        .set({ kycStatus: "pending" }, { merge: true });
    // refId is an opaque provider reference, safe to return to the client.
    return { refId };
}
async function verifyAadhaarOtpHandler(uid, refId, otp) {
    if (typeof refId !== "string" || !refId) {
        throw new https_1.HttpsError("invalid-argument", "Missing verification reference.");
    }
    if (typeof otp !== "string" || !/^\d{4,8}$/.test(otp.trim())) {
        throw new https_1.HttpsError("invalid-argument", "Enter the OTP you received.");
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
            .set({
            status: "failed",
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        throw new https_1.HttpsError("failed-precondition", "OTP verification failed. Check the code and try again.");
    }
    // Store only what the app/admin need. Never persist photo_link / xml blobs.
    const db = admin.firestore();
    const batch = db.batch();
    const kycRef = db.collection("kycVerifications").doc(uid);
    batch.set(kycRef, {
        status: "verified",
        refId,
        name: data?.name ?? null,
        dob: data?.dob ?? null,
        gender: data?.gender ?? null,
        careOf: data?.care_of ?? null,
        address: data?.address ?? null,
        yearOfBirth: data?.year_of_birth ?? null,
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    batch.set(db.collection("users").doc(uid), {
        kycStatus: "verified",
        kycName: data?.name ?? null,
        kycDob: data?.dob ?? null,
    }, { merge: true });
    await batch.commit();
    return { verified: true, name: data?.name ?? "" };
}
//# sourceMappingURL=kyc.js.map