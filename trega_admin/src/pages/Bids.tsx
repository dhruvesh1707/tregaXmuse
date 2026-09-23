import { useState } from 'react';
import { useBids } from '../lib/firestore';
import type { Bid } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import StatusBadge from '../components/StatusBadge';
import { formatINR, timeAgo } from '../utils/format';

const PAGE_SIZE = 20;
const TABS: Array<{ key: string; label: string }> = [
  { key: 'all', label: 'All' },
  { key: 'open', label: 'Open' },
  { key: 'accepted', label: 'Accepted' },
  { key: 'rejected', label: 'Rejected' },
  { key: 'expired', label: 'Expired' },
];

export default function Bids() {
  const [status, setStatus] = useState('all');
  const [page, setPage] = useState(1);
  const { rows, total, loading, error } = useBids(status, page, PAGE_SIZE);

  const columns: Column<Bid>[] = [
    {
      key: 'listing',
      header: 'Listing',
      render: (b) => (
        <div>
          <div className="max-w-xs truncate font-medium text-stone-900">{b.listingTitle}</div>
          <div className="text-xs text-stone-500">Asking {formatINR(b.listingPrice)}</div>
        </div>
      ),
    },
    {
      key: 'bidder',
      header: 'Bidder',
      render: (b) => <span>{b.buyerName}</span>,
    },
    {
      key: 'amount',
      header: 'Amount',
      render: (b) => (
        <div>
          <div className="font-semibold text-trega-700">{formatINR(b.amount)}</div>
          {b.counterAmount != null && (
            <div className="text-xs text-stone-500">Counter: {formatINR(b.counterAmount)}</div>
          )}
        </div>
      ),
    },
    { key: 'status', header: 'Status', render: (b) => <StatusBadge value={b.status} /> },
    {
      key: 'placed',
      header: 'Placed',
      render: (b) => <span className="text-stone-600">{timeAgo(b.createdAt)}</span>,
    },
  ];

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Bids & Offers</h1>
        <p className="text-sm text-stone-500">
          Structured bids are created by the app through Cloud Functions — no chat, no manual bids here.
        </p>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      <div className="flex flex-wrap gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            onClick={() => {
              setStatus(t.key);
              setPage(1);
            }}
            className={`rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
              status === t.key
                ? 'bg-trega-600 text-white'
                : 'bg-white text-stone-600 ring-1 ring-stone-300 hover:bg-stone-100'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <DataTable
        columns={columns}
        rows={rows}
        keyOf={(b) => b.id}
        loading={loading}
        emptyMessage="No bids found."
        pagination={{
          page,
          totalPages: Math.max(1, Math.ceil(total / PAGE_SIZE)),
          total,
          onPage: setPage,
        }}
      />
    </div>
  );
}
