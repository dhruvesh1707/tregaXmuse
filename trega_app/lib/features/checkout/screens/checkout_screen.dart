import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/delivery/express_delivery.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/firebase/functions_service.dart';
import '../../../core/models/bid.dart';
import '../../../core/models/listing.dart';
import '../../../core/payments/cashfree_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/trega_button.dart';
import '../../orders/screens/orders_screen.dart';

/// Arguments for [CheckoutScreen].
class CheckoutArgs {
  final String bidId;

  const CheckoutArgs({required this.bidId});
}

/// Checkout for a seller-accepted offer.
///
/// The winner — and only the winner — lands here from the listing page's
/// "Buy Now at ₹X" button. The screen shows the order summary (accepted
/// price), collects the buyer's delivery address, then creates the Cashfree
/// order server-side (`createCashfreeOrder` with `bidId` + `deliveryAddress`)
/// and opens the Cashfree drop checkout.
///
/// The delivery address is validated again server-side and stored on the
/// order document so the seller knows where to ship.
class CheckoutScreen extends ConsumerStatefulWidget {
  static const String routeName = '/checkout';

  final String bidId;

  const CheckoutScreen({super.key, required this.bidId});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();

  String? _error;
  bool _placing = false;
  bool _confirmingPayment = false;
  bool _prefilled = false;
  bool _expressSelected = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _line1.dispose();
    _line2.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    super.dispose();
  }

  /// Prefill name/phone from the user's profile once.
  Future<void> _prefill(String? uid) async {
    if (_prefilled || uid == null) return;
    _prefilled = true;
    final me = await ref.read(firestoreServiceProvider).getUser(uid);
    if (!mounted) return;
    if (me != null) {
      if (_name.text.isEmpty) _name.text = me.name;
      if (_phone.text.isEmpty) _phone.text = me.phone;
    }
  }

  Map<String, String>? _validate() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final line1 = _line1.text.trim();
    final line2 = _line2.text.trim();
    final city = _city.text.trim();
    final state = _state.text.trim();
    final pincode = _pincode.text.trim();

    String? error;
    if (name.length < 2) {
      error = "Enter the receiver's name.";
    } else if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      error = 'Enter a valid 10-digit mobile number.';
    } else if (line1.length < 6) {
      error = 'Enter your house/flat and street.';
    } else if (city.isEmpty) {
      error = 'Enter your city.';
    } else if (state.isEmpty) {
      error = 'Enter your state.';
    } else if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pincode)) {
      error = 'Enter a valid 6-digit PIN code.';
    }
    setState(() => _error = error);
    if (error != null) return null;
    return {
      'name': name,
      'phone': phone,
      'line1': line1,
      if (line2.isNotEmpty) 'line2': line2,
      'city': city,
      'state': state,
      'pincode': pincode,
    };
  }

  Future<void> _pay(Bid bid) async {
    if (_placing) return;
    final address = _validate();
    if (address == null) return;
    // Re-check express eligibility server-side inputs: the listing's city
    // against the buyer's typed delivery city. The callable validates again
    // before honoring 'express' — the client can never force it.
    final listing = await ref
        .read(firestoreServiceProvider)
        .watchListing(bid.listingId)
        .first;
    final expressConfig = ref.read(expressConfigProvider).valueOrNull ??
        ExpressDeliveryConfig.defaults;
    final express = listing != null &&
        _expressSelected &&
        expressConfig.isOrderEligible(
          listingCity: listing.city,
          buyerCity: address['city']!,
        );
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(functionsServiceProvider).createCashfreeOrder(
                bidId: bid.id,
                customerPhone: address['phone']!,
                deliveryAddress: address,
                deliveryType: express ? 'express' : 'standard',
              );
      if (!mounted) return;
      final sessionId = result['paymentSessionId'] as String?;
      final orderId = result['orderId'] as String?;
      if (sessionId == null || orderId == null) {
        throw StateError('no session');
      }
      final cfOrderId =
          (result['cfOrderRef'] as String?) ?? 'trega_$orderId';
      CashfreeService().pay(
        cfOrderId: cfOrderId,
        paymentSessionId: sessionId,
        onVerified: (_) async {
          if (!mounted) return;
          // The SDK callback only means the sheet reported success on this
          // device — NOT that money moved. Verify with the server (which
          // asks Cashfree directly) before celebrating or navigating.
          // A failed payment or a back-press surfaces through onError and
          // never reaches here.
          setState(() => _confirmingPayment = true);
          try {
            final verification = await ref
                .read(functionsServiceProvider)
                .verifyPayment(orderId: orderId);
            if (!mounted) return;
            final status = verification['paymentStatus'] as String?;
            if (status == 'SUCCESS') {
              setState(() => _confirmingPayment = false);
              await showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const _PaymentCelebration(),
              );
              if (!mounted) return;
              Navigator.of(context)
                  .pushReplacementNamed(OrdersScreen.routeName);
            } else {
              setState(() {
                _placing = false;
                _confirmingPayment = false;
                _error = status == 'FAILED'
                    ? 'The payment did not go through. No money was debited — please try again.'
                    : 'We could not confirm your payment yet. If money was debited it will reflect shortly — please check Orders before paying again.';
              });
            }
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _placing = false;
              _confirmingPayment = false;
              _error = functionsErrorMessage(e,
                  fallback:
                      'Could not confirm your payment. Please check Orders before paying again.',);
            });
          }
        },
        onError: (message, _) {
          if (!mounted) return;
          setState(() {
            _placing = false;
            _error = 'Payment failed: $message';
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _error = functionsErrorMessage(e,
            fallback: 'Could not start checkout. Try again.',);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    _prefill(uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: StreamBuilder<Bid?>(
        stream: ref.read(firestoreServiceProvider).watchBid(widget.bidId),
        builder: (context, bidSnap) {
          if (bidSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final bid = bidSnap.data;
          if (bid == null) {
            return const Center(child: Text('Offer not found.'));
          }
          if (uid != null && bid.buyerId != uid) {
            return const Center(
              child: Text('This checkout is not for you.'),
            );
          }
          if (bid.status != BidStatus.accepted) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This offer is no longer accepted '
                  '(${bid.status.label}).',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Nested scaffold so the Pay bar stays pinned while the form
          // scrolls; it re-streams the bid, so a seller cancellation
          // disables Pay immediately.
          return Scaffold(
            body: _buildForm(context, bid),
            bottomSheet: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border:
                    Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: SafeArea(
                top: false,
                child: TregaButton(
                  label: _confirmingPayment
                      ? 'Confirming payment...'
                      : _placing
                          ? 'Processing...'
                          : 'Pay ${formatINR(bid.amount)}',
                  onPressed:
                      (_placing || _confirmingPayment) ? null : () => _pay(bid),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, Bid bid) {
    final textTheme = Theme.of(context).textTheme;
    return StreamBuilder<Listing?>(
      stream: ref.read(firestoreServiceProvider).watchListing(bid.listingId),
      builder: (context, listingSnap) {
        final listing = listingSnap.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // ── Order summary ──────────────────────────────────────
            Text('Order summary', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  if (listing != null &&
                      listing.product.imageUrls.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: listing.product.imageUrls.first,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 72,
                          height: 72,
                          color: AppColors.primarySoft,
                          child: const Icon(PhosphorIconsRegular.prohibit),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing?.product.title ?? 'Item',
                          style: textTheme.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Accepted offer price',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          formatINR(bid.amount),
                          style: textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Delivery address ───────────────────────────────────
            Text('Delivery address', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The seller ships the item to this address.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _field(_name, 'Receiver name', TextInputType.name),
            const SizedBox(height: 12),
            _field(
              _phone,
              'Mobile number',
              TextInputType.phone,
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              _line1,
              'Flat / House no, Street',
              TextInputType.streetAddress,
            ),
            const SizedBox(height: 12),
            _field(
              _line2,
              'Landmark (optional)',
              TextInputType.streetAddress,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_city, 'City', TextInputType.text)),
                const SizedBox(width: 12),
                Expanded(child: _field(_state, 'State', TextInputType.text)),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              _pincode,
              'PIN code',
              TextInputType.number,
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),
            const SizedBox(height: 24),
            // Rebuilds as the buyer types their city, so the express
            // option unlocks live.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _city,
              builder: (context, value, _) => _buildDeliveryOptions(
                context,
                listing: listing,
                buyerCity: value.text,
                config: ref.watch(expressConfigProvider).valueOrNull ??
                    ExpressDeliveryConfig.defaults,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    TextInputType keyboardType, {
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
    );
  }
  /// Delivery-speed selector. Express is offered only when the listing's
  /// city is express-eligible AND the buyer's typed city matches it —
  /// anything else would be a promise we can't keep.
  Widget _buildDeliveryOptions(
    BuildContext context, {
    required Listing? listing,
    required String buyerCity,
    required ExpressDeliveryConfig config,
  }) {
    if (listing == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final listingEligible = config.isCityEligible(listing.city);
    final orderEligible = listingEligible &&
        config.isOrderEligible(
          listingCity: listing.city,
          buyerCity: buyerCity,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delivery speed', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        if (listingEligible) ...[
          _DeliveryOptionTile(
            selected: orderEligible && _expressSelected,
            enabled: orderEligible,
            icon: PhosphorIconsRegular.truck,
            title: 'Express delivery',
            subtitle: orderEligible
                ? 'Arrives ${config.deliveryDayLabel(DateTime.now())}'
                : buyerCity.trim().isEmpty
                    ? 'Enter your city above to check eligibility'
                    : 'Only available for deliveries within ${listing.city}',
            onTap: orderEligible
                ? () => setState(() => _expressSelected = true)
                : null,
          ),
          const SizedBox(height: 8),
        ],
        _DeliveryOptionTile(
          selected: !orderEligible || !_expressSelected,
          enabled: true,
          icon: PhosphorIconsRegular.package,
          title: 'Standard delivery',
          subtitle: 'The seller ships the item in 2-4 days',
          onTap: () => setState(() => _expressSelected = false),
        ),
        if (!listingEligible)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Trega Express is coming to more cities soon.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}


/// "Payment successful" celebration shown after Cashfree verifies payment.
///
/// Auto-dismisses once the check draws itself; the screen then replaces
/// itself with Orders. Pure presentation — the order is already placed.
class _PaymentCelebration extends StatefulWidget {
  const _PaymentCelebration();

  @override
  State<_PaymentCelebration> createState() => _PaymentCelebrationState();
}

class _PaymentCelebrationState extends State<_PaymentCelebration> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SuccessCheck(size: 96),
            const SizedBox(height: 20),
            Text(
              'Payment successful!',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your order is confirmed. The seller has been notified to hand over the item for pickup.',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable delivery-speed row on the checkout screen.
class _DeliveryOptionTile extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _DeliveryOptionTile({
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (selected
                          ? AppColors.primary
                          : AppColors.textSecondary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  PhosphorIconsRegular.checkCircle,
                  color: AppColors.primary,
                )
              else
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.textSecondary,
                      width: 1.6,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
