import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/category.dart';
import '../../../core/models/product.dart';
import '../../../core/models/saved_address.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/trega_button.dart';
import '../../home/providers/listing_providers.dart';
import '../../profile/screens/kyc_screen.dart';

/// Multi-step "Sell in 30 seconds" flow (OLX-style, category-first).
///
/// Steps: 1) Category  2) Photos & video  3) Details  4) Price
/// 5) Pickup address  6) Review & publish.
///
/// Media is captured with the camera only — gallery uploads are disabled by
/// policy (trust & safety). Media uploads to Firebase Storage
/// (`listingMedia/{listingId}/…`), then the URLs are attached to the
/// listing document in Firestore, which the `onListingCreate` trigger flips
/// to `live` immediately — no pre-review gate. The team monitors new
/// listings and flags/removes suspicious ones after the fact.
///
/// The pickup address is captured as structured fields (street, landmark,
/// city, state, PIN) and stored under `listings/{id}/private/details`
/// (seller + admin eyes only, never public).
class SellFlowScreen extends ConsumerStatefulWidget {
  static const String routeName = '/sell';

  const SellFlowScreen({super.key});

  @override
  ConsumerState<SellFlowScreen> createState() => _SellFlowScreenState();
}

/// Formats a price field with Indian digit grouping (1,38,000) as you type.
class _IndianGroupingFormatter extends TextInputFormatter {
  static String group(String digits) {
    if (digits.length <= 3) return digits;
    final tail = digits.substring(digits.length - 3);
    var head = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    return '${parts.join(',')},$tail';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final formatted = group(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _SellFlowScreenState extends ConsumerState<SellFlowScreen> {
  static const _lastStep = 5;

  int _step = 0;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  // Structured pickup address (India): house/street, landmark, city,
  // state, PIN — separate fields like other marketplace apps, so the
  // team can actually route a pickup from it.
  final _addrLine1Controller = TextEditingController();
  final _addrLine2Controller = TextEditingController();
  final _addrCityController = TextEditingController();
  final _addrStateController = TextEditingController();
  final _addrPinController = TextEditingController();
  // Payout UPI ID — prefilled from the seller's saved value, saved back
  // on publish. Owner-only, like the pickup address.
  final _upiController = TextEditingController();
  String? _selectedSavedAddressId;

  String? _categoryId;
  Condition _condition = Condition.likeNew;
  bool _negotiable = true;
  bool _publishing = false;
  String? _error;

  final List<XFile> _pickedMedia = [];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _addrLine1Controller.dispose();
    _addrLine2Controller.dispose();
    _addrCityController.dispose();
    _addrStateController.dispose();
    _addrPinController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  /// Camera-only capture (policy: no gallery uploads). One photo per tap —
  /// tapping "Add" again captures another.
  Future<void> _pickMedia() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    setState(() => _pickedMedia.add(file));
  }

  double? get _parsedPrice {
    final digits = _priceController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  Category? _selectedCategory(List<Category> categories) {
    for (final c in categories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  /// Median asking price of live listings in the chosen category, when
  /// there are enough to be meaningful.
  String? _similarPriceHint(List<Category> categories) {
    if (_categoryId == null) return null;
    final feed = ref.watch(liveListingsProvider).valueOrNull;
    if (feed == null) return null;
    final prices = feed
        .where((l) => l.product.categoryId == _categoryId)
        .map((l) => l.price)
        .toList()
      ..sort();
    if (prices.length < 3) return null;
    final median = prices[prices.length ~/ 2];
    final name = _selectedCategory(categories)?.name ?? 'this category';
    return 'Similar $name items are listed around ${formatINR(median)}';
  }

  /// Per-step validation when tapping Continue.
  bool _validateStep(int step) {
    switch (step) {
      case 0:
        if (_categoryId == null) {
          setState(() => _error = 'Pick a category to continue.');
          return false;
        }
        return true;
      case 2:
        if (_titleController.text.trim().isEmpty) {
          setState(() => _error = 'Give your item a title.');
          return false;
        }
        return true;
      case 3:
        final price = _parsedPrice;
        if (price == null || price <= 0) {
          setState(() => _error = 'Enter a valid price to continue.');
          return false;
        }
        return true;
      case 4:
        if (_addrLine1Controller.text.trim().length < 6) {
          setState(() => _error =
              'Add your house/flat and street so we can pick up the item.',);
          return false;
        }
        if (_addrCityController.text.trim().isEmpty) {
          setState(() => _error = 'Add your city.');
          return false;
        }
        if (!RegExp(r'^[1-9][0-9]{5}$')
            .hasMatch(_addrPinController.text.trim())) {
          setState(() => _error = 'Enter a valid 6-digit PIN code.');
          return false;
        }
        if (_addrStateController.text.trim().isEmpty) {
          setState(() => _error = 'Add your state.');
          return false;
        }
        return true;
      default:
        return true; // photos (1) are optional; review (5) publishes.
    }
  }

  @override
  void initState() {
    super.initState();
    _prefillSavedPayout();
  }

  /// Prefills the payout UPI field from the seller's saved value, if any.
  Future<void> _prefillSavedPayout() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    try {
      final upi =
          await ref.read(firestoreServiceProvider).getPayoutUpi(uid);
      if (!mounted || upi == null || upi.isEmpty) return;
      _upiController.text = upi;
    } catch (_) {
      // Best-effort prefill; the seller can type it manually.
    }
  }

    /// One-tap picker for a previously saved pickup address.
  Widget _buildSavedAddressPicker() {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<List<SavedAddress>>(
      stream:
          ref.watch(firestoreServiceProvider).watchSavedAddresses(uid),
      builder: (context, snap) {
        final addresses = snap.data ?? const <SavedAddress>[];
        if (addresses.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            value: _selectedSavedAddressId,
            decoration: const InputDecoration(
              labelText: 'Use a saved address',
            ),
            items: addresses
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      a.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              final a = addresses.firstWhere((x) => x.id == id);
              setState(() {
                _selectedSavedAddressId = id;
                _addrLine1Controller.text = a.line1;
                _addrLine2Controller.text = a.line2;
                _addrCityController.text = a.city;
                _addrStateController.text = a.state;
                _addrPinController.text = a.pincode;
              });
            },
          ),
        );
      },
    );
  }

static bool _isValidUpi(String upi) =>
      RegExp(r'^[\w.\-]{2,64}@[a-zA-Z]{2,64}$').hasMatch(upi);

  Future<void> _publish() async {
    final title = _titleController.text.trim();
    final price = _parsedPrice;
    final line1 = _addrLine1Controller.text.trim();
    final line2 = _addrLine2Controller.text.trim();
    final city = _addrCityController.text.trim();
    final state = _addrStateController.text.trim();
    final pin = _addrPinController.text.trim();
    final uid = ref.read(currentUidProvider);
    if (title.isEmpty || price == null || price <= 0) {
      setState(() => _error = 'Add a title and a valid price to continue.');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = 'Pick a category for your listing.');
      return;
    }
    if (line1.length < 6) {
      setState(() => _error =
          'Add your house/flat and street so we can pick up the item.',);
      return;
    }
    if (city.isEmpty) {
      setState(() => _error = 'Add your city.');
      return;
    }
    if (state.isEmpty) {
      setState(() => _error = 'Add your state.');
      return;
    }
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)) {
      setState(
          () => _error = 'Enter a valid 6-digit PIN code.',);
      return;
    }
    final upi = _upiController.text.trim();
    if (!_isValidUpi(upi)) {
      setState(() => _error =
          'Enter a valid UPI ID for your payout (e.g. name@okhdfcbank).',);
      return;
    }
    if (uid == null) {
      setState(() => _error = 'You need to be signed in to sell.');
      return;
    }
    // Aadhaar gate: only verified users may sell. The server enforces this
    // too (firestore.rules blocks unverified listing creates), this is the
    // friendly early prompt.
    final me = await ref.read(firestoreServiceProvider).getUser(uid);
    if (me == null || !me.isKycVerified) {
      if (!mounted) return;
      setState(() => _error =
          'Verify your Aadhaar to sell on Trega. It takes a minute.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aadhaar verification is required to sell.'),
        ),
      );
      Navigator.of(context).pushNamed(KycScreen.routeName);
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final firestore = ref.read(firestoreServiceProvider);
      final storage = ref.read(storageServiceProvider);

      // 1) Create the listing doc (status = draft). The
      //    `onListingCreate` trigger flips it to `live` immediately —
      //    listings go public on publish; the team flags suspicious ones
      //    after the fact.
      final listingId = await firestore.createListingDraft(
        sellerId: uid,
        title: title,
        description: _descriptionController.text.trim(),
        categoryId: _categoryId!,
        price: price,
        condition: _condition.wireValue,
        negotiable: _negotiable,
      );

      // 2) Upload media to Storage, then attach URLs to the listing.
      if (_pickedMedia.isNotEmpty) {
        final imageUrls =
            await storage.uploadListingImages(listingId, _pickedMedia);
        await firestore.updateListingMedia(listingId, imageUrls);
      }

      // 3) Owner-only pickup address — never on the public listing doc.
      // The payout UPI rides along so the team can release this sale's
      // payout even if the seller changes it later.
      await firestore.saveListingPrivateDetails(
        listingId,
        pickupAddress: {
          'line1': line1,
          'line2': line2,
          'city': city,
          'state': state,
          'pincode': pin,
          'payoutUpi': upi,
        },
      );

      // 4) Remember the address + UPI for next time (dedupe addresses).
      final address = SavedAddress(
        id: '',
        line1: line1,
        line2: line2,
        city: city,
        state: state,
        pincode: pin,
        createdAt: DateTime.now(),
      );
      final existing = await firestore.getSavedAddresses(uid);
      if (!existing.any((a) => a.sameAs(address))) {
        await firestore.saveAddress(uid, address);
      }
      await firestore.savePayoutUpi(uid, upi);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your listing is now live!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = 'Could not publish. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Firestore categories; falls back to bundled defaults when the
    // collection is empty.
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final selectedCategory = _selectedCategory(categories);
    final priceHint = _similarPriceHint(categories);

    return Scaffold(
      appBar: AppBar(title: const Text('Sell an item')),
      body: Column(
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12,),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.35),),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 20,),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stepper(
              currentStep: _step,
              onStepTapped: (i) {
                if (_publishing) return;
                setState(() {
                  _step = i;
                  _error = null;
                });
              },
              onStepContinue: () {
                if (_publishing) return;
                if (_step < _lastStep) {
                  if (!_validateStep(_step)) return;
                  setState(() {
                    _step += 1;
                    _error = null;
                  });
                } else {
                  _publish();
                }
              },
              onStepCancel: () {
                if (_publishing) return;
                if (_step > 0) {
                  setState(() {
                    _step -= 1;
                    _error = null;
                  });
                }
              },
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TregaButton(
                          label: _publishing
                              ? 'Publishing…'
                              : (_step == _lastStep
                                  ? 'Publish listing'
                                  : 'Continue'),
                          onPressed:
                              _publishing ? null : details.onStepContinue,
                        ),
                      ),
                      if (_step > 0) ...[
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: const Text('Back'),
                        ),
                      ],
                    ],
                  ),
                );
              },
              steps: [
                Step(
                  title: const Text('Category'),
                  subtitle: const Text('What are you selling?'),
                  isActive: _step >= 0,
                  state:
                      _step > 0 ? StepState.complete : StepState.indexed,
                  content: Column(
                    children: [
                      for (final c in categories)
                        _CategoryTile(
                          name: c.name,
                          selected: c.id == _categoryId,
                          onTap: () => setState(() {
                            _categoryId = c.id;
                            _error = null;
                          }),
                        ),
                      if (categories.isEmpty)
                        Text(
                          'Loading categories…',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Photos & video'),
                  subtitle: const Text('Show the real product working'),
                  isActive: _step >= 1,
                  state:
                      _step > 1 ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._pickedMedia.asMap().entries.map(
                                (e) => Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      child: Image.file(
                                        // ignore: avoid-unnecessary-type-casts
                                        File(e.value.path),
                                        width: 96,
                                        height: 96,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                          width: 96,
                                          height: 96,
                                          color: AppColors.primarySoft,
                                          child: const Icon(Icons.image,
                                              color: AppColors.primary,),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => setState(() =>
                                            _pickedMedia
                                                .removeAt(e.key),),
                                        child: Container(
                                          padding:
                                              const EdgeInsets.all(4),
                                          decoration:
                                              const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          InkWell(
                            onTap: _pickMedia,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary,
                                  style: BorderStyle.solid,
                                  width: 1.5,
                                ),
                              ),
                              child: const Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_outlined,
                                      color: AppColors.primary,),
                                  SizedBox(height: 4),
                                  Text('Add',
                                      style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight:
                                              FontWeight.w600,),),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Use your camera to capture the real product — clear, well-lit photos sell faster. Gallery uploads are disabled for trust & safety.',
                        style:
                            Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Details'),
                  subtitle: const Text('Describe your item'),
                  isActive: _step >= 2,
                  state:
                      _step > 2 ? StepState.complete : StepState.indexed,
                  content: Column(
                    children: [
                      // Headroom so the floating labels are never clipped
                      // against the step header.
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleController,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'e.g. Sony PS5 Disc Edition',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Condition>(
                        initialValue: _condition,
                        decoration: const InputDecoration(
                            labelText: 'Condition',),
                        items: Condition.values
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c.label),
                                ),)
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _condition = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descriptionController,
                        maxLines: 4,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText:
                              'Usage, age, defects, what’s included…',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Price'),
                  subtitle: const Text('Set your asking price'),
                  isActive: _step >= 3,
                  state:
                      _step > 3 ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [_IndianGroupingFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          prefixText: '₹ ',
                          hintText: '35,000',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (priceHint != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.insights_outlined,
                                size: 16,
                                color: AppColors.textSecondary,),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                priceHint,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                      SwitchListTile(
                        title: const Text('Negotiable'),
                        subtitle: const Text(
                            'Let buyers send you offers on this price',),
                        value: _negotiable,
                        activeThumbColor: AppColors.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) =>
                            setState(() => _negotiable = v),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Pickup address'),
                  subtitle: const Text('Where do we collect it?'),
                  isActive: _step >= 4,
                  state:
                      _step > 4 ? StepState.complete : StepState.indexed,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Where should we collect the item once it sells?',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      _buildSavedAddressPicker(),
                      TextField(
                        controller: _addrLine1Controller,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'House / Flat, Street',
                          hintText: 'B-402, Green Acres, MG Road',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _addrLine2Controller,
                        textCapitalization:
                            TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Landmark (optional)',
                          hintText: 'Near City Mall',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _addrCityController,
                              textCapitalization:
                                  TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'City',
                                hintText: 'Pune',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _addrPinController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'PIN code',
                                hintText: '411001',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _addrStateController,
                        textCapitalization:
                            TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'State',
                          hintText: 'Maharashtra',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Payout UPI ID',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _upiController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'UPI ID',
                          hintText: 'yourname@okhdfcbank',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 14,
                              color: AppColors.textSecondary,),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Only you and the Trega team can see this — buyers never see your address.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 14,
                              color: AppColors.textSecondary,),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Your sale payout is sent to this UPI ID after a successful transaction.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Review'),
                  subtitle: const Text('Check before you publish'),
                  isActive: _step >= 5,
                  state: StepState.indexed,
                  content: _ReviewSummary(
                    title: _titleController.text.trim(),
                    categoryName:
                        selectedCategory?.name ?? 'Not selected',
                    conditionLabel: _condition.label,
                    price: _parsedPrice,
                    negotiable: _negotiable,
                    description: _descriptionController.text.trim(),
                    photoCount: _pickedMedia.length,
                    addressLine:
                        '${_addrLine1Controller.text.trim()}, ${_addrCityController.text.trim()} ${_addrPinController.text.trim()}'
                            .trim(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single selectable row in the category-first step.
class _CategoryTile extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.divider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        title: Text(
          name,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
        trailing: selected
            ? const Icon(Icons.check_circle, color: AppColors.primary)
            : const Icon(Icons.chevron_right,
                color: AppColors.textSecondary,),
        onTap: onTap,
      ),
    );
  }
}

/// Read-only summary shown on the final step before publishing.
class _ReviewSummary extends StatelessWidget {
  final String title;
  final String categoryName;
  final String conditionLabel;
  final double? price;
  final bool negotiable;
  final String description;
  final int photoCount;
  final String addressLine;

  const _ReviewSummary({
    required this.title,
    required this.categoryName,
    required this.conditionLabel,
    required this.price,
    required this.negotiable,
    required this.description,
    required this.photoCount,
    required this.addressLine,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, String value, {bool highlight = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: (highlight
                        ? textTheme.titleMedium
                        : textTheme.bodyLarge)
                    ?.copyWith(
                  fontWeight:
                      highlight ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              row('Photos', '$photoCount captured'),
              const Divider(height: 1),
              row('Title', title),
              const Divider(height: 1),
              row('Category', categoryName),
              const Divider(height: 1),
              row('Condition', conditionLabel),
              const Divider(height: 1),
              row(
                'Price',
                price == null
                    ? ''
                    : '${formatINR(price!)}${negotiable ? ' · Negotiable' : ''}',
                highlight: true,
              ),
              if (description.isNotEmpty) ...[
                const Divider(height: 1),
                row(
                  'Description',
                  description.length > 120
                      ? '${description.substring(0, 120)}…'
                      : description,
                ),
              ],
              const Divider(height: 1),
              row('Pickup', addressLine),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.bolt_outlined,
                size: 16, color: AppColors.primary,),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Your listing goes live the moment you publish. Our team reviews new listings after they go live and will notify you if anything needs attention.',
                style: textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
