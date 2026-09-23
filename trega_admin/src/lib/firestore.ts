import { useEffect, useState } from 'react';
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  limit,
  onSnapshot,
  query,
  serverTimestamp,
  updateDoc,
  where,
  type DocumentData,
  type QueryConstraint,
  type Timestamp,
} from 'firebase/firestore';
import { httpsCallable } from 'firebase/functions';
import { db, functions } from './firebase';
import type {
  AdminUser,
  Bid,
  Category,
  DashboardStats,
  KycStatus,
  Listing,
  Order,
  UserLite,
} from '../api/types';

/** Firestore Timestamp | ISO string | {seconds} → ISO string. */
export function tsToIso(v: unknown): string {
  if (!v) return '';
  if (typeof v === 'string') return v;
  const t = v as Partial<Timestamp>;
  if (typeof t.toDate === 'function') return (t as Timestamp).toDate().toISOString();
  const s = (v as { seconds?: number }).seconds;
  if (typeof s === 'number') return new Date(s * 1000).toISOString();
  return '';
}

// ── In-memory enrichment caches ──────────────────────────────────────────
// Users and listings change rarely relative to admin browsing; caching keeps
// the N+1 lookups (seller names, listing titles) cheap.
const userCache = new Map<string, UserLite>();
const listingLiteCache = new Map<string, { id: string; title: string; price: number; photos: string[] }>();

function toUserLite(id: string, d: DocumentData): UserLite {
  return {
    id,
    name: (d.name as string) || (d.phone as string) || 'Unknown user',
    phone: d.phone as string | undefined,
    avatarUrl: d.avatarUrl as string | undefined,
    role: (d.role as UserLite['role']) ?? 'buyer',
    kycStatus: (d.kycStatus as KycStatus) ?? 'unverified',
    verifiedSeller: (d.verifiedSeller as boolean) ?? false,
  };
}

export async function fetchUserLite(uid: string): Promise<UserLite> {
  const hit = userCache.get(uid);
  if (hit) return hit;
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    const lite = snap.exists() ? toUserLite(snap.id, snap.data()) : { id: uid, name: 'Unknown user', role: 'buyer', kycStatus: 'unverified', verifiedSeller: false } as UserLite;
    userCache.set(uid, lite);
    return lite;
  } catch {
    return { id: uid, name: 'Unknown user', role: 'buyer', kycStatus: 'unverified', verifiedSeller: false };
  }
}

async function fetchListingLite(id: string) {
  const hit = listingLiteCache.get(id);
  if (hit) return hit;
  const fallback = { id, title: 'Listing', price: 0, photos: [] as string[] };
  try {
    const snap = await getDoc(doc(db, 'listings', id));
    if (!snap.exists()) return fallback;
    const d = snap.data();
    const lite = {
      id,
      title: (d.title as string) ?? 'Listing',
      price: (d.price as number) ?? 0,
      photos: (d.photos as string[]) ?? [],
    };
    listingLiteCache.set(id, lite);
    return lite;
  } catch {
    return fallback;
  }
}

// ── Mappers ──────────────────────────────────────────────────────────────
export function mapListing(id: string, d: DocumentData, seller: UserLite, categoryName: string): Listing {
  return {
    id,
    title: (d.title as string) ?? '',
    description: (d.description as string) ?? '',
    price: (d.price as number) ?? 0,
    categoryId: (d.categoryId as string) ?? '',
    categoryName,
    condition: (d.condition as Listing['condition']) ?? 'good',
    status: (d.status as Listing['status']) ?? 'draft',
    photos: (d.photos as string[]) ?? [],
    videoUrl: d.videoUrl as string | undefined,
    sellerId: (d.sellerId as string) ?? '',
    seller,
    rejectionReason: d.rejectionReason as string | undefined,
    viewCount: (d.viewCount as number) ?? 0,
    createdAt: tsToIso(d.createdAt),
    submittedAt: d.submittedAt ? tsToIso(d.submittedAt) : undefined,
  };
}

export async function mapOrder(id: string, d: DocumentData): Promise<Order> {
  const [listing, buyer, seller] = await Promise.all([
    fetchListingLite(d.listingId as string),
    fetchUserLite(d.buyerId as string),
    fetchUserLite(d.sellerId as string),
  ]);
  return {
    id,
    listingId: (d.listingId as string) ?? '',
    listingTitle: listing.title,
    listingThumb: listing.photos[0],
    buyerId: (d.buyerId as string) ?? '',
    buyerName: buyer.name,
    sellerId: (d.sellerId as string) ?? '',
    sellerName: seller.name,
    amount: (d.amount as number) ?? 0,
    currency: (d.currency as string) ?? 'INR',
    status: (d.status as Order['status']) ?? 'placed',
    paymentStatus: (d.paymentStatus as Order['paymentStatus']) ?? 'PENDING',
    trackingNote: d.trackingNote as string | undefined,
    createdAt: tsToIso(d.createdAt),
  };
}

