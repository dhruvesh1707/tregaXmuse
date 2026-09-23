# Trega Cloud Functions — `tregaxmuse`

TypeScript (Node 20) Cloud Functions backend for the Trega marketplace.
Replaces the earlier Node/Express scaffold; the Flutter app talks to these
callables + Firestore directly. Region: `asia-south1`.

## Functions

| Function | Type | Auth | What it does |
|---|---|---|---|
| `requestAadhaarOtp` | callable | user | Validates 12-digit Aadhaar → BulkPe `verifyAadhar` → returns `{refId}` |
| `verifyAadhaarOtp` | callable | user | BulkPe `verifyAadharOtp` → on VALID writes `kycVerifications/{uid}` + `users/{uid}.kycStatus=verified` |
| `createCashfreeOrder` | callable | user | Server-side amount from Firestore → Cashfree order → returns `{paymentSessionId, orderId, cfOrderId}`; creates `orders/{id}` PENDING |
| `cashfreeWebhook` | https | signature | Verifies HMAC-SHA256 signature → SUCCESS marks order paid + listing `sold` |
| `onListingCreate` | firestore trigger | — | New listing → `pending` + `adminNotifications` entry |
| `reviewListing` | callable | admin claim | `approve` → `live`, `reject` (reason required) → `rejected` |
| `setUserKycStatus` | callable | admin claim | `{uid, status: verified\|rejected, note?}` → updates `users/{uid}.kycStatus` + `verifiedSeller` badge |
| `updateOrderFulfillment` | callable | admin claim | `{orderId, status?, trackingNote?}` → fulfillment updates (payment status stays owned by the Cashfree webhook) |
| `placeBid` | callable | user | Structured offer on a live listing (no chat) |
| `acceptBid` | callable | seller | Accepts one bid, auto-rejects competing open bids |

## Secrets

Set these with the Firebase CLI (values never go in the repo):

```bash
cd ~/workspace/trega/trega_functions

# Cashfree PG — from the Cashfree dashboard (use sandbox keys first)
firebase functions:secrets:set CASHFREE_APP_ID
firebase functions:secrets:set CASHFREE_SECRET_KEY
# "sandbox" or "production"
firebase functions:secrets:set CASHFREE_ENV

# BulkPe Aadhaar OKYC token — from the BulkPe dashboard
firebase functions:secrets:set BULKPE_API_TOKEN
```

> **BulkPe + Secure Vault note:** the BulkPe API credential is also connected
> in this workspace's Secure Vault (`custom.bulkpe`) and is used by the
> agent-side skill at `~/workspace/skills/bulkpe/` (`bin/bulkpe_aadhaar.py
> request-otp/verify-otp`) for testing the KYC flow without deploying.
> Deployed Cloud Functions run on Google's infrastructure and cannot reach
> the agent's Secure Vault, so production still needs `BULKPE_API_TOKEN`
> set as a Firebase secret as above.

## Deploy

```bash
npm install
npm run build
firebase deploy --only functions
# or emulators:
npm run serve
```

Prerequisite: `firebase use tregaxmuse` (or `firebase use --add`) in this
directory so deploys target the right project.

## Cashfree webhook registration

After deploy, register this URL in the Cashfree dashboard
(Developers → Webhooks), for both sandbox and production:

```
https://asia-south1-tregaxmuse.cloudfunctions.net/cashfreeWebhook
```

The function verifies the `x-webhook-signature` header
(base64 HMAC-SHA256 of the raw body with your secret key) and ignores
anything that fails verification.

## Admin access

`reviewListing` requires the Firebase Auth custom claim `{admin: true}`:

```bash
# needs a service-account JSON from
# Firebase Console > Project settings > Service accounts
GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json \
  node scripts/setAdminClaim.js <uid>
# revoke with: node scripts/setAdminClaim.js <uid> --revoke
```

The user must sign in again after the claim changes.

## Flutter wiring

```dart
final res = await FirebaseFunctions.instance
    .httpsCallable('requestAadhaarOtp')
    .call({'aadhaarNumber': '234567890123'});
final refId = res.data['refId'];
```

Set the region in Flutter: `FirebaseFunctions.instanceFor(region: 'asia-south1')`.

## Security rules (to apply in Firestore)

Tighten these before production; the functions use the Admin SDK and
bypass rules, so clients should get least privilege:

- `users/{uid}`: read all, write own doc except `kycStatus`, `role`
- `listings`: read `live` only; create own with `status == 'draft'`; update own draft only
- `bids`: buyer reads own, seller reads bids on own listings; create via `placeBid` only
- `orders`: buyer/seller read own; no client writes
- `kycVerifications/{uid}`: read/write own only (functions write verified state)
- `adminNotifications`: admin read only

## Data model

See [FIRESTORE_MODEL.md](sandbox://workspace/trega/trega_functions/FIRESTORE_MODEL.md).
