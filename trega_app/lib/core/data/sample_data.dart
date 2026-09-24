import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/bid.dart';
import '../models/category.dart';
import '../models/listing.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/user.dart';

/// Placeholder catalogue used to render UI before the backend is wired.
///
/// TODO(backend): delete this file once repositories backed by [ApiClient]
/// land (see README.md "Backend wiring").
abstract final class SampleData {
  static const List<Category> categories = [
    Category(id: 'gaming', name: 'Gaming', slug: 'gaming', icon: PhosphorIconsRegular.gameController),
    Category(id: 'mobiles', name: 'Mobiles', slug: 'mobile', icon: PhosphorIconsRegular.deviceMobile),
    Category(id: 'laptops', name: 'Laptops', slug: 'laptop', icon: PhosphorIconsRegular.laptop),
    Category(id: 'cameras', name: 'Cameras', slug: 'camera', icon: PhosphorIconsRegular.camera),
    Category(id: 'music', name: 'Music', slug: 'music', icon: PhosphorIconsRegular.musicNote),
    Category(id: 'others', name: 'Others', slug: 'others', icon: PhosphorIconsRegular.dotsThree),
  ];

  static final AppUser demoSeller = AppUser(
    id: 'u-seller-1',
    name: 'Aarav Mehta',
    phone: '+91 98765 43210',
    isVerifiedSeller: true,
    rating: 4.8,
    reviewsCount: 132,
    joinedAt: DateTime(2023, 4, 12),
  );

  static final AppUser demoBuyer = AppUser(
    id: 'u-buyer-1',
    name: 'Dhruvesh',
    phone: '+91 91234 56780',
    isVerifiedSeller: false,
    rating: 4.9,
    reviewsCount: 21,
    joinedAt: DateTime(2024, 1, 8),
  );

  static final List<Listing> listings = [
    Listing(
      id: 'l-1',
      product: const Product(
        id: 'p-1',
        title: 'Sony PS5 Disc Edition 825GB',
        description:
            'Barely used PS5, single owner, no scratches. Comes with 2 DualSense controllers and 3 games.',
        categoryId: 'gaming',
        condition: Condition.likeNew,
        imageUrls: [
          'https://picsum.photos/seed/trega-ps5/600/600',
          'https://picsum.photos/seed/trega-ps5b/600/600',
        ],
        specs: {'Storage': '825 GB', 'Edition': 'Disc'},
      ),
      seller: demoSeller,
      price: 38999,
      negotiable: true,
      biddingEnabled: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      viewsCount: 231,
      likesCount: 18,
      isLiked: true,
    ),
    Listing(
      id: 'l-2',
      product: const Product(
        id: 'p-2',
        title: 'iPhone 13 128GB Midnight',
        description:
            'Battery health 89%. Original bill and box available. No repairs done.',
        categoryId: 'mobiles',
        condition: Condition.good,
        imageUrls: ['https://picsum.photos/seed/trega-ip13/600/600'],
        specs: {'Storage': '128 GB', 'Battery': '89%'},
      ),
      seller: demoSeller,
      price: 32999,
      negotiable: true,
      biddingEnabled: false,
      createdAt: DateTime.now().subtract(const Duration(hours: 11)),
      viewsCount: 412,
      likesCount: 34,
    ),
    Listing(
      id: 'l-3',
      product: const Product(
        id: 'p-3',
        title: 'MacBook Pro 14" M3 Pro 18/512',
        description:
            'AppleCare+ till 2026. Cycle count 42. Perfect for dev and design work.',
        categoryId: 'laptops',
        condition: Condition.likeNew,
        imageUrls: ['https://picsum.photos/seed/trega-mbp/600/600'],
        specs: {'Chip': 'M3 Pro', 'RAM': '18 GB', 'Storage': '512 GB'},
      ),
      seller: demoSeller,
      price: 145000,
      negotiable: false,
      biddingEnabled: true,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      viewsCount: 188,
      likesCount: 27,
    ),
    Listing(
      id: 'l-4',
      product: const Product(
        id: 'p-4',
        title: 'Sony A7 III + 28-70mm Kit',
        description:
            'Shutter count 12k. Sensor clean, includes 2 batteries and bag.',
        categoryId: 'cameras',
        condition: Condition.good,
        imageUrls: ['https://picsum.photos/seed/trega-a7/600/600'],
        specs: {'Shutter count': '12,400'},
      ),
      seller: demoSeller,
      price: 98000,
      negotiable: true,
      biddingEnabled: true,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      viewsCount: 156,
      likesCount: 12,
    ),
    Listing(
      id: 'l-5',
      product: const Product(
        id: 'p-5',
        title: 'Fender Stratocaster Player Series',
        description:
            'Made in Mexico, sunburst. New strings, set up last month. Hard case included.',
        categoryId: 'music',
        condition: Condition.likeNew,
        imageUrls: ['https://picsum.photos/seed/trega-strat/600/600'],
        specs: {'Origin': 'Mexico'},
      ),
      seller: demoSeller,
      price: 52000,
      negotiable: true,
      biddingEnabled: false,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      viewsCount: 98,
      likesCount: 9,
    ),
    Listing(
      id: 'l-6',
      product: const Product(
        id: 'p-6',
        title: 'Meta Quest 3 512GB',
        description:
            'Sealed box opened only for testing. Includes elite strap.',
        categoryId: 'others',
        condition: Condition.brandNew,
        imageUrls: ['https://picsum.photos/seed/trega-quest/600/600'],
        specs: {'Storage': '512 GB'},
      ),
      seller: demoSeller,
      price: 44000,
      negotiable: false,
      biddingEnabled: false,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
      viewsCount: 74,
      likesCount: 6,
    ),
  ];

  static final List<Bid> myBids = [
    Bid(
      id: 'b-1',
      listingId: 'l-1',
      listingTitle: 'Sony PS5 Disc Edition 825GB',
      buyerId: demoBuyer.id,
      sellerId: demoSeller.id,
      amount: 36000,
      status: BidStatus.open,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    Bid(
      id: 'b-2',
      listingId: 'l-3',
      listingTitle: 'MacBook Pro 14" M3 Pro 18/512',
      buyerId: demoBuyer.id,
      sellerId: demoSeller.id,
      amount: 140000,
      status: BidStatus.accepted,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  static final List<Bid> offersReceived = [
    Bid(
      id: 'b-3',
      listingId: 'l-4',
      listingTitle: 'Sony A7 III + 28-70mm Kit',
      buyerId: 'u-buyer-2',
      buyerName: 'Riya Shah',
      sellerId: demoSeller.id,
      amount: 92000,
      status: BidStatus.open,
      createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
  ];

  static final List<Order> orders = [
    Order(
      id: 'o-1',
      listing: listings[1],
      buyer: demoBuyer,
      amount: 32999,
      status: OrderStatus.inTransit,
      trackingId: 'TRG834210987',
      pickupAddress: 'Andheri West, Mumbai',
      deliveryAddress: 'Koramangala, Bengaluru',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    Order(
      id: 'o-2',
      listing: listings[4],
      buyer: demoBuyer,
      amount: 52000,
      status: OrderStatus.delivered,
      trackingId: 'TRG834210654',
      pickupAddress: 'Indiranagar, Bengaluru',
      deliveryAddress: 'Koramangala, Bengaluru',
      createdAt: DateTime.now().subtract(const Duration(days: 9)),
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];
}
