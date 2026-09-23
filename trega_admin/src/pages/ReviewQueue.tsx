import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useReviewQueue, useCategories } from '../lib/firestore';
import type { Listing } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import { formatINR, formatDateTime, timeAgo, conditionLabel } from '../utils/format';

const PAGE_SIZE = 20;

export default function ReviewQueue() {
  const navigate = useNavigate();
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const { map: categories } = useCategories();
  const { rows, total, loading, error } = useReviewQueue(page, PAGE_SIZE, query, categories);

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
      render: (l) => (
        <div>
          <div className="font-medium">{l.seller.name}</div>
          <div className="text-xs text-stone-500">KYC: {l.seller.kycStatus}</div>
        </div>
      ),
    },
    {
      key: 'price',
      header: 'Price',
      render: (l) => <span className="font-semibold text-trega-700">{formatINR(l.price)}</span>,
    },
    {
      key: 'submitted',
      header: 'Submitted',
      render: (l) => (
        <span title={formatDateTime(l.submittedAt || l.createdAt)} className="text-stone-600">
          {timeAgo(l.submittedAt || l.createdAt)}
        </span>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Review Queue</h1>
        <p className="text-sm text-stone-500">
          New listings must be approved before they go live in the app.
        </p>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

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
        emptyMessage="No listings waiting for review."
        onRowClick={(l) => navigate(`/review/${l.id}`)}
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
