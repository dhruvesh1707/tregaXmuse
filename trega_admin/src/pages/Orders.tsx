import { useState } from 'react';
import type { FormEvent } from 'react';
import { useOrders, updateOrder } from '../lib/firestore';
import type { Order, OrderStatus } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import StatusBadge, { prettyStatus } from '../components/StatusBadge';
import Modal from '../components/Modal';
import { formatINR, timeAgo } from '../utils/format';

const PAGE_SIZE = 20;
const TABS: Array<{ key: string; label: string }> = [
  { key: 'all', label: 'All' },
  { key: 'placed', label: 'Placed' },
  { key: 'pickup_scheduled', label: 'Pickup scheduled' },
  { key: 'picked_up', label: 'Picked up' },
  { key: 'in_transit', label: 'In transit' },
  { key: 'delivered', label: 'Delivered' },
  { key: 'cancelled', label: 'Cancelled' },
];

const ORDER_STATUSES: OrderStatus[] = [
  'placed',
  'pickup_scheduled',
  'picked_up',
  'in_transit',
  'delivered',
  'cancelled',
  'returned',
];

const PAYMENT_TONE: Record<string, string> = {
  PENDING: 'bg-amber-100 text-amber-800 ring-amber-200',
  SUCCESS: 'bg-emerald-100 text-emerald-800 ring-emerald-200',
  FAILED: 'bg-red-100 text-red-800 ring-red-200',
  USER_DROPPED: 'bg-stone-200 text-stone-700 ring-stone-300',
};

export default function Orders() {
  const [status, setStatus] = useState('all');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [editing, setEditing] = useState<Order | null>(null);
  const [newStatus, setNewStatus] = useState<OrderStatus>('placed');
  const [trackingNote, setTrackingNote] = useState('');
  const [saving, setSaving] = useState(false);
  const { rows, total, loading, error, refresh } = useOrders(status, page, PAGE_SIZE, query);

  const openEdit = (o: Order) => {
    setEditing(o);
    setNewStatus(o.status);
    setTrackingNote(o.trackingNote ?? '');
  };

  const save = async (e: FormEvent) => {
    e.preventDefault();
    if (!editing) return;
    setSaving(true);
    try {
      await updateOrder(editing.id, newStatus, trackingNote.trim());
      setEditing(null);
      refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Update failed.');
    } finally {
      setSaving(false);
    }
  };

  const columns: Column<Order>[] = [
    {
      key: 'order',
      header: 'Order',
      render: (o) => (
        <div className="flex items-center gap-3">
          <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-stone-200">
            {o.listingThumb && (
              <img src={o.listingThumb} alt="" className="h-full w-full object-cover" />
            )}
          </div>
          <div className="min-w-0">
            <div className="max-w-xs truncate font-medium text-stone-900">{o.listingTitle}</div>
            <div className="text-xs text-stone-500">
              #{o.id.slice(0, 8)} · {timeAgo(o.createdAt)}
            </div>
          </div>
        </div>
      ),
    },
    {
      key: 'parties',
      header: 'Buyer / Seller',
      render: (o) => (
        <div className="text-xs">
          <div>{o.buyerName}</div>
          <div className="text-stone-500">→ {o.sellerName}</div>
        </div>
      ),
    },
    {
      key: 'amount',
      header: 'Amount',
      render: (o) => <span className="font-semibold text-trega-700">{formatINR(o.amount)}</span>,
    },
    {
      key: 'payment',
      header: 'Payment',
      render: (o) => (
        <span
          className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ring-inset ${
            PAYMENT_TONE[o.paymentStatus] ?? 'bg-stone-200 text-stone-700 ring-stone-300'
          }`}
        >
          {prettyStatus(o.paymentStatus.toLowerCase())}
        </span>
      ),
    },
    { key: 'status', header: 'Status', render: (o) => <StatusBadge value={o.status} /> },
    {
      key: 'actions',
      header: '',
      render: (o) => (
        <button
          onClick={(e) => {
            e.stopPropagation();
            openEdit(o);
          }}
          className="rounded-lg bg-trega-100 px-3 py-1.5 text-xs font-semibold text-trega-700 hover:bg-trega-200"
        >
          Update
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Orders & Fulfillment</h1>
        <p className="text-sm text-stone-500">Track pickup and doorstep delivery for every order.</p>
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
          placeholder="Search order, item or user…"
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
        keyOf={(o) => o.id}
        loading={loading}
        emptyMessage="No orders found."
        onRowClick={openEdit}
        pagination={{
          page,
          totalPages: Math.max(1, Math.ceil(total / PAGE_SIZE)),
          total,
          onPage: setPage,
        }}
      />

      {editing && (
        <Modal title={`Order #${editing.id.slice(0, 8)}`} onClose={() => setEditing(null)}>
          <form onSubmit={save} className="space-y-4">
            <div className="rounded-lg bg-stone-50 p-3 text-sm">
              <div className="font-medium text-stone-900">{editing.listingTitle}</div>
              <div className="text-xs text-stone-500">
                {editing.buyerName} → {editing.sellerName} · {formatINR(editing.amount)}
              </div>
              <div className="mt-1 text-xs text-stone-500">
                Payment: <StatusBadge value={editing.paymentStatus.toLowerCase()} />{' '}
                <span className="text-stone-400">(set by the Cashfree webhook)</span>
              </div>
            </div>

            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">Status</label>
              <select
                value={newStatus}
                onChange={(e) => setNewStatus(e.target.value as OrderStatus)}
                className="w-full rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm outline-none focus:border-trega-500"
              >
                {ORDER_STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {prettyStatus(s)}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">
                Tracking note <span className="font-normal text-stone-400">(visible to buyer)</span>
              </label>
              <textarea
                value={trackingNote}
                onChange={(e) => setTrackingNote(e.target.value)}
                rows={3}
                placeholder="e.g. Courier picked up, AWB 482913…"
                className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
              />
            </div>

            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setEditing(null)}
                className="flex-1 rounded-lg border border-stone-300 px-4 py-2.5 text-sm font-semibold text-stone-700 hover:bg-stone-100"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={saving}
                className="flex-1 rounded-lg bg-trega-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-trega-700 disabled:opacity-60"
              >
                {saving ? 'Saving…' : 'Save'}
              </button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
