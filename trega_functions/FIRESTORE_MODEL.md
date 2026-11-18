# Trega Firestore Data Model

Project: `tregaxmuse`. Status enums use **lowercase** strings to match the
admin panel (`~/workspace/trega/trega_admin/`). There is **no chat** collection
by design, negotiation happens through structured bids/offers.

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

### `users/{uid}/private/{docId}`, owner-only private data

| Field | Type | Notes |
|---|---|---|
| (payout doc) upiId | string | seller's payout UPI ID (`docId: 'payout'`) |
| (address doc) kind | string | always `'address'` (`docId: 'address_<pushId>'`) |
| (address doc) label | string | optional label, e.g. "Home" |
| (address doc) line1/line2/city/state/pincode | string | structured pickup address |
| (address doc) createdAt | string | ISO-8601 |

Rules: only the owning user (and admins) may read; only the owner may
write. Buyers never see this, pickup addresses are copied per-listing into
`listings/{id}/private/details` (which also snapshots the `payoutUpi` used
at publish time, so payouts stay correct even if the seller changes it
later). The sell flow auto-saves new pickup addresses here (deduped) and
prefills the payout UPI field from the saved value; Profile → Settings
manages both. Checkout reuses the same collection for the buyer's delivery
address (one-tap picker + auto-save on order creation, deduped), manual
entry always stays available on both flows.

Client-only notes (no schema change, 2026-10-24): the sell flow keeps a
local draft in SharedPreferences (`sell_draft_v1`: step, category,
fields, payout UPI, camera photo paths that still exist) and restores it
when the seller returns; it is cleared on publish or discard. PIN →
city/state autofill uses the free India Post API
(`api.postalpincode.in/pincode/<pin>`, no key) on both sell and checkout
forms; a failed lookup leaves both fields manually editable. Offer cards
show counterparty names by reading the public `users/{uid}` profile
client-side (bid docs carry ids only); the listing seller card shows
`avatarUrl` when set.

### `categories/{id}`
| Field | Type | Notes |
|---|---|---|
| name | string | e.g. "Gaming" |
| slug | string | e.g. "gaming" |
| icon | string? | icon name / URL |
| active | boolean | |
| sortOrder | number | |

Seed: Gaming, Mobiles, Laptops, Cameras, Music, Fashion, Furniture, Home Appliances, Cycles, Watches, Collectibles, Books, Others.

### `config/app`

Single doc. Public read, console-only write (see `firestore.rules`).
Strict force-update gate, one minimum build number per platform. No
Cloud Function is involved, and no rules change is needed, the existing
public `config/{docId}` read already covers this doc (only
`config/rateLimits` is excluded from it). The app's bundled default is
unenforced.

| Field | Type | Notes |
|---|---|---|
| minAndroidBuild | number | integer, minimum Android build number, `0` or absent means unenforced |
| minIosBuild | number | integer, minimum iOS build number, `0` or absent means unenforced |

Enforcement is per platform. At launch (splash flow) the app reads this
doc and compares the installed build number (integer, from
`package_info_plus`) against the minimum for its platform. An installed
build below the minimum is blocked on a non-dismissible update-required
screen. Version names are never compared, build numbers only. An absent
doc, an absent field, or `0` means unenforced for that platform.

Fail open: a fetch error, timeout, unparseable build number, or missing
doc or field means the app proceeds normally and re-checks on the next
launch. A transient failure never locks users out.

**Operational rule:** raise a minimum ONLY after the target build is
live where users get it, the Play Store for Android, the sideload
distribution channel for iOS. Raising it earlier leaves users on a
dead-end update screen with no newer build to install. Only builds
containing the check can be forced, so enforcement bites from the
release AFTER the one that ships the check.

Update targets: Android opens
`https://play.google.com/store/apps/details?id=com.trega.trega`. iOS has
no store link, the app is sideloaded with no App Store entry, so the
iOS screen is message-only plus a re-check.

### `config/delivery`

Single doc. Public read, console-only write (see `firestore.rules`).
Overrides the app's bundled Trega Express defaults, add a city here and
the app picks it up without a release.

