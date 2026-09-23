/** Shared domain types for the Trega admin panel.
 *  These mirror the Firestore documents described in
 *  ~/workspace/trega/trega_functions/FIRESTORE_MODEL.md (snake_case fields,
 *  lowercase status enums). The admin panel reads them via Firestore
 *  listeners and performs privileged writes through Cloud Functions
 *  callables — never through the old REST API (removed). */

export type ListingStatus = 'draft' | 'pending' | 'live' | 'sold' | 'rejected';
export type ConditionGrade = 'brand_new' | 'like_new' | 'good' | 'fair';
export type KycStatus = 'unverified' | 'pending' | 'verified' | 'rejected';
export type OrderStatus =
  | 'placed'
  | 'pickup_scheduled'
  | 'picked_up'
  | 'in_transit'
  | 'delivered'
  | 'cancelled'
  | 'returned';
export type PaymentStatus = 'PENDING' | 'SUCCESS' | 'FAILED' | 'USER_DROPPED';
export type BidStatus = 'open' | 'accepted' | 'rejected' | 'expired' | 'countered';

/** Photo/video item for the gallery (built from photos + videoUrl). */
export interface MediaItem {
  url: string;
  type: 'image' | 'video';
}

/** Minimal user summary — users/{uid} in Firestore. */
export interface UserLite {
  id: string;
  name: string;
  phone?: string;
  avatarUrl?: string;
  role: 'buyer' | 'seller' | 'admin';
  kycStatus: KycStatus;
  verifiedSeller: boolean;
}

/** Full user row for the Users page (users/{uid}). */
export interface AdminUser extends UserLite {
  kycNote?: string;
  createdAt: string; // ISO
}

/** Listing row for queue/list pages (listings/{id}), enriched client-side. */
export interface Listing {
  id: string;
  title: string;
  description: string;
  price: number;
  categoryId: string;
  categoryName: string;
  condition: ConditionGrade;
  status: ListingStatus;
  photos: string[];
  videoUrl?: string;
  sellerId: string;
  seller: UserLite;
  rejectionReason?: string;
  viewCount: number;
  createdAt: string; // ISO
  submittedAt?: string; // ISO
}

/** Order row (orders/{id}), enriched client-side. */
export interface Order {
  id: string;
  listingId: string;
  listingTitle: string;
  listingThumb?: string;
  buyerId: string;
  buyerName: string;
  sellerId: string;
  sellerName: string;
  amount: number;
  currency: string;
  status: OrderStatus;
  paymentStatus: PaymentStatus;
  trackingNote?: string;
  createdAt: string; // ISO
}

/** Bid row (bids/{id}), enriched client-side. */
export interface Bid {
  id: string;
  listingId: string;
  listingTitle: string;
  listingPrice: number;
  buyerId: string;
  buyerName: string;
  amount: number;
  status: BidStatus;
  counterAmount?: number;
  createdAt: string; // ISO
}

export interface Category {
  id: string;
  name: string;
  slug: string;
  icon?: string;
  active: boolean;
  sortOrder: number;
}

export interface DashboardStats {
  pendingReview: number;
  liveListings: number;
  soldThisMonth: number;
  gmvThisMonth: number;
  totalUsers: number;
  ordersInTransit: number;
  bidsToday: number;
}
