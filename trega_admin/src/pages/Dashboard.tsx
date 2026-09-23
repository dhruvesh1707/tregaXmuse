import { Link } from 'react-router-dom';
import { useDashboard } from '../lib/firestore';
import StatCard from '../components/StatCard';
import StatusBadge from '../components/StatusBadge';
import { formatINR, timeAgo } from '../utils/format';

export default function Dashboard() {
  const { stats, pending, orders, loading, error } = useDashboard();

  if (error) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 p-6 text-sm text-red-700">
        <p className="font-semibold">Could not load dashboard data.</p>
        <p className="mt-1">{error}</p>
        <p className="mt-2 text-xs">
          Check that your <code>.env</code> has the Firebase web config (see README) and that
          Firestore rules are deployed.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Dashboard</h1>
        <p className="text-sm text-stone-500">Marketplace health at a glance</p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Pending review"
          value={loading || !stats ? '—' : String(stats.pendingReview)}
          sub="Listings waiting for approval"
          icon="✓"
          accent
        />
        <StatCard
          label="Live listings"
          value={loading || !stats ? '—' : String(stats.liveListings)}
          sub="Currently visible in the app"
          icon="▤"
        />
        <StatCard
          label="Sold this month"
          value={loading || !stats ? '—' : String(stats.soldThisMonth)}
          sub="Completed sales"
          icon="◈"
        />
        <StatCard
          label="GMV this month"
          value={loading || !stats ? '—' : formatINR(stats.gmvThisMonth)}
          sub="Paid orders (Cashfree)"
          icon="₹"
        />
        <StatCard
          label="Total users"
          value={loading || !stats ? '—' : String(stats.totalUsers)}
          sub="Buyers + sellers"
          icon="◉"
        />
        <StatCard
          label="Orders in transit"
          value={loading || !stats ? '—' : String(stats.ordersInTransit)}
          sub="Pickup / delivery in progress"
          icon="▣"
        />
        <StatCard
          label="Bids today"
          value={loading || !stats ? '—' : String(stats.bidsToday)}
          sub="Bids & offers placed today"
          icon="◈"
        />
      </div>

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-2">
        <div className="rounded-xl border border-stone-200 bg-white p-5 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-base font-bold text-stone-900">Awaiting review</h2>
            <Link to="/review" className="text-sm font-medium text-trega-600 hover:underline">
              View queue →
            </Link>
          </div>
          {loading ? (
            <p className="py-6 text-center text-sm text-stone-500">Loading…</p>
          ) : pending.length === 0 ? (
            <p className="py-6 text-center text-sm text-stone-500">Queue is clear. 🎉</p>
          ) : (
            <ul className="divide-y divide-stone-100">
              {pending.map((l) => (
                <li key={l.id}>
                  <Link
                    to={`/review/${l.id}`}
                    className="flex items-center gap-3 py-3 hover:bg-trega-50 rounded-lg px-2"
                  >
                    <div className="h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-stone-200">
                      {l.photos[0] && (
                        <img src={l.photos[0]} alt="" className="h-full w-full object-cover" />
                      )}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm font-medium text-stone-900">{l.title}</div>
                      <div className="text-xs text-stone-500">
                        {l.seller.name} · {timeAgo(l.submittedAt || l.createdAt)}
                      </div>
                    </div>
                    <div className="text-sm font-semibold text-trega-700">{formatINR(l.price)}</div>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="rounded-xl border border-stone-200 bg-white p-5 shadow-sm">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-base font-bold text-stone-900">Recent orders</h2>
            <Link to="/orders" className="text-sm font-medium text-trega-600 hover:underline">
              View all →
            </Link>
          </div>
          {loading ? (
            <p className="py-6 text-center text-sm text-stone-500">Loading…</p>
          ) : orders.length === 0 ? (
            <p className="py-6 text-center text-sm text-stone-500">No orders yet.</p>
          ) : (
            <ul className="divide-y divide-stone-100">
              {orders.map((o) => (
                <li key={o.id} className="flex items-center gap-3 py-3">
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-medium text-stone-900">
                      {o.listingTitle}
                    </div>
                    <div className="text-xs text-stone-500">
                      {o.buyerName} → {formatINR(o.amount)} · {timeAgo(o.createdAt)}
                    </div>
                  </div>
                  <StatusBadge value={o.status} />
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}
