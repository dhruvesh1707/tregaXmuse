import { useState } from 'react';
import type { FormEvent } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useListing, useCategories, approveListing, rejectListing } from '../lib/firestore';
import type { MediaItem } from '../api/types';
import ImageGallery from '../components/ImageGallery';
import StatusBadge from '../components/StatusBadge';
import Modal from '../components/Modal';
import { formatINR, formatDateTime, conditionLabel } from '../utils/format';

/** Full listing detail used by both /review/:id and /listings/:id. */
export default function ListingDetail({ backTo }: { backTo: string }) {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { map: categories } = useCategories();
  const { listing, loading, error } = useListing(id, categories);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [acting, setActing] = useState(false);

  const approve = async () => {
    if (!id || !confirm('Approve this listing and make it live?')) return;
    setActing(true);
    try {
      await approveListing(id);
      navigate(backTo);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Approve failed.');
      setActing(false);
    }
  };

  const reject = async (e: FormEvent) => {
    e.preventDefault();
    if (!id || !reason.trim()) return;
    setActing(true);
    try {
      await rejectListing(id, reason.trim());
      navigate(backTo);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Reject failed.');
      setActing(false);
    }
  };

  if (loading) return <p className="py-10 text-center text-stone-500">Loading listing…</p>;
  if (error || !listing)
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 p-6 text-sm text-red-700">
        {error ?? 'Listing not found.'}
      </div>
    );

  const media: MediaItem[] = [
    ...listing.photos.map((url) => ({ url, type: 'image' as const })),
    ...(listing.videoUrl ? [{ url: listing.videoUrl, type: 'video' as const }] : []),
  ];

  return (
    <div className="space-y-5">
      <button
        onClick={() => navigate(backTo)}
        className="text-sm font-medium text-trega-600 hover:underline"
      >
        ← Back
      </button>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <ImageGallery media={media} title={listing.title} />

        <div className="space-y-4">
          <div className="flex items-start justify-between gap-3">
            <h1 className="text-xl font-bold text-stone-900">{listing.title}</h1>
            <StatusBadge value={listing.status} />
          </div>

          <div className="text-2xl font-bold text-trega-700">{formatINR(listing.price)}</div>

          <dl className="grid grid-cols-2 gap-3 rounded-xl border border-stone-200 bg-white p-4 text-sm">
            <div>
              <dt className="text-xs text-stone-500">Category</dt>
              <dd className="font-medium">{listing.categoryName}</dd>
            </div>
            <div>
              <dt className="text-xs text-stone-500">Condition</dt>
              <dd className="font-medium">{conditionLabel(listing.condition)}</dd>
            </div>
            <div>
              <dt className="text-xs text-stone-500">Submitted</dt>
              <dd className="font-medium">{formatDateTime(listing.submittedAt || listing.createdAt)}</dd>
            </div>
            <div>
              <dt className="text-xs text-stone-500">Views</dt>
              <dd className="font-medium">{listing.viewCount}</dd>
            </div>
          </dl>

          <div className="rounded-xl border border-stone-200 bg-white p-4">
            <h2 className="mb-1 text-sm font-bold text-stone-900">Description</h2>
            <p className="whitespace-pre-wrap text-sm text-stone-700">{listing.description}</p>
          </div>

          <div className="rounded-xl border border-stone-200 bg-white p-4">
            <h2 className="mb-2 text-sm font-bold text-stone-900">Seller</h2>
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-trega-100 font-bold text-trega-700">
                {listing.seller.avatarUrl ? (
                  <img src={listing.seller.avatarUrl} alt="" className="h-full w-full rounded-full object-cover" />
                ) : (
                  listing.seller.name.charAt(0).toUpperCase()
                )}
              </div>
              <div className="flex-1">
                <div className="text-sm font-medium">{listing.seller.name}</div>
                <div className="text-xs text-stone-500">
                  {listing.seller.phone ?? ''} {listing.seller.verifiedSeller ? '· ✓ Verified seller' : ''}
                </div>
              </div>
              <StatusBadge value={listing.seller.kycStatus} />
            </div>
          </div>

          {listing.status === 'rejected' && listing.rejectionReason && (
            <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
              <span className="font-semibold">Rejection reason: </span>
              {listing.rejectionReason}
            </div>
          )}

          {listing.status === 'pending' && (
            <div className="flex gap-3">
              <button
                onClick={approve}
                disabled={acting}
                className="flex-1 rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
              >
                {acting ? 'Working…' : 'Approve & publish'}
              </button>
              <button
                onClick={() => setRejectOpen(true)}
                disabled={acting}
                className="flex-1 rounded-lg bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-60"
              >
                Reject
              </button>
            </div>
          )}
        </div>
      </div>

      {rejectOpen && (
        <Modal title="Reject listing" onClose={() => setRejectOpen(false)}>
          <form onSubmit={reject} className="space-y-4">
            <p className="text-sm text-stone-600">
              Tell the seller why this listing was rejected. They'll see this reason in the app.
            </p>
            <textarea
              required
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={4}
              placeholder="e.g. Photos are blurry and the video doesn't show the product working…"
              className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm outline-none focus:border-trega-500 focus:ring-2 focus:ring-trega-100"
            />
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setRejectOpen(false)}
                className="flex-1 rounded-lg border border-stone-300 px-4 py-2.5 text-sm font-semibold text-stone-700 hover:bg-stone-100"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={acting || !reason.trim()}
                className="flex-1 rounded-lg bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-60"
              >
                {acting ? 'Rejecting…' : 'Confirm reject'}
              </button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
