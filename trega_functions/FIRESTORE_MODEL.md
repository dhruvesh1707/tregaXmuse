# Trega Firestore Data Model

Project: `tregaxmuse`. Status enums use **lowercase** strings to match the
admin panel (`~/workspace/trega/trega_admin/`). There is **no chat** collection
by design — negotiation happens through structured bids/offers.

## Collections

### `users/{uid}` (uid = Firebase Auth uid)
| Field | Type | Notes |
|---|---|---|
| phone | string | E.164, from Firebase phone auth |
| name | string | display name |
| avatarUrl | string? | Storage URL |
| role | string | `buyer` \| `seller` \| `admin` |
| verifiedSeller | boolean | admin-verified seller badge (set by `setUserKycStatus`) |
| kycStatus | string | `unverified` \| `pending` \| `verified` \| `rejected` (server/admin-managed) |
| kycNote | string? | admin note set on manual verify/reject via `setUserKycStatus` (shown in the admin panel) |
| kycName | string? | from Aadhaar (on verified) |
| kycDob | string? | from Aadhaar (on verified) |
| createdAt | timestamp | |

### `users/{uid}/private/{docId}` — owner-only private data

| Field | Type | Notes |
|---|---|---|
| (payout doc) upiId | string | seller's payout UPI ID (`docId: 'payout'`) |
| (address doc) kind | string | always `'address'` (`docId: 'address_<pushId>'`) |
| (address doc) label | string | optional label, e.g. "Home" |
| (address doc) line1/line2/city/state/pincode | string | structured pickup address |
| (address doc) createdAt | string | ISO-8601 |

Rules: only the owning user (and admins) may read; only the owner may
write. Buyers never see this — pickup addresses are copied per-listing into
`listings/{id}/private/details` (which also snapshots the `payoutUpi` used
at publish time, so payouts stay correct even if the seller changes it
later). The sell flow auto-saves new pickup addresses here (deduped) and
prefills the payout UPI field from the saved value; Profile → Settings
manages both.

### `categories/{id}`
| Field | Type | Notes |
|---|---|---|
| name | string | e.g. "Gaming" |
| slug | string | e.g. "gaming" |
| icon | string? | icon name / URL |
| active | boolean | |
| sortOrder | number | |

Seed: Gaming, Mobile, Laptops, Cameras, Music, Others.

### `listings/{id}`
| Field | Type | Notes |
|---|---|---|
| sellerId | string | users/{uid} |
| title | string | |
| description | string | |
| categoryId | string | categories/{id} |
| price | number | INR |
| condition | string | `brand_new` \| `like_new` \| `good` \| `fair` |
| photos | string[] | Storage URLs |
| videoUrl | string? | Storage URL (video-verified listing) |
| status | string | `draft` → `live` → `sold`, or `rejected` (`pending` kept for legacy docs) |
| rejectionReason | string? | set when flagged/rejected |
| acceptedBidId | string? | bids/{id} once seller accepts an offer |
| viewCount | number | |
| liveAt / soldAt | timestamp? | lifecycle markers |
| createdAt | timestamp | |

Write rule of thumb: clients create with `status: "draft"`; the
`onListingCreate` trigger flips it to `live` immediately and notifies
admins (reactive moderation — the team reviews new listings and flags
suspicious ones after the fact). `reviewListing` (admin claim) may set
`live`/`rejected` from `live` or legacy `pending`.

### `listings/{id}/private/details` (owner-only)

Never on the public listing doc. Readable only by the seller and admins
(see `firestore.rules`).

| Field | Type | Notes |
|---|---|---|
| pickupAddress | map | `line1`, `line2` (optional landmark), `city`, `state`, `pincode` |
| updatedAt | timestamp | |

### `bids/{id}`
| Field | Type | Notes |
|---|---|---|
| listingId | string | |
| buyerId | string | |
| sellerId | string | |
| amount | number | INR |
| status | string | `open` \| `accepted` \| `rejected` \| `expired` \| `countered` — a `rejected` buyer may send a new offer (only one `open` offer per buyer+listing) |
| counterAmount | number? | seller counter-offer |
| createdAt / acceptedAt | timestamp? | |

