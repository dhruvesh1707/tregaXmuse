import type { ReactNode } from 'react';

export default function StatCard({
  label,
  value,
  sub,
  icon,
  accent,
}: {
  label: string;
  value: string;
  sub?: string;
  icon: ReactNode;
  accent?: boolean;
}) {
  return (
    <div
      className={`rounded-xl border bg-white p-5 shadow-sm ${
        accent ? 'border-gold-400/60 ring-1 ring-gold-400/40' : 'border-stone-200'
      }`}
    >
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-stone-500">{label}</span>
        <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-trega-50 text-lg text-trega-600">
          {icon}
        </span>
      </div>
      <div className="mt-2 text-2xl font-bold text-stone-900">{value}</div>
      {sub && <div className="mt-1 text-xs text-stone-500">{sub}</div>}
    </div>
  );
}
