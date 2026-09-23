/** Colored pill badge for listing / KYC / order / bid statuses. */

const TONES: Record<string, string> = {
  // listings
  pending: 'bg-amber-100 text-amber-800 ring-amber-200',
  live: 'bg-emerald-100 text-emerald-800 ring-emerald-200',
  sold: 'bg-sky-100 text-sky-800 ring-sky-200',
  rejected: 'bg-red-100 text-red-800 ring-red-200',
  draft: 'bg-stone-200 text-stone-700 ring-stone-300',
  // kyc
  unverified: 'bg-stone-200 text-stone-700 ring-stone-300',
  verified: 'bg-emerald-100 text-emerald-800 ring-emerald-200',
  // orders
  placed: 'bg-sky-100 text-sky-800 ring-sky-200',
  pickup_scheduled: 'bg-amber-100 text-amber-800 ring-amber-200',
  picked_up: 'bg-indigo-100 text-indigo-800 ring-indigo-200',
  in_transit: 'bg-violet-100 text-violet-800 ring-violet-200',
  delivered: 'bg-emerald-100 text-emerald-800 ring-emerald-200',
  cancelled: 'bg-red-100 text-red-800 ring-red-200',
  returned: 'bg-orange-100 text-orange-800 ring-orange-200',
  // bids
  open: 'bg-amber-100 text-amber-800 ring-amber-200',
  accepted: 'bg-emerald-100 text-emerald-800 ring-emerald-200',
  expired: 'bg-stone-200 text-stone-700 ring-stone-300',
  countered: 'bg-sky-100 text-sky-800 ring-sky-200',
  // roles / misc
  admin: 'bg-trega-100 text-trega-700 ring-trega-200',
  seller: 'bg-gold-300/40 text-gold-600 ring-gold-400/40',
  buyer: 'bg-stone-200 text-stone-700 ring-stone-300',
  active: 'bg-emerald-100 text-emerald-800 ring-emerald-200',
  inactive: 'bg-stone-200 text-stone-700 ring-stone-300',
};

export function prettyStatus(value: string): string {
  return value
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

export default function StatusBadge({ value }: { value: string }) {
  const tone = TONES[value] ?? 'bg-stone-200 text-stone-700 ring-stone-300';
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ring-inset ${tone}`}
    >
      {prettyStatus(value)}
    </span>
  );
}
