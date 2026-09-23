import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';
import { getFunctions } from 'firebase/functions';

/**
 * Firebase initialisation for the Trega admin panel (project `tregaxmuse`).
 *
 * Web config values come from Vite env vars (see .env.example). Get them from
 * Firebase console → Project settings → Your apps → Web app config.
 * None of these are secrets — they identify the project, and access is
 * enforced by Firestore rules + the `admin` custom claim.
 */
const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY as string,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN as string,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID as string,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET as string,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID as string,
  appId: import.meta.env.VITE_FIREBASE_APP_ID as string,
};

if (!firebaseConfig.projectId) {
  console.warn(
    '[trega-admin] Missing VITE_FIREBASE_* env vars. Copy .env.example to .env and fill in the web config.'
  );
}

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
// Cloud Functions are deployed in asia-south1 — the region MUST match or
// callable invocations 404.
export const functions = getFunctions(app, 'asia-south1');
