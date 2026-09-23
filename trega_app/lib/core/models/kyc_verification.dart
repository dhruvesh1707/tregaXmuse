/// Status of an Aadhaar KYC attempt, stored in `kycVerifications/{uid}`.
///
/// Canonical values (`trega_functions/FIRESTORE_MODEL.md`):
/// `otp_sent` → `verified` | `failed`. When no document exists the user is
/// treated as unverified.
enum KycStatus {
  unverified,
  otpSent,
  verified,
  failed,
}

extension KycStatusWire on KycStatus {
  String get wireValue {
    switch (this) {
      case KycStatus.unverified:
        return 'unverified';
      case KycStatus.otpSent:
        return 'otp_sent';
      case KycStatus.verified:
        return 'verified';
      case KycStatus.failed:
        return 'failed';
    }
  }

  static KycStatus fromWire(String value) {
    return KycStatus.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => KycStatus.unverified,
    );
  }
}

/// Aadhaar verification record.
///
/// The Aadhaar number itself is NEVER stored — only the BulkPe `refId` and
/// the verified demographic fields returned after OTP validation. The actual
/// BulkPe calls happen in Cloud Functions (which hold the API token); the app
/// only invokes the `requestAadhaarOtp` / `verifyAadhaarOtp` callables via
/// [FunctionsService].
class KycVerification {
  final String uid;
  final KycStatus status;
  final String? refId;
  final String? name;
  final String? dob;
  final String? gender;
  final String? address;

  const KycVerification({
    required this.uid,
    this.status = KycStatus.unverified,
    this.refId,
    this.name,
    this.dob,
    this.gender,
    this.address,
  });

  static KycVerification fromFirestore(Map<String, dynamic> data, String uid) {
    return KycVerification(
      uid: uid,
      status: KycStatusWire.fromWire(data['status'] as String? ?? ''),
      refId: data['refId'] as String?,
      name: data['name'] as String?,
      dob: data['dob'] as String?,
      gender: data['gender'] as String?,
      address: data['address'] as String?,
    );
  }
}
