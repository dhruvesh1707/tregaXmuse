import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import { useOrders, updateOrder, retryShipment, fetchDispute, resolveDispute, markSettlementPaid } from '../lib/firestore';
import type { Dispute, Order, OrderStatus } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import StatusBadge, { prettyStatus } from '../components/StatusBadge';
import Modal from '../components/Modal';
import { formatAddressLines, formatINR, timeAgo } from '../utils/format';

const PAGE_SIZE = 20;
const TABS: Array<{ key: string; label: string }> = [
  { key: 'all', label: 'All' },
  { key: 'placed', label: 'Placed' },
  { key: 'pickup_scheduled', label: 'Pickup scheduled' },
  { key: 'picked_up', label: 'Picked up' },
  { key: 'in_transit', label: 'In transit' },
  { key: 'delivered', label: 'Delivered' },
  { key: 'cancelled', label: 'Cancelled' },
  { key: 'reports', label: 'Reports' },
];

const ORDER_STATUSES: OrderStatus[] = [
  'placed',
  'pickup_scheduled',
  'picked_up',
  'in_transit',
  'out_for_delivery',
  'delivered',
  'cancelled',
  'returned',
];

const SETTLEMENT_LABELS: Record<string, string> = {
  pending: 'Pending, inside the 72 hour support window',
  eligible: 'Eligible, ready to pay out',
  held: 'On hold',
  paid: 'Paid',
  cancelled: 'Cancelled (refunded)',
};

