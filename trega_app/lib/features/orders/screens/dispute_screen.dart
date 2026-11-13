import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/firebase/functions_service.dart';
import '../../../core/models/order.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/glass_sheet.dart';
import '../../../core/widgets/no_internet_state.dart';
import '../../../core/widgets/trega_button.dart';
import '../../../core/widgets/trega_scaffold.dart';
import '../../../core/widgets/trega_toast.dart';
import '../../home/providers/listing_providers.dart';

/// Espresso header zone: the solid espresso gradient behind a plain
/// [AppBar], so the automatic back button and title keep working
/// exactly as on the tracking screen. Rounded bottom corners let the
/// cream body show through at the edges.
class _EspressoHeader extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;

  const _EspressoHeader({required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
          ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.headerEspresso,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
      ),
    );
  }
}

/// Report a problem with a delivered order, inside the 72-hour support
/// window. One report per order, enforced server-side; filing freezes
/// the seller's payout until the Trega team resolves the report.
///
/// Streams `orders/{orderId}` from Firestore for the item summary and
/// the delivery time the window runs from.
class DisputeScreen extends ConsumerStatefulWidget {
  static const String routeName = '/orders/dispute';

  final String? orderId;

  const DisputeScreen({super.key, this.orderId});

  @override
  ConsumerState<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends ConsumerState<DisputeScreen> {
  /// Bumped on retry so the [StreamBuilder] below gets a new key and
  /// resubscribes to a fresh order stream.
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    final id = widget.orderId;
    if (id == null) {
      return TregaScaffold(
        appBar: const _EspressoHeader(title: Text('Report a problem')),
        body: const Center(child: Text('Order not found.')),
      );
    }
    final orderAsync = ref.watch(firestoreServiceProvider).watchOrder(id);
    return StreamBuilder<Order?>(
      key: ValueKey(_nonce),
      stream: orderAsync,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return TregaScaffold(
            appBar: const _EspressoHeader(title: Text('Report a problem')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final order = snap.data;
        if (snap.hasError) {
          return TregaScaffold(
            appBar: const _EspressoHeader(title: Text('Report a problem')),
            body: errorStateFor(
              snap.error!,
              title: 'Couldn\'t load this order',
              onRetry: () => setState(() => _nonce++),
            ),
          );
        }
        if (order == null) {
          return TregaScaffold(
            appBar: const _EspressoHeader(title: Text('Report a problem')),
            body: const Center(
              child: Text('Couldn\'t load this order. Check your connection.'),
            ),
          );
        }
        return _DisputeForm(order: order);
      },
    );
  }
}

class _DisputeForm extends ConsumerStatefulWidget {
  final Order order;

  const _DisputeForm({required this.order});

  @override
  ConsumerState<_DisputeForm> createState() => _DisputeFormState();
}

class _DisputeFormState extends ConsumerState<_DisputeForm> {
  static const _reasons = <(String, String)>[
    ('not_as_described', 'Item not as described'),
    ('damaged', 'Damaged or defective'),
    ('wrong_item', 'Wrong item received'),
    ('other', 'Something else'),
  ];

  static const _maxPhotos = 4;

  String _reason = 'not_as_described';
  final _descriptionController = TextEditingController();
  final _photos = <XFile>[];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// The window runs 72 hours from delivery. The tracking screen gates
  /// the entry point, but this screen re-checks: it can be reached
  /// from a stale state, and the server enforces the same rule.
  bool get _windowOpen {
    final deliveredAt = widget.order.deliveredAt;
    if (deliveredAt == null) return false;
    if (widget.order.status != OrderStatus.delivered) return false;
    if (widget.order.disputeStatus == 'open' ||
        widget.order.disputeStatus == 'resolved') {
      return false;
    }
    return DateTime.now().difference(deliveredAt) <
        const Duration(hours: 72);
  }

  String get _closedMessage {
    if (widget.order.disputeStatus == 'open') {
      return 'A report already exists for this order and is under review. '
          'We will update you here.';
    }
    if (widget.order.disputeStatus == 'resolved') {
      return 'The report for this order was already resolved.';
    }
    return 'The 72 hour support window for this order has closed. '
        'Write to contact@trega.in and we will still help.';
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final source = await showGlassSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(PhosphorIconsRegular.camera),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.images),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    // 2048px, same as listing photos: damage detail must stay sharp
    // under zoom, and the evidence is read by a human, not a feed.
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() => _photos.add(image));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final description = _descriptionController.text.trim();
    if (description.length < 10) {
      setState(() {
        _error = 'Please describe what happened in at least 10 characters.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var photoUrls = const <String>[];
      if (_photos.isNotEmpty) {
        photoUrls = await ref
            .read(storageServiceProvider)
            .uploadDisputeEvidence(widget.order.id, _photos);
      }
      await ref.read(functionsServiceProvider).fileDispute(
            orderId: widget.order.id,
            reason: _reason,
            description: description,
            photoUrls: photoUrls,
          );
      if (!mounted) return;
      await showTregaToast(
        context,
        'Your report is with the Trega team. We will update you here.',
        title: 'Report sent',
        kind: TregaToastKind.success,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = functionsErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Same title resolution as the tracking screen: live listing
    // first, purchase-time snapshot when the listing is gone.
    final listingAsync =
        ref.watch(listingDetailProvider(widget.order.listing.id));
    final title = listingAsync.valueOrNull?.product.title ??
        widget.order.listingTitle ??
        'Listing unavailable';
    final deliveredAt = widget.order.deliveredAt;
    final deadline =
        deliveredAt?.add(const Duration(hours: 72));

    return TregaScaffold(
      appBar: const _EspressoHeader(title: Text('Report a problem')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Order ${widget.order.id.toUpperCase()} · '
                  '${formatINR(widget.order.amount)}',
                  style: textTheme.bodySmall,
                ),
                if (deadline != null && _windowOpen) ...[
                  const SizedBox(height: 8),
                  Text(
                    'You can report a problem until '
                    '${formatDayTime(deadline)}.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!_windowOpen) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.tileBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                _closedMessage,
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
            TregaButton(
              label: 'Back to tracking',
              secondary: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ] else ...[
            Text('What went wrong?', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (value, label) in _reasons) ...[
              _ReasonOption(
                label: label,
                selected: _reason == value,
                onTap: () => setState(() => _reason = value),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Text('Tell us what happened', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                hintText: 'Describe the problem with the item you received.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Text('Photos (optional)', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Photos help us resolve this faster, especially for damage '
              'or wrong-item reports. Up to $_maxPhotos.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  _PhotoThumb(
                    file: _photos[i],
                    onRemove: () => setState(() => _photos.removeAt(i)),
                  ),
                if (_photos.length < _maxPhotos)
                  _AddPhotoButton(onTap: _addPhoto),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.tileBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text(
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            TregaButton(
              label: _submitting ? 'Sending report…' : 'Send report',
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: 12),
            Text(
              'Filing this report pauses the seller\'s payout until the '
              'Trega team reviews it. Change of mind after a delivery '
              'that matches the listing does not qualify for a refund.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReasonOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.tileBackground : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ),
            if (selected)
              const Icon(
                PhosphorIconsRegular.checkCircle,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _PhotoThumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(file.path),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                PhosphorIconsRegular.x,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPhotoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.tileBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Icon(
          PhosphorIconsRegular.plus,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
