# Trega — Flutter App

**Trega** is a peer-to-peer marketplace for pre-owned gear (gaming, mobiles,
laptops, cameras, music). Buyers browse video-verified listings, place bids /
offers, and pay securely in-app; sellers list in ~30 seconds with doorstep
pickup handled by Trega logistics. There is **intentionally no buyer↔seller
chat** — negotiation happens through structured bids and offers.

This repo is an original implementation inspired by the marketplace concept.
All UI, code, branding and assets are Trega's own.

## Brand

| Token      | Value     | Usage                          |
|------------|-----------|--------------------------------|
| Primary    | `#8B3A1C` | Logo brown — buttons, app bars |
| Primary dark | `#6E2E16` | Pressed / emphasis states      |
| Accent     | `#F7B600` | Logo yellow dot — highlights, badges |
| Background | `#FFFBF7` | Warm paper scaffold background |
| Surface    | `#FFFFFF` | Cards, sheets, inputs          |

Logo: `assets/logo/trega_logo.png` (wired in `pubspec.yaml`).

## Project structure

```
lib/
├── main.dart                      # entry: inits ApiClient, ProviderScope
├── app.dart                       # TregaApp: theme + named-route table
├── core/
│   ├── config/app_config.dart     # base URL (dart-define override), constants
│   ├── theme/app_theme.dart       # AppColors + buildTregaTheme()
│   ├── api/
│   │   ├── api_client.dart        # Dio singleton + auth interceptor stub
│   │   └── endpoints.dart         # REST endpoint catalogue
│   ├── models/                    # Product, Listing, Bid, Order, AppUser, Category
│   │                              # Condition enum: brandNew/likeNew/good/fair
│   ├── data/sample_data.dart      # placeholder catalogue (delete after backend)
│   ├── utils/format.dart          # formatINR(), timeAgo()
│   └── widgets/                   # TregaButton, ProductCard, ConditionBadge,
│                                  # SectionHeader, StatusChip, EmptyState
└── features/
    ├── auth/screens/              # Splash, Onboarding, PhoneAuth (OTP)
    ├── home/screens/              # Home feed + Explore by Passion
    ├── search/screens/            # Search, Category
    ├── listing_detail/screens/    # ListingDetail (gallery, seller card, Buy/Bid/Offer)
    ├── sell/screens/              # SellFlow (3-step Stepper)
    ├── bids/screens/              # BidsOffers (My Bids / Offers Received tabs)
    ├── orders/screens/            # Orders, OrderTracking (timeline)
    ├── wishlist/screens/          # Wishlist
    ├── notifications/screens/     # Notifications inbox
    └── profile/screens/           # Profile hub
```

State management: **flutter_riverpod** (`ProviderScope` is wired; feature
providers are TODO). Networking: **dio**. Media: **image_picker**,
**video_player**, **cached_network_image**.

## Backend: Firebase (`tregaxmuse`)

The app talks **only** to Firebase — there is no REST backend. The legacy
Dio client in `lib/core/api/` is DEPRECATED and kept for reference only.

| Concern        | Firebase product                                  |
|----------------|---------------------------------------------------|
| Auth           | Firebase Authentication — phone OTP sign-in       |
| Database       | Cloud Firestore (`FirestoreService`)              |
| Media          | Firebase Storage (`StorageService`)               |
| KYC / payments | Cloud Functions callables (`FunctionsService`), region `asia-south1` |
| Push           | Firebase Cloud Messaging                          |

Callable names (exact, must match `trega_functions/src/index.ts`):
`requestAadhaarOtp`, `verifyAadhaarOtp`, `createCashfreeOrder`, `placeBid`,
`acceptBid`. BulkPe + Cashfree secrets live only in Cloud Functions config —
never in the app or repo.

Key flows:

- **Sell** — `createListingDraft()` writes `listings/{id}` with
  `status: 'draft'`; media uploads to `listingMedia/{listingId}/…`; the
  `onListingCreate` trigger moves the draft to `pending` for team review and
  the admin panel's `reviewListing` flips it `live`/`rejected`.
