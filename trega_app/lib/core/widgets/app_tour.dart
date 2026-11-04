import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

/// Anchor keys for the first-run spotlight tour.
///
/// The widgets the tour points at carry these keys (search button and
/// category rail on Home, the first listing card, the Make an Offer
/// button on the listing page, and the Sell / Bids / Profile items of
/// the floating tab bar). If a layout change drops a key, that one step
/// is skipped automatically instead of breaking the tour.
class TourKeys {
  TourKeys._();

  static final GlobalKey search = GlobalKey(debugLabel: 'tour-search');
  static final GlobalKey categories =
      GlobalKey(debugLabel: 'tour-categories');
  static final GlobalKey firstCard = GlobalKey(debugLabel: 'tour-card');
  static final GlobalKey offerButton = GlobalKey(debugLabel: 'tour-offer');
  static final GlobalKey tabSell = GlobalKey(debugLabel: 'tour-tab-sell');
  static final GlobalKey tabBids = GlobalKey(debugLabel: 'tour-tab-bids');
  static final GlobalKey tabProfile =
      GlobalKey(debugLabel: 'tour-tab-profile');
}

enum _StepId { search, categories, firstCard, offer, sell, bids, profile }

class _Step {
  const _Step(this.id, this.key, this.title, this.body,
      {this.nextLabel = 'Next'});

  final _StepId id;
  final GlobalKey key;
  final String title;
  final String body;
  final String nextLabel;
}

/// First-run spotlight tour for brand-new accounts.
///
/// Dims the real screen, cuts a window around the actual control, and
/// explains it in one short card: search, categories, a real listing,
/// the Make an Offer button on that listing's page, then the Sell,
/// Bids and Profile tabs. Skippable at every step; the caller marks it
/// seen on finish or skip, and it is only ever started for new users
/// (the gate lives in HomeScreen + FirestoreService.shouldShowTour).
class AppTour {
  AppTour._();

  static OverlayEntry? _entry;
  static List<_Step> _steps = const [];
  static int _index = 0;
  static BuildContext? _rootContext;
  static VoidCallback? _openFirstListing;
  static VoidCallback? _onDone;
  static bool _onDetail = false;

  static bool get isRunning => _entry != null;

  static void start({
    required BuildContext context,
    required bool hasListings,
    required VoidCallback openFirstListing,
    required VoidCallback onDone,
  }) {
    if (isRunning) return;
    _rootContext = context;
    _openFirstListing = openFirstListing;
    _onDone = onDone;
    _onDetail = false;
    _steps = [
      _Step(
        _StepId.search,
        TourKeys.search,
        'Search anything',
        'Tap the search icon to find any pre-owned phone, console, '
            'camera and more.',
      ),
      _Step(
        _StepId.categories,
        TourKeys.categories,
        'Browse by category',
        'Gaming, mobiles, laptops, cameras, fashion and more. Tap a '
            'category to see what people are selling.',
      ),
      if (hasListings)
        _Step(
          _StepId.firstCard,
          TourKeys.firstCard,
          'Open any product',
          'Tap a listing to see its photos, price and seller. Let me '
              'open this one for you.',
          nextLabel: 'Show me',
        ),
      if (hasListings)
        _Step(
          _StepId.offer,
          TourKeys.offerButton,
          'This is the offer button',
          'Buying on Trega works on offers, not fixed prices. Name '
              'your price here. If the seller accepts it, you pay and '
              'the item is yours. No chats, no calls.',
          nextLabel: 'Got it',
        ),
      _Step(
        _StepId.sell,
        TourKeys.tabSell,
        'This button is for selling',
        'Tap Sell, take photos with your camera, set your price. '
            'That is all it takes to list your gear.',
      ),
      _Step(
        _StepId.bids,
        TourKeys.tabBids,
        'Your offers live here',
        'Every offer you send, and every offer on your own listings, '
            'shows up here.',
      ),
      _Step(
        _StepId.profile,
        TourKeys.tabProfile,
        'Your account',
        'Your listings, orders and settings live here. One quick '
            'Aadhaar verification before you sell '
            'keeps every seller genuine.',
        nextLabel: 'Done',
      ),
    ];
    _index = 0;
    _showCurrent();
  }

