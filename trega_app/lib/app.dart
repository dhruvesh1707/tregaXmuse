import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/auth/screens/phone_auth_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/bids/screens/bids_offers_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/listing_detail/screens/listing_detail_screen.dart';
import 'features/notifications/screens/notifications_screen.dart';
import 'features/orders/screens/order_tracking_screen.dart';
import 'features/orders/screens/orders_screen.dart';
import 'features/profile/screens/kyc_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/search/screens/category_screen.dart';
import 'features/search/screens/search_screen.dart';
import 'features/sell/screens/sell_flow_screen.dart';
import 'features/wishlist/screens/wishlist_screen.dart';

/// Root widget: theme + named-route table.
///
/// Navigation is deliberately kept on [MaterialApp.onGenerateRoute] so deep
/// links (e.g. trega://listing/<id>) can be added later without restructuring.
/// TODO: migrate to go_router once deep-link requirements are finalised.
class TregaApp extends StatelessWidget {
  const TregaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trega',
      debugShowCheckedModeBanner: false,
      theme: buildTregaTheme(),
      initialRoute: SplashScreen.routeName,
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    WidgetBuilder builder;
    switch (settings.name) {
      case SplashScreen.routeName:
        builder = (_) => const SplashScreen();
      case OnboardingScreen.routeName:
        builder = (_) => const OnboardingScreen();
      case PhoneAuthScreen.routeName:
        builder = (_) => const PhoneAuthScreen();
      case HomeScreen.routeName:
        builder = (_) => const HomeScreen();
      case SearchScreen.routeName:
        builder = (_) => const SearchScreen();
      case CategoryScreen.routeName:
        final args = settings.arguments as CategoryArgs?;
        builder = (_) => CategoryScreen(args: args);
      case ListingDetailScreen.routeName:
        final listingId = settings.arguments as String?;
        builder = (_) => ListingDetailScreen(listingId: listingId);
      case SellFlowScreen.routeName:
        builder = (_) => const SellFlowScreen();
      case BidsOffersScreen.routeName:
        builder = (_) => const BidsOffersScreen();
      case OrdersScreen.routeName:
        builder = (_) => const OrdersScreen();
      case OrderTrackingScreen.routeName:
        final orderId = settings.arguments as String?;
        builder = (_) => OrderTrackingScreen(orderId: orderId);
      case WishlistScreen.routeName:
        builder = (_) => const WishlistScreen();
      case NotificationsScreen.routeName:
        builder = (_) => const NotificationsScreen();
      case ProfileScreen.routeName:
        builder = (_) => const ProfileScreen();
      case KycScreen.routeName:
        builder = (_) => const KycScreen();
      default:
        builder = (_) => const SplashScreen();
    }
    return MaterialPageRoute(builder: builder, settings: settings);
  }
}
