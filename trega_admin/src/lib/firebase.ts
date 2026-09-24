import { initializeApp } from 'firebase/app';
import type { FirebaseApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import type { Auth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import type { Firestore } from 'firebase/firestore';
import { getFunctions } from 'firebase/functions';
import type { Functions } from 'firebase/functions';

/**
 * Firebase initialisation for the Trega admin panel (project `tregaxmuse`).
 *
 * Web config values come from Vite env vars, written by `npm run setup`
 * (see scripts/setup.mjs). None of these are secrets — they identify the
 * project, and access is enforced by Firestore rules + the `admin` custom
 * claim.
 *
 * If the config is missing (setup never ran), `configError` is set and the
 * Firebase services are stubbed — main.tsx renders the error instead of
 * the app, so a missing `.env` shows an actionable message rather than a
 * blank page. (Without this guard, getAuth() throws auth/invalid-api-key
 * at import time and React never mounts.)
 */
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY as string,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN as string,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID as string,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET as string,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID as string,
  appId: import.meta.env.VITE_FIREBASE_APP_ID as string,
};

const hasConfig = Boolean(firebaseConfig.apiKey && firebaseConfig.projectId);

export const configError: string | null = hasConfig
  ? null
  : 'Firebase web config is missing. Run "npm run setup" inside trega_admin, then restart with "npm run dev".';

// Never touched when configError is set (main.tsx refuses to render the
// app), so the stub casts are safe.
export const app: FirebaseApp = (hasConfig ? initializeApp(firebaseConfig) : {}) as FirebaseApp;
export const auth: Auth = (hasConfig ? getAuth(app) : {}) as Auth;
export const db: Firestore = (hasConfig ? getFirestore(app) : {}) as Firestore;
// Cloud Functions are deployed in asia-south1 — the region MUST match or
// callable invocations 404.
export const functions: Functions = (hasConfig ? getFunctions(app, 'asia-south1') : {}) as Functions;
