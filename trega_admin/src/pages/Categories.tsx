import { useState } from 'react';
import type { FormEvent } from 'react';
import { useCategories, upsertCategory, deleteCategory } from '../lib/firestore';
import type { Category } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import StatusBadge from '../components/StatusBadge';
import Modal from '../components/Modal';

export default function Categories() {
  const { rows, loading, error } = useCategories();
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<Category | null>(null);
  const [name, setName] = useState('');
  const [icon, setIcon] = useState('');
  const [active, setActive] = useState(true);
  const [saving, setSaving] = useState(false);

  const openAdd = () => {
    setEditing(null);
    setName('');
    setIcon('');
    setActive(true);
    setModalOpen(true);
  };

  const openEdit = (c: Category) => {
    setEditing(c);
    setName(c.name);
    setIcon(c.icon ?? '');
    setActive(c.active);
    setModalOpen(true);
  };

  const save = async (e: FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    setSaving(true);
    try {
      await upsertCategory({
        id: editing?.id,
        name: name.trim(),
        icon: icon.trim() || undefined,
        active,
        sortOrder: editing?.sortOrder ?? rows.length,
      });
      setModalOpen(false);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Save failed.');
    } finally {
      setSaving(false);
    }
  };

  const remove = async (c: Category) => {
    if (!confirm(`Delete the "${c.name}" category? Listings in it must be moved first.`)) return;
    try {
      await deleteCategory(c.id);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Delete failed.');
    }
  };

  const columns: Column<Category>[] = [
    {
      key: 'name',
      header: 'Category',
      render: (c) => (
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-lg bg-trega-50 text-lg">
            {c.icon || '▦'}
          </span>
          <div>
            <div className="font-medium text-stone-900">{c.name}</div>
            <div className="text-xs text-stone-500">/{c.slug}</div>
          </div>
        </div>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      render: (c) => <StatusBadge value={c.active ? 'active' : 'inactive'} />,
    },
    {
      key: 'actions',
      header: '',
      render: (c) => (
        <div className="flex justify-end gap-2">
          <button
            onClick={() => openEdit(c)}
            className="rounded-lg bg-trega-100 px-3 py-1.5 text-xs font-semibold text-trega-700 hover:bg-trega-200"
          >
            Edit
          </button>
          <button
            onClick={() => void remove(c)}
            className="rounded-lg bg-red-100 px-3 py-1.5 text-xs font-semibold text-red-700 hover:bg-red-200"
          >
            Delete
          </button>
        </div>
      ),
      className: 'text-right',
    },
  ];

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-stone-900">Categories</h1>
          <p className="text-sm text-stone-500">These power the "Explore by Passion" sections in the app.</p>
        </div>
        <button
          onClick={openAdd}
          className="rounded-lg bg-trega-600 px-4 py-2 text-sm font-semibold text-white hover:bg-trega-700"
        >
          + Add category
        </button>
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      <DataTable
        columns={columns}
        rows={rows}
        keyOf={(c) => c.id}
        loading={loading}
        emptyMessage="No categories yet."
      />

      {modalOpen && (
        <Modal title={editing ? 'Edit category' : 'Add category'} onClose={() => setModalOpen(false)}>
          <form onSubmit={save} className="space-y-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">Name</label>
              <input
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g. Gaming"
                className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
              />
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium text-stone-700">
                Icon <span className="font-normal text-stone-400">(emoji or glyph)</span>
              </label>
              <input
                value={icon}
                onChange={(e) => setIcon(e.target.value)}
                placeholder="🎮"
                maxLength={4}
                className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
              />
            </div>
            <label className="flex items-center gap-2 text-sm text-stone-700">
              <input
                type="checkbox"
                checked={active}
                onChange={(e) => setActive(e.target.checked)}
                className="h-4 w-4 accent-[#8b3a1c]"
              />
              Visible in the app
            </label>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                className="flex-1 rounded-lg border border-stone-300 px-4 py-2.5 text-sm font-semibold text-stone-700 hover:bg-stone-100"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={saving || !name.trim()}
                className="flex-1 rounded-lg bg-trega-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-trega-700 disabled:opacity-60"
              >
                {saving ? 'Saving…' : editing ? 'Save changes' : 'Add category'}
              </button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