  static void _showCurrent() {
    final context = _rootContext;
    if (context == null || !context.mounted) return;
    _removeEntry();
    final step = _steps[_index];
    final entry = OverlayEntry(
      builder: (_) => _TourSheet(
        step: step,
        index: _index,
        total: _steps.length,
        onNext: _next,
        onSkip: _finish,
        onMissing: _skipCurrent,
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  static Future<void> _next() async {
    if (!isRunning) return;
    final step = _steps[_index];
    if (step.id == _StepId.firstCard) {
      // Open the listing for real, then point at its offer button.
      _removeEntry();
      _openFirstListing?.call();
      _onDetail = true;
      await Future<void>.delayed(const Duration(milliseconds: 750));
      _index++;
      if (_index >= _steps.length) {
        _finish();
        return;
      }
      _showCurrent();
      return;
    }
    if (step.id == _StepId.offer) {
      _removeEntry();
      _popDetail();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _index++;
      if (_index >= _steps.length) {
        _finish();
        return;
      }
      _showCurrent();
      return;
    }
    _index++;
    if (_index >= _steps.length) {
      _finish();
      return;
    }
    _showCurrent();
  }

  /// The step's anchor never appeared (layout changed or the listing
  /// had no offer button): drop just this step and move on.
  static void _skipCurrent() {
    if (!isRunning) return;
    final step = _steps[_index];
    _removeEntry();
    if (step.id == _StepId.offer && _onDetail) _popDetail();
    _index++;
    if (_index >= _steps.length) {
      _finish();
      return;
    }
    _showCurrent();
  }

  static void _finish() {
    _removeEntry();
    if (_onDetail) _popDetail();
    final done = _onDone;
    _rootContext = null;
    _openFirstListing = null;
    _onDone = null;
    _onDetail = false;
    done?.call();
  }

  static void _popDetail() {
    if (!_onDetail) return;
    final context = _rootContext;
    if (context == null || !context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _onDetail = false;
  }

  static void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }
}

/// One tour step: dimmed scrim with a cut-out over the target, a ring
/// around it, and the explanation card.
class _TourSheet extends StatefulWidget {
  const _TourSheet({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
    required this.onMissing,
  });

  final _Step step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onMissing;

  @override
  State<_TourSheet> createState() => _TourSheetState();
}

class _TourSheetState extends State<_TourSheet> {
  Rect? _hole;
  Timer? _timer;
  int _tries = 0;
  bool _reportedMissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    _timer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _measure(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _measure() {
    if (!mounted || _hole != null) return;
    _tries++;
    final ctx = widget.step.key.currentContext;
    final obj = ctx?.findRenderObject();
    if (obj is RenderBox && obj.hasSize) {
      final rect = (obj.localToGlobal(Offset.zero) & obj.size).inflate(6);
      final screen = MediaQuery.sizeOf(context);
      if (rect.overlaps(Offset.zero & screen)) {
        _timer?.cancel();
        setState(() => _hole = rect);
        return;
      }
    }
    // About 1.8 seconds without the anchor: skip this step silently.
    if (_tries >= 15 && !_reportedMissing) {
      _reportedMissing = true;
      _timer?.cancel();
      widget.onMissing();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hole = _hole;
    final placeBelow = hole != null && hole.bottom < size.height * 0.55;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Scrim: blocks every tap on the real screen underneath.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _ScrimPainter(hole)),
            ),
          ),
          if (hole != null)
            Positioned.fromRect(
              rect: hole,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.accent, width: 2.5),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            top: hole == null
                ? null
                : placeBelow
                    ? hole.bottom + 14
                    : null,
            bottom: hole == null
                ? 24
                : placeBelow
                    ? null
                    : (size.height - hole.top + 14),
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.step.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.step.body,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: widget.onSkip,
                          child: const Text(
                            'Skip tour',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${widget.index + 1} of ${widget.total}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: widget.onNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                          ),
                          child: Text(widget.step.nextLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final full = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(full, paint);
      return;
    }
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(h, const Radius.circular(14)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, cut),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) => oldDelegate.hole != hole;
}