export async function mapBid(id: string, d: DocumentData): Promise<Bid> {
  const [listing, buyer] = await Promise.all([
    fetchListingLite(d.listingId as string),
    fetchUserLite(d.buyerId as string),
  ]);
  return {
    id,
    listingId: (d.listingId as string) ?? '',
    listingTitle: listing.title,
    listingPrice: listing.price,
    buyerId: (d.buyerId as string) ?? '',
    buyerName: buyer.name,
    amount: (d.amount as number) ?? 0,
    status: (d.status as Bid['status']) ?? 'open',
    counterAmount: d.counterAmount as number | undefined,
    createdAt: tsToIso(d.createdAt),
  };
}

export function mapCategory(id: string, d: DocumentData): Category {
  return {
    id,
    name: (d.name as string) ?? '',
    slug: (d.slug as string) ?? id,
    icon: d.icon as string | undefined,
    active: (d.active as boolean) ?? true,
    sortOrder: (d.sortOrder as number) ?? 0,
  };
}

function mapAdminUser(id: string, d: DocumentData): AdminUser {
  return {
    ...toUserLite(id, d),
    kycNote: d.kycNote as string | undefined,
    createdAt: tsToIso(d.createdAt),
  };
}

// ── Pagination helpers ───────────────────────────────────────────────────
export interface Paged<T> {
  rows: T[];
  total: number;
  loading: boolean;
  error: string | null;
  refresh: () => void;
}

function paginate<T>(rows: T[], page: number, pageSize: number): { rows: T[]; total: number } {
  const total = rows.length;
  return { rows: rows.slice((page - 1) * pageSize, page * pageSize), total };
}

/** Generic paged listener: single-field Firestore query, everything else
 * (sort / search / pagination) client-side so no composite indexes are needed. */
function usePagedQuery<T>(
  collectionName: string,
  constraints: QueryConstraint[],
  depsKey: string,
  mapRow: (id: string, data: DocumentData) => Promise<T> | T,
  opts: {
    page: number;
    pageSize: number;
    search?: string;
    searchIn?: (row: T) => string;
    sort?: (a: T, b: T) => number;
    fetchLimit?: number;
  },
): Paged<T> {
  const [all, setAll] = useState<T[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    const q = query(
      collection(db, collectionName),
      ...constraints,
      limit(opts.fetchLimit ?? 400),
    );
    const unsub = onSnapshot(
      q,
      (snap) => {
        void (async () => {
          try {
            const rows = await Promise.all(snap.docs.map((d) => mapRow(d.id, d.data())));
            if (cancelled) return;
            setAll(rows);
            setError(null);
          } catch (e) {
            if (!cancelled) setError(e instanceof Error ? e.message : 'Failed to load.');
          } finally {
            if (!cancelled) setLoading(false);
          }
        })();
      },
      (e) => {
        if (!cancelled) {
          setError(e.message);
          setLoading(false);
        }
      },
    );
    return () => {
      cancelled = true;
      unsub();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collectionName, depsKey, tick]);

  let rows = all;
  if (opts.sort) rows = [...rows].sort(opts.sort);
  if (opts.search && opts.searchIn) {
    const s = opts.search.toLowerCase();
    rows = rows.filter((r) => opts.searchIn!(r).toLowerCase().includes(s));
  }
  const { rows: pageRows, total } = paginate(rows, opts.page, opts.pageSize);
  return { rows: pageRows, total, loading, error, refresh: () => setTick((t) => t + 1) };
}

// ── Page hooks ───────────────────────────────────────────────────────────
const byNewest = <T extends { createdAt: string }>(a: T, b: T) =>
  (b.createdAt || '').localeCompare(a.createdAt || '');
const byOldest = <T extends { createdAt: string }>(a: T, b: T) =>
  (a.createdAt || '').localeCompare(b.createdAt || '');

/** Review queue: listings awaiting approval, oldest first. */
export function useReviewQueue(page: number, pageSize: number, search: string, categories: Map<string, string>): Paged<Listing> {
  return usePagedQuery<Listing>(
    'listings',
    [where('status', '==', 'pending')],
    `review|${page}|${search}`,
    async (id, d) => {
      const seller = await fetchUserLite(d.sellerId as string);
      return mapListing(id, d, seller, categories.get(d.categoryId as string) ?? (d.categoryId as string) ?? '');
    },
    {
      page,
      pageSize,
      search,
      searchIn: (l) => `${l.title} ${l.seller.name} ${l.description}`,
      sort: byOldest,
    },
  );
}

