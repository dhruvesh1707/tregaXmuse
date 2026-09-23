import { useEffect, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { collection, getCountFromServer, query, where } from 'firebase/firestore';
import { useAuth } from '../auth/AuthContext';
import { db } from '../lib/firebase';

const NAV = [
  { to: '/', label: 'Dashboard', end: true, icon: '▦' },
  { to: '/review', label: 'Review Queue', icon: '✓' },
  { to: '/listings', label: 'All Listings', icon: '▤' },
  { to: '/users', label: 'Users', icon: '◉' },
  { to: '/orders', label: 'Orders', icon: '▣' },
  { to: '/bids', label: 'Bids & Offers', icon: '◈' },
  { to: '/categories', label: 'Categories', icon: '▦' },
];

export default function Layout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [pendingCount, setPendingCount] = useState<number | null>(null);

  useEffect(() => {
    getCountFromServer(
      query(collection(db, 'listings'), where('status', '==', 'pending')),
    )
      .then((s) => setPendingCount(s.data().count))
      .catch(() => setPendingCount(null));
  }, []);

  const sidebar = (
    <div className="flex h-full flex-col">
      <button
        onClick={() => {
          setSidebarOpen(false);
          navigate('/');
        }}
        className="flex items-center gap-3 border-b border-trega-800 px-5 py-4"
      >
        <img src="/logo.png" alt="Trega" className="h-9 w-auto bg-white rounded-md px-1" />
        <div className="text-left">
          <div className="text-sm font-bold text-white">Trega Admin</div>
          <div className="text-[11px] text-trega-200">Marketplace control</div>
        </div>
      </button>

      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
        {NAV.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            onClick={() => setSidebarOpen(false)}
            className={({ isActive }) =>
              `flex items-center justify-between rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${
                isActive
                  ? 'bg-gold-400 text-trega-900'
                  : 'text-trega-100 hover:bg-trega-700 hover:text-white'
              }`
            }
          >
            <span className="flex items-center gap-3">
              <span className="w-5 text-center">{item.icon}</span>
              {item.label}
            </span>
            {item.to === '/review' && pendingCount !== null && pendingCount > 0 && (
              <span className="rounded-full bg-red-500 px-2 py-0.5 text-[11px] font-bold text-white">
                {pendingCount}
              </span>
            )}
          </NavLink>
        ))}
      </nav>

      <div className="border-t border-trega-800 px-5 py-4">
        <div className="truncate text-sm font-medium text-white">Admin</div>
        <div className="truncate text-xs text-trega-200">{user?.phone}</div>
        <button
          onClick={logout}
          className="mt-3 w-full rounded-lg border border-trega-600 px-3 py-2 text-sm font-medium text-trega-100 transition-colors hover:bg-trega-700 hover:text-white"
        >
          Sign out
        </button>
      </div>
    </div>
  );

  return (
    <div className="flex min-h-screen">
      {/* Desktop sidebar */}
      <aside className="hidden w-64 shrink-0 bg-trega-800 lg:block">
        <div className="fixed inset-y-0 w-64">{sidebar}</div>
      </aside>

      {/* Mobile sidebar */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div
            className="absolute inset-0 bg-black/50"
            onClick={() => setSidebarOpen(false)}
          />
          <aside className="absolute inset-y-0 left-0 w-64 bg-trega-800">
            {sidebar}
          </aside>
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Topbar (mobile) */}
        <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-stone-200 bg-white px-4 py-3 lg:hidden">
          <button
            onClick={() => setSidebarOpen(true)}
            className="rounded-md p-2 text-stone-600 hover:bg-stone-100"
            aria-label="Open menu"
          >
            ☰
          </button>
          <img src="/logo.png" alt="Trega" className="h-7 w-auto" />
          <span className="text-sm font-bold text-trega-700">Trega Admin</span>
        </header>

        <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 sm:px-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
