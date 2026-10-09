import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useReports, rejectListing } from '../lib/firestore';
import type { Report } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import StatusBadge from '../components/StatusBadge';
import { formatDateTime, timeAgo } from '../utils/format';

const PAGE_SIZE = 20;

/** User-submitted listing reports. Reports themselves are write-protected
 *  (firestore.rules denies update/delete, even for admins), so there is no
 *  dismiss action — moderation happens on the reported listing. */
export default function Reports() {
  const [page, setPage] = useState(1);
  const { rows, total, loading, error, refresh } = useReports(page, PAGE_SIZE);
  const [actingId, setActingId] = useState<string | null>(null);

  const takeDown = async (r: Report) => {
    const reason = `Removed after user report: ${r.reason}`;
    if (
      !window.confirm(
        `Take down "${r.listingTitle}"?\n\nThe listing will be rejected and hidden from the app.\nReason: ${reason}`,
      )
    ) {
      return;
    }
    setActingId(r.id);
    try {
      await rejectListing(r.listingId, reason);
      refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Take-down failed.');
    } finally {
      setActingId(null);
    }
  };

  const columns: Column<Report>[] = [
    {
      key: 'listing',
      header: 'Reported listing',
      render: (r) => (
        <Link
          to={`/listings/${r.listingId}`}
          title={r.listingId}
          className="block max-w-xs truncate font-medium text-trega-600 hover:underline"
        >
          {r.listingTitle}
        </Link>
      ),
    },
    { key: 'reason', header: 'Reason', render: (r) => <StatusBadge value={r.reason} /> },
    {
      key: 'reporter',
      header: 'Reporter',
      render: (r) => <span>{r.reporterName}</span>,
    },
    {
      key: 'date',
      header: 'Reported',
      render: (r) => (
        <span title={formatDateTime(r.createdAt)} className="text-stone-600">
          {timeAgo(r.createdAt)}
        </span>
      ),
    },
    {
      key: 'action',
      header: 'Action',
      render: (r) => (
        <button
          onClick={() => void takeDown(r)}
          disabled={actingId !== null}
          className="rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-red-700 disabled:opacity-50"
        >
          {actingId === r.id ? 'Taking down…' : 'Take down'}
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Listing Reports</h1>
        <p className="text-sm text-stone-500">
          Listings flagged by users. Reports can't be dismissed or deleted from this
          panel — if a report has no merit, take no action.
        </p>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      <DataTable
        columns={columns}
        rows={rows}
        keyOf={(r) => r.id}
        loading={loading}
        emptyMessage="No reports."
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
