import { createContext, useContext, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { onAuthStateChanged, signOut } from 'firebase/auth';
import type { User } from 'firebase/auth';
import { auth } from '../lib/firebase';

export interface AdminAuthUser {
  uid: string;
  phone: string;
}

interface AuthContextValue {
  user: AdminAuthUser | null;
  loading: boolean;
  /** Signed in, but the account lacks the `admin` custom claim. */
  denied: boolean;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AdminAuthUser | null>(null);
  const [denied, setDenied] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (fbUser: User | null) => {
      if (!fbUser) {
        setUser(null);
        setDenied(false);
        setLoading(false);
        return;
      }
      try {
        const token = await fbUser.getIdTokenResult(true);
        if (token.claims.admin === true) {
          setUser({ uid: fbUser.uid, phone: fbUser.phoneNumber ?? '' });
          setDenied(false);
        } else {
          // Signed in, but not an admin — don't let them see anything.
          await signOut(auth);
          setUser(null);
          setDenied(true);
        }
      } catch {
        setUser(null);
        setDenied(false);
      } finally {
        setLoading(false);
      }
    });
    return unsub;
  }, []);

  const logout = async () => {
    await signOut(auth);
    setUser(null);
    setDenied(false);
    window.location.href = '/login';
  };

  return (
    <AuthContext.Provider value={{ user, loading, denied, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
