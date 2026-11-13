import type { DeliveryAddress } from '../api/types';

/** INR currency formatting */
export function formatINR(amount: number): string {
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    maximumFractionDigits: 0,
  }).format(amount);
}

/** Short date, e.g. "23 Sep 2026" */
export function formatDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

/** Date + time, e.g. "23 Sep 2026, 11:05" */
export function formatDateTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/** Relative time, e.g. "3h ago" */
export function timeAgo(iso: string): string {
  const d = new Date(iso).getTime();
  if (Number.isNaN(d)) return '';
  const seconds = Math.floor((Date.now() - d) / 1000);
  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months}mo ago`;
  return `${Math.floor(months / 12)}y ago`;
}

const CONDITION_LABELS: Record<string, string> = {
  brand_new: 'Brand New',
  new: 'Brand New', // legacy alias
  like_new: 'Like New',
  good: 'Good',
  fair: 'Fair',
};

export function conditionLabel(condition: string): string {
  return CONDITION_LABELS[condition] ?? condition;
}

/** Address (structured map or legacy plain string) → display lines.
 * Empty parts are dropped, so pickup addresses without a name/phone
 * still render cleanly. */
export function formatAddressLines(
  addr: DeliveryAddress | string | null | undefined,
): string[] {
  if (!addr) return [];
  if (typeof addr === 'string') {
    return addr
      .split('\n')
      .map((s) => s.trim())
      .filter(Boolean);
  }
  const cityLine = [addr.city, addr.state].filter(Boolean).join(', ');
  const lastLine = [cityLine, addr.pincode].filter(Boolean).join(' ');
  return [
    addr.name,
    addr.phone,
    addr.line1,
    addr.line2,
    lastLine,
  ]
    .map((s) => s?.trim())
    .filter((s): s is string => Boolean(s));
}