| Field | Type | Notes |
|---|---|---|
| enabled | bool | master kill-switch |
| expressCities | string[] | city names, e.g. `["Mumbai", "Bengaluru"]` (matched case-insensitively) |
| cutoffHour | number | 24h local hour; order before → delivery tomorrow, after → day after tomorrow |

### `config/fees`

Single doc. Public read, console-only write (see `firestore.rules`).
The single source of truth for marketplace pricing, the server
(`createCashfreeOrder`) recomputes every fee from this; the app mirrors it
for display only via `FeeConfig`.

| Field | Type | Notes |
|---|---|---|
| promoActive | bool | `true` during the Zero Fee Launch, marketing flag for banners |
| sellerPct | number | seller commission %, `0` launch month, `3` standard |
| buyerPct | number | buyer protection fee %, `0` launch month, `5` standard |
| deliveryFlat | number | fixed delivery fee in INR, `99`, split 50-50 buyer/seller |
| gstPct | number | GST % on the platform fees, `18` |

Launch month: `promoActive: true, sellerPct: 0, buyerPct: 0`, only the
fixed delivery fee is charged. Month 2: flip to `sellerPct: 3`,
`buyerPct: 5` (keep `promoActive: false`) from the console, no app
update, no function deploy. TDS u/s 194O (1% of the gross sale amount)
always applies on the seller side regardless of these values.

### `config/rateLimits`

Single doc. **Server-only** (clients cannot read it, excluded from the
public `config/{docId}` read in `firestore.rules`; functions read it via
the Admin SDK). Live-overridable rate-limit thresholds per tier; any
missing/invalid tier falls back to the bundled defaults in
`trega_functions/src/rateLimit.ts`.

| Field | Type | Notes |
|---|---|---|
| `<tier>` | map | `{ limit, windowSec, blockBaseSec, blockMaxSec }` per tier |

Tiers: `kycOtp` (5/hr per account+IP), `kycVerify` (10/10min),
`bootstrap` (5/hr), `webhook` (120/hr per IP), `adminOps` (120/hr),
`bids` (60/hr), `payments` (30/hr), `deleteAccount` (3/day),
`views` (300/hr), `listingDelete` (10/hr), `shipmentRetry` (20/hr),
`disputes` (10/hr), `parcelInfo` (20/hr).
Exceeding a limit blocks with exponential backoff
(`blockBaseSec * 2^(violations-1)`, capped at `blockMaxSec`); a clean
window resets the violation count, so backoff never becomes a lockout.

### `rateLimits/{tier:uid:uid | tier:ip:ip}`

Server-side rate-limit counters. Functions-only (`allow read, write: if
false` for clients).

| Field | Type | Notes |
|---|---|---|
| count | number | requests in the current window |
| windowStart | number | window start (ms epoch) |
| violations | number | consecutive over-limit hits (drives backoff) |
| blockedUntil | number | ms epoch until which requests are rejected |

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
| status | string | `draft` → `live` → `sold` → `archived` (48h after payment), or `rejected` (`pending` kept for legacy docs) |
| rejectionReason | string? | set when flagged/rejected |
| acceptedBidId | string? | bids/{id} once seller accepts an offer |
| soldTo | string? | buyer uid, set when payment succeeds; gates who may still read the listing after it archives |
| viewCount | number | IG-style counter: incremented ONLY by the `recordListingView` callable (3s detail-screen dwell, seller self-views never count, 1h per-viewer cooldown). Clients cannot write it (see `firestore.rules`). |
| liveAt / soldAt | timestamp? | lifecycle markers; `soldAt` starts the 48h clock to `archived` |
| createdAt | timestamp | |
| city | string | denormalized from the seller's pickup address at publish time; drives Trega Express eligibility |
| weightKg | number? | packed parcel weight in kg, legacy: captured in the sell flow only by the build that shipped parcel capture; the sell flow no longer asks, new listings carry no parcel fields, and the shipment backend reads the order's parcel fields first |
| lengthCm / breadthCm / heightCm | number? | packed box dimensions in cm, same legacy capture; caps 0.1 to 50 kg and 1 to 200 cm per side, enforced by the after-sale parcel prompt and clamped server-side |

