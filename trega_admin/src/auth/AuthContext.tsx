import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import type { ReactNode } from 'react';
import { onAuthStateChanged, signOut } from 'firebase/auth';
import type { User } from 'firebase/auth';
import { auth } from '../lib/firebase';
import { claimAdminAccess } from '../lib/firestore';

export interface AdminAuthUser {
  uid: string;
  phone: string;
}

interface AuthContextValue {
  user: AdminAuthUser | null;
  loading: boolean;
  /** Signed in, but the account lacks the `admin` custom claim. */
  denied: boolean;
  /** Raw Firebase user — present while signed in, even when denied. */
  fbUser: User | null;
  /** One-shot bootstrap: claims the `admin` custom claim for the founder's
   * number (the backend only grants it to ADMIN_BOOTSTRAP_PHONE). */
  claimAdmin: () => Promise<void>;
  claimError: string | null;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AdminAuthUser | null>(null);
  const [fbUser, setFbUser] = useState<User | null>(null);
  const [denied, setDenied] = useState(false);
  const [loading, setLoading] = useState(true);
  const [claimError, setClaimError] = useState<string | null>(null);

  const applyClaims = useCallback((u: User, isAdmin: boolean) => {
    setFbUser(u);
    if (isAdmin) {
      setUser({ uid: u.uid, phone: u.phoneNumber ?? '' });
      setDenied(false);
    } else {
      // Signed in but not an admin: stay signed in (routes stay gated on
      // `user`) so the founder can claim access via the bootstrap callable.
      setUser(null);
      setDenied(true);
    }
  }, []);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (u: User | null) => {
      setClaimError(null);
      if (!u) {
        setUser(null);
        setFbUser(null);
        setDenied(false);
        setLoading(false);
        return;
      }
      try {
        const token = await u.getIdTokenResult(true);
        applyClaims(u, token.claims.admin === true);
      } catch {
        setUser(null);
        setFbUser(null);
        setDenied(false);
      } finally {
        setLoading(false);
      }
    });
    return unsub;
  }, [applyClaims]);

  const claimAdmin = useCallback(async () => {
    const u = auth.currentUser;
    if (!u) {
      setClaimError('Sign in first.');
      return;
    }
    setClaimError(null);
    try {
      await claimAdminAccess();
      const token = await u.getIdTokenResult(true);
      applyClaims(u, token.claims.admin === true);
      if (token.claims.admin !== true) {
        setClaimError('Claim granted but not visible yet — sign out and back in.');
      }
    } catch (e) {
      setClaimError(e instanceof Error ? e.message : 'Could not claim admin access.');
    }
  }, [applyClaims]);

  const logout = async () => {
    await signOut(auth);
    setUser(null);
    setFbUser(null);
    setDenied(false);
    setClaimError(null);
    window.location.href = '/login';
  };

  return (
    <AuthContext.Provider
      value={{ user, loading, denied, fbUser, claimAdmin, claimError, logout }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
