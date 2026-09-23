import { useState } from 'react';
import type { FormEvent } from 'react';
import { useUsers, setUserKyc } from '../lib/firestore';
import type { AdminUser } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import StatusBadge from '../components/StatusBadge';
import Modal from '../components/Modal';
import { formatDate } from '../utils/format';

const PAGE_SIZE = 20;
const TABS: Array<{ key: string; label: string }> = [
  { key: 'all', label: 'All' },
  { key: 'pending', label: 'KYC Pending' },
  { key: 'verified', label: 'Verified' },
  { key: 'rejected', label: 'Rejected' },
  { key: 'unverified', label: 'Unverified' },
];

export default function Users() {
  const [kyc, setKyc] = useState('all');
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [actingId, setActingId] = useState<string | null>(null);
  const [rejectUser, setRejectUser] = useState<AdminUser | null>(null);
  const [note, setNote] = useState('');
  const { rows, total, loading, error, refresh } = useUsers(kyc, page, PAGE_SIZE, query);

  const verify = async (u: AdminUser, status: 'verified' | 'rejected', kycNote?: string) => {
    if (status === 'verified' && !confirm(`Mark ${u.name} as a verified seller?`)) return;
    setActingId(u.id);
    try {
      await setUserKyc(u.id, status, kycNote);
      refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Action failed.');
    } finally {
      setActingId(null);
      setRejectUser(null);
      setNote('');
    }
  };

  const rejectSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (rejectUser) void verify(rejectUser, 'rejected', note.trim() || undefined);
  };

  const columns: Column<AdminUser>[] = [
    {
      key: 'user',
      header: 'User',
      render: (u) => (
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-trega-100 font-bold text-trega-700">
            {u.avatarUrl ? (
              <img src={u.avatarUrl} alt="" className="h-full w-full rounded-full object-cover" />
            ) : (
              u.name.charAt(0).toUpperCase()
            )}
          </div>
          <div>
            <div className="font-medium text-stone-900">
              {u.name} {u.verifiedSeller && <span className="text-emerald-600">✓</span>}
            </div>
            <div className="text-xs text-stone-500">{u.phone ?? u.id}</div>
          </div>
        </div>
      ),
    },
    { key: 'role', header: 'Role', render: (u) => <StatusBadge value={u.role} /> },
    { key: 'kyc', header: 'KYC', render: (u) => <StatusBadge value={u.kycStatus} /> },
    {
      key: 'note',
      header: 'KYC note',
      render: (u) => <span className="max-w-xs truncate text-xs text-stone-500">{u.kycNote ?? '—'}</span>,
    },
    { key: 'joined', header: 'Joined', render: (u) => <span className="text-stone-600">{u.createdAt ? formatDate(u.createdAt) : '—'}</span> },
    {
      key: 'actions',
      header: 'Actions',
      render: (u) =>
        actingId === u.id ? (
          <span className="text-sm text-stone-500">Working…</span>
        ) : (
          <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
            {u.kycStatus !== 'verified' && (
              <button
                onClick={() => void verify(u, 'verified')}
                className="rounded-lg bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700"
              >
                Verify
              </button>
            )}
            {u.kycStatus !== 'rejected' && (
              <button
                onClick={() => setRejectUser(u)}
                className="rounded-lg bg-red-100 px-3 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-200"
              >
                Reject
              </button>
            )}
          </div>
        ),
    },
  ];

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Users</h1>
        <p className="text-sm text-stone-500">Verify sellers and manage KYC status.</p>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      <div className="flex flex-wrap gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            onClick={() => {
              setKyc(t.key);
              setPage(1);
            }}
            className={`rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
              kyc === t.key
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
          placeholder="Search name or phone…"
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
        keyOf={(u) => u.id}
        loading={loading}
        emptyMessage="No users found."
        pagination={{
          page,
          totalPages: Math.max(1, Math.ceil(total / PAGE_SIZE)),
          total,
          onPage: setPage,
        }}
      />

      {rejectUser && (
        <Modal title={`Reject KYC — ${rejectUser.name}`} onClose={() => setRejectUser(null)}>
          <form onSubmit={rejectSubmit} className="space-y-4">
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={3}
              placeholder="Reason (optional)…"
              className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
            />
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setRejectUser(null)}
                className="flex-1 rounded-lg border border-stone-300 px-4 py-2.5 text-sm font-semibold text-stone-700 hover:bg-stone-100"
              >
                Cancel
              </button>
              <button
                type="submit"
                className="flex-1 rounded-lg bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700"
              >
                Confirm reject
              </button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
