import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useListings, useCategories } from '../lib/firestore';
import type { Listing } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import StatusBadge from '../components/StatusBadge';
import { formatINR, timeAgo, conditionLabel } from '../utils/format';

const PAGE_SIZE = 20;
const TABS: Array<{ key: string; label: string }> = [
  { key: 'all', label: 'All' },
  { key: 'pending', label: 'Pending' },
  { key: 'live', label: 'Live' },
  { key: 'sold', label: 'Sold' },
  { key: 'rejected', label: 'Rejected' },
];

export default function Listings() {
  const navigate = useNavigate();
  const [status, setStatus] = useState('all');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const { map: categories } = useCategories();
  const { rows, total, loading, error } = useListings(status, page, PAGE_SIZE, query, categories);

  const columns: Column<Listing>[] = [
    {
      key: 'item',
      header: 'Listing',
      render: (l) => (
        <div className="flex items-center gap-3">
          <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-stone-200">
            {l.photos[0] ? (
              <img src={l.photos[0]} alt="" className="h-full w-full object-cover" />
            ) : l.videoUrl ? (
              <span className="flex h-full w-full items-center justify-center text-stone-500">▶</span>
            ) : null}
          </div>
          <div className="min-w-0">
            <div className="max-w-xs truncate font-medium text-stone-900">{l.title}</div>
            <div className="text-xs text-stone-500">
              {l.categoryName} · {conditionLabel(l.condition)}
            </div>
          </div>
        </div>
      ),
    },
    {
      key: 'seller',
      header: 'Seller',
      render: (l) => <span>{l.seller.name}</span>,
    },
    {
      key: 'price',
      header: 'Price',
      render: (l) => <span className="font-semibold text-trega-700">{formatINR(l.price)}</span>,
    },
    {
      key: 'status',
      header: 'Status',
      render: (l) => <StatusBadge value={l.status} />,
    },
    {
      key: 'updated',
      header: 'Created',
      render: (l) => <span className="text-stone-600">{timeAgo(l.createdAt)}</span>,
    },
  ];

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">All Listings</h1>
        <p className="text-sm text-stone-500">Every listing on the marketplace, any status.</p>
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

      <form
        onSubmit={(e) => {
          e.preventDefault();
          setPage(1);
          setQuery(search.trim());
        }}
        className="flex max-w-md gap-2"
      >
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search title or seller…"
          className="w-full rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
        />
        <button
          type="submit"
          className="rounded-lg bg-trega-600 px-4 py-2 text-sm font-semibold text-white hover:bg-trega-700"
        >
          Search
        </button>
      </form>

      <DataTable
        columns={columns}
        rows={rows}
        keyOf={(l) => l.id}
        loading={loading}
        emptyMessage="No listings found."
        onRowClick={(l) => navigate(`/listings/${l.id}`)}
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
