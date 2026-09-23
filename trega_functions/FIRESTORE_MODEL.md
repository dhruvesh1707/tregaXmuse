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
| status | string | `draft` → `pending` → `live` → `sold`, or `rejected` |
| rejectionReason | string? | set when rejected |
| acceptedBidId | string? | bids/{id} once seller accepts an offer |
| viewCount | number | |
| submittedAt / liveAt / soldAt | timestamp? | lifecycle markers |
| createdAt | timestamp | |

Write rule of thumb: clients create with `status: "draft"`; the
`onListingCreate` trigger moves it to `pending` and notifies admins.
Only `reviewListing` (admin claim) may set `live`/`rejected`.

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
`avatars/{uid}/{filename}` — profile pictures.

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
