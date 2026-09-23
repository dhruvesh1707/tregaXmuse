import { useState } from 'react';
import type { FormEvent } from 'react';
import { useNavigate, Navigate } from 'react-router-dom';
import { RecaptchaVerifier, signInWithPhoneNumber } from 'firebase/auth';
import type { ConfirmationResult } from 'firebase/auth';
import { auth } from '../lib/firebase';
import { useAuth } from '../auth/AuthContext';

type Step = 'phone' | 'otp';

/** Admin sign-in via Firebase phone OTP.
 *  Only phone numbers whose Firebase user carries the `admin` custom claim
 *  can proceed — everyone else sees an access-denied message. */
export default function Login() {
  const { user, denied, loading } = useAuth();
  const navigate = useNavigate();
  const [step, setStep] = useState<Step>('phone');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [confirmation, setConfirmation] = useState<ConfirmationResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (!loading && user) return <Navigate to="/" replace />;

  const sendOtp = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    const digits = phone.replace(/\D/g, '');
    const e164 = digits.startsWith('91') && digits.length === 12 ? `+${digits}` : `+91${digits.slice(-10)}`;
    if (e164.length < 12) {
      setError('Enter a valid 10-digit mobile number.');
      return;
    }
    setSubmitting(true);
    try {
      // Invisible reCAPTCHA, created per attempt (avoids StrictMode double-mount issues).
      const verifier = new RecaptchaVerifier(auth, 'recaptcha-container', { size: 'invisible' });
      const result = await signInWithPhoneNumber(auth, e164, verifier);
      setConfirmation(result);
      setPhone(e164);
      setStep('otp');
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setSubmitting(false);
    }
  };

  const verifyOtp = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!confirmation || code.trim().length < 6) {
      setError('Enter the 6-digit OTP.');
      return;
    }
    setSubmitting(true);
    try {
      await confirmation.confirm(code.trim());
      // onAuthStateChanged in AuthContext takes over: admin claim → dashboard,
      // non-admin → signed out + access denied.
      navigate('/', { replace: true });
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-trega-800 px-4">
      <div id="recaptcha-container" />
      <div className="w-full max-w-sm rounded-2xl bg-white p-8 shadow-2xl">
        <div className="mb-6 flex flex-col items-center">
          <img src="/logo.png" alt="Trega" className="h-12 w-auto" />
          <h1 className="mt-4 text-xl font-bold text-stone-900">Trega Admin</h1>
          <p className="text-sm text-stone-500">
            {step === 'phone' ? 'Sign in with your admin phone number' : `OTP sent to ${phone}`}
          </p>
        </div>

        {denied && (
          <div className="mb-4 rounded-lg bg-red-50 px-3 py-2.5 text-sm text-red-700">
            This number is signed in but doesn't have admin access. Contact the
            marketplace owner to grant the <span className="font-semibold">admin</span> claim.
          </div>
        )}

        {step === 'phone' ? (
          <form onSubmit={sendOtp} className="space-y-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">Mobile number</label>
              <input
                type="tel"
                required
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="98765 43210"
                className="w-full rounded-lg border border-stone-300 px-3 py-2.5 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
              />
            </div>
            {error && (
              <div className="rounded-lg bg-red-50 px-3 py-2.5 text-sm text-red-700">{error}</div>
            )}
            <button
              type="submit"
              disabled={submitting}
              className="w-full rounded-lg bg-trega-600 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-trega-700 disabled:opacity-60"
            >
              {submitting ? 'Sending OTP…' : 'Send OTP'}
            </button>
          </form>
        ) : (
          <form onSubmit={verifyOtp} className="space-y-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">6-digit OTP</label>
              <input
                type="text"
                inputMode="numeric"
                required
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                placeholder="••••••"
                className="w-full rounded-lg border border-stone-300 px-3 py-2.5 text-center text-lg tracking-[0.5em] outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
              />
            </div>
            {error && (
              <div className="rounded-lg bg-red-50 px-3 py-2.5 text-sm text-red-700">{error}</div>
            )}
            <button
              type="submit"
              disabled={submitting}
              className="w-full rounded-lg bg-trega-600 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-trega-700 disabled:opacity-60"
            >
              {submitting ? 'Verifying…' : 'Verify & sign in'}
            </button>
            <button
              type="button"
              onClick={() => {
                setStep('phone');
                setCode('');
                setConfirmation(null);
              }}
              className="w-full text-sm font-medium text-trega-600 hover:underline"
            >
              ← Use a different number
            </button>
          </form>
        )}

        <p className="mt-6 text-center text-xs text-stone-400">
          Only accounts with the <span className="font-semibold">admin</span> custom claim can sign in here.
        </p>
      </div>
    </div>
  );
}

function friendlyError(err: unknown): string {
  const code = (err as { code?: string })?.code ?? '';
  if (code.includes('invalid-phone-number')) return 'That phone number looks invalid.';
  if (code.includes('too-many-requests')) return 'Too many attempts. Try again later.';
  if (code.includes('invalid-verification-code')) return 'Wrong OTP. Check and try again.';
  if (code.includes('code-expired')) return 'OTP expired. Request a new one.';
  return err instanceof Error ? err.message : 'Sign in failed.';
}