/** All listings with an optional status filter. */
export function useListings(status: string, page: number, pageSize: number, search: string, categories: Map<string, string>): Paged<Listing> {
  const constraints: QueryConstraint[] = status === 'all' ? [] : [where('status', '==', status)];
  return usePagedQuery<Listing>(
    'listings',
    constraints,
    `listings|${status}|${page}|${search}`,
    async (id, d) => {
      const seller = await fetchUserLite(d.sellerId as string);
      return mapListing(id, d, seller, categories.get(d.categoryId as string) ?? (d.categoryId as string) ?? '');
    },
    {
      page,
      pageSize,
      search,
      searchIn: (l) => `${l.title} ${l.seller.name} ${l.description}`,
      sort: byNewest,
    },
  );
}

/** Single listing detail (real-time). */
export function useListing(id: string | undefined, categories: Map<string, string>) {
  const [listing, setListing] = useState<Listing | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) {
      setLoading(false);
      return;
    }
    setLoading(true);
    const unsub = onSnapshot(
      doc(db, 'listings', id),
      (snap) => {
        void (async () => {
          if (!snap.exists()) {
            setListing(null);
            setError('Listing not found.');
            setLoading(false);
            return;
          }
          const d = snap.data();
          const seller = await fetchUserLite(d.sellerId as string);
          setListing(mapListing(snap.id, d, seller, categories.get(d.categoryId as string) ?? (d.categoryId as string) ?? ''));
          setError(null);
          setLoading(false);
        })();
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  return { listing, loading, error };
}

export function useUsers(kyc: string, page: number, pageSize: number, search: string): Paged<AdminUser> {
  const constraints: QueryConstraint[] = kyc === 'all' ? [] : [where('kycStatus', '==', kyc)];
  return usePagedQuery<AdminUser>(
    'users',
    constraints,
    `users|${kyc}|${page}|${search}`,
    (id, d) => mapAdminUser(id, d),
    {
      page,
      pageSize,
      search,
      searchIn: (u) => `${u.name} ${u.phone ?? ''}`,
      sort: byNewest,
    },
  );
}

export function useOrders(status: string, page: number, pageSize: number, search: string): Paged<Order> {
  const constraints: QueryConstraint[] = status === 'all' ? [] : [where('status', '==', status)];
  return usePagedQuery<Order>(
    'orders',
    constraints,
    `orders|${status}|${page}|${search}`,
    mapOrder,
    {
      page,
      pageSize,
      search,
      searchIn: (o) => `${o.listingTitle} ${o.buyerName} ${o.sellerName} ${o.id}`,
      sort: byNewest,
    },
  );
}

export function useBids(status: string, page: number, pageSize: number): Paged<Bid> {
  const constraints: QueryConstraint[] = status === 'all' ? [] : [where('status', '==', status)];
  return usePagedQuery<Bid>('bids', constraints, `bids|${status}|${page}`, mapBid, {
    page,
    pageSize,
    sort: byNewest,
  });
}

export function useCategories() {
  const [rows, setRows] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const unsub = onSnapshot(
      query(collection(db, 'categories'), limit(100)),
      (snap) => {
        const cats = snap.docs.map((d) => mapCategory(d.id, d.data()));
        cats.sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name));
        setRows(cats);
        setError(null);
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
  }, []);

  const map = new Map(rows.map((c) => [c.id, c.name]));
  return { rows, map, loading, error };
}