Write rule of thumb: clients create with `status: "draft"`; the
`onListingCreate` trigger flips it to `live` immediately and notifies
admins (reactive moderation, the team reviews new listings and flags
suspicious ones after the fact). `reviewListing` (admin claim) may set
`live`/`rejected` from `live` or legacy `pending`. Payment flips a
listing to `sold` (`applyPaymentSuccess`, shared by the webhook and
`verifyPayment`); the hourly `archiveSoldListings` schedule flips `sold`
listings older than 48h to `archived`, after which single-doc reads are
restricted to the seller, the buyer (`soldTo`) and admins
(`firestore.rules`: `allow get` conditional, `allow list` open, since
rules are not filters and the app's queries already exclude non-live
listings). Neither `sold` nor `archived` listings can be deleted
(callables and rules enforce this, an order references them).

### `listingViews/{listingId}_{viewerUid}`

Per-viewer state for the IG-style view counter. Server-only (`allow read,
write: if false` for clients; written by `recordListingView` via Admin SDK).

| Field | Type | Notes |
|---|---|---|
| listingId | string | listings/{id} |
| viewerId | string | users/{uid} |
| lastViewedAt | timestamp | last counted view; drives the 1h per-viewer cooldown |
| views | number | counted views by this viewer (diagnostic) |

