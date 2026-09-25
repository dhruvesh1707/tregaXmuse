import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _prefilled = false;

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
          // Payment success beats a snackbar: celebrate, then move to
          // Orders where the new purchase is already listed.
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _PaymentCelebration(),
          );
          if (!mounted) return;
          Navigator.of(context)
              .pushReplacementNamed(OrdersScreen.routeName);
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
                  label: _placing
                      ? 'Processing...'
                      : 'Pay ${formatINR(bid.amount)}',
                  onPressed: _placing ? null : () => _pay(bid),
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
