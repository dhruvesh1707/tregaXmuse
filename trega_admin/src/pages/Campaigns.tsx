import { useState } from 'react';
import type { FormEvent } from 'react';
import {
  useCampaigns,
  useCategories,
  useListings,
  sendCampaign,
} from '../lib/firestore';
import type { Campaign } from '../api/types';
import DataTable from '../components/DataTable';
import type { Column } from '../components/DataTable';
import Modal from '../components/Modal';
import { formatINR, formatDateTime } from '../utils/format';

type LinkType = 'none' | 'listing' | 'category';
const HISTORY_PAGE_SIZE = 20;

const inputCls =
  'w-full rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100';

/**
 * Zomato-style broadcast composer: title + message + optional image +
 * optional deep link, sent to every user with a saved device token via
 * the sendCampaign callable. History below comes from `campaigns`.
 */
export default function Campaigns() {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [imageOk, setImageOk] = useState(true);
  const [linkType, setLinkType] = useState<LinkType>('none');
  const [listingId, setListingId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [sending, setSending] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  const { rows: categories, map: categoryMap } = useCategories();
  const { rows: liveListings } = useListings('live', 1, 100, '', categoryMap);
  const { rows, total, loading, error: historyError, refresh } = useCampaigns(page, HISTORY_PAGE_SIZE);

  const image = imageUrl.trim();
  const formValid =
    title.trim().length > 0 &&
    body.trim().length > 0 &&
    (image === '' || image.startsWith('https://')) &&
    (linkType !== 'listing' || listingId !== '') &&
    (linkType !== 'category' || categoryId !== '');

  const selectedListing = liveListings.find((l) => l.id === listingId);
  const selectedCategory = categories.find((c) => c.id === categoryId);
  const targetLabel =
    linkType === 'listing'
      ? `Listing: ${selectedListing?.title ?? ''}`
      : linkType === 'category'
        ? `Category: ${selectedCategory?.name ?? ''}`
        : 'Just opens the app';

  const openConfirm = (e: FormEvent) => {
    e.preventDefault();
    if (!formValid) return;
    setError(null);
    setResult(null);
    setConfirmOpen(true);
  };

  const doSend = async () => {
    setSending(true);
    try {
      const res = await sendCampaign({
        title: title.trim(),
        body: body.trim(),
        imageUrl: image || undefined,
        linkType,
        listingId: linkType === 'listing' ? listingId : undefined,
        categoryId: linkType === 'category' ? categoryId : undefined,
      });
      setResult(
        `Sent to ${res.sent} of ${res.recipients} devices.` +
          (res.failed > 0 ? ` ${res.failed} failed (unreachable tokens were cleaned up).` : ''),
      );
      setTitle('');
      setBody('');
      setImageUrl('');
      setLinkType('none');
      setListingId('');
      setCategoryId('');
      setConfirmOpen(false);
      refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Send failed.');
      setConfirmOpen(false);
    } finally {
      setSending(false);
    }
  };

  const columns: Column<Campaign>[] = [
    {
      key: 'when',
      header: 'Sent',
      render: (c) => (
        <span title={formatDateTime(c.createdAt)} className="whitespace-nowrap text-stone-600">
          {formatDateTime(c.createdAt)}
        </span>
      ),
    },
    {
      key: 'campaign',
      header: 'Campaign',
      render: (c) => (
        <div className="flex items-center gap-3">
          {c.imageUrl ? (
            <img src={c.imageUrl} alt="" className="h-10 w-10 shrink-0 rounded-lg object-cover" />
          ) : null}
          <div className="min-w-0">
            <div className="max-w-xs truncate font-medium text-stone-900">{c.title}</div>
            <div className="max-w-xs truncate text-xs text-stone-500">{c.body}</div>
          </div>
        </div>
      ),
    },
    {
      key: 'opens',
      header: 'Tap opens',
      render: (c) =>
        c.linkType === 'listing'
          ? 'A listing'
          : c.linkType === 'category'
            ? (c.categoryName ?? 'A category')
            : '—',
    },
    {
      key: 'delivery',
      header: 'Delivered',
      render: (c) => (
        <span className="whitespace-nowrap">
          {c.sent} / {c.recipients} devices
        </span>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-stone-900">Push Notifications</h1>
        <p className="text-sm text-stone-500">
          Send a custom notification to every user who has the app and is signed in.
          Add a photo and pick what the tap opens, like the big apps do.
        </p>
      </div>

      {result && (
        <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">
          {result}
        </div>
      )}
      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      <form
        onSubmit={openConfirm}
        className="space-y-4 rounded-xl border border-stone-200 bg-white p-5"
      >
        <div>
          <label className="mb-1 block text-sm font-medium text-stone-700">
            Title <span className="text-stone-400">({title.length}/100)</span>
          </label>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={100}
            required
            placeholder="e.g. Weekend price drops in Gaming"
            className={inputCls}
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-stone-700">
            Message <span className="text-stone-400">({body.length}/300)</span>
          </label>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            maxLength={300}
            required
            rows={3}
            placeholder="e.g. Fresh PS5 and Xbox listings just went live. Tap to take a look before they go."
            className={inputCls}
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-stone-700">
            Image link (optional)
          </label>
          <input
            value={imageUrl}
            onChange={(e) => {
              setImageUrl(e.target.value);
              setImageOk(true);
            }}
            placeholder="https://… (a listing photo link works well)"
            className={inputCls}
          />
          {image !== '' && !image.startsWith('https://') && (
            <p className="mt-1 text-xs text-red-600">The image link must start with https://</p>
          )}
          {image.startsWith('https://') && (
            <div className="mt-2">
              <img
                src={image}
                alt=""
                onLoad={() => setImageOk(true)}
                onError={() => setImageOk(false)}
                className="max-h-44 rounded-lg border border-stone-200 object-cover"
              />
              {!imageOk && (
                <p className="mt-1 text-xs text-red-600">
                  This link did not load as an image. The push will still send, but without the photo.
                </p>
              )}
            </div>
          )}
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-stone-700">When tapped, open</label>
          <div className="flex flex-wrap gap-2">
            {(
              [
                ['none', 'Just the app'],
                ['listing', 'A listing'],
                ['category', 'A category'],
              ] as [LinkType, string][]
            ).map(([value, label]) => (
              <button
                key={value}
                type="button"
                onClick={() => setLinkType(value)}
                className={`rounded-lg px-4 py-2 text-sm font-semibold ${
                  linkType === value
                    ? 'bg-trega-600 text-white'
                    : 'border border-stone-300 text-stone-700 hover:bg-stone-100'
                }`}
              >
                {label}
              </button>
            ))}
          </div>

          {linkType === 'listing' && (
            <select
              value={listingId}
              onChange={(e) => setListingId(e.target.value)}
              required
              className={`${inputCls} mt-3`}
            >
              <option value="">Pick a live listing…</option>
              {liveListings.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.title} — {formatINR(l.price)}
                </option>
              ))}
            </select>
          )}
          {linkType === 'category' && (
            <select
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              required
              className={`${inputCls} mt-3`}
            >
              <option value="">Pick a category…</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          )}
        </div>

        <button
          type="submit"
          disabled={!formValid}
          className="rounded-lg bg-trega-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-trega-700 disabled:opacity-60"
        >
          Preview & send
        </button>
      </form>

      <div>
        <h2 className="mb-3 text-lg font-bold text-stone-900">Sent campaigns</h2>
        {historyError && (
          <div className="mb-3 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
            {historyError}
          </div>
        )}
        <DataTable
          columns={columns}
          rows={rows}
          keyOf={(c) => c.id}
          loading={loading}
          emptyMessage="No campaigns sent yet."
          pagination={{
            page,
            totalPages: Math.max(1, Math.ceil(total / HISTORY_PAGE_SIZE)),
            total,
            onPage: setPage,
          }}
        />
      </div>

      {confirmOpen && (
        <Modal title="Send this notification?" onClose={() => setConfirmOpen(false)}>
          <div className="space-y-4">
            <div className="mx-auto max-w-xs rounded-2xl border border-stone-200 bg-stone-50 p-3">
              <div className="flex items-start gap-2.5">
                <img src="/logo.png" alt="" className="mt-0.5 h-8 w-8 shrink-0 rounded-md bg-white object-contain p-1" />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold text-stone-900">{title.trim()}</div>
                  <div className="text-sm text-stone-600">{body.trim()}</div>
                </div>
                <span className="text-[11px] text-stone-400">now</span>
              </div>
              {image.startsWith('https://') && (
                <img src={image} alt="" className="mt-2.5 w-full rounded-xl object-cover" />
              )}
            </div>
            <p className="text-center text-xs text-stone-500">Tap opens: {targetLabel}</p>
            <p className="text-sm text-stone-600">
              This goes to every signed-in user's phone right away. It can't be unsent.
            </p>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setConfirmOpen(false)}
                disabled={sending}
                className="flex-1 rounded-lg border border-stone-300 px-4 py-2.5 text-sm font-semibold text-stone-700 hover:bg-stone-100 disabled:opacity-60"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={doSend}
                disabled={sending}
                className="flex-1 rounded-lg bg-trega-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-trega-700 disabled:opacity-60"
              >
                {sending ? 'Sending…' : 'Send to all users'}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