### `orders/{id}`
| Field | Type | Notes |
|---|---|---|
| listingId | string | |
| bidId | string? | set when the order came from an accepted bid |
| buyerId / sellerId | string | |
| amount | number | INR — always set server-side |
| currency | string | `INR` |
| paymentStatus | string | `PENDING` \| `SUCCESS` \| `FAILED` \| `USER_DROPPED` |
| status | string | `placed` → `pickup_scheduled` → `picked_up` → `in_transit` → `delivered`, plus `cancelled`, `returned` |
| cfOrderId | number? | Cashfree order id |
| cfOrderRef | string? | our `trega_<orderId>` reference |
| paymentSessionId | string? | for the Cashfree SDK |
| deliveryAddress | map? | buyer delivery address from checkout: `name`, `phone`, `line1`, `line2?`, `city`, `state`, `pincode` (required when the order came from an accepted bid) |
| trackingNote | string? | latest fulfillment note |
| paidAt | timestamp? | |
| createdAt | timestamp | |

### `kycVerifications/{uid}`
| Field | Type | Notes |
|---|---|---|
| refId | string? | BulkPe reference (opaque, safe) |
| status | string | `otp_sent` \| `verified` \| `failed` |
| name / dob / gender / careOf | string? | from Aadhaar on VALID |
| address / yearOfBirth | string? | from Aadhaar on VALID |
| requestedAt / verifiedAt / failedAt | timestamp? | |
| consentAt | timestamp? | set on OTP request — the app gates the Aadhaar field behind an explicit consent checkbox, so requesting the OTP means consent was given |
| aadhaarFingerprint | string? | salted HMAC-SHA256 of the Aadhaar (never the number); used for the duplicate-KYC check |
| method | string? | `manual` when verified/rejected by an admin via `setUserKycStatus` (absent for Aadhaar flow) |
| verifiedBy | string? | admin uid who manually verified/rejected |
| reviewedAt | timestamp? | when the admin manually verified/rejected |
| note | string? | admin's note on manual verify/reject |

Client reads: owner-only, plus admins (the admin panel shows how each
user was verified).

### `aadhaarIndex/{fingerprint}`
Duplicate-KYC guard. Doc ID is the salted fingerprint of an Aadhaar number; the number itself is never stored anywhere.

| Field | Type | Notes |
|---|---|---|
| uid | string | the account that verified this Aadhaar |
| verifiedAt | timestamp | |

`verifyAadhaarOtp` claims the fingerprint in a transaction: if the doc already exists under a **different** uid, verification is rejected with `already-exists` ("already verified on another Trega account"). The check runs at verify time (not OTP-request time) so a bare Aadhaar number can't be used to probe whether it's taken. Client access is fully denied in `firestore.rules` — only the callable (Admin SDK) touches it. Same uid re-verifying is idempotent and allowed.

Never store `photo_link` / XML blobs here.

### `adminNotifications/{id}`
| Field | Type | Notes |
|---|---|---|
| type | string | `listing_review`, … |
| listingId | string? | |
| title / message | string | |
| read | boolean | |
| createdAt | timestamp | |

### `users/{uid}/notifications/{id}` (server-written inbox)

| Field | Type | Notes |
|---|---|---|
| title / body | string | |
| type | string | `bid_received` \| `outbid` \| `bid_accepted` \| `bid_rejected` \| `listing_flagged` \| `kyc_verified` \| `kyc_rejected` \| `order_update` \| legacy `bid`/`order`/`listing` |
| read | boolean | clients may only flip this (see `firestore.rules`) |
| createdAt | timestamp | |

Writers (all in `trega_functions/src/marketplace.ts`):
- `onBidCreate` trigger → `bid_received` to the seller; `outbid` to the
  previous highest bidder when beaten.
- `acceptBid` callable → `bid_accepted` to the winner ("pay within 24h");
  `bid_rejected` to the auto-rejected losers.
- `reviewListing` callable → `listing_flagged` to the seller on takedown.

Writers (in `trega_functions/src/admin.ts`):
- `setUserKycStatus` callable → `kyc_verified` / `kyc_rejected` to the user
  when the admin manually verifies or rejects their KYC.

### `reports/{listingId}_{reporterId}` (user-submitted, reactive moderation)

| Field | Type | Notes |
|---|---|---|
| listingId | string | |
| reporterId | string | users/{uid} — must equal the writer's uid |
| reason | string | fixed set: Spam or misleading / Fraud or scam / Inappropriate content / Wrong category |
| createdAt | timestamp | |