// ── Dashboard ────────────────────────────────────────────────────────────
export function useDashboard() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [pending, setPending] = useState<Listing[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const { map: categories } = useCategories();

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        setLoading(true);
        const monthStart = new Date();
        monthStart.setDate(1);
        monthStart.setHours(0, 0, 0, 0);
        const dayStart = new Date();
        dayStart.setHours(0, 0, 0, 0);

        const listingsCol = collection(db, 'listings');
        const ordersCol = collection(db, 'orders');
        const [pendingC, liveC, usersC, inTransitC, soldSnap, ordersSnap, bidsSnap, recentPendingSnap, recentOrdersSnap] =
          await Promise.all([
            getCountFromServer(query(listingsCol, where('status', '==', 'pending'))),
            getCountFromServer(query(listingsCol, where('status', '==', 'live'))),
            getCountFromServer(collection(db, 'users')),
            getCountFromServer(
              query(ordersCol, where('status', 'in', ['placed', 'pickup_scheduled', 'picked_up', 'in_transit'])),
            ),
            getDocs(query(listingsCol, where('status', '==', 'sold'), limit(500))),
            getDocs(query(ordersCol, limit(1000))),
            getDocs(query(collection(db, 'bids'), where('createdAt', '>=', dayStart), limit(500))),
            getDocs(query(listingsCol, where('status', '==', 'pending'), limit(50))),
            getDocs(query(ordersCol, limit(50))),
          ]);
        if (cancelled) return;

        const soldThisMonth = soldSnap.docs.filter((d) => {
          const t = tsToIso(d.data().soldAt ?? d.data().createdAt);
          return t >= monthStart.toISOString();
        }).length;

        let gmvThisMonth = 0;
        ordersSnap.forEach((d) => {
          const x = d.data();
          if (x.paymentStatus === 'SUCCESS' && tsToIso(x.paidAt ?? x.createdAt) >= monthStart.toISOString()) {
            gmvThisMonth += Number(x.amount) || 0;
          }
        });

        setStats({
          pendingReview: pendingC.data().count,
          liveListings: liveC.data().count,
          soldThisMonth,
          gmvThisMonth,
          totalUsers: usersC.data().count,
          ordersInTransit: inTransitC.data().count,
          bidsToday: bidsSnap.size,
        });

        const pend = await Promise.all(
          recentPendingSnap.docs.map(async (d) => {
            const seller = await fetchUserLite(d.data().sellerId as string);
            return mapListing(d.id, d.data(), seller, categories.get(d.data().categoryId as string) ?? '');
          }),
        );
        pend.sort(byOldest);
        setPending(pend.slice(0, 5));

        const ords = await Promise.all(recentOrdersSnap.docs.map((d) => mapOrder(d.id, d.data())));
        ords.sort(byNewest);
        setOrders(ords.slice(0, 5));

        setError(null);
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Failed to load dashboard.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { stats, pending, orders, loading, error };
}

// ── Cloud Functions callables (exact names from trega_functions/src/index.ts) ──
const reviewListingFn = httpsCallable<{ listingId: string; decision: 'approve' | 'reject'; reason?: string }, { status: string }>(
  functions,
  'reviewListing',
);
const setUserKycStatusFn = httpsCallable<{ uid: string; status: 'verified' | 'rejected'; note?: string }, { kycStatus: string }>(
  functions,
  'setUserKycStatus',
);
const updateOrderFulfillmentFn = httpsCallable<{ orderId: string; status?: string; trackingNote?: string }, { status: string }>(
  functions,
  'updateOrderFulfillment',
);

function callableError(e: unknown): string {
  const err = e as { code?: string; message?: string };
  if (err?.message) return err.message.replace(/^FirebaseError:\s*/, '');
  return 'Action failed.';
}

export async function approveListing(listingId: string): Promise<void> {
  try {
    await reviewListingFn({ listingId, decision: 'approve' });
  } catch (e) {
    throw new Error(callableError(e));
  }
}

export async function rejectListing(listingId: string, reason: string): Promise<void> {
  try {
    await reviewListingFn({ listingId, decision: 'reject', reason });
  } catch (e) {
    throw new Error(callableError(e));
  }
}

export async function setUserKyc(uid: string, status: 'verified' | 'rejected', note?: string): Promise<void> {
  try {
    await setUserKycStatusFn({ uid, status, note });
  } catch (e) {
    throw new Error(callableError(e));
  }
}

export async function updateOrder(orderId: string, status?: string, trackingNote?: string): Promise<void> {
  try {
    await updateOrderFulfillmentFn({ orderId, status, trackingNote });
  } catch (e) {
    throw new Error(callableError(e));
  }
}

// ── Categories (Firestore rules grant create/update/delete to admins) ────
function slugify(name: string): string {
  return name.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export async function upsertCategory(input: { id?: string; name: string; icon?: string; active: boolean; sortOrder?: number }): Promise<void> {
  const data = {
    name: input.name.trim(),
    slug: slugify(input.name),
    icon: input.icon?.trim() || null,
    active: input.active,
    sortOrder: input.sortOrder ?? 0,
  };
  if (input.id) {
    await updateDoc(doc(db, 'categories', input.id), { ...data, icon: input.icon?.trim() || null });
  } else {
    await addDoc(collection(db, 'categories'), { ...data, createdAt: serverTimestamp() });
  }
}

export async function deleteCategory(id: string): Promise<void> {
  await deleteDoc(doc(db, 'categories', id));
}
