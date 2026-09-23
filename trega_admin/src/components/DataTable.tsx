import type { ReactNode } from 'react';

export interface Column<T> {
  key: string;
  header: string;
  render: (row: T) => ReactNode;
  className?: string;
}

interface Pagination {
  page: number;
  totalPages: number;
  total: number;
  onPage: (page: number) => void;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  rows: T[];
  keyOf: (row: T) => string;
  loading?: boolean;
  emptyMessage?: string;
  onRowClick?: (row: T) => void;
  pagination?: Pagination;
}

export default function DataTable<T>({
  columns,
  rows,
  keyOf,
  loading,
  emptyMessage = 'No records found.',
  onRowClick,
  pagination,
}: DataTableProps<T>) {
  return (
    <div className="overflow-hidden rounded-xl border border-stone-200 bg-white shadow-sm">
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-stone-200 text-sm">
          <thead className="bg-stone-50">
            <tr>
              {columns.map((col) => (
                <th
                  key={col.key}
                  className={`px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-stone-500 ${col.className ?? ''}`}
                >
                  {col.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100">
            {loading ? (
              <tr>
                <td colSpan={columns.length} className="px-4 py-10 text-center text-stone-500">
                  Loading…
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td colSpan={columns.length} className="px-4 py-10 text-center text-stone-500">
                  {emptyMessage}
                </td>
              </tr>
            ) : (
              rows.map((row) => (
                <tr
                  key={keyOf(row)}
                  onClick={onRowClick ? () => onRowClick(row) : undefined}
                  className={onRowClick ? 'cursor-pointer hover:bg-trega-50' : undefined}
                >
                  {columns.map((col) => (
                    <td key={col.key} className={`px-4 py-3 align-middle ${col.className ?? ''}`}>
                      {col.render(row)}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {pagination && pagination.totalPages > 1 && (
        <div className="flex items-center justify-between border-t border-stone-200 bg-stone-50 px-4 py-3 text-sm">
          <span className="text-stone-500">
            {pagination.total} records · Page {pagination.page} of {pagination.totalPages}
          </span>
          <div className="flex gap-2">
            <button
              disabled={pagination.page <= 1}
              onClick={() => pagination.onPage(pagination.page - 1)}
              className="rounded-lg border border-stone-300 bg-white px-3 py-1.5 font-medium text-stone-700 disabled:opacity-40 hover:bg-stone-100"
            >
              ← Prev
            </button>
            <button
              disabled={pagination.page >= pagination.totalPages}
              onClick={() => pagination.onPage(pagination.page + 1)}
              className="rounded-lg border border-stone-300 bg-white px-3 py-1.5 font-medium text-stone-700 disabled:opacity-40 hover:bg-stone-100"
            >
              Next →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
