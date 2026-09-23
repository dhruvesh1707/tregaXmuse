# Trega Admin

Separate web admin panel for the **Trega** marketplace (the Vingo-inspired peer-to-peer
marketplace for pre-owned gear). This is a standalone app — it is **not** part of the
Flutter mobile app.

- **Stack:** React 19 + TypeScript + Vite + Tailwind CSS v4 + React Router
- **Backend:** Firebase (project `tregaxmuse`) — Firestore for data, Firebase Auth
  (phone OTP) for sign-in, Cloud Functions callables for privileged actions
- **Theme:** Trega branding — primary `#8B3A1C` (logo brown), accent `#F7B600` (logo gold dot)
- **Logo:** `public/logo.png` is the official Trega PNG logo, used on the login screen and sidebar

## Setup

### 1. Firebase web config

```bash
cp .env.example .env
```

Fill in the values from **Firebase console → Project settings → Your apps → Web app**
(create one if needed) → "SDK setup and configuration" → Config. These are not
secrets — access is enforced by Firestore rules + the `admin` custom claim.

### 2. Enable Phone Auth

Firebase console → **Authentication → Sign-in method → Phone** → Enable.
Add your domain (and `localhost` for dev) under **Authorized domains**.

### 3. Grant the admin claim

Sign in once via the app's phone OTP (or the mobile app) to create your Firebase
user, then grant the claim from the functions project:

```bash
cd ../trega_functions
node scripts/setAdminClaim.js +91XXXXXXXXXX   # or the Firebase uid
```

Only users with `{admin: true}` can see the panel — everyone else gets an
access-denied screen after sign-in.

### 4. Deploy rules + functions

```bash
cd ../trega_functions
firebase use tregaxmuse
firebase deploy --only firestore:rules,functions
```

The admin panel needs the rules in `../firestore.rules` (admin reads on bids,
admin writes on categories) and the `reviewListing`, `setUserKycStatus` and
`updateOrderFulfillment` callables.

### 5. Run

```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # production bundle in dist/
```

## What the panel does

| Page | Source | Notes |
|---|---|---|
| Dashboard | Firestore counts + recent docs | GMV counts only `SUCCESS` Cashfree payments |
| Review Queue | `listings` where `status == pending` | Approve/reject via the `reviewListing` callable |
| All Listings | `listings` | read-only detail |
| Users | `users` | KYC verify/reject via `setUserKycStatus` callable |
| Orders | `orders` | fulfillment updates via `updateOrderFulfillment`; payment status is set only by the Cashfree webhook |
| Bids | `bids` | read-only overview (rules allow admin reads) |
| Categories | `categories` | direct Firestore writes (rules allow admins) |

## Notes

- **No composite Firestore indexes required** — all queries are single-field;
  sorting, search and pagination happen client-side.
- **No buyer↔seller chat** anywhere in Trega — negotiation is structured
  bids/offers only.
- The old REST `ApiClient` (`src/api/client.ts`, `VITE_API_URL`) has been
  removed; `src/lib/firestore.ts` is the only data layer.
- Functions are deployed in **asia-south1** — `src/lib/firebase.ts` pins the
  Functions client to that region, or callable invocations 404.

## Deploying the panel

Any static host works (the panel is a pure SPA):

- **Firebase Hosting:** `firebase init hosting` → target `dist/`, then `firebase deploy --only hosting`
- **Vercel / Netlify:** import the repo, set the `VITE_FIREBASE_*` env vars in
  the dashboard, build command `npm run build`, output dir `dist`
