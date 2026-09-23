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
| kycNote | string? | admin note set when KYC is rejected via `setUserKycStatus` |
| kycName | string? | from Aadhaar (on verified) |
| kycDob | string? | from Aadhaar (on verified) |
| createdAt | timestamp | |

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
| status | string | `open` \| `accepted` \| `rejected` \| `expired` \| `countered` |
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
| type | string | `bid_received` \| `outbid` \| `bid_accepted` \| `bid_rejected` \| `listing_flagged` \| `order_update` \| legacy `bid`/`order`/`listing` |
| read | boolean | clients may only flip this (see `firestore.rules`) |
| createdAt | timestamp | |

Writers (all in `trega_functions/src/marketplace.ts`):
- `onBidCreate` trigger → `bid_received` to the seller; `outbid` to the
  previous highest bidder when beaten.
- `acceptBid` callable → `bid_accepted` to the winner ("pay within 24h");
  `bid_rejected` to the auto-rejected losers.
- `reviewListing` callable → `listing_flagged` to the seller on takedown.

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

## Storage
`listingMedia/{listingId}/{filename}` — listing photos and videos.
`avatars/{uid}.jpg` — profile pictures.

## Composite indexes (`firestore.indexes.json`, deployed with `firebase deploy`)

- `listings`: `status` ASC + `createdAt` DESC (feed)
- `listings`: `status` ASC + `categoryId` ASC + `createdAt` DESC (category feed)
- `listings`: `sellerId` ASC + `createdAt` DESC (my listings)
- `bids`: `listingId` ASC + `createdAt` DESC (bids on a listing)
- `bids`: `buyerId` ASC + `createdAt` DESC (my bids)
- `bids`: `sellerId` ASC + `createdAt` DESC (offers received)
- `orders`: `buyerId` ASC + `createdAt` DESC (my purchases)
- `orders`: `sellerId` ASC + `createdAt` DESC (my sales)
- `categories`: `active` ASC + `sortOrder` ASC