View-counting rules (mirrors how Instagram counts reel views):
- A view counts only after the detail screen has been **continuously
  visible for 3 seconds** (IG's video-view threshold), never on screen open.
- The **seller's own views never count** (IG counts self-views; we
  deliberately don't, sellers could otherwise inflate their listings).
- **Replays count** like IG, but a **1-hour per-viewer-per-listing cooldown**
  stops open → back → open tap-spam.
- The increment is **atomic** (transaction) and **server-side**; the old
  client-side `FieldValue.increment` path is removed.

### `listings/{id}/private/details` (owner-only)

Never on the public listing doc. Readable only by the seller and admins
(see `firestore.rules`).

| Field | Type | Notes |
|---|---|---|
| pickupAddress | map | `line1`, `line2` (optional landmark), `city`, `state`, `pincode` |
| updatedAt | timestamp | |

### `shiprocketPickups/{sellerUid}`

Versioned Shiprocket pickup locations, one record per seller.
Shiprocket has no API to edit a pickup location's address, so each
address change mints a new versioned nickname. Written only via the
Admin SDK (`ensurePickupLocation` in `shiprocket.ts`); no client rule
exists, so clients can neither read nor write it.

| Field | Type | Notes |
|---|---|---|
| nickname | string | current Shiprocket `pickup_location`: `TREGA-<uid>` (v1), then `TREGA-<uid>-v2`, `-v3`, ... |
| version | number | 1 for the first address, incremented on every address change |
| addressHash | string | SHA-256 hex of the normalized address (`line1\|line2\|city\|state\|pincode`, trimmed and lowercased); a matching hash reuses the nickname |
| updatedAt | timestamp | last version minted |

Known limitation: a new version applies only to shipments created
after the address change. Shiprocket orders already created keep
their original pickup location; moving one needs a manual change in
the Shiprocket panel.

### `bids/{id}`
| Field | Type | Notes |
|---|---|---|
| listingId | string | |
| buyerId | string | |
| sellerId | string | |
| amount | number | INR |
| status | string | `open` \| `accepted` \| `rejected` \| `expired` \| `countered`, a `rejected` buyer may send a new offer (only one `open` offer per buyer+listing) |
| counterAmount | number? | seller counter-offer |
| createdAt / acceptedAt | timestamp? | |

### `orders/{id}`
| Field | Type | Notes |
|---|---|---|
| listingId | string | |
| listingTitle | string | purchase-time snapshot of the listing title, written by `createCashfreeOrder`; the order card falls back to it when the listing was deleted |
| listingPhotoUrl | string? | purchase-time snapshot of the listing's first photo, same fallback; absent when the listing had no photo |
| bidId | string? | set when the order came from an accepted bid |
| buyerId / sellerId | string | |
| amount | number | INR, always set server-side |
| buyerTotal | number | INR, what the buyer pays (item price + buyer fee + GST + delivery buyer-share); the Cashfree `order_amount` |
| fees | map | full breakdown, all INR, computed server-side by `quoteFees`: `promoActive`, `sellerPct`, `buyerPct`, `gstPct`, `sellerCommission`, `sellerCommissionGst`, `buyerFee`, `buyerFeeGst`, `deliveryFlat`, `deliveryBuyerShare`, `deliverySellerShare`, `tds` (1% of gross), `sellerPayout` (what the seller receives), `buyerTotal` |
| currency | string | `INR` |
| paymentStatus | string | `PENDING` \| `SUCCESS` \| `FAILED` \| `USER_DROPPED` |
| status | string | `placed` → `pickup_scheduled` → `picked_up` → `in_transit` → `out_for_delivery` → `delivered`, plus `cancelled`, `returned` |
| deliveredAt | timestamp? | first delivery only, stamped by the Shiprocket webhook or the admin manual update, whichever delivers first; starts the 72-hour support window and the settlement clock, never rewritten |
| cfOrderId | number? | Cashfree order id |
| cfOrderRef | string? | our `trega_<orderId>` reference |
| paymentSessionId | string? | for the Cashfree SDK |
| deliveryAddress | map? | buyer delivery address from checkout: `name`, `phone`, `line1`, `line2?`, `city`, `state`, `pincode` (required when the order came from an accepted bid) |
| deliveryType | string | `standard` \| `express`, set server-side; `express` only when same-city express eligibility validates |
| trackingNote | string? | latest fulfillment note |
| srOrderId / srShipmentId | number? | Shiprocket order / shipment ids, written when the shipment is created (see Shiprocket below) |
| awbCode | string? | courier AWB, written on AWB assignment (this debits the Shiprocket wallet) |
| courierName | string? | e.g. `Delhivery Surface` |
| shipmentStatus | string? | creation state machine: `awaiting_parcel` \| `creating` \| `pickup_scheduled` \| `failed` \| `manual` (`awaiting_parcel` = paid standard order waiting up to 12h for the seller's parcel size; `manual` = express order, team books Shiprocket Quick by hand, no automatic shipment); absent until the payment flip |
| shipmentStep | string? | last step reached: `pickup_location` \| `create_order` \| `assign_awb` \| `request_pickup` \| `done` |
| shipmentError | string? | failure message when `shipmentStatus` is `failed`; deleted on success |
| weightKg | number? | packed parcel weight in kg, written by the `submitParcelInfo` callable after the sale; absent until the seller answers |
| lengthCm / breadthCm / heightCm | number? | packed box dimensions in cm, same capture |
| parcelDeadline | timestamp? | end of the 12-hour parcel hold, stamped when the order starts waiting; the hourly `shipAwaitingParcels` sweep ships the order with category defaults after this time |
| pickupScheduledDate | string? | Shiprocket pickup date string |
| etd | string? | estimated delivery date string from Shiprocket |
| paidAt | timestamp? | |
| disputeStatus | string? | `open` \| `resolved`; absent = no report. Set by the dispute callables, never by clients |
| settlementStatus | string? | payout record: `pending` (delivered, inside the window) → `eligible` (window passed, no open report) → `paid`; `held` while a report is open or the order was returned after delivery; `cancelled` when a report resolves in the buyer's favor. Absent on orders delivered before settlement tracking shipped (the admin may mark those paid directly) |
| settlementPaidAt | timestamp? | when the admin marked the payout sent |
| settlementReference | string? | UPI payment reference recorded by the admin |
| refundStatus | string? | `refunded` when a report resolves in the buyer's favor; the money itself is returned through the Cashfree dashboard |
| refundReference | string? | refund reference recorded by the admin |
| createdAt | timestamp | |

### `disputes/{orderId}` (one report per order, doc id = order id)

Written only by the `fileDispute` / `resolveDispute` callables; clients
never write dispute docs directly (see `firestore.rules`).

| Field | Type | Notes |
|---|---|---|
| orderId / listingId | string | |
| buyerId / sellerId | string | |
| amount | number | INR, the order amount |
| reason | string | `not_as_described` \| `damaged` \| `wrong_item` \| `other` |
| description | string | 10 to 1000 chars, the buyer's account of the problem |
| photoUrls | string[] | 0 to 4 evidence photos under `disputeEvidence/{orderId}/` in Storage |
| status | string | `open` \| `resolved_buyer` \| `resolved_seller` |
| filedAt | timestamp | must be within 72 hours of the order's `deliveredAt`, enforced server-side |
| resolvedAt | timestamp? | |
| resolutionNote | string? | admin's note |
| refundReference | string? | recorded when resolved in the buyer's favor |

Filing freezes the settlement (`settlementStatus: held`) until resolved.
Resolving in the seller's favor releases it (`eligible`) at once, the
single allowed report is spent. Resolving in the buyer's favor cancels
the payout and records the refund.

### `kycVerifications/{uid}`
| Field | Type | Notes |
|---|---|---|
| refId | string? | BulkPe reference (opaque, safe) |
| status | string | `otp_sent` \| `verified` \| `failed` |
| name / dob / gender / careOf | string? | from Aadhaar on VALID |
| address / yearOfBirth | string? | from Aadhaar on VALID |
| requestedAt / verifiedAt / failedAt | timestamp? | |
| consentAt | timestamp? | set on OTP request, the app gates the Aadhaar field behind an explicit consent checkbox, so requesting the OTP means consent was given |
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

`verifyAadhaarOtp` claims the fingerprint in a transaction: if the doc already exists under a **different** uid, verification is rejected with `already-exists` ("already verified on another Trega account"). The check runs at verify time (not OTP-request time) so a bare Aadhaar number can't be used to probe whether it's taken. Client access is fully denied in `firestore.rules`, only the callable (Admin SDK) touches it. Same uid re-verifying is idempotent and allowed.

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
| type | string | `bid_received` \| `outbid` \| `bid_accepted` \| `bid_rejected` \| `listing_flagged` \| `kyc_verified` \| `kyc_rejected` \| `order_update` \| `shipment_update` \| `payment_received` \| `fulfillment_update` \| `dispute_filed` \| `dispute_resolved` \| `settlement_paid` \| `acceptance_expired` \| legacy `bid`/`order`/`listing` |
| read | boolean | clients may only flip this (see `firestore.rules`) |
| createdAt | timestamp | |
| data | map | deep-link payload the app opens on tap: `listingId` / `bidId` / `orderId` (only the relevant keys are set) |
| pushSent | boolean | set by the `onNotificationCreate` trigger when it claims FCM delivery; stops a trigger redelivery from double-sending the push |

Push delivery is async (perf fix, 2026-11-13): callables only write the
inbox doc and return. The `onNotificationCreate` trigger fires on every
new doc and sends the matching FCM push, claimed via `pushSent`.

Tap targets (see `trega_app/lib/core/notifications/notification_router.dart`):
`bid_received` → Offers Received tab · `outbid` → listing detail ·
`bid_accepted` → checkout · `bid_rejected` → My Offers tab ·
`listing_flagged` → My Listings · `kyc_verified`/`kyc_rejected` → KYC screen ·
`order_update` → order tracking · `parcel_info_needed` → order tracking.

Writers (all in `trega_functions/src/marketplace.ts`):
- `onBidCreate` trigger → `bid_received` to the seller; `outbid` to the
  previous highest bidder when beaten.
- `acceptBid` callable → `bid_accepted` to the winner ("pay within 24h");
  `bid_rejected` to the auto-rejected losers.
- `reviewListing` callable → `listing_flagged` to the seller on takedown.
- `expireAcceptances` schedule → `acceptance_expired` to the buyer and
  the seller when an accepted offer lapses unpaid after 24 hours.

Writers (in `trega_functions/src/payments.ts`):
- `applyPaymentSuccess` (webhook + `verifyPayment`) → `payment_received`
  to the buyer ("Order confirmed") and the seller ("Your item sold").

Writers (in `trega_functions/src/admin.ts`):
- `setUserKycStatus` callable → `kyc_verified` / `kyc_rejected` to the user
  when the admin manually verifies or rejects their KYC.
- `updateOrderFulfillment` callable → `fulfillment_update` to the buyer
  and the seller on every manual status or tracking-note change.

Writers (in `trega_functions/src/disputes.ts`):
- `fileDispute` callable → `dispute_filed` to the seller.
- `resolveDispute` callable → `dispute_resolved` to the buyer and the
  seller, with the outcome.
- `markSettlementPaid` callable → `settlement_paid` to the seller.

Writers (in `trega_functions/src/shiprocket.ts`):
- `onOrderPaid` trigger → `parcel_info_needed` to the seller on
  payment, asking for the packed weight and box size (standard orders
  wait for the answer, express orders need it for the manual Quick
  booking).
- `onOrderPaid` trigger → `shipment_update` to the buyer and the seller
  when pickup is scheduled.
- `courierTracking` webhook → `shipment_update` to the buyer on
  delivery (with the 72-hour window note), and to both parties on a
  return.

### `reports/{listingId}_{reporterId}` (user-submitted, reactive moderation)

| Field | Type | Notes |
|---|---|---|
| listingId | string | |
| reporterId | string | users/{uid}, must equal the writer's uid |
| reason | string | fixed set: Spam or misleading / Fraud or scam / Inappropriate content / Wrong category |
| createdAt | timestamp | |

Doc ID guarantees one report per user per listing. Clients may only
create; reads are admin-only (`firestore.rules`).

### `campaigns/{id}` (broadcast push history, server-written)

| Field | Type | Notes |
|---|---|---|
| title / body | string | push text (title ≤ 100, body ≤ 300 chars) |
| imageUrl | string? | https image shown in the Android push |
| linkType | string | `none` \| `listing` \| `category` |
| listingId / categoryId / categoryName | string? | deep-link target |
| recipients / sent / failed | number | distinct-token audience + FCM delivery counts |
| createdBy | string? | admin uid |
| createdAt | timestamp | |

Written only by the `sendCampaign` callable; admin-read only in rules.
One doc per broadcast, this is the admin panel's campaign history.

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

- `placeBid({listingId, amount})`, guards: listing must be `live`; buyer must
  not be the seller; at most **one open offer per buyer per listing** (a
  rejected buyer may offer again). No Aadhaar gate for buyers since
  2026-11-04 (KYC is sellers-only; buyers are phone-OTP verified). Writes the bid (`status: open`) and bumps
  `highestBid`/`bidCount` when appropriate.
- `acceptBid({bidId})`, seller only; the listing must be `live` and have no
  `acceptedBidId` yet (accepting is exclusive). Marks the bid `accepted`,
  sets `listings/{id}.acceptedBidId` (reserves the listing for the winner
  until they pay), rejects the other open bids. The winner's listing page
  then shows the single "Buy Now at ₹X" button → checkout. The winner has
  24 hours to pay: the hourly `expireAcceptances` schedule flips unpaid
  accepted bids to `expired` and clears the reservation (skipping bids
  with a SUCCESS order, or a payment in flight in the last 30 minutes).
- `rejectBid({bidId})`, seller only; bid must be `open`. Marks it
  `rejected`; the buyer is notified and may send a new offer.
- `cancelAcceptance({bidId})`, seller only; bid must be `accepted` and the
  listing still `live`. Marks the bid `rejected`, clears
  `listings/{id}.acceptedBidId`, notifies the buyer; the listing is open for
  offers again (used when the winner never pays).
- `deleteOwnListing({listingId})`, seller only; the caller must own the
  listing, it must not be `sold`, and it must have no `acceptedBidId` (an
  accepted offer reserves the listing for the winner until they pay).
  Deletes the bids, the doc plus its `private` subcollection, and the
  media files. The admin takedown `deleteListing` shares the same deletion
  and additionally notifies the seller. Firestore rules enforce the same
  guards on direct client deletes.
- `createCashfreeOrder({listingId?, bidId?, customerPhone, deliveryAddress?})`
 `deliveryAddress` is required when `bidId` is set (accepted-offer
  checkout), validated server-side and stored on the order; the `bidId` path
  charges exactly the accepted bid amount. The listing must still be
  `live`: the bid stays `accepted` after payment, so without this check
  a second checkout on the same bid would charge again for a sold item.
- `verifyPayment({orderId})`, server-side payment verification. The app
  calls this after the Cashfree SDK reports success and shows its success UI
  ONLY when this returns `paymentStatus: "SUCCESS"`. The server asks
  the Cashfree Orders API directly (secret key) and applies the same sale
  side-effects as the webhook (order → SUCCESS, listing → sold, other open
  bids rejected), idempotent, so the webhook and the verifier can safely
  race. The on-device SDK callback alone is never treated as proof of
  payment (a user pressing back / a failed payment surfaces through the
  SDK error callback, never as success).

KYC (`kyc.ts`): `requestAadhaarOtp` / `verifyAadhaarOtp`, provider errors
are surfaced with their real message (invalid Aadhaar, throttled, provider
outage) instead of a generic failure.

Admin (`trega_functions/src/admin.ts`, `admin` custom claim required):

- `bootstrapAdmin()`, one-shot self-service bootstrap. Grants
  `{admin: true}` to the caller **only** when their verified phone number
  matches the `ADMIN_BOOTSTRAP_PHONE` secret (E.164). After it returns, the
  client refreshes its ID token. The admin panel's login flow exposes this
  as "Claim admin access" on the access-denied screen.
- `setUserKycStatus({uid, status: "verified" | "rejected", note?})`,
  manual KYC verification from the admin panel's Users page. Sets
  `users/{uid}` (`kycStatus`, `verifiedSeller`, `kycNote`), merges a
  `kycVerifications/{uid}` audit record (`method: "manual"`, `verifiedBy`,
  `reviewedAt`, note), and notifies the user (`kyc_verified` /
  `kyc_rejected`). A manually-verified user passes the same seller gate as
  an Aadhaar-verified one (listing creation reads `users/{uid}.kycStatus`;
  making offers needs no KYC since 2026-11-04).
- `updateOrderFulfillment({orderId, status?, trackingNote?})`, advances
  order fulfillment from the admin panel's Orders page. Payment status is
  owned by the Cashfree webhook and cannot be set here. Setting `delivered`
  stamps `deliveredAt` (first delivery only) and opens the settlement
  record; setting `returned` after delivery holds the payout. Every
  status or note change notifies the buyer and the seller.
- `resolveDispute({orderId, decision: "buyer" | "seller", note?,
  refundReference?})`, resolves an open delivery report. Buyer favor
  records the refund and cancels the payout; seller favor releases the
  payout at once. Both parties are notified with the outcome.
- `markSettlementPaid({orderId, reference})`, records a payout the team
  sent by UPI (the transfer itself happens outside this system).
  Requires `eligible`, except orders delivered before settlement
  tracking shipped, which may be marked paid directly. Notifies the
  seller with the amount and reference.
- `sendCampaign({title, body, imageUrl?, linkType?, listingId?, categoryId?})`
 broadcasts a custom campaign push to every user with a saved FCM
  token (batched multicast, dead tokens pruned). `linkType: "listing"`
  requires a live listing; `"category"` resolves the category name
  server-side. Writes one `campaigns/{id}` history doc with delivery
  counts; the push is tray-only (never copied into user inboxes).

Disputes + settlement (`trega_functions/src/disputes.ts`):

- `fileDispute({orderId, reason, description, photoUrls?})`, buyer only.
  The order must be `delivered` and inside the 72-hour window from
  `deliveredAt`; one report per order. Filing freezes the settlement
  (`held`) and notifies the seller. Rate tier `disputes`.
- `releaseSettlements` (hourly schedule): flips delivered orders whose
  window passed with no open report from `pending` to `eligible`.

Account (`trega_functions/src/account.ts`):

- `deleteAccount()`, wipes the caller's account completely: `users/{uid}`
  and all its subcollections, the user's listings (+ private details, media
  in Storage, bids on them), bids placed, orders as buyer or seller, reviews
  by/about the user, reports filed, `kycVerifications/{uid}`, the user's
  `aadhaarIndex` claims (frees the Aadhaar for a future account), the avatar,
  and finally the Firebase Auth user. No undo; the app confirms explicitly.

Shiprocket courier integration (`trega_functions/src/shiprocket.ts`):

- `onOrderPaid` (Firestore trigger on `orders/{orderId}` updates): when
  `paymentStatus` flips to `SUCCESS`, a standard order is held for
  parcel info (`shipmentStatus: "awaiting_parcel"` with a 12-hour
  `parcelDeadline`) and the seller is asked for the packed weight and
  box size; the shipment is created when the seller replies (see
  `submitParcelInfo`) or when the hourly `shipAwaitingParcels` sweep
  fires after the deadline. Express orders
  (`deliveryType: "express"`) get `shipmentStatus: "manual"` and are
  booked by hand via Shiprocket Quick so the order never ships twice,
  and the seller is still asked for parcel info since the team needs
  the weight for the Quick booking. Shipment steps: ensure the
  seller pickup location (versioned nickname, see
  `shiprocketPickups/{sellerUid}` above, so address changes reach
  Shiprocket), create an adhoc order
  (Shiprocket `order_id` is the Trega order doc id), pick a courier
  from the serviceability response (Blue Dart for Rs 10,000+ orders
  when available, else highest-rated with earliest ETD), assign an AWB
  (debits the Shiprocket wallet), request pickup. Resumable from the
  stored ids; failures land as `shipmentStatus: "failed"` on the order
  doc and never break payment. No-ops entirely until the Shiprocket
  secrets are set.
- `submitParcelInfo({orderId, weightKg, lengthCm, breadthCm, heightCm})`
  (seller-only callable, rate tier `parcelInfo`): the seller sends the
  packed parcel size after the sale, from the prompt on the order
  tracking view. Caps 0.1 to 50 kg and 1 to 200 cm per side are
  enforced; the fields are written on the order doc, and a standard
  order still awaiting parcel info ships at once. Express orders only
  record the fields.
- `shipAwaitingParcels` (hourly schedule): ships paid orders whose
  12-hour parcel hold expired without a seller reply, with category
  defaults. Single-field query on `shipmentStatus`, deadline filtered
  in code, at most 100 orders per run; no composite index needed.
- `retryShipment({orderId})` (admin-only callable, rate tier
  `shipmentRetry`): retries a failed shipment from the stored step, or
  force-books an order still awaiting parcel info (ships with category
  defaults when the seller never replied).
- `courierTracking` (HTTPS webhook, `x-api-key` token auth): Shiprocket
  tracking events move the order forward (pickup_scheduled, picked_up,
  in_transit, delivered, cancelled, returned; forward-only, terminal
  states stick) and refresh `trackingNote` / `etd`. Named
  `courierTracking` because Shiprocket rejects callback URLs containing
  `shiprocket`, `kartrocket`, `sr` or `kr`. Register the deployed URL
  plus the `SHIPROCKET_WEBHOOK_KEY` token in the Shiprocket panel.
- Secrets: `SHIPROCKET_API_EMAIL`, `SHIPROCKET_API_PASSWORD` (API user
  created in the panel with Buyer Details Access ALLOWED),
  `SHIPROCKET_WEBHOOK_KEY`. No sandbox exists: every call is live.
- Parcel weight/dimensions come from the order's own parcel fields
  (`weightKg`, `lengthCm`, `breadthCm`, `heightCm`), sent by the seller
  after the sale; then the listing's parcel fields (legacy, only on
  listings published while the sell flow captured them); category
  defaults in `FREIGHT_DEFAULTS` apply only when neither has usable
  parcel fields. Wrong weights cause Shiprocket weight discrepancy
  charges.

## Storage
`listingMedia/{listingId}/{filename}`, listing photos and videos.
`avatars/{uid}.jpg`, profile pictures.

## Composite indexes (`firestore.indexes.json`, deployed with `firebase deploy`)

- `listings`: `status` ASC + `createdAt` DESC (feed)
- `listings`: `status` ASC + `categoryId` ASC + `createdAt` DESC (category feed)
- `listings`: `sellerId` ASC + `createdAt` DESC (my listings)
- `bids`: `listingId` ASC + `createdAt` DESC (bids on a listing)
- `bids`: `buyerId` ASC + `createdAt` DESC (my bids)
- `bids`: `buyerId` ASC + `listingId` ASC (my offers on one listing, the listing detail action bar)
- `bids`: `sellerId` ASC + `createdAt` DESC (offers received)
- `orders`: `buyerId` ASC + `createdAt` DESC (my purchases)
- `orders`: `sellerId` ASC + `createdAt` DESC (my sales)
- `categories`: `active` ASC + `sortOrder` ASC

