import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/category.dart';
import '../../../core/models/product.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/trega_button.dart';
import '../../home/providers/listing_providers.dart';

/// Multi-step "Sell in 30 seconds" flow.
///
/// Steps: 1) Photos & video  2) Details  3) Price & publish.
///
/// Media uploads to Firebase Storage (`listingMedia/{listingId}/…`), then the
/// URLs are attached to a `draft` listing document in Firestore — it goes
/// live only after the admin panel approves it.
class SellFlowScreen extends ConsumerStatefulWidget {
  static const String routeName = '/sell';

  const SellFlowScreen({super.key});

  @override
  ConsumerState<SellFlowScreen> createState() => _SellFlowScreenState();
}

class _SellFlowScreenState extends ConsumerState<SellFlowScreen> {
  int _step = 0;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();

  String? _categoryId;
  Condition _condition = Condition.likeNew;
  bool _publishing = false;
  String? _error;

  final List<XFile> _pickedMedia = [];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    setState(() => _pickedMedia.addAll(files));
  }

  Future<void> _publish() async {
    final title = _titleController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    final uid = ref.read(currentUidProvider);
    if (title.isEmpty || price == null || price <= 0) {
      setState(() => _error = 'Add a title and a valid price to continue.');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = 'Pick a category for your listing.');
      return;
    }
    if (uid == null) {
      setState(() => _error = 'You need to be signed in to sell.');
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final firestore = ref.read(firestoreServiceProvider);
      final storage = ref.read(storageServiceProvider);

      // 1) Create a draft listing doc (status = draft). The
      //    `onListingCreate` trigger moves it to `pending` for team review.
      final listingId = await firestore.createListingDraft(
        sellerId: uid,
        title: title,
        description: _descriptionController.text.trim(),
        categoryId: _categoryId!,
        price: price,
        condition: _condition.wireValue,
      );

      // 2) Upload media to Storage, then attach URLs to the draft.
      if (_pickedMedia.isNotEmpty) {
        final imageUrls =
            await storage.uploadListingImages(listingId, _pickedMedia);
        await firestore.updateListingMedia(listingId, imageUrls);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Listing submitted! Our team will review it before it goes live.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = 'Could not publish. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Firestore categories; default the selection once they load.
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    _categoryId ??= categories.isNotEmpty ? categories.first.id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Sell an item')),
      body: Stepper(
        currentStep: _step,
        onStepTapped: (i) => setState(() => _step = i),
        onStepContinue: () {
          if (_publishing) return;
          if (_step < 2) {
            setState(() => _step += 1);
          } else {
            _publish();
          }
        },
        onStepCancel: () {
          if (_step > 0) setState(() => _step -= 1);
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                Expanded(
                  child: TregaButton(
                    label: _step == 2 ? 'Publish listing' : 'Continue',
                    onPressed: details.onStepContinue,
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
            title: const Text('Photos & video'),
            subtitle: const Text('Show the real product working'),
            isActive: _step >= 0,
            state: _step > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._pickedMedia.map(
                      (f) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          // ignore: avoid-unnecessary-type-casts
                          File(f.path),
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 96,
                            height: 96,
                            color: AppColors.primarySoft,
                            child: const Icon(Icons.image,
                                color: AppColors.primary),
                          ),
                        ),
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                color: AppColors.primary),
                            SizedBox(height: 4),
                            Text('Add',
                                style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tip: a short video of the product working builds trust and sells faster.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Details'),
            subtitle: const Text('What are you selling?'),
            isActive: _step >= 1,
            state: _step > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Sony PS5 Disc Edition',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration:
                      const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _categoryId = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Condition>(
                  initialValue: _condition,
                  decoration:
                      const InputDecoration(labelText: 'Condition'),
                  items: Condition.values
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.label),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _condition = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
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
            title: const Text('Price & publish'),
            subtitle: const Text('Set your price'),
            isActive: _step >= 2,
            content: Column(
              children: [
                TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixText: '₹ ',
                    hintText: '35000',
                  ),
                ),
                const SwitchListTile(
                  title: const Text('Negotiable'),
                  subtitle: const Text(
                      'Bids & offers are on for every listing — no chats'),
                  value: true,
                  activeThumbColor: AppColors.primary,
                  onChanged: null,
                ),
                const SizedBox(height: 8),
                Text(
                  'Every new listing is reviewed by our team before it goes live, so listings stay accurate.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
