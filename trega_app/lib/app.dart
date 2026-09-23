import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/auth/screens/phone_auth_screen.dart';
import 'features/auth/screens/profile_setup_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/bids/screens/bids_offers_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/listing_detail/screens/listing_detail_screen.dart';
import 'features/notifications/screens/notifications_screen.dart';
import 'features/orders/screens/order_tracking_screen.dart';
import 'features/orders/screens/orders_screen.dart';
import 'features/profile/screens/help_screen.dart';
import 'features/profile/screens/kyc_screen.dart';
import 'features/profile/screens/my_listings_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/profile/screens/settings_screen.dart';
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
      case ProfileSetupScreen.routeName:
        builder = (_) => const ProfileSetupScreen();
      case HomeScreen.routeName:
        builder = (_) => const HomeScreen();
      case SearchScreen.routeName:
        builder = (_) => const SearchScreen();
      case CategoryScreen.routeName:
        final args = settings.arguments as CategoryArgs?;
        builder = (_) => CategoryScreen(args: args);
      case ListingDetailScreen.routeName:
        final args = settings.arguments;
        if (args is ListingDetailArgs) {
          builder = (_) => ListingDetailScreen(
                listingId: args.listingId,
                initialListing: args.initial,
              );
        } else {
          // Back-compat: older callers pass a raw listing id string.
          builder =
              (_) => ListingDetailScreen(listingId: args as String?);
        }
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
      case MyListingsScreen.routeName:
        builder = (_) => const MyListingsScreen();
      case SettingsScreen.routeName:
        builder = (_) => const SettingsScreen();
      case HelpScreen.routeName:
        builder = (_) => const HelpScreen();
      case KycScreen.routeName:
        builder = (_) => const KycScreen();
      default:
        builder = (_) => const SplashScreen();
    }
    return _TregaPageRoute(builder: builder, settings: settings);
  }
}

/// Trega's route transition: a quick fade with a gentle 5% rise.
///
/// One consistent transition language across the whole app feels more
/// premium than per-screen effects, and it composes cleanly with the
/// product-image Hero flights on the listing detail route.
class _TregaPageRoute<T> extends PageRouteBuilder<T> {
  _TregaPageRoute({
    required WidgetBuilder builder,
    required RouteSettings settings,
  }) : super(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