Doc ID guarantees one report per user per listing. Clients may only
create; reads are admin-only (`firestore.rules`).

### `reviews/{id}`
| Field | Type | Notes |
|---|---|---|
| orderId / listingId | string | |
| reviewerId / revieweeId | string | |
| rating | number | 1–5 |
| comment | string? | |
| createdAt | timestamp | |

## Cloud Functions callables (region `asia-south1`)

Offer / checkout flow (`trega_functions/src/marketplace.ts`, `payments.ts`):

- `placeBid({listingId, amount})` — guards: listing must be `live`; buyer
  must be Aadhaar-verified (`users/{uid}.kycStatus == "verified"`); buyer must
  not be the seller; at most **one open offer per buyer per listing** (a
  rejected buyer may offer again). Writes the bid (`status: open`) and bumps
  `highestBid`/`bidCount` when appropriate.
- `acceptBid({bidId})` — seller only; the listing must be `live` and have no
  `acceptedBidId` yet (accepting is exclusive). Marks the bid `accepted`,
  sets `listings/{id}.acceptedBidId` (reserves the listing for the winner
  until they pay), rejects the other open bids. The winner's listing page
  then shows the single "Buy Now at ₹X" button → checkout.
- `rejectBid({bidId})` — seller only; bid must be `open`. Marks it
  `rejected`; the buyer is notified and may send a new offer.
- `cancelAcceptance({bidId})` — seller only; bid must be `accepted` and the
  listing still `live`. Marks the bid `rejected`, clears
  `listings/{id}.acceptedBidId`, notifies the buyer; the listing is open for
  offers again (used when the winner never pays).
- `createCashfreeOrder({listingId?, bidId?, customerPhone, deliveryAddress?})`
  — `deliveryAddress` is required when `bidId` is set (accepted-offer
  checkout), validated server-side and stored on the order; the `bidId` path
  charges exactly the accepted bid amount.

KYC (`kyc.ts`): `requestAadhaarOtp` / `verifyAadhaarOtp` — provider errors
are surfaced with their real message (invalid Aadhaar, throttled, provider
outage) instead of a generic failure.

Admin (`trega_functions/src/admin.ts`, `admin` custom claim required):

- `bootstrapAdmin()` — one-shot self-service bootstrap. Grants
  `{admin: true}` to the caller **only** when their verified phone number
  matches the `ADMIN_BOOTSTRAP_PHONE` secret (E.164). After it returns, the
  client refreshes its ID token. The admin panel's login flow exposes this
  as "Claim admin access" on the access-denied screen.
- `setUserKycStatus({uid, status: "verified" | "rejected", note?})` —
  manual KYC verification from the admin panel's Users page. Sets
  `users/{uid}` (`kycStatus`, `verifiedSeller`, `kycNote`), merges a
  `kycVerifications/{uid}` audit record (`method: "manual"`, `verifiedBy`,
  `reviewedAt`, note), and notifies the user (`kyc_verified` /
  `kyc_rejected`). A manually-verified user passes the same gates as an
  Aadhaar-verified one (selling, making offers) because both read
  `users/{uid}.kycStatus`.
- `updateOrderFulfillment({orderId, status?, trackingNote?})` — advances
  order fulfillment from the admin panel's Orders page. Payment status is
  owned by the Cashfree webhook and cannot be set here.

## Storage
`listingMedia/{listingId}/{filename}` — listing photos and videos.
`avatars/{uid}.jpg` — profile pictures.

## Composite indexes (`firestore.indexes.json`, deployed with `firebase deploy`)

- `listings`: `status` ASC + `createdAt` DESC (feed)
- `listings`: `status` ASC + `categoryId` ASC + `createdAt` DESC (category feed)
- `listings`: `sellerId` ASC + `createdAt` DESC (my listings)
- `bids`: `listingId` ASC + `createdAt` DESC (bids on a listing)
- `bids`: `buyerId` ASC + `createdAt` DESC (my bids)
- `bids`: `buyerId` ASC + `listingId` ASC (my offers on one listing — the listing detail action bar)
- `bids`: `sellerId` ASC + `createdAt` DESC (offers received)
- `orders`: `buyerId` ASC + `createdAt` DESC (my purchases)
- `orders`: `sellerId` ASC + `createdAt` DESC (my sales)
- `categories`: `active` ASC + `sortOrder` ASC