const DISPUTE_REASON_LABELS: Record<string, string> = {
  not_as_described: 'Item not as described',
  damaged: 'Damaged or defective',
  wrong_item: 'Wrong item received',
  other: 'Something else',
};

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
  const [expressOnly, setExpressOnly] = useState(false);
  const [newStatus, setNewStatus] = useState<OrderStatus>('placed');
  const [trackingNote, setTrackingNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const [dispute, setDispute] = useState<Dispute | null | undefined>(undefined);
  const [resolveNote, setResolveNote] = useState('');
  const [refundReference, setRefundReference] = useState('');
  const [settlementReference, setSettlementReference] = useState('');
  const [resolving, setResolving] = useState(false);
  const [paying, setPaying] = useState(false);
  const { rows, total, loading, error, refresh } = useOrders(status, page, PAGE_SIZE, query, expressOnly);

  const editingId = editing?.id;
  useEffect(() => {
    if (!editingId) {
      setDispute(undefined);
      return;
    }
    let cancelled = false;
    setDispute(undefined);
    setResolveNote('');
    setRefundReference('');
    setSettlementReference('');
    void fetchDispute(editingId).then((d) => {
      if (!cancelled) setDispute(d);
    });
    return () => {
      cancelled = true;
    };
  }, [editingId]);

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

  const retry = async () => {
    if (!editing) return;
    setRetrying(true);
    try {
      await retryShipment(editing.id);
      setEditing(null);
      refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Retry failed.');
    } finally {
      setRetrying(false);
    }
  };

  const resolve = async (decision: 'buyer' | 'seller') => {
    if (!editing) return;
    setResolving(true);
    try {
      await resolveDispute(
        editing.id,
        decision,
        resolveNote.trim() || undefined,
        refundReference.trim() || undefined,
      );
      setEditing(null);
      refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Resolution failed.');
    } finally {
      setResolving(false);
    }
  };

  const markPaid = async () => {
    if (!editing || !settlementReference.trim()) return;
    setPaying(true);
    try {
      await markSettlementPaid(editing.id, settlementReference.trim());
      setEditing(null);
      refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Update failed.');
    } finally {
      setPaying(false);
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
    {
      key: 'delivery',
      header: 'Delivery',
      render: (o) =>
        o.deliveryType === 'express' ? (
          <span className="inline-flex items-center rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-semibold text-amber-800 ring-1 ring-inset ring-amber-200">
            ⚡ Express
          </span>
        ) : (
          <span className="inline-flex items-center rounded-full bg-stone-100 px-2.5 py-0.5 text-xs font-medium text-stone-600 ring-1 ring-inset ring-stone-200">
            Standard
          </span>
        ),
    },
    { key: 'status', header: 'Status', render: (o) => (
      <span className="inline-flex flex-wrap items-center gap-1.5">
        <StatusBadge value={o.status} />
        {o.disputeStatus === 'open' && (
          <span className="inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-800 ring-1 ring-inset ring-red-200">
            Report
          </span>
        )}
      </span>
    ) },
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
        <button
          onClick={() => {
            setExpressOnly((v) => !v);
            setPage(1);
          }}
          className={`rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
            expressOnly
              ? 'bg-amber-500 text-white'
              : 'bg-white text-stone-600 ring-1 ring-stone-300 hover:bg-stone-100'
          }`}
        >
          ⚡ Express only
        </button>
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
              <div className="mt-1 text-xs">
                {editing.deliveryType === 'express' ? (
                  <span className="font-semibold text-amber-700">
                    ⚡ Express delivery: book same-day courier for this order
                  </span>
                ) : (
                  <span className="text-stone-500">Delivery: Standard</span>
                )}
              </div>
              <div className="mt-3 grid gap-3 border-t border-stone-200 pt-3 sm:grid-cols-2">
                <div>
                  <div className="mb-1 text-xs font-semibold text-stone-700">
                    Pick up from (seller)
                  </div>
                  {editing.pickupAddress ? (
                    <div className="text-xs leading-relaxed text-stone-600">
                      {formatAddressLines(editing.pickupAddress).map((line) => (
                        <div key={line}>{line}</div>
                      ))}
                    </div>
                  ) : (
                    <div className="text-xs text-stone-400">
                      No pickup address saved for this listing.
                    </div>
                  )}
                </div>
                <div>
                  <div className="mb-1 text-xs font-semibold text-stone-700">
                    Deliver to (buyer)
                  </div>
                  {editing.deliveryAddress ? (
                    <div className="text-xs leading-relaxed text-stone-600">
                      {formatAddressLines(editing.deliveryAddress).map((line) => (
                        <div key={line}>{line}</div>
                      ))}
                    </div>
                  ) : (
                    <div className="text-xs text-stone-400">
                      No delivery address on this order.
                    </div>
                  )}
                </div>
              </div>
              <div className="mt-3 border-t border-stone-200 pt-3">
                <div className="mb-1 text-xs font-semibold text-stone-700">
                  Shipment (Shiprocket)
                </div>
                {editing.awbCode ? (
                  <div className="text-xs leading-relaxed text-stone-600">
                    <div>
                      {editing.courierName} · AWB {editing.awbCode}
                    </div>
                    {editing.etd && <div>Expected by {editing.etd}</div>}
                    {editing.pickupScheduledDate && (
                      <div>Pickup: {editing.pickupScheduledDate}</div>
                    )}
                  </div>
                ) : editing.shipmentStatus === 'failed' ? (
                  <div className="text-xs leading-relaxed">
                    <div className="text-red-600">
                      Shipment failed
                      {editing.shipmentStep
                        ? ` at ${editing.shipmentStep}`
                        : ''}
                      .
                    </div>
                    {editing.shipmentError && (
                      <div className="text-stone-600">
                        {editing.shipmentError}
                      </div>
                    )}
                    <button
                      type="button"
                      onClick={retry}
                      disabled={retrying}
                      className="mt-2 rounded-lg bg-trega-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-trega-700 disabled:opacity-60"
                    >
                      {retrying ? 'Retrying…' : 'Retry shipment'}
                    </button>
                  </div>
                ) : editing.shipmentStatus === 'creating' ? (
                  <div className="text-xs text-stone-400">
                    Shipment is being created…
                  </div>
                ) : (
                  <div className="text-xs text-stone-400">
                    No shipment yet. Created automatically when the order is
                    paid.
                  </div>
                )}
              </div>
              {editing.paymentStatus === 'SUCCESS' && (
                <div className="mt-3 border-t border-stone-200 pt-3">
                  <div className="mb-1 text-xs font-semibold text-stone-700">
                    Settlement (seller payout)
                  </div>
                  <div className="text-xs leading-relaxed text-stone-600">
                    <div>
                      Payout:{' '}
                      {editing.sellerPayout != null
                        ? formatINR(editing.sellerPayout)
                        : '-'}
                      {' · '}
                      {editing.settlementStatus
                        ? SETTLEMENT_LABELS[editing.settlementStatus] ??
                          editing.settlementStatus
                        : 'No payout record yet'}
                    </div>
                    <div>
                      UPI: {editing.payoutUpi ?? 'not saved by the seller'}
                    </div>
                    {editing.settlementStatus === 'paid' && (
                      <div>
                        Paid {editing.settlementPaidAt
                          ? timeAgo(editing.settlementPaidAt)
                          : ''}
                        {editing.settlementReference
                          ? ` · Ref ${editing.settlementReference}`
                          : ''}
                      </div>
                    )}
                    {editing.refundStatus === 'refunded' && (
                      <div>
                        Refunded to the buyer
                        {editing.refundReference
                          ? ` · Ref ${editing.refundReference}`
                          : ''}
                      </div>
                    )}
                  </div>
                  {(editing.settlementStatus === 'eligible' ||
                    (editing.settlementStatus == null &&
                      editing.status === 'delivered' &&
                      editing.disputeStatus !== 'open')) && (
                    <div className="mt-2 flex gap-2">
                      <input
                        value={settlementReference}
                        onChange={(e) => setSettlementReference(e.target.value)}
                        placeholder="UPI payment reference"
                        className="w-full rounded-lg border border-stone-300 bg-white px-3 py-1.5 text-xs outline-none focus:border-trega-500"
                      />
                      <button
                        type="button"
                        onClick={markPaid}
                        disabled={paying || !settlementReference.trim()}
                        className="shrink-0 rounded-lg bg-trega-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-trega-700 disabled:opacity-60"
                      >
                        {paying ? 'Saving…' : 'Mark paid'}
                      </button>
                    </div>
                  )}
                  {editing.settlementStatus === 'held' && (
                    <div className="mt-1 text-xs text-amber-700">
                      Payout is on hold until the open report is resolved.
                    </div>
                  )}
                </div>
              )}
              {dispute && (
                <div className="mt-3 border-t border-stone-200 pt-3">
                  <div className="mb-1 text-xs font-semibold text-stone-700">
                    Delivery report · {DISPUTE_REASON_LABELS[dispute.reason] ?? dispute.reason}
                  </div>
                  <div className="text-xs leading-relaxed text-stone-600">
                    <div>{dispute.description}</div>
                    <div className="mt-1 text-stone-400">
                      Filed {timeAgo(dispute.filedAt)} · Status: {dispute.status}
                    </div>
                    {dispute.resolutionNote && (
                      <div className="mt-1">Note: {dispute.resolutionNote}</div>
                    )}
                  </div>
                  {dispute.photoUrls.length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-2">
                      {dispute.photoUrls.map((url) => (
                        <a key={url} href={url} target="_blank" rel="noreferrer">
                          <img
                            src={url}
                            alt="Report evidence"
                            className="h-16 w-16 rounded-lg object-cover ring-1 ring-stone-200"
                          />
                        </a>
                      ))}
                    </div>
                  )}
                  {dispute.status === 'open' && (
                    <div className="mt-3 space-y-2">
                      <input
                        value={resolveNote}
                        onChange={(e) => setResolveNote(e.target.value)}
                        placeholder="Resolution note (optional)"
                        className="w-full rounded-lg border border-stone-300 bg-white px-3 py-1.5 text-xs outline-none focus:border-trega-500"
                      />
                      <input
                        value={refundReference}
                        onChange={(e) => setRefundReference(e.target.value)}
                        placeholder="Refund reference (only when resolving for the buyer)"
                        className="w-full rounded-lg border border-stone-300 bg-white px-3 py-1.5 text-xs outline-none focus:border-trega-500"
                      />
                      <p className="text-xs text-stone-400">
                        Resolving for the buyer records the refund here; the
                        money itself is returned through the Cashfree
                        dashboard. Resolving for the seller releases the
                        payout at once.
                      </p>
                      <div className="flex gap-2">
                        <button
                          type="button"
                          onClick={() => resolve('buyer')}
                          disabled={resolving}
                          className="flex-1 rounded-lg bg-red-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-red-700 disabled:opacity-60"
                        >
                          {resolving ? 'Saving…' : 'Resolve for buyer (refund)'}
                        </button>
                        <button
                          type="button"
                          onClick={() => resolve('seller')}
                          disabled={resolving}
                          className="flex-1 rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                        >
                          {resolving ? 'Saving…' : 'Resolve for seller'}
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )}
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