- **Bids/offers** — `placeBid` / `acceptBid` callables (server-validated;
  accepting rejects competing bids and marks the listing `sold`). No chat —
  negotiation is structured accept/reject/counter.
- **Buy** — `createCashfreeOrder` returns a `paymentSessionId` for the
  Cashfree SDK; `cashfreeWebhook` flips `orders/{id}.paymentStatus`.
- **KYC** — Aadhaar OTP via BulkPe (`KycScreen`); status watched from
  `kycVerifications/{uid}` (`otp_sent` → `verified`/`failed`). The Aadhaar
  number is never stored.
- **Wishlist** — `likedBy[]` array on the listing doc; toggle via
  `FirestoreService.toggleLike`.

Until Firestore is reachable, screens fall back to
`lib/core/data/sample_data.dart` and show a demo banner.

## Getting started

### Prerequisites

- Flutter SDK ≥ 3.22 (stable)
- A Firebase project — `tregaxmuse` (already created)

### One-time setup

```sh
# 1) Generate the real platform config (replaces the placeholder
#    lib/firebase_options.dart that throws until you do this):
flutterfire configure --project=tregaxmuse

# 2) In the Firebase console (project tregaxmuse):
#    - Authentication → Sign-in method → enable Phone
#    - Firestore Database → create database (asia-south1)
#    - Storage → enable (asia-south1)
#    - (optional) Cloud Messaging → upload APNs key for iOS push

# 3) Deploy rules + functions from ~/workspace/trega/:
firebase deploy --only firestore:rules
firebase deploy --only storage
cd trega_functions && firebase deploy --only functions

# 4) Set server-side secrets (NEVER in the app or repo):
firebase functions:secrets:set BULKPE_API_TOKEN
firebase functions:secrets:set CASHFREE_APP_ID
firebase functions:secrets:set CASHFREE_SECRET_KEY
firebase functions:secrets:set CASHFREE_ENV   # TEST or PROD
```

Required Firestore composite indexes (create from the console links that
Firestore errors surface, or via `firebase.json`):

- `listings`: `status ASC, createdAt DESC`
- `listings`: `status ASC, categoryId ASC, createdAt DESC`
- `listings`: `sellerId ASC, createdAt DESC`
- `bids`: `buyerId ASC, createdAt DESC`
- `bids`: `sellerId ASC, createdAt DESC`
- `bids`: `listingId ASC, createdAt DESC`
- `orders`: `buyerId ASC, createdAt DESC`
- `orders`: `sellerId ASC, createdAt DESC`
- `categories`: `active ASC, sortOrder ASC`

### Run

```sh
cd trega_app
flutter pub get
flutter run
```

### Build

```sh
flutter build apk --release            # Android
flutter build appbundle --release      # Play Store
flutter build ipa --release           # iOS (macOS + Xcode)
```

## Backend wiring — remaining

- **Cashfree SDK** — add the `cashfree_pg` package and complete
  `ListingDetailScreen._buyNow` (marked `TODO(checkout)`): hand the
  returned `paymentSessionId` to the SDK.
- **FCM** — request permission, persist the FCM token on the user doc,
  and route notification taps (bid/order/KYC events are emitted by the
  functions).
- **Reject/counter on bids** — same pattern as `acceptBid`; add server
  callables or extend `acceptBid`.
- **Seller listings screen** — `FirestoreService.watchSellerListings` exists;
  profile's "My Listings" tile needs the UI.
- **In-app notification inbox** — persist to
  `notifications/{uid}/items` (schema TBD) instead of the placeholder.

## Conventions

- Feature-first folders; shared code lives in `core/`.
- All Firestore field names match `trega_functions/FIRESTORE_MODEL.md`.
- No chat feature — do not add buyer↔seller messaging screens.
- Run `flutter analyze` before committing; follow `analysis_options.yaml`.
